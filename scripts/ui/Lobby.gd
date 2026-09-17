extends Control

# ============================================================
# LOBBY - pick a monkey, host or join by IP, start.
#
# Manual IP entry rather than LAN discovery. Discovery films better, but it
# is a protocol to debug and this is twenty lines that work on any network
# including a phone hotspot. Discovery is the optional upgrade, not the
# starting point.
# ============================================================

@onready var _status: Label = %Status
@onready var _roster_list: Label = %RosterList
@onready var _ip_field: LineEdit = %IpField
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _solo_button: Button = %SoloButton
@onready var _start_button: Button = %StartButton
@onready var _leave_button: Button = %LeaveButton
@onready var _hosts_list: VBoxContainer = %HostsList
@onready var _monkey_row: HBoxContainer = %MonkeyRow
@onready var _map_row: HBoxContainer = %MapRow
@onready var _mode_row: HBoxContainer = %ModeRow
@onready var _store_button: Button = %StoreButton
@onready var _restore_button: Button = %RestoreButton
@onready var _blurb: Label = %Blurb

var _selected: StringName = &"gorilla"
var _monkey_buttons: Dictionary = {}
var _map_buttons: Dictionary = {}
var _mode_buttons: Dictionary = {}


func _ready() -> void:
	_host_button.pressed.connect(_on_host)
	_join_button.pressed.connect(_on_join)
	_solo_button.pressed.connect(_on_solo)
	_start_button.pressed.connect(_on_start)
	_leave_button.pressed.connect(_on_leave)
	_store_button.pressed.connect(func() -> void: Purchases.buy_premium())
	_restore_button.pressed.connect(func() -> void: Purchases.restore())

	Net.roster_changed.connect(_refresh)
	Discovery.hosts_changed.connect(_refresh_hosts)
	Discovery.start_listening()
	Net.config_changed.connect(_refresh_config)
	Net.connection_failed.connect(func() -> void: _set_status("Could not reach that host. Same wifi?"))
	Net.server_disconnected.connect(func() -> void: _set_status("Host closed the game."))
	Purchases.entitlement_changed.connect(_on_entitlement_changed)
	Purchases.purchase_finished.connect(_on_purchase_finished)

	_build_monkey_row()
	_build_match_rows()
	_refresh_hosts()
	_select_monkey(_selected)
	_refresh_config()
	_refresh()
	_set_status("Pick a monkey. Host, join, or play solo.")


func _build_monkey_row() -> void:
	for id in GameConfig.roster_ids():
		var stats := GameConfig.get_monkey(id)
		var button := Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(150.0, 54.0)
		button.text = stats.display_name
		button.pressed.connect(_on_monkey_pressed.bind(id))
		_monkey_row.add_child(button)
		_monkey_buttons[id] = button
	_refresh_locks()


func _build_match_rows() -> void:
	for id in GameConfig.map_ids():
		var button := Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(190.0, 48.0)
		button.text = GameConfig.MAP_NAMES.get(id, String(id))
		button.pressed.connect(_on_map_pressed.bind(id))
		_map_row.add_child(button)
		_map_buttons[id] = button

	for mode in [GameConfig.Mode.FREE_PLAY, GameConfig.Mode.RACE, GameConfig.Mode.HOARD]:
		var button := Button.new()
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(150.0, 48.0)
		button.text = GameConfig.MODE_NAMES[mode]
		button.pressed.connect(_on_mode_pressed.bind(mode))
		_mode_row.add_child(button)
		_mode_buttons[mode] = button


## Only the host picks the map and the mode. A client that could would load
## a different level into the same match and desync on the first frame.
func _can_configure() -> bool:
	return not Net.is_online() or Net.is_host()


func _on_map_pressed(id: StringName) -> void:
	if not _can_configure():
		_set_status("Only the host picks the map.")
		_refresh_config()
		return
	Net.set_match_config(id, Net.mode)


func _on_mode_pressed(mode: int) -> void:
	if not _can_configure():
		_set_status("Only the host picks the mode.")
		_refresh_config()
		return
	Net.set_match_config(Net.map_id, mode)


func _refresh_config() -> void:
	for id in _map_buttons.keys():
		var button := _map_buttons[id] as Button
		button.button_pressed = id == Net.map_id
		button.disabled = not _can_configure()
	for mode in _mode_buttons.keys():
		var button := _mode_buttons[mode] as Button
		button.button_pressed = int(mode) == Net.mode
		button.disabled = not _can_configure()


func _on_monkey_pressed(id: StringName) -> void:
	if not GameConfig.is_unlocked(id):
		_set_status("%s is locked. Unlock it in the store panel." % GameConfig.get_monkey(id).display_name)
		_refresh_locks()
		return
	_select_monkey(id)


func _select_monkey(id: StringName) -> void:
	_selected = id
	Net.set_local_monkey(id)
	var stats := GameConfig.get_monkey(id)
	_blurb.text = "%s\nSpeed %s  Weight %s  Power %s  Climb %s  Swing %s" % [
		stats.blurb,
		_bar(stats.speed), _bar(stats.weight), _bar(stats.power),
		_bar(stats.climb), _bar(stats.swing),
	]
	for key in _monkey_buttons.keys():
		(_monkey_buttons[key] as Button).button_pressed = key == id


## Stats as blocks rather than numbers: nobody reads 1.9 as "very high", but
## everybody reads a longer bar as a bigger number.
func _bar(value: float) -> String:
	var filled := clampi(int(round(value * 2.5)), 1, 5)
	return "█".repeat(filled) + "·".repeat(5 - filled)


func _refresh_locks() -> void:
	for id in _monkey_buttons.keys():
		var button := _monkey_buttons[id] as Button
		var unlocked := GameConfig.is_unlocked(id)
		var stats := GameConfig.get_monkey(id)
		button.text = stats.display_name if unlocked else "%s  (locked)" % stats.display_name
		button.modulate = Color.WHITE if unlocked else Color(0.65, 0.65, 0.65)
	_store_button.disabled = Purchases.has_premium()
	_store_button.text = "Unlocked" if Purchases.has_premium() else "Unlock premium monkey"


func _refresh() -> void:
	var online := Net.is_online()
	_start_button.visible = Net.is_host()
	_leave_button.visible = online
	_host_button.disabled = online
	_join_button.disabled = online
	_solo_button.disabled = online
	_ip_field.editable = not online
	_refresh_config()
	_refresh_hosts()

	if not online:
		_roster_list.text = "Not connected."
		return
	var lines: PackedStringArray = []
	for id in Net.roster.keys():
		var entry: Dictionary = Net.roster[id]
		var who := "you" if int(id) == Net.local_id() else "peer %d" % int(id)
		lines.append("%s - %s" % [who, GameConfig.get_monkey(entry["monkey"]).display_name])
	_roster_list.text = "\n".join(lines)


# --- Buttons -------------------------------------------------------

func _on_host() -> void:
	var error := Net.host_game()
	if error.is_empty():
		Discovery.start_advertising()
		_set_status("Hosting on %s port %d. Start when everyone is in." % [Net.local_ip_hint(), GameConfig.NET_DEFAULT_PORT])
	else:
		_set_status(error)
	_refresh()


func _on_join() -> void:
	var address := _ip_field.text.strip_edges()
	if address.is_empty():
		_set_status("Type the host's IP, or pick one from the list if it found any.")
		return
	_join_address(address, GameConfig.NET_DEFAULT_PORT)


func _join_address(address: String, port: int) -> void:
	var error := Net.join_game(address, port)
	_set_status("Connecting to %s..." % address if error.is_empty() else error)
	_refresh()


## Hosts found by UDP broadcast. The typed field stays: broadcast is blocked
## on plenty of networks, and a list is a shortcut, not the only door in.
func _refresh_hosts() -> void:
	for child in _hosts_list.get_children():
		child.queue_free()
	if Net.is_online():
		return
	if Discovery.hosts.is_empty():
		var empty := Label.new()
		empty.text = "No hosts found yet. Type an IP if the list stays empty."
		_hosts_list.add_child(empty)
		return
	for ip in Discovery.hosts.keys():
		var entry: Dictionary = Discovery.hosts[ip]
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 48.0)
		button.text = "%s   %d in lobby   %s on %s" % [ip, int(entry["players"]), entry["mode"], entry["map"]]
		button.pressed.connect(_join_address.bind(String(ip), int(entry["port"])))
		_hosts_list.add_child(button)


func _on_solo() -> void:
	Net.leave()
	Net.local_monkey = _selected
	Net.start_match()


func _on_start() -> void:
	Net.start_match()


func _on_leave() -> void:
	Net.leave()
	Discovery.stop_advertising()
	Discovery.start_listening()
	_set_status("Left the game.")
	_refresh()


func _exit_tree() -> void:
	# Stop listening on the way into a match, but keep the host's beacon
	# alive: a host mid-match is still a host worth finding.
	Discovery.stop_listening()


func _on_entitlement_changed(_unlocked: bool) -> void:
	_refresh_locks()


func _on_purchase_finished(success: bool, message: String) -> void:
	_set_status("Purchase succeeded. Premium monkey unlocked." if success else "Purchase did not complete: %s" % message)
	_refresh_locks()


func _set_status(text: String) -> void:
	_status.text = text
