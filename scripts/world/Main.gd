extends Node2D

# ============================================================
# ARENA - owns the monkeys, the map, the respawn rule, and the snapshot wire.
#
# One arena script serves offline, host, and client. The difference is only
# who simulates: offline and host spawn and simulate everyone, a client
# spawns the same bodies but drives only its own and replays the rest.
#
# The map is swapped into MapSlot rather than the arena being rebuilt per
# level, so a new level is one scene file and nothing else.
#
# No death and no health, per the design spine. Falling out of the world
# costs you a short delay and sends you back to your last checkpoint. The
# delay is the entire punishment.
# ============================================================

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const TOUCH_CONTROLS_SCENE := preload("res://scenes/TouchControls.tscn")
const HUD_SCENE := preload("res://scenes/Hud.tscn")
const RESULTS_SCENE := preload("res://scenes/Results.tscn")

## Forces the on-screen stick and buttons on desktop, for layout work.
@export var force_touch_controls: bool = false

var players: Dictionary = {}           # player_id -> Player
var map: MapData = null

var _checkpoints: Dictionary = {}      # player_id -> Vector2
var _respawning: Dictionary = {}       # player_id -> bool
var _local_id: int = 1
var _idle_frame: InputFrame = InputFrame.new()

@onready var _map_slot: Node2D = $MapSlot
@onready var _player_root: Node2D = $Players
@onready var _pickup_root: Node2D = $Pickups
@onready var race: RaceDirector = $RaceDirector
@onready var hoard: HoardDirector = $HoardDirector


func _ready() -> void:
	add_to_group(&"arena")
	_local_id = Net.local_id()
	Net.arena = self
	_load_map()
	_spawn_ui()
	_spawn_all_players()
	_start_mode()


func _exit_tree() -> void:
	if Net.arena == self:
		Net.arena = null


func _load_map() -> void:
	var scene := GameConfig.load_map(Net.map_id)
	if scene == null:
		push_error("Map %s failed to load." % Net.map_id)
		return
	map = scene.instantiate() as MapData
	_map_slot.add_child(map)


func _spawn_ui() -> void:
	add_child(HUD_SCENE.instantiate())
	if force_touch_controls or OS.has_feature("mobile"):
		add_child(TOUCH_CONTROLS_SCENE.instantiate())


func _start_mode() -> void:
	race.setup(self, map)
	hoard.setup(self, map, _pickup_root)
	if map == null:
		return
	race.race_over.connect(_on_match_over)
	hoard.hoard_over.connect(_on_match_over)

	# Only the host counts down. Clients follow the broadcast, otherwise four
	# machines each start their own round a few frames apart.
	if Net.is_online() and not Net.is_host():
		return
	match Net.mode:
		GameConfig.Mode.RACE:
			race.begin()
		GameConfig.Mode.HOARD:
			hoard.begin()
		_:
			pass


func _on_match_over(results: Array) -> void:
	var overlay := RESULTS_SCENE.instantiate()
	add_child(overlay)
	if overlay.has_method(&"show_results"):
		overlay.call(&"show_results", results)


# --- Spawning ------------------------------------------------------

func _spawn_all_players() -> void:
	if not Net.is_online():
		_spawn_player(1, Net.local_monkey, 0)
		return
	for peer_id in Net.roster.keys():
		var entry: Dictionary = Net.roster[peer_id]
		_spawn_player(int(peer_id), entry["monkey"], int(entry["slot"]))


func _spawn_player(id: int, monkey_id: StringName, slot: int) -> Player:
	if players.has(id):
		return players[id]
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = "Player_%d" % id
	player.setup(GameConfig.get_monkey(monkey_id), id, id == _local_id, GameConfig.tint_for_index(slot))
	player.position = _spawn_position(slot)
	_player_root.add_child(player)
	players[id] = player
	_checkpoints[id] = player.position
	_respawning[id] = false
	return player


func _spawn_position(slot: int) -> Vector2:
	if map == null:
		return Vector2(160.0, 400.0) + Vector2(72.0, 0.0) * float(slot)
	return map.spawn_point + map.spawn_stride * float(slot)


func despawn_player(id: int) -> void:
	if not players.has(id):
		return
	players[id].queue_free()
	players.erase(id)
	_checkpoints.erase(id)
	_respawning.erase(id)


# --- Per-tick routing ----------------------------------------------

func _physics_process(_delta: float) -> void:
	_route_input()
	if _is_authority():
		_check_falls()


func _is_authority() -> bool:
	return not Net.is_online() or Net.is_host()


func _route_input() -> void:
	var local_frame := GameInput.take_local_frame()
	if _input_locked():
		# Intent is dropped rather than buffered during the countdown, so a
		# player mashing jump on "3" does not launch on "GO".
		local_frame = _idle_frame

	# The local monkey always gets its intent directly, even on a client.
	# Waiting for the host to echo your own jump back is exactly the lag
	# that makes a LAN game feel worse than a local one.
	var local_player := players.get(_local_id) as Player
	if local_player != null:
		local_player.feed_input(local_frame)

	if Net.is_online() and not Net.is_host():
		Net.send_local_input(local_frame)
		return

	if Net.is_host():
		for id in players.keys():
			if int(id) == _local_id:
				continue
			var frame := Net.take_remote_input(int(id))
			if _input_locked():
				frame = _idle_frame
			players[id].feed_input(frame)


func _input_locked() -> bool:
	return race.is_input_locked() or hoard.is_input_locked()


func _check_falls() -> void:
	var limit := map.kill_depth if map != null else 1400.0
	for id in players.keys():
		if bool(_respawning.get(id, false)):
			continue
		var player := players[id] as Player
		if player.global_position.y > limit:
			_begin_respawn(int(id))


func _begin_respawn(id: int) -> void:
	_respawning[id] = true
	var player := players.get(id) as Player
	if player == null:
		return
	# Parked far below rather than freed: freeing and reinstancing a body
	# mid-match invalidates every reference the netcode is holding.
	var limit := map.kill_depth if map != null else 1400.0
	player.velocity = Vector2.ZERO
	player.global_position = Vector2(0.0, limit + 4000.0)
	await get_tree().create_timer(GameConfig.RESPAWN_DELAY).timeout
	if not is_instance_valid(player):
		return
	player.respawn_at(_checkpoints.get(id, _spawn_position(0)))
	_respawning[id] = false


## Called by Checkpoint areas. Host authoritative: a client claiming a
## checkpoint it never reached would be the cheapest possible cheat.
func set_checkpoint(id: int, point: Vector2) -> void:
	if not _is_authority():
		return
	_checkpoints[id] = point


# --- Snapshot wire (host -> clients) -------------------------------

func collect_snapshot() -> Dictionary:
	var out: Dictionary = {}
	for id in players.keys():
		out[id] = players[id].get_net_state()
	return out


func apply_snapshot(snapshot: Dictionary) -> void:
	for id in snapshot.keys():
		var pid := int(id)
		var player := players.get(pid) as Player
		if player == null:
			# A monkey the host knows about and this client does not: the
			# roster arrived after the arena loaded, so fill the gap rather
			# than dropping the player until the next scene change.
			var entry: Dictionary = Net.roster.get(pid, {"monkey": &"gibbon", "slot": players.size()})
			player = _spawn_player(pid, entry["monkey"], int(entry["slot"]))
		player.apply_net_state(snapshot[id])


func apply_remote_hit(target_id: int, force: Vector2, stun: float, attacker_id: int) -> void:
	var player := players.get(target_id) as Player
	if player != null:
		player.take_hit(attacker_id, force, stun)


func apply_remote_ability(target_id: int, ability_id: StringName, duration: float) -> void:
	var player := players.get(target_id) as Player
	if player != null:
		player.set_ability(ability_id, duration)
