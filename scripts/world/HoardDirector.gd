class_name HoardDirector
extends Node

# ============================================================
# BANANA HOARD - fixed timer, open map, most bananas wins.
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

## Three minutes, per the design doc. Long enough for a comeback, short
## enough that losing one is not an evening.
@export var round_seconds: float = 180.0
@export var countdown_seconds: float = 3.0
@export var spawn_interval: float = 1.4
## Cap on bananas lying around. An uncapped spawner turns a contested map
## into a field where nobody has to take a risk.
@export var max_pickups: int = 18
@export var ability_duration: float = 8.0
## Four tuned abilities beat seven half-tuned ones.
const ABILITIES: Array[StringName] = [&"speed_boost", &"super_hit", &"magnet", &"ghost"]

const PICKUP_SCENE := preload("res://scenes/Pickup.tscn")

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
	# Group lookup rather than a type filter: BananaSpawn adds itself on
	# _ready, and add_child readies the whole map subtree before this runs.
	for node in get_tree().get_nodes_in_group(&"banana_spawn"):
		var anchor := node as BananaSpawn
		if anchor != null:
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
		_spawn_at_free_anchor()

	if time_left <= 0.0:
		_send(&"over", [results()])


## A few bananas already on the map at GO, so the first ten seconds are a
## race to a known thing rather than everyone standing still waiting.
func _seed_field() -> void:
	for i in mini(6, _anchors.size()):
		_spawn_at_free_anchor()


func _spawn_at_free_anchor() -> void:
	if _anchors.is_empty() or _pickups.size() >= max_pickups:
		return
	var free: Array[BananaSpawn] = []
	for anchor in _anchors:
		if not _anchor_occupied(anchor):
			free.append(anchor)
	if free.is_empty():
		return
	var anchor: BananaSpawn = free[randi() % free.size()]
	var kind := Pickup.Kind.LUCKY_BOX if randf() < anchor.lucky_chance else Pickup.Kind.BANANA
	_spawn_pickup(anchor.global_position, kind, anchor.value)


func _anchor_occupied(anchor: BananaSpawn) -> bool:
	for pickup in _pickups.values():
		if (pickup as Pickup).global_position.distance_squared_to(anchor.global_position) < 2500.0:
			return true
	return false


func _spawn_pickup(point: Vector2, kind: int, value: int) -> void:
	var id := _next_id
	_next_id += 1
	_send(&"spawn", [id, kind, point, value])


## Called by a monkey that just got hit. The director owns the score, so it
## decides how much comes loose, then scatters it: a contested pile, not a
## pile the attacker vacuums up on the spot.
func knock_bananas_loose(player_id: int, point: Vector2, double_drop: bool, fraction: float) -> void:
	if not _is_authority() or phase != Phase.RUNNING:
		return
	var held := int(scores.get(player_id, 0))
	if held <= 0:
		return
	var share := fraction * (2.0 if double_drop else 1.0)
	var dropped := clampi(int(ceil(float(held) * share)), 1, held)
	scores[player_id] = held - dropped
	_send(&"scores", [scores.duplicate()])
	_scatter(point, dropped)


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


func _scatter(point: Vector2, count: int) -> void:
	var drops := mini(count, 6)
	var per_drop := maxi(int(round(float(count) / float(drops))), 1)
	for i in drops:
		var angle := randf() * TAU
		var offset := Vector2(cos(angle), sin(angle)) * randf_range(40.0, 120.0)
		_spawn_pickup(point + offset, Pickup.Kind.BANANA, per_drop)


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
	}
	var method: StringName = callables[event]
	if Net.is_online():
		var forwarded: Array = [method]
		forwarded.append_array(args)
		callv(&"rpc", forwarded)
	callv(method, args)


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
