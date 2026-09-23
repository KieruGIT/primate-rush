extends Node

# ============================================================
# DISCOVERY - finds hosts on the local network over UDP broadcast.
#
# Manual IP entry stays. This is the convenience layer on top of it, not a
# replacement: broadcast is filtered on plenty of networks (guest wifi,
# client isolation, some phone hotspots), and a join screen that only lists
# hosts is a join screen that cannot connect at all when that happens.
#
# The host shouts, clients listen. The reverse (clients ask, host answers)
# needs the same broadcast to work anyway and costs an extra round trip.
# ============================================================

signal hosts_changed

const PORT: int = 27016
const BEACON_INTERVAL: float = 1.0
## Drop a host after this long without a beacon. Four beacons of slack, so a
## single dropped packet never makes a host flicker out of the list.
const HOST_TIMEOUT: float = 4.0
## Guards against parsing whatever else happens to be broadcasting.
const MAGIC: String = "monkey-lan-1"

var hosts: Dictionary = {}     # ip -> {"port", "players", "map", "mode", "mode_id", "queue", "open", "seen"}

var _beacon: PacketPeerUDP = null
var _listener: PacketPeerUDP = null
var _beacon_timer: float = 0.0


func _process(delta: float) -> void:
	if _beacon != null:
		_beacon_timer -= delta
		if _beacon_timer <= 0.0:
			_beacon_timer = BEACON_INTERVAL
			_send_beacon()
	if _listener != null:
		_drain()
		_prune()


## Called by the host once it is listening for players. Matchmaking keeps
## listening while it advertises, so two searchers that both opened a room
## can still find each other and merge.
func start_advertising(keep_listening: bool = false) -> void:
	if not keep_listening:
		stop_listening()
	if _beacon != null:
		return
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	var err := _beacon.set_dest_address("255.255.255.255", PORT)
	if err != OK:
		push_warning("LAN beacon unavailable (error %d). Players can still join by IP." % err)
		_beacon = null
		return
	_beacon_timer = 0.0


func stop_advertising() -> void:
	if _beacon != null:
		_beacon.close()
		_beacon = null


func start_listening() -> void:
	if _listener != null:
		return
	_listener = PacketPeerUDP.new()
	var err := _listener.bind(PORT)
	if err != OK:
		# Usually another copy of the game already holding the port on this
		# machine. Not fatal, and not worth a popup.
		push_warning("LAN discovery could not bind port %d (error %d)." % [PORT, err])
		_listener = null
		return
	hosts.clear()
	hosts_changed.emit()


func stop_listening() -> void:
	if _listener != null:
		_listener.close()
		_listener = null
	if not hosts.is_empty():
		hosts.clear()
		hosts_changed.emit()


func _send_beacon() -> void:
	var payload := {
		"magic": MAGIC,
		"port": GameConfig.NET_DEFAULT_PORT,
		"players": Net.roster.size(),
		"map": GameConfig.MAP_NAMES.get(Net.map_id, String(Net.map_id)),
		"mode": GameConfig.MODE_NAMES.get(Net.mode, "?"),
		"mode_id": Net.mode,
		"queue": Net.queue,
		"open": Net.searching and Net.roster.size() < GameConfig.NET_MAX_PLAYERS,
	}
	_beacon.put_packet(JSON.stringify(payload).to_utf8_buffer())


func _drain() -> void:
	var changed := false
	while _listener.get_available_packet_count() > 0:
		var packet := _listener.get_packet()
		var ip := _listener.get_packet_ip()
		if _is_own_address(ip):
			# Our own beacon, heard because matchmaking listens while it
			# advertises. Never offer a room to the machine hosting it.
			continue
		var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if not (parsed is Dictionary) or str((parsed as Dictionary).get("magic", "")) != MAGIC:
			continue
		var entry: Dictionary = parsed
		var known: bool = hosts.has(ip)
		hosts[ip] = {
			"port": int(entry.get("port", GameConfig.NET_DEFAULT_PORT)),
			"players": int(entry.get("players", 0)),
			"map": str(entry.get("map", "?")),
			"mode": str(entry.get("mode", "?")),
			"mode_id": int(entry.get("mode_id", -1)),
			"queue": int(entry.get("queue", -1)),
			"open": bool(entry.get("open", false)),
			"seen": _now(),
		}
		# Only a new host redraws the list. A beacon every second from a host
		# already listed is not news.
		changed = changed or not known
	if changed:
		hosts_changed.emit()


func _prune() -> void:
	var now := _now()
	var stale: Array = []
	for ip in hosts.keys():
		if now - float(hosts[ip]["seen"]) > HOST_TIMEOUT:
			stale.append(ip)
	for ip in stale:
		hosts.erase(ip)
	if not stale.is_empty():
		hosts_changed.emit()


## An open matchmaking room for this queue and mode, or "" if none is heard.
## Lowest address first, so every searcher on the network agrees on which
## room to merge into.
func open_room(queue: int, mode: int) -> String:
	var best := ""
	for ip in hosts.keys():
		var entry: Dictionary = hosts[ip]
		if not bool(entry.get("open", false)):
			continue
		if int(entry.get("queue", -1)) != queue or int(entry.get("mode_id", -1)) != mode:
			continue
		if best.is_empty() or address_less(String(ip), best):
			best = String(ip)
	return best


func is_listening() -> bool:
	return _listener != null


func _is_own_address(ip: String) -> bool:
	if ip.begins_with("127."):
		return true
	return IP.get_local_addresses().has(ip)


func address_less(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	if pa.size() != 4 or pb.size() != 4:
		return a < b
	for i in 4:
		if int(pa[i]) != int(pb[i]):
			return int(pa[i]) < int(pb[i])
	return false


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
