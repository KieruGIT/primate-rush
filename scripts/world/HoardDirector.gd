class_name HoardDirector
extends Node

# ============================================================
# BANANA HOARD - first to 30 bananas wins (most bananas if time runs out).
#
# Bananas are scarce on purpose: one or two appear every few seconds, each
# in a different spot, each worth exactly one. So every banana is a race,
# and the other way to get them is to take them: every hit on a carrier
# steals one straight into the attacker's hands and knocks one loose.
#
# The drop-on-hit rule is load bearing. Without it players ignore each other
# and farm separate corners, and a party mode with no reason to interact is
# just a single player game with witnesses.
#
# Host authoritative for the same reason as everything else: spawning,
# collecting, and scoring all resolve on one machine and get replayed. A
# client that spawned its own bananas would be scoring against a different
# map than everybody else.
# ============================================================

signal countdown_changed(value: int)
signal hoard_began
signal scores_changed(scores: Dictionary)
signal time_changed(seconds_left: float)
signal hoard_over(results: Array)

enum Phase { IDLE, COUNTDOWN, RUNNING, OVER }

## First to this many bananas wins on the spot.
@export var win_target: int = 30
## A backstop only: if nobody reaches the target, most bananas wins when
## time runs out.
@export var round_seconds: float = 240.0
@export var countdown_seconds: float = 3.0
## Slow and few: bananas are rare, so the fight is over the ones people
## are carrying, not a race to farm the map.
@export var spawn_interval: float = 5.0
## Cap on bananas lying around (knocked-loose ones included). An
## uncapped spawner turns a contested map into a field where nobody has to
## take a risk.
@export var max_pickups: int = 4
## New bananas land at least this far from each other and from any banana
## already down, so two of them are two different races.
@export var spawn_spread: float = 520.0
## Per hit on a monkey carrying bananas: this many go straight to the
## attacker, and this many more are knocked loose. Doubled for big hits.
const STEAL_PER_HIT := 1
const LOOSE_PER_HIT := 1
@export var ability_duration: float = 8.0
## Four tuned abilities beat seven half-tuned ones.
const ABILITIES: Array[StringName] = [&"speed_boost", &"super_hit", &"magnet", &"ghost"]

const PICKUP_SCENE := preload("res://scenes/Pickup.tscn")
const SkillFx = preload("res://scripts/player/SkillFx.gd")

var phase: int = Phase.IDLE
var time_left: float = 0.0
var scores: Dictionary = {}          # player_id -> int

var _arena: Node = null
var _container: Node2D = null
var _anchors: Array[BananaSpawn] = []
var _pickups: Dictionary = {}        # pickup_id -> Pickup
var _next_id: int = 1
var _spawn_timer: float = 0.0
var _countdown_left: float = 0.0
var _last_announced: int = -1
var _time_broadcast: float = 0.0


func _ready() -> void:
	add_to_group(&"hoard_director")
	Net.peer_joined.connect(_on_peer_joined)


## A player who joins mid-round would otherwise see an empty map and a blank
## scoreboard, then collect bananas nobody else can see.
func _on_peer_joined(peer_id: int) -> void:
	if not _is_authority() or phase == Phase.IDLE:
		return
	for id in _pickups.keys():
		var pickup := _pickups[id] as Pickup
		if pickup != null:
			_net_spawn.rpc_id(peer_id, int(id), pickup.kind, pickup.global_position, pickup.value)
	_net_scores.rpc_id(peer_id, scores.duplicate())


func setup(arena: Node, map: MapData, container: Node2D) -> void:
	_arena = arena
	_container = container
	_anchors.clear()
	if map == null:
		return
	# Group lookup finds every spawn in the tree, including the previous
	# match's map while it is still queued for deletion, so anchors are
	# filtered to this map. Without that, a rematch spawns bananas onto
	# freed nodes and every lookup after it throws.
	for node in get_tree().get_nodes_in_group(&"banana_spawn"):
		var anchor := node as BananaSpawn
		if anchor != null and map.is_ancestor_of(anchor):
			_anchors.append(anchor)
	if _anchors.is_empty():
		push_warning("Hoard on a map with no banana spawns: %s" % map.display_name)


func begin() -> void:
	phase = Phase.COUNTDOWN
	_countdown_left = countdown_seconds
	_last_announced = -1
	time_left = round_seconds
	scores.clear()
	_spawn_timer = 0.0


func is_input_locked() -> bool:
	return phase == Phase.COUNTDOWN


func is_running() -> bool:
	return phase == Phase.RUNNING


func results() -> Array:
	var out: Array = []
	# Built from the player table, not the scores table: a monkey that never
	# picked anything up still finished the round and still gets a row.
	for id in _player_ids():
		out.append({"id": int(id), "score": int(scores.get(int(id), 0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	return out


func _player_ids() -> Array:
	if _arena == null:
		return scores.keys()
	var table: Variant = _arena.get(&"players")
	return table.keys() if table is Dictionary else scores.keys()


func _process(delta: float) -> void:
	if not _is_authority():
		return
	match phase:
		Phase.COUNTDOWN:
			_tick_countdown(delta)
		Phase.RUNNING:
			_tick_running(delta)
		_:
			pass


func _is_authority() -> bool:
	return not Net.is_online() or Net.is_host()


func _tick_countdown(delta: float) -> void:
	_countdown_left -= delta
	var shown := int(ceil(maxf(_countdown_left, 0.0)))
	if shown != _last_announced:
		_last_announced = shown
		_send(&"countdown", [shown])
	if _countdown_left <= 0.0:
		_send(&"begin", [])
		_seed_field()


func _tick_running(delta: float) -> void:
	time_left = maxf(time_left - delta, 0.0)
	_time_broadcast -= delta
	if _time_broadcast <= 0.0:
		_time_broadcast = 0.5
		_send(&"time", [time_left])

	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = spawn_interval
		# One or two at a time, each in its own spot.
		for i in randi_range(1, 2):
			_spawn_at_free_anchor()

	if time_left <= 0.0:
		_send(&"over", [results()])


## A few bananas already on the map at GO, so the first ten seconds are a
## race to a known thing rather than everyone standing still waiting.
func _seed_field() -> void:
	for i in mini(2, _anchors.size()):
		_spawn_at_free_anchor()


func _spawn_at_free_anchor() -> void:
	if _anchors.is_empty() or _pickups.size() >= max_pickups:
		return
	var free: Array[BananaSpawn] = []
	var near: Array[BananaSpawn] = []
	for anchor in _anchors:
		if _anchor_clear(anchor, spawn_spread):
			free.append(anchor)
		elif _anchor_clear(anchor, 50.0):
			near.append(anchor)
	# Far from every banana down if possible; otherwise anywhere empty.
	if free.is_empty():
		free = near
	if free.is_empty():
		return
	var anchor: BananaSpawn = free[randi() % free.size()]
	var kind := Pickup.Kind.LUCKY_BOX if randf() < anchor.lucky_chance else Pickup.Kind.BANANA
	# Always worth one: no stacks, every banana counts the same.
	_spawn_pickup(anchor.global_position, kind, 1)


func _anchor_clear(anchor: BananaSpawn, radius: float) -> bool:
	for pickup in _pickups.values():
		if is_instance_valid(pickup) and (pickup as Pickup).global_position.distance_squared_to(anchor.global_position) < radius * radius:
			return false
	return true


func _spawn_pickup(point: Vector2, kind: int, value: int) -> void:
	var id := _next_id
	_next_id += 1
	_send(&"spawn", [id, kind, point, value])


## Called by a monkey that just got hit. Fighting is a way to get bananas:
## the attacker takes one straight away, and one more is knocked loose for
## whoever is quickest (big hits: two and two). Small and steady per hit,
## so a string of hits on a carrier pays, and one lucky hit does not end
## the round.
func knock_bananas_loose(player_id: int, point: Vector2, double_drop: bool, _fraction: float, attacker_id: int = 0) -> void:
	if not _is_authority() or phase != Phase.RUNNING:
		return
	var held := int(scores.get(player_id, 0))
	if held <= 0:
		return
	var times := 2 if double_drop else 1
	var thief := _player(attacker_id)
	var stolen := 0
	if thief != null and attacker_id != player_id:
		stolen = mini(STEAL_PER_HIT * times, held)
	var loose := mini(LOOSE_PER_HIT * times, held - stolen)
	scores[player_id] = held - stolen - loose
	if stolen > 0:
		scores[attacker_id] = int(scores.get(attacker_id, 0)) + stolen
	_send(&"scores", [scores.duplicate()])
	if stolen > 0:
		_send(&"stolen", [attacker_id, stolen])
	if loose > 0:
		_scatter(point, loose)
	if stolen > 0:
		_check_win(attacker_id)


## Capuchin's Snatch. A transfer, not a drop: the bananas go straight to the
## thief, which is what makes the capuchin worth playing in this mode and
## infuriating to play against.
func steal_bananas(from_id: int, to_id: int, fraction: float) -> void:
	if not _is_authority() or phase != Phase.RUNNING:
		return
	var held := int(scores.get(from_id, 0))
	if held <= 0:
		return
	var taken := clampi(int(ceil(float(held) * fraction)), 1, held)
	scores[from_id] = held - taken
	scores[to_id] = int(scores.get(to_id, 0)) + taken
	_send(&"scores", [scores.duplicate()])
	_check_win(to_id)


func _scatter(point: Vector2, count: int) -> void:
	for i in count:
		# Up and to one side, off the monkey it came out of.
		var offset := Vector2(randf_range(60.0, 130.0) * (1.0 if randf() < 0.5 else -1.0), randf_range(-60.0, -10.0))
		_spawn_pickup(point + offset, Pickup.Kind.BANANA, 1)


func _on_pickup_touched(pickup_id: int, player_id: int) -> void:
	if not _is_authority() or phase != Phase.RUNNING:
		return
	var pickup := _pickups.get(pickup_id) as Pickup
	if pickup == null:
		return
	var player := _player(player_id)
	if player == null or player.is_ghost():
		return

	if pickup.kind == Pickup.Kind.LUCKY_BOX:
		# A lucky box is not a score, so it never touches the scores table.
		_send(&"ability", [player_id, String(ABILITIES[randi() % ABILITIES.size()]), ability_duration])
	else:
		scores[player_id] = int(scores.get(player_id, 0)) + pickup.value
		_send(&"scores", [scores.duplicate()])
	_send(&"collect", [pickup_id])
	if pickup.kind != Pickup.Kind.LUCKY_BOX:
		_check_win(player_id)


## Reached the target: the round ends right there.
func _check_win(player_id: int) -> void:
	if phase == Phase.RUNNING and int(scores.get(player_id, 0)) >= win_target:
		_send(&"over", [results()])


func _player(player_id: int) -> Player:
	if _arena == null:
		return null
	var table: Variant = _arena.get(&"players")
	if not (table is Dictionary):
		return null
	return table.get(player_id) as Player


# --- Replication ---------------------------------------------------
#
# Every hoard event is reliable except the clock, which corrects itself on
# the next tick. A dropped banana spawn would leave a pickup that exists on
# one machine only, which is a point one player can score twice.

func _send(event: StringName, args: Array) -> void:
	var callables := {
		&"countdown": &"_net_countdown",
		&"begin": &"_net_begin",
		&"time": &"_net_time",
		&"spawn": &"_net_spawn",
		&"collect": &"_net_collect",
		&"scores": &"_net_scores",
		&"ability": &"_net_ability",
		&"over": &"_net_over",
		&"stolen": &"_net_stolen",
	}
	var method: StringName = callables[event]
	if Net.is_online():
		var forwarded: Array = [method]
		forwarded.append_array(args)
		callv(&"rpc", forwarded)
	callv(method, args)


## Everyone sees the steal: a +1 over the monkey that took it.
@rpc("authority", "reliable")
func _net_stolen(player_id: int, amount: int) -> void:
	var thief := _player(player_id)
	if thief != null:
		SkillFx.popup(thief.get_parent(), thief.global_position + Vector2(0.0, -70.0), "+%d STOLEN" % amount, JunglePalette.BANANA)
		Sfx.play(&"pickup")


@rpc("authority", "reliable")
func _net_countdown(value: int) -> void:
	phase = Phase.COUNTDOWN
	countdown_changed.emit(value)


@rpc("authority", "reliable")
func _net_begin() -> void:
	phase = Phase.RUNNING
	hoard_began.emit()


@rpc("authority", "unreliable_ordered")
func _net_time(seconds: float) -> void:
	time_left = seconds
	time_changed.emit(seconds)


@rpc("authority", "reliable")
func _net_spawn(id: int, kind: int, point: Vector2, value: int) -> void:
	if _pickups.has(id) or _container == null:
		return
	var pickup := PICKUP_SCENE.instantiate() as Pickup
	pickup.setup(id, kind, point, value)
	pickup.touched.connect(_on_pickup_touched)
	_container.add_child(pickup)
	_pickups[id] = pickup


@rpc("authority", "reliable")
func _net_collect(id: int) -> void:
	var pickup := _pickups.get(id) as Pickup
	if pickup != null:
		Sfx.play(&"lucky" if pickup.kind == Pickup.Kind.LUCKY_BOX else &"pickup")
		pickup.queue_free()
	_pickups.erase(id)


@rpc("authority", "reliable")
func _net_scores(wire: Dictionary) -> void:
	scores = wire
	for id in scores.keys():
		var player := _player(int(id))
		if player != null:
			player.set_bananas(int(scores[id]))
	scores_changed.emit(scores)


@rpc("authority", "reliable")
func _net_ability(player_id: int, ability_id: String, duration: float) -> void:
	var player := _player(player_id)
	if player != null:
		player.set_ability(StringName(ability_id), duration)


@rpc("authority", "reliable")
func _net_over(payload: Array) -> void:
	phase = Phase.OVER
	hoard_over.emit(payload)
