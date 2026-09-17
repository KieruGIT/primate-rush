extends Node

# ============================================================
# PORT MAP - asks the router to let strangers in, over UPnP.
#
# The LAN path needs none of this. This is the cheapest possible step up to
# playing with someone who is not in the room: no relay server, no hosting
# bill, no accounts. The host's router opens one UDP port and the other side
# connects to the host's public address exactly like they would on a LAN.
#
# It fails on plenty of networks and that is expected, not a bug:
#   * UPnP disabled on the router, which is a common and defensible default
#   * carrier-grade NAT, where the host has no public address to forward to,
#     which is most mobile data and a lot of newer home ISPs
#   * corporate, campus and guest networks
# So every failure returns a reason the lobby can show, and hosting still
# works on the LAN regardless. docs/MULTIPLAYER.md has the fallbacks.
#
# discover() blocks for a couple of seconds, so it runs on a thread. Freezing
# the lobby on the frame someone presses Host would read as a crash.
# ============================================================

signal finished(external_address: String, error: String)

var external_address: String = ""
var last_error: String = ""
var busy: bool = false

var _thread: Thread = null
var _upnp: UPNP = null
var _mapped_port: int = 0


func is_supported() -> bool:
	# The class is compiled into official templates, but a custom build can
	# strip the module, and asking is cheaper than crashing.
	return ClassDB.class_exists("UPNP")


func try_open(port: int) -> void:
	if busy or not is_supported():
		if not is_supported():
			_report("", "This build has no UPnP support.")
		return
	busy = true
	external_address = ""
	last_error = ""
	_thread = Thread.new()
	_thread.start(_work.bind(port))


func close() -> void:
	if _upnp != null and _mapped_port > 0:
		# Leaving a mapping behind on someone's router after the game closes
		# is rude, and routers have a finite table.
		_upnp.delete_port_mapping(_mapped_port, "UDP")
	_mapped_port = 0
	_upnp = null


func _exit_tree() -> void:
	close()
	_join_thread()


func _work(port: int) -> void:
	var upnp := UPNP.new()
	var err := upnp.discover()
	if err != OK:
		_report.call_deferred("", "No router answered the UPnP search (error %d)." % err)
		return
	var gateway := upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		_report.call_deferred("", "Found a device but it is not a usable gateway.")
		return

	# Duration 0 means until deleted. A lease would expire mid-match on the
	# routers that honour it, which is a disconnect nobody could explain.
	var mapped := upnp.add_port_mapping(port, port, "Monkey", "UDP", 0)
	if mapped != OK:
		_report.call_deferred("", "The router refused to open UDP %d (error %d)." % [port, mapped])
		return

	var address := upnp.query_external_address()
	_upnp = upnp
	_mapped_port = port
	if address.is_empty():
		_report.call_deferred("", "Port opened, but the router would not report a public address.")
		return
	_report.call_deferred(address, "")


func _report(address: String, error: String) -> void:
	_join_thread()
	busy = false
	external_address = address
	last_error = error
	finished.emit(address, error)


func _join_thread() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
