extends Control

# ============================================================
# LOBBY - pick a monkey, set the match up, play.
#
# Two cards: who you are on the left, what you are about to play on the
# right. Everything that changes the match itself - map, mode, how many AI
# opponents and how hard they are - sits in one column above one big button,
# because the reason a party game gets played is that somebody could see the
# button from across the room.
#
# Rows of choices are built from data rather than laid out in the scene. A
# sixth monkey or a third map should be a dictionary entry, not a .tscn edit,
# and a row built in code cannot drift out of sync with the roster it shows.
# ============================================================

## Stat axes, in the order they read best: what you do most, first.
const STAT_AXES: Array = [
	{"name": "Speed", "field": "speed", "color": UiTheme.BANANA},
	{"name": "Climb", "field": "climb", "color": UiTheme.LEAF},
	{"name": "Swing", "field": "swing", "color": UiTheme.SKY},
	{"name": "Power", "field": "power", "color": UiTheme.CORAL},
	{"name": "Weight", "field": "weight", "color": Color(0.72, 0.62, 0.95)},
]

## A stat of 1.0 is the reference monkey, and nothing in the roster goes far
## past 2.0, so a full bar means "twice the baseline" rather than a number
## pulled out of the air.
const STAT_MAX: float = 2.0

@onready var _status: Label = %Status
@onready var _roster_list: Label = %RosterList
@onready var _ip_field: LineEdit = %IpField
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _solo_button: Button = %SoloButton
@onready var _start_button: Button = %StartButton
@onready var _leave_button: Button = %LeaveButton
@onready var _hosts_list: Container = %HostsList
@onready var _monkey_row: Container = %MonkeyRow
@onready var _hat_row: Container = %HatRow
@onready var _map_row: Container = %MapRow
@onready var _mode_row: Container = %ModeRow
@onready var _bot_row: Container = %BotRow
@onready var _bot_label: Label = %BotLabel
@onready var _skill_row: Container = %SkillRow
@onready var _store_button: Button = %StoreButton
@onready var _restore_button: Button = %RestoreButton
@onready var _portrait: TextureRect = %Portrait
@onready var _picked_name: Label = %PickedName
@onready var _blurb: Label = %Blurb
@onready var _stats_grid: GridContainer = %Stats
@onready var _skill_text: Label = %Skill
@onready var _career: Label = %Career
@onready var _internet_button: Button = %InternetButton
@onready var _public_address: Label = %PublicAddress

var _selected: StringName = &"gorilla"
var _monkey_buttons: Dictionary = {}
var _hat_buttons: Dictionary = {}
var _map_buttons: Dictionary = {}
var _mode_buttons: Dictionary = {}
var _bot_buttons: Dictionary = {}
var _skill_buttons: Dictionary = {}
var _stat_bars: Dictionary = {}


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
	Profile.stats_changed.connect(_refresh_career)
	_internet_button.pressed.connect(_on_open_to_internet)
	PortMap.finished.connect(_on_port_mapped)
	Purchases.entitlement_changed.connect(_on_entitlement_changed)
	Purchases.purchase_finished.connect(_on_purchase_finished)

	_build_monkey_row()
	_build_hat_row()
	_build_stat_bars()
	_build_match_rows()
	_refresh_hosts()
	# After both rows exist: locks set the button labels, and a row built
	# after the last refresh would otherwise sit there blank.
	_refresh_locks()
	_select_monkey(_selected)
	_refresh_config()
	_refresh_career()
	_refresh()
	_set_status("Pick a monkey, then hit Play solo. Host or join to bring people in.")
	_solo_button.grab_focus()


# --- Rows built from data ------------------------------------------

func _build_monkey_row() -> void:
	for id in GameConfig.roster_ids():
		var button := _monkey_card(id)
		_monkey_row.add_child(button)
		_monkey_buttons[id] = button
	_refresh_locks()


## A face over a name, not a name on its own. Five words in a row is a list;
## five faces is a roster, and the difference is whether anyone can tell the
## gorilla from the gibbon before they have played either.
func _monkey_card(id: StringName) -> Button:
	var button := _choice("", Vector2(0.0, 112.0), _on_monkey_pressed.bind(id))
	var stack := VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The stack is decoration sitting on top of the button, so it must never
	# eat the click that the button below it exists to receive.
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override(&"separation", 2)
	button.add_child(stack)

	var face := TextureRect.new()
	face.texture = MonkeyPortrait.texture(id)
	# Nearest, or a 24px face scaled to 56 comes out as a brown smudge.
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.custom_minimum_size = Vector2(0.0, 56.0)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stack.add_child(face)

	var caption := Label.new()
	caption.name = "Caption"
	caption.text = GameConfig.get_monkey(id).display_name
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override(&"font_size", 14)
	caption.add_theme_color_override(&"font_color", UiTheme.INK_DARK)
	stack.add_child(caption)
	return button


func _build_hat_row() -> void:
	for id in GameConfig.hat_ids():
		var button := _choice("", Vector2(0.0, 48.0), _on_hat_pressed.bind(id))
		_hat_row.add_child(button)
		_hat_buttons[id] = button
	_select_hat(Net.local_hat)


func _build_match_rows() -> void:
	for id in GameConfig.map_ids():
		var map_label: String = GameConfig.MAP_NAMES.get(id, String(id))
		_map_buttons[id] = _add_choice(_map_row, map_label, 50.0, _on_map_pressed.bind(id))

	for mode in [GameConfig.Mode.FREE_PLAY, GameConfig.Mode.RACE, GameConfig.Mode.HOARD]:
		_mode_buttons[mode] = _add_choice(_mode_row, GameConfig.MODE_NAMES[mode], 50.0, _on_mode_pressed.bind(mode))

	for count in range(GameConfig.NET_MAX_PLAYERS):
		_bot_buttons[count] = _add_choice(_bot_row, str(count), 48.0, _on_bots_pressed.bind(count))

	for skill in GameConfig.BOT_SKILL_NAMES.keys():
		var skill_label: String = GameConfig.BOT_SKILL_NAMES[skill]
		_skill_buttons[skill] = _add_choice(_skill_row, skill_label, 48.0, _on_skill_pressed.bind(skill))


func _add_choice(row: Container, text: String, height: float, on_pressed: Callable) -> Button:
	var button := _choice(text, Vector2(0.0, height), on_pressed)
	row.add_child(button)
	return button


## Every pickable thing in this screen is the same widget: a toggle that goes
## green when it is the one in force. One factory rather than five near-copies
## is also the only reason the rows above are three lines each.
func _choice(text: String, min_size: Vector2, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.theme_type_variation = &"ChoiceButton"
	button.custom_minimum_size = min_size
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text = text
	button.pressed.connect(on_pressed)
	return button


## One bar per stat axis, built once and refilled on every pick. Bars rather
## than numbers, because nobody reads 1.9 as "very high" and everybody reads
## a longer bar as a bigger number.
func _build_stat_bars() -> void:
	for axis in STAT_AXES:
		var caption := Label.new()
		caption.text = axis["name"]
		caption.theme_type_variation = &"Muted"
		caption.custom_minimum_size = Vector2(72.0, 0.0)
		_stats_grid.add_child(caption)

		var bar := ProgressBar.new()
		bar.theme_type_variation = &"StatBar"
		bar.show_percentage = false
		bar.max_value = STAT_MAX
		bar.custom_minimum_size = Vector2(0.0, 12.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# The fill colour is the one thing that differs per axis, so it is an
		# override on the bar rather than five near-identical theme types.
		var fill := StyleBoxFlat.new()
		fill.bg_color = axis["color"]
		fill.set_corner_radius_all(6)
		bar.add_theme_stylebox_override(&"fill", fill)
		_stats_grid.add_child(bar)
		_stat_bars[axis["field"]] = bar


# --- Selection -----------------------------------------------------

func _on_hat_pressed(id: StringName) -> void:
	if not GameConfig.is_hat_unlocked(id):
		Sfx.play(&"ui_deny")
		_set_status("%s comes with the premium unlock." % GameConfig.get_hat(id)["name"])
		_refresh_locks()
		return
	_select_hat(id)


func _select_hat(id: StringName) -> void:
	Net.set_local_hat(id)
	for key in _hat_buttons.keys():
		(_hat_buttons[key] as Button).button_pressed = key == id


func _on_monkey_pressed(id: StringName) -> void:
	if not GameConfig.is_unlocked(id):
		Sfx.play(&"ui_deny")
		_set_status("%s is locked. Unlock it in the store panel." % GameConfig.get_monkey(id).display_name)
		_refresh_locks()
		return
	_select_monkey(id)


func _select_monkey(id: StringName) -> void:
	_selected = id
	Net.set_local_monkey(id)
	var stats := GameConfig.get_monkey(id)
	_portrait.texture = MonkeyPortrait.texture(id)
	_picked_name.text = stats.display_name.to_upper()
	_blurb.text = stats.blurb
	for field in _stat_bars.keys():
		(_stat_bars[field] as ProgressBar).value = clampf(float(stats.get(field)), 0.0, STAT_MAX)
	_skill_text.text = "SKILL   %s" % _skill_name(stats)
	for key in _monkey_buttons.keys():
		(_monkey_buttons[key] as Button).button_pressed = key == id


func _skill_name(stats: MonkeyStats) -> String:
	if stats.skill_id == &"":
		return "none"
	return String(stats.skill_id).replace("_", " ").to_upper()


# --- Match configuration -------------------------------------------

## Only the host picks the map and the mode. A client that could would load
## a different level into the same match and desync on the first frame.
func _can_configure() -> bool:
	return not Net.is_online() or Net.is_host()


func _on_map_pressed(id: StringName) -> void:
	if not _host_only("Only the host picks the map."):
		return
	Net.set_match_config(id, Net.mode)


func _on_mode_pressed(mode: int) -> void:
	if not _host_only("Only the host picks the mode."):
		return
	Net.set_match_config(Net.map_id, mode)


func _on_bots_pressed(count: int) -> void:
	if not _host_only("Only the host adds AI players."):
		return
	Net.set_bot_count(count)
	var seats := GameConfig.NET_MAX_PLAYERS - maxi(Net.roster.size(), 1)
	if count > seats:
		_set_status("Room for %d AI player(s) with the people already in. The rest are dropped." % maxi(seats, 0))


func _on_skill_pressed(skill: int) -> void:
	if not _host_only("Only the host sets how hard the AI plays."):
		return
	Net.set_bot_skill(skill)


func _host_only(refusal: String) -> bool:
	if _can_configure():
		return true
	Sfx.play(&"ui_deny")
	_set_status(refusal)
	_refresh_config()
	return false


func _refresh_config() -> void:
	_check(_map_buttons, Net.map_id)
	_check(_mode_buttons, Net.mode)
	_check(_bot_buttons, Net.bot_count)
	_check(_skill_buttons, Net.bot_skill)
	# AI difficulty is dead weight with no AI in the match, so it says so
	# rather than sitting there looking like it did nothing.
	var has_bots := Net.bot_count > 0
	for skill in _skill_buttons.keys():
		(_skill_buttons[skill] as Button).disabled = not _can_configure() or not has_bots
	_bot_label.text = "AI OPPONENTS" if has_bots else "AI OPPONENTS   (none - you play alone)"


## Toggles the one button whose key matches and disables the lot when this
## machine is not allowed to change them.
func _check(buttons: Dictionary, current: Variant) -> void:
	for key in buttons.keys():
		var button := buttons[key] as Button
		button.button_pressed = _same(key, current)
		button.disabled = not _can_configure()


func _same(key: Variant, current: Variant) -> bool:
	if key is StringName or key is String:
		return StringName(key) == StringName(current)
	return int(key) == int(current)


# --- State ---------------------------------------------------------

func _refresh_locks() -> void:
	for id in _hat_buttons.keys():
		var hat_button := _hat_buttons[id] as Button
		var hat: Dictionary = GameConfig.get_hat(id)
		var hat_unlocked := GameConfig.is_hat_unlocked(id)
		hat_button.text = hat["name"] if hat_unlocked else "%s  ●" % hat["name"]
		hat_button.modulate = Color.WHITE if hat_unlocked else Color(0.7, 0.7, 0.7)

	for id in _monkey_buttons.keys():
		var button := _monkey_buttons[id] as Button
		var unlocked := GameConfig.is_unlocked(id)
		var stats := GameConfig.get_monkey(id)
		var caption := button.find_child("Caption", true, false) as Label
		if caption != null:
			caption.text = stats.display_name if unlocked else "%s (locked)" % stats.display_name
		# Locked monkeys are dimmed rather than hidden: you cannot want a
		# character you have never seen.
		button.modulate = Color.WHITE if unlocked else Color(0.62, 0.62, 0.62)
	_store_button.disabled = Purchases.has_premium()
	_store_button.text = "PREMIUM UNLOCKED" if Purchases.has_premium() else "UNLOCK PREMIUM MONKEY"


func _refresh() -> void:
	var online := Net.is_online()
	_start_button.visible = Net.is_host()
	_leave_button.visible = online
	# Solo and a hosted match are the same button press to the player, so the
	# solo one steps aside rather than sitting there greyed out next to it.
	_solo_button.visible = not online
	_host_button.disabled = online
	_join_button.disabled = online
	_ip_field.editable = not online
	_internet_button.disabled = not Net.is_host() or PortMap.busy
	_refresh_config()
	_refresh_hosts()

	if not online:
		_roster_list.text = "Playing on this machine. %s" % _field_summary()
		return
	var lines: PackedStringArray = []
	for id in Net.roster.keys():
		var entry: Dictionary = Net.roster[id]
		var who := "you" if int(id) == Net.local_id() else "peer %d" % int(id)
		lines.append("%s - %s" % [who, GameConfig.get_monkey(entry["monkey"]).display_name])
	if Net.bot_count > 0:
		lines.append("+ %d AI (%s)" % [Net.bot_count, GameConfig.BOT_SKILL_NAMES[Net.bot_skill]])
	_roster_list.text = "\n".join(lines)


## What pressing the big button will actually produce, in one line. Without
## it "Play solo" is a promise the lobby never quite states.
func _field_summary() -> String:
	if Net.bot_count <= 0:
		return "No AI opponents - the level to yourself."
	return "%d AI opponent(s), %s." % [Net.bot_count, GameConfig.BOT_SKILL_NAMES[Net.bot_skill].to_lower()]


func _refresh_career() -> void:
	_career.text = Profile.summary_line()


func _set_status(text: String) -> void:
	_status.text = text


# --- Buttons -------------------------------------------------------

## Optional and host only. The LAN path never needs it, and it fails on
## plenty of networks by design, so the lobby says what happened instead of
## pretending it worked.
func _on_open_to_internet() -> void:
	if not Net.is_host():
		_set_status("Host a game first, then open it to the internet.")
		return
	_public_address.text = "Asking the router..."
	PortMap.try_open(GameConfig.NET_DEFAULT_PORT)


func _on_port_mapped(address: String, error: String) -> void:
	if error.is_empty():
		_public_address.text = "Open. Others outside your network join at %s" % address
		_set_status("Router opened UDP %d. Share that address." % GameConfig.NET_DEFAULT_PORT)
	else:
		_public_address.text = error
		_set_status("Could not open the port automatically. See docs/MULTIPLAYER.md for the fallbacks.")


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
		empty.theme_type_variation = &"Muted"
		empty.text = "Nothing found yet. Type an IP if the list stays empty."
		_hosts_list.add_child(empty)
		return
	for ip in Discovery.hosts.keys():
		var entry: Dictionary = Discovery.hosts[ip]
		var button := Button.new()
		button.theme_type_variation = &"QuietButton"
		button.custom_minimum_size = Vector2(0.0, 46.0)
		button.text = "%s   %d in lobby   %s on %s" % [ip, int(entry["players"]), entry["mode"], entry["map"]]
		button.pressed.connect(_join_address.bind(String(ip), int(entry["port"])))
		_hosts_list.add_child(button)


## Solo is a hosted match with nobody else in it: same roster, same spawn,
## same directors, and the AI seats already filled in from the lobby. There
## is no second code path here to drift out of sync with the first.
func _on_solo() -> void:
	Net.leave()
	Net.local_monkey = _selected
	Net.start_match()


func _on_start() -> void:
	Net.start_match()


func _on_leave() -> void:
	Net.leave()
	PortMap.close()
	_public_address.text = ""
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
