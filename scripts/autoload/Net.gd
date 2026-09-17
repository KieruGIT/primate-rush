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
signal peer_joined(peer_id: int)
signal match_started
signal match_ended
signal config_changed
signal connection_failed
signal server_disconnected

## Connection state. Named `link` rather than `mode` because `mode` is the
## match mode everywhere else in the project, and one of the two had to go.
enum Link { OFFLINE, HOST, CLIENT }

const SNAPSHOT_HZ: float = 30.0

var link: int = Link.OFFLINE
var roster: Dictionary = {}          # peer_id -> {"monkey": StringName, "hat": StringName, "slot": int}
var local_monkey: StringName = &"gorilla"
var local_hat: StringName = &"none"
## Match setup. Host owns it; clients receive it and never edit it, so two
## people cannot load two different maps into the same match.
var map_id: StringName = &"map_a"
var mode: int = GameConfig.Mode.RACE
## Filled into the roster at match start. Bots are ordinary roster entries
## with a negative id, so clients spawn them exactly like people.
var bot_count: int = 0
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
	return link != Link.OFFLINE


func is_host() -> bool:
	return link == Link.HOST


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
	link = Link.HOST
	roster.clear()
	roster[1] = {"monkey": local_monkey, "hat": local_hat, "slot": 0}
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
	link = Link.CLIENT
	return ""


func leave() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	link = Link.OFFLINE
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
	roster[id] = {"monkey": &"gibbon", "hat": &"none", "slot": roster.size()}
	_remote_inputs[id] = InputFrame.new()
	_broadcast_roster()
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	roster.erase(id)
	_remote_inputs.erase(id)
	if is_host():
		_broadcast_roster()
	if arena != null and arena.has_method(&"despawn_player"):
		arena.call(&"despawn_player", id)


func _on_connected_to_server() -> void:
	_register_player.rpc_id(1, String(local_monkey), String(local_hat))


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	leave()
	server_disconnected.emit()


@rpc("any_peer", "reliable")
func _register_player(monkey_id: String, hat_id: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not roster.has(id):
		roster[id] = {"monkey": StringName(monkey_id), "hat": StringName(hat_id), "slot": roster.size()}
	else:
		roster[id]["monkey"] = StringName(monkey_id)
		roster[id]["hat"] = StringName(hat_id)
	_broadcast_roster()


func set_local_monkey(id: StringName) -> void:
	local_monkey = id
	_push_local_choice()


func set_local_hat(id: StringName) -> void:
	local_hat = id
	_push_local_choice()


func _push_local_choice() -> void:
	if link == Link.HOST:
		roster[1]["monkey"] = local_monkey
		roster[1]["hat"] = local_hat
		_broadcast_roster()
	elif link == Link.CLIENT and multiplayer.has_multiplayer_peer():
		_register_player.rpc_id(1, String(local_monkey), String(local_hat))


func _broadcast_roster() -> void:
	_sync_roster.rpc(roster_wire())
	roster_changed.emit()


## The roster as it travels: string keys, plain types, no StringNames. Split
## out from the RPC so it can be exercised without a socket, which is the
## only way any of this gets tested on a machine with no second machine.
func roster_wire() -> Dictionary:
	var wire: Dictionary = {}
	for id in roster.keys():
		wire[str(id)] = {
			"monkey": String(roster[id]["monkey"]),
			"hat": String(roster[id].get("hat", &"none")),
			"slot": int(roster[id]["slot"]),
			"bot": bool(roster[id].get("bot", false)),
		}
	return wire


func apply_roster_wire(wire: Dictionary) -> void:
	roster.clear()
	for key in wire.keys():
		roster[int(key)] = {
			"monkey": StringName(wire[key]["monkey"]),
			"hat": StringName(wire[key].get("hat", "none")),
			"slot": int(wire[key]["slot"]),
			"bot": bool(wire[key].get("bot", false)),
		}
	roster_changed.emit()


@rpc("authority", "reliable")
func _sync_roster(wire: Dictionary) -> void:
	apply_roster_wire(wire)


func set_match_config(new_map: StringName, new_mode: int) -> void:
	map_id = new_map
	mode = new_mode
	config_changed.emit()
	if is_host():
		_sync_config.rpc(String(new_map), new_mode, bot_count)


func set_bot_count(count: int) -> void:
	bot_count = clampi(count, 0, GameConfig.NET_MAX_PLAYERS - 1)
	config_changed.emit()
	if is_host():
		_sync_config.rpc(String(map_id), mode, bot_count)


@rpc("authority", "reliable")
func _sync_config(wire_map: String, wire_mode: int, wire_bots: int) -> void:
	map_id = StringName(wire_map)
	mode = wire_mode
	bot_count = wire_bots
	config_changed.emit()


## Works offline too, so solo play and a hosted match take the same path
## instead of the lobby having two ways to start the same thing.
func start_match() -> void:
	if not is_online():
		# Offline still builds a roster, so the arena has one way to spawn a
		# field instead of a solo path and a networked path that drift.
		roster.clear()
		roster[1] = {"monkey": local_monkey, "hat": local_hat, "slot": 0}
		_assign_bots()
		_start_match()
		return
	if not is_host():
		return
	_assign_bots()
	# Config and roster first, and reliably, so a client cannot start loading
	# a match before it knows the map or who is in it.
	_sync_config.rpc(String(map_id), mode, bot_count)
	_broadcast_roster()
	_start_match.rpc()
	_start_match()


## Bots fill the seats nobody took. Capped by the same player limit, since a
## bot costs the host exactly what a person does.
func _assign_bots() -> void:
	_clear_bots()
	var seats := GameConfig.NET_MAX_PLAYERS - roster.size()
	var wanted := mini(bot_count, maxi(seats, 0))
	var slot := roster.size()
	for index in wanted:
		roster[-(index + 1)] = {
			"monkey": GameConfig.random_bot_monkey(),
			"hat": &"none",
			"slot": slot,
			"bot": true,
		}
		slot += 1


func _clear_bots() -> void:
	for id in roster.keys():
		if int(id) < 0:
			roster.erase(id)


@rpc("authority", "reliable")
func _start_match() -> void:
	match_started.emit()


func end_match() -> void:
	if not is_online():
		_end_match()
		return
	if not is_host():
		return
	_end_match.rpc()
	_end_match()


## The host leaving ends the match for everyone, because a host that walks
## out is not a match any more. A client leaving is just that client.
func leave_match() -> void:
	if is_host():
		end_match()
		return
	leave()
	match_ended.emit()


@rpc("authority", "reliable")
func _end_match() -> void:
	# Bots are reassigned per match, so they never pile up across rematches.
	_clear_bots()
	match_ended.emit()


# --- Input relay ---------------------------------------------------

## Called by a client every physics tick with its own intent.
func send_local_input(frame: InputFrame) -> void:
	if link != Link.CLIENT:
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


## Temporary abilities are host-decided too. A client that granted its own
## speed boost would simply be faster than everyone else.
func broadcast_ability(target_id: int, ability_id: StringName, duration: float) -> void:
	if not is_host():
		return
	_push_ability.rpc(target_id, String(ability_id), duration)


@rpc("authority", "reliable")
func _push_ability(target_id: int, ability_id: String, duration: float) -> void:
	if is_host() or arena == null:
		return
	if arena.has_method(&"apply_remote_ability"):
		arena.call(&"apply_remote_ability", target_id, StringName(ability_id), duration)


@rpc("authority", "reliable")
func _push_hit(target_id: int, force: Vector2, stun: float, attacker_id: int) -> void:
	if is_host() or arena == null:
		return
	if arena.has_method(&"apply_remote_hit"):
		arena.call(&"apply_remote_hit", target_id, force, stun, attacker_id)
