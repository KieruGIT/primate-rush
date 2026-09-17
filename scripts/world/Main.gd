extends Node2D

# ============================================================
# ARENA - owns the monkeys, the respawn rule, and the snapshot wire.
#
# One arena script serves offline, host, and client. The difference is only
# who simulates: offline and host spawn and simulate everyone, a client
# spawns the same bodies but drives only its own and replays the rest.
#
# No death and no health, per the design spine. Falling out of the world
# costs you a short delay and sends you back to your last checkpoint. The
# delay is the entire punishment.
# ============================================================

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const TOUCH_CONTROLS_SCENE := preload("res://scenes/TouchControls.tscn")
const HUD_SCENE := preload("res://scenes/Hud.tscn")

@export var spawn_point: Vector2 = Vector2(160.0, 380.0)
## Spread so four monkeys do not spawn inside each other.
@export var spawn_stride: Vector2 = Vector2(72.0, 0.0)
@export var kill_depth: float = 1400.0
@export var respawn_delay: float = 0.7
## Forces the on-screen stick and buttons on desktop, for layout work.
@export var force_touch_controls: bool = false

var players: Dictionary = {}          # player_id -> Player
var _checkpoints: Dictionary = {}      # player_id -> Vector2
var _respawning: Dictionary = {}       # player_id -> bool
var _local_id: int = 1

@onready var _player_root: Node2D = $Players


func _ready() -> void:
	add_to_group(&"arena")
	_local_id = Net.local_id()
	Net.arena = self
	_spawn_ui()
	_spawn_all_players()


func _exit_tree() -> void:
	if Net.arena == self:
		Net.arena = null


func _spawn_ui() -> void:
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	if force_touch_controls or OS.has_feature("mobile"):
		add_child(TOUCH_CONTROLS_SCENE.instantiate())


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
	player.position = spawn_point + spawn_stride * float(slot)
	_player_root.add_child(player)
	players[id] = player
	_checkpoints[id] = player.position
	_respawning[id] = false
	return player


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
			players[id].feed_input(Net.take_remote_input(int(id)))


func _check_falls() -> void:
	for id in players.keys():
		if bool(_respawning.get(id, false)):
			continue
		var player := players[id] as Player
		if player.global_position.y > kill_depth:
			_begin_respawn(int(id))


func _begin_respawn(id: int) -> void:
	_respawning[id] = true
	var player := players.get(id) as Player
	if player == null:
		return
	# Parked far below rather than freed: freeing and reinstancing a body
	# mid-match invalidates every reference the netcode is holding.
	player.velocity = Vector2.ZERO
	player.global_position = Vector2(0.0, kill_depth + 4000.0)
	if Net.is_host():
		_net_respawn_notice.rpc(id)
	await get_tree().create_timer(respawn_delay).timeout
	if not is_instance_valid(player):
		return
	player.respawn_at(_checkpoints.get(id, spawn_point))
	_respawning[id] = false


@rpc("authority", "reliable")
func _net_respawn_notice(id: int) -> void:
	var player := players.get(id) as Player
	if player != null:
		player.velocity = Vector2.ZERO


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
