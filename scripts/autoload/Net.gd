extends Node

# ============================================================
# NET - LAN multiplayer, host authoritative.
#
# Deliberately built without MultiplayerSpawner or MultiplayerSynchronizer.
# Both store their configuration inside scene files, which means the netcode
# half-lives in a .tscn that cannot be reviewed in a diff. Spawning and
# snapshots are a few dozen lines here instead, and every replicated field
# is visible in source.
#
# Split of traffic, chosen so packet loss degrades gracefully:
#   axes      client -> host, unreliable_ordered, every tick (self correcting)
#   buttons   client -> host, reliable (a dropped jump is a bug report)
#   snapshot  host -> clients, unreliable_ordered, every tick
#   hits      host -> clients, reliable (knockback must never disagree)
# ============================================================

signal roster_changed
signal match_started
signal connection_failed
signal server_disconnected

enum Mode { OFFLINE, HOST, CLIENT }

const SNAPSHOT_HZ: float = 30.0

var mode: int = Mode.OFFLINE
var roster: Dictionary = {}          # peer_id -> {"monkey": StringName, "slot": int}
var local_monkey: StringName = &"gorilla"
var arena: Node = null

var _peer: ENetMultiplayerPeer = null
var _remote_inputs: Dictionary = {}  # peer_id -> InputFrame
var _snapshot_accumulator: float = 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_online() -> bool:
	return mode != Mode.OFFLINE


func is_host() -> bool:
	return mode == Mode.HOST


func local_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


# --- Lifecycle -----------------------------------------------------

func host_game(port: int = GameConfig.NET_DEFAULT_PORT) -> String:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, GameConfig.NET_MAX_PLAYERS)
	if err != OK:
		_peer = null
		return "Could not host on port %d (error %d)" % [port, err]
	multiplayer.multiplayer_peer = _peer
	mode = Mode.HOST
	roster.clear()
	roster[1] = {"monkey": local_monkey, "slot": 0}
	roster_changed.emit()
	return ""


func join_game(address: String, port: int = GameConfig.NET_DEFAULT_PORT) -> String:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		_peer = null
		return "Could not reach %s:%d (error %d)" % [address, port, err]
	multiplayer.multiplayer_peer = _peer
	mode = Mode.CLIENT
	return ""


func leave() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	mode = Mode.OFFLINE
	roster.clear()
	_remote_inputs.clear()
	arena = null


## Best-effort local address, shown on the host screen so the other phone
## has something to type. Loopback is filtered out because typing 127.0.0.1
## into a second device is the classic five-minute LAN debugging detour.
func local_ip_hint() -> String:
	for address in IP.get_local_addresses():
		if address.begins_with("127.") or address.contains(":"):
			continue
		if address.begins_with("169.254."):
			continue
		return address
	return "unknown"


# --- Roster --------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	# The host assigns the slot. Letting clients pick would race two players
	# onto the same colour the moment they connect in the same second.
	roster[id] = {"monkey": &"gibbon", "slot": roster.size()}
	_remote_inputs[id] = InputFrame.new()
	_broadcast_roster()


func _on_peer_disconnected(id: int) -> void:
	roster.erase(id)
	_remote_inputs.erase(id)
	if is_host():
		_broadcast_roster()
	if arena != null and arena.has_method(&"despawn_player"):
		arena.call(&"despawn_player", id)


func _on_connected_to_server() -> void:
	_register_player.rpc_id(1, String(local_monkey))


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	leave()
	server_disconnected.emit()


@rpc("any_peer", "reliable")
func _register_player(monkey_id: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not roster.has(id):
		roster[id] = {"monkey": StringName(monkey_id), "slot": roster.size()}
	else:
		roster[id]["monkey"] = StringName(monkey_id)
	_broadcast_roster()


func set_local_monkey(id: StringName) -> void:
	local_monkey = id
	if mode == Mode.HOST:
		roster[1]["monkey"] = id
		_broadcast_roster()
	elif mode == Mode.CLIENT and multiplayer.has_multiplayer_peer():
		_register_player.rpc_id(1, String(id))


func _broadcast_roster() -> void:
	var wire: Dictionary = {}
	for id in roster.keys():
		wire[str(id)] = {"monkey": String(roster[id]["monkey"]), "slot": int(roster[id]["slot"])}
	_sync_roster.rpc(wire)
	roster_changed.emit()


@rpc("authority", "reliable")
func _sync_roster(wire: Dictionary) -> void:
	roster.clear()
	for key in wire.keys():
		roster[int(key)] = {
			"monkey": StringName(wire[key]["monkey"]),
			"slot": int(wire[key]["slot"]),
		}
	roster_changed.emit()


func start_match() -> void:
	if not is_host():
		return
	_start_match.rpc()
	_start_match()


@rpc("authority", "reliable")
func _start_match() -> void:
	match_started.emit()


# --- Input relay ---------------------------------------------------

## Called by a client every physics tick with its own intent.
func send_local_input(frame: InputFrame) -> void:
	if mode != Mode.CLIENT:
		return
	_push_axes.rpc_id(1, frame.move, frame.jump_held)
	var buttons := frame.button_counts()
	if not buttons.is_empty():
		_push_buttons.rpc_id(1, buttons)


@rpc("any_peer", "unreliable_ordered")
func _push_axes(move: Vector2, jump_held: bool) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var frame: InputFrame = _remote_inputs.get(id)
	if frame == null:
		frame = InputFrame.new()
		_remote_inputs[id] = frame
	frame.move = move.limit_length(1.0)
	frame.jump_held = jump_held


@rpc("any_peer", "reliable")
func _push_buttons(counts: Dictionary) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var frame: InputFrame = _remote_inputs.get(id)
	if frame == null:
		frame = InputFrame.new()
		_remote_inputs[id] = frame
	frame.apply_button_counts(counts)


## Host side. Returns the intent the host should feed to that peer's monkey.
func take_remote_input(peer_id: int) -> InputFrame:
	var frame: InputFrame = _remote_inputs.get(peer_id)
	if frame == null:
		return InputFrame.new()
	var out := InputFrame.new()
	out.move = frame.move
	out.jump_held = frame.jump_held
	out.merge_buttons(frame)
	frame.clear_buttons()
	return out


# --- Snapshots -----------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_host() or arena == null:
		return
	_snapshot_accumulator += delta
	var interval := 1.0 / SNAPSHOT_HZ
	if _snapshot_accumulator < interval:
		return
	_snapshot_accumulator = 0.0
	if not arena.has_method(&"collect_snapshot"):
		return
	var snapshot: Dictionary = arena.call(&"collect_snapshot")
	if not snapshot.is_empty():
		_push_snapshot.rpc(snapshot)


@rpc("authority", "unreliable_ordered")
func _push_snapshot(snapshot: Dictionary) -> void:
	if is_host() or arena == null:
		return
	if arena.has_method(&"apply_snapshot"):
		arena.call(&"apply_snapshot", snapshot)


# --- Hits ----------------------------------------------------------

## Host only. Clients replay the result rather than resolving their own,
## because two machines disagreeing about knockback is what makes a party
## game feel broken.
func broadcast_hit(target_id: int, force: Vector2, stun: float, attacker_id: int) -> void:
	if not is_host():
		return
	_push_hit.rpc(target_id, force, stun, attacker_id)


@rpc("authority", "reliable")
func _push_hit(target_id: int, force: Vector2, stun: float, attacker_id: int) -> void:
	if is_host() or arena == null:
		return
	if arena.has_method(&"apply_remote_hit"):
		arena.call(&"apply_remote_hit", target_id, force, stun, attacker_id)
