extends Control

# ============================================================
# MENU - the home screen and everything one tap away from it.
#
# Built like a phone game, not a settings page. Home is your monkey, big,
# on a stage, with the PLAY button where a right thumb rests and the match
# it will start written on the card above it. Everything else is a page you
# visit and come back from:
#
#   MONKEYS  swipe through the roster with arrows, pick one, pick a hat
#   PLAY     mode, then map, then opponents - one choice per step
#   PARTY    host or join a room; seats nobody takes are filled with AI
#   SHOP     the premium unlock
#
# Built in code, like the theme and the old lobby before it: a sixth monkey
# or a third map is a dictionary entry, never a .tscn edit.
# ============================================================

# SETTINGS is last so the capture tool's page numbers stay put.
enum Page { HOME, MONKEYS, PLAY, PARTY, SHOP, SETTINGS }

## What every key does, in the order a new player needs them.
const KEYS: Array = [
	["A  D", "Move"], ["SPACE", "Jump. Hold on a wall to climb"], ["W  S", "Climb up / down"],
	["SHIFT", "Sprint"], ["L  or  CTRL", "Dash  (any direction, once in the air)"],
	["LEFT CLICK  or  J", "Slap"], ["E  or  K", "Monkey skill"], ["ESC", "Pause"],
]
const TOUCH: Array = [
	["LEFT THUMB", "Drag anywhere on the left half: move and climb"],
	["STICK TO THE EDGE", "Sprint"], ["JUMP", "Jump; hold on a wall to climb; jump into a vine to grab it"],
	["SLAP", "Slap"], ["DASH", "Dash the way the stick points"], ["SKILL", "Monkey skill"],
]

const STAT_AXES: Array = [
	{"name": "Speed", "field": "speed", "color": UiTheme.BANANA},
	{"name": "Climb", "field": "climb", "color": UiTheme.LEAF},
	{"name": "Swing", "field": "swing", "color": UiTheme.SKY},
	{"name": "Power", "field": "power", "color": UiTheme.CORAL},
	{"name": "Weight", "field": "weight", "color": Color(0.72, 0.62, 0.95)},
]
## A stat of 1.0 is the reference monkey, and nothing goes far past 2.0.
const STAT_MAX: float = 2.0

const MODE_BLURBS: Dictionary = {
	GameConfig.Mode.FREE_PLAY: "No clock, no score. Learn the ropes and shove your friends off them.",
	GameConfig.Mode.RACE: "First to the finish wins. Knock the leader off the route.",
	GameConfig.Mode.HOARD: "Grab the most bananas before time runs out. Steal the rest.",
	GameConfig.Mode.SLAP: "Two teams, one tiny island. Slap the other team into the sea. First to 5.",
}
const MODE_COLOURS: Dictionary = {
	GameConfig.Mode.FREE_PLAY: UiTheme.SKY,
	GameConfig.Mode.RACE: UiTheme.BANANA,
	GameConfig.Mode.HOARD: UiTheme.LEAF,
	GameConfig.Mode.SLAP: UiTheme.CORAL,
}
const SKILL_BLURBS: Dictionary = {
	GameConfig.BotSkill.RELAXED: "Slow to notice you. Good for learning.",
	GameConfig.BotSkill.NORMAL: "Plays the route and punches back.",
	GameConfig.BotSkill.FIERCE: "Reacts fast and goes for the leader.",
}

var _pages: Dictionary = {}
var _page: int = Page.HOME
var _toast: Label
var _toast_tween: Tween

# Home
var _home_stage: MonkeyStage
var _home_name: Label
var _home_skill: Label
var _mode_card: Button
var _play_button: Button
var _party_strip: HBoxContainer
var _profile_line: Label
var _level_badge: Label
var _xp_bar: ProgressBar
var _banana_count: Label
var _shop_badge: Control

# Monkeys
var _view_index: int = 0
var _monkey_stage: MonkeyStage
var _monkey_name: Label
var _monkey_blurb: Label
var _monkey_skill: Label
var _monkey_dots: HBoxContainer
var _stat_bars: Dictionary = {}
var _hat_buttons: Dictionary = {}
var _pick_button: Button

# Play setup
var _step: int = 0
var _step_pills: Array[Label] = []
var _step_body: Control
var _next_button: Button

# Party
var _party_body: VBoxContainer
var _ip_field: LineEdit
var _hosts_list: VBoxContainer
var _public_address: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	if not GameConfig.is_unlocked(Net.local_monkey):
		Net.local_monkey = GameConfig.roster_ids()[0]

	_pages[Page.HOME] = _build_home()
	_pages[Page.MONKEYS] = _build_monkeys()
	_pages[Page.PLAY] = _build_play()
	_pages[Page.PARTY] = _build_party()
	_pages[Page.SHOP] = _build_shop()
	_pages[Page.SETTINGS] = _build_settings()
	for page in _pages.values():
		add_child(page)

	_toast = _label("", &"Display", 20)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_bottom = -18.0
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	add_child(_toast)

	Net.roster_changed.connect(_refresh)
	Net.config_changed.connect(_refresh)
	Net.connection_failed.connect(func() -> void: toast("Could not reach that room. Same wifi?"))
	Net.server_disconnected.connect(func() -> void: toast("The host closed the room."))
	Discovery.hosts_changed.connect(_refresh_hosts)
	Discovery.start_listening()
	Profile.stats_changed.connect(_refresh)
	PortMap.finished.connect(_on_port_mapped)
	Purchases.entitlement_changed.connect(func(_on: bool) -> void: _refresh())
	Purchases.purchase_finished.connect(_on_purchase_finished)
	GameInput.pause_requested.connect(_go_back)

	_view_index = maxi(GameConfig.roster_ids().find(Net.local_monkey), 0)
	_show(Page.HOME, false)
	_refresh()


func _exit_tree() -> void:
	# Stop listening on the way into a match, but keep a host's beacon: a
	# host mid-match is still a host worth finding.
	Discovery.stop_listening()


# --- Pages and navigation ------------------------------------------

func _show(page: int, animate: bool = true) -> void:
	_page = page
	for key in _pages.keys():
		var node: Control = _pages[key]
		node.visible = key == page
	var shown: Control = _pages[page]
	if animate:
		shown.modulate.a = 0.0
		shown.position.x = 40.0
		var tween := create_tween().set_parallel(true)
		tween.tween_property(shown, "modulate:a", 1.0, 0.18)
		tween.tween_property(shown, "position:x", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if page == Page.PLAY:
		_set_step(0)
	if page == Page.MONKEYS:
		_view_monkey(maxi(GameConfig.roster_ids().find(Net.local_monkey), 0))
	_refresh()


## Android back and Escape: one page up, never out of the app from a page.
func _go_back() -> void:
	if not is_visible_in_tree():
		return
	if _page == Page.PLAY and _step > 0:
		_set_step(_step - 1)
	elif _page != Page.HOME:
		Sfx.play(&"ui_back")
		_show(Page.HOME)


func _page_root(title: String) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if title.is_empty():
		return root
	# Secondary screens share one quiet header surface. It separates navigation
	# from the animated canopy and keeps both BACK and the page title readable
	# on bright phones without turning every page into a boxed-in dialog.
	var header := PanelContainer.new()
	header.name = "PageHeader"
	header.theme_type_variation = &"Glass"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 12.0
	header.offset_top = 10.0
	header.offset_right = -12.0
	header.offset_bottom = 92.0
	header.z_index = 9
	root.add_child(header)
	var back := _button("    BACK", &"QuietButton", Vector2(170, 66), _go_back)
	back.name = "BackButton"
	back.position = Vector2(24, 20)
	# Full-height page cards are added after the shared header. Keep navigation
	# above them so a tall panel can never paint over BACK or clip the title.
	back.z_index = 10
	var back_icon := ArrowIcon.new()
	back_icon.left = true
	back_icon.position = Vector2(8, 4)
	back_icon.size = Vector2(50, 52)
	back_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(back_icon)
	root.add_child(back)
	var heading := _label(title, &"DisplayBig", 48)
	heading.name = "PageTitle"
	heading.z_index = 10
	heading.set_anchors_preset(Control.PRESET_CENTER_TOP)
	heading.grow_horizontal = Control.GROW_DIRECTION_BOTH
	heading.offset_top = 18.0
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(heading)
	return root


# --- Home ----------------------------------------------------------

func _build_home() -> Control:
	var root := _page_root("")

	# Profile chip, top left.
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"Glass"
	chip.position = Vector2(20, 18)
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override(&"separation", 12)
	chip.add_child(chip_row)
	var face := _portrait(Net.local_monkey, 52)
	face.name = "ProfileFace"
	chip_row.add_child(face)
	var chip_text := VBoxContainer.new()
	chip_text.alignment = BoxContainer.ALIGNMENT_CENTER
	chip_text.add_theme_constant_override(&"separation", 3)
	chip_row.add_child(chip_text)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override(&"separation", 10)
	chip_text.add_child(name_row)
	# Level badge: a star-yellow number, the first thing a returning player
	# looks for.
	_level_badge = _label("LV 1", &"Display", 20)
	_level_badge.add_theme_color_override(&"font_color", UiTheme.BANANA)
	name_row.add_child(_level_badge)
	name_row.add_child(_label("PLAYER", &"Display", 22))
	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(150, 10)
	_xp_bar.max_value = 1.0
	var xp_fill := StyleBoxFlat.new()
	xp_fill.bg_color = UiTheme.BANANA
	xp_fill.set_corner_radius_all(5)
	_xp_bar.add_theme_stylebox_override(&"fill", xp_fill)
	chip_text.add_child(_xp_bar)
	_profile_line = _label("", &"Subheading", 13)
	chip_text.add_child(_profile_line)
	root.add_child(chip)

	# Top right: bananas banked over a career, and the settings cog.
	var corner := HBoxContainer.new()
	corner.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.offset_right = -20.0
	corner.offset_top = 18.0
	corner.add_theme_constant_override(&"separation", 12)
	root.add_child(corner)
	var wallet := PanelContainer.new()
	wallet.theme_type_variation = &"Glass"
	var wallet_row := HBoxContainer.new()
	wallet_row.add_theme_constant_override(&"separation", 8)
	wallet.add_child(wallet_row)
	var banana := Glyph.new()
	banana.kind = &"banana"
	banana.custom_minimum_size = Vector2(34, 34)
	wallet_row.add_child(banana)
	_banana_count = _label("0", &"Display", 24)
	wallet_row.add_child(_banana_count)
	corner.add_child(wallet)
	var cog := _button("", &"QuietButton", Vector2(66, 66), _show.bind(Page.SETTINGS))
	cog.add_child(_glyph_fill(&"cog"))
	corner.add_child(cog)

	# Title, top centre.
	var title := _label("MONKEY SLAP", &"DisplayBig", 52)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.offset_top = 14.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	# Navigation, down the left edge where a left thumb reaches.
	var nav := VBoxContainer.new()
	nav.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	nav.grow_vertical = Control.GROW_DIRECTION_BOTH
	nav.offset_left = 24.0
	nav.add_theme_constant_override(&"separation", 14)
	nav.add_child(_nav_button("MONKEYS", &"monkey", &"NavButton", _show.bind(Page.MONKEYS)))
	nav.add_child(_nav_button("PARTY", &"party", &"NavButton", _show.bind(Page.PARTY)))
	var shop := _nav_button("SHOP", &"cart", &"DangerButton", _show.bind(Page.SHOP))
	_shop_badge = Glyph.new()
	_shop_badge.kind = &"badge"
	_shop_badge.size = Vector2(30, 30)
	_shop_badge.position = Vector2(206, -8)
	_shop_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop.add_child(_shop_badge)
	nav.add_child(shop)
	nav.add_child(_nav_button("CONTROLS", &"pad", &"NavButton", _show.bind(Page.SETTINGS)))
	root.add_child(nav)

	# The monkey, centre stage, with arrows to swap without leaving home.
	var centre := VBoxContainer.new()
	centre.set_anchors_preset(Control.PRESET_CENTER)
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	centre.grow_vertical = Control.GROW_DIRECTION_BOTH
	centre.offset_top = 10.0
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_theme_constant_override(&"separation", 4)
	root.add_child(centre)
	var stage_row := HBoxContainer.new()
	stage_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stage_row.add_theme_constant_override(&"separation", 8)
	centre.add_child(stage_row)
	stage_row.add_child(_arrow("<", _cycle_home.bind(-1)))
	_home_stage = MonkeyStage.new()
	_home_stage.pixel_scale = 6
	_home_stage.custom_minimum_size = Vector2(300, 320)
	stage_row.add_child(_home_stage)
	stage_row.add_child(_arrow(">", _cycle_home.bind(1)))
	_home_name = _label("", &"Display", 38)
	_home_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(_home_name)
	_home_skill = _label("", &"Subheading", 16)
	_home_skill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(_home_skill)

	# Teammates in a party, stood to the right of your monkey.
	_party_strip = HBoxContainer.new()
	_party_strip.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_party_strip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_party_strip.grow_vertical = Control.GROW_DIRECTION_BOTH
	_party_strip.offset_right = -410.0
	_party_strip.offset_top = -40.0
	root.add_child(_party_strip)

	# Match card over the PLAY button, bottom right, under the right thumb.
	var play_column := VBoxContainer.new()
	play_column.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	play_column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	play_column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	play_column.offset_right = -24.0
	play_column.offset_bottom = -22.0
	play_column.add_theme_constant_override(&"separation", 10)
	root.add_child(play_column)
	_mode_card = _button("", &"TileButton", Vector2(360, 104), _open_play_setup)
	var card_row := HBoxContainer.new()
	card_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_row.offset_left = 12.0
	card_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_row.add_theme_constant_override(&"separation", 12)
	_mode_card.add_child(card_row)
	var card_icon := ModeIcon.new()
	card_icon.name = "CardIcon"
	card_icon.custom_minimum_size = Vector2(84, 0)
	card_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_row.add_child(card_icon)
	var card_text := VBoxContainer.new()
	card_text.alignment = BoxContainer.ALIGNMENT_CENTER
	card_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_row.add_child(card_text)
	var card_mode := _label("", &"Display", 28)
	card_mode.name = "CardMode"
	card_text.add_child(card_mode)
	var card_detail := _label("", &"Subheading", 15)
	card_detail.name = "CardDetail"
	card_text.add_child(card_detail)
	var card_hint := _label("", &"Heading", 14)
	card_hint.name = "CardHint"
	card_text.add_child(card_hint)
	play_column.add_child(_mode_card)
	_play_button = _button("PLAY", &"PlayButton", Vector2(360, 124), _on_play)
	play_column.add_child(_play_button)
	# PLAY breathes, gently, so the eye lands on it without being told to.
	_play_button.resized.connect(func() -> void: _play_button.pivot_offset = _play_button.size * 0.5)
	var pulse := _play_button.create_tween().set_loops()
	pulse.tween_property(_play_button, "scale", Vector2.ONE * 1.035, 0.7).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_play_button, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)
	return root


func _nav_button(text: String, icon: StringName, variation: StringName, on_pressed: Callable) -> Button:
	var button := _button("", variation, Vector2(236, 76), on_pressed)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14.0
	row.offset_bottom = -6.0
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 12)
	button.add_child(row)
	var glyph := Glyph.new()
	glyph.kind = icon
	glyph.custom_minimum_size = Vector2(44, 0)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(glyph)
	var label := _label(text, &"Display", 21)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_FILL
	row.add_child(label)
	return button


func _glyph_fill(kind: StringName) -> Glyph:
	var glyph := Glyph.new()
	glyph.kind = kind
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.offset_left = 12.0
	glyph.offset_right = -12.0
	glyph.offset_top = 10.0
	glyph.offset_bottom = -16.0
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return glyph


func _cycle_home(step: int) -> void:
	var ids := GameConfig.roster_ids()
	var at := ids.find(Net.local_monkey)
	# Skip locked monkeys here: home only shows ones you can take into a
	# match. The monkeys page is where locked ones are shown off.
	for i in ids.size():
		at = posmod(at + step, ids.size())
		if GameConfig.is_unlocked(ids[at]):
			break
	_pick_monkey(ids[at])


func _pick_monkey(id: StringName) -> void:
	Net.set_local_monkey(id)
	Net.local_monkey = id
	_refresh()
	_home_stage.cheer()


func _open_play_setup() -> void:
	if Net.is_online() and not Net.is_host():
		_deny("The host picks the match.")
		return
	_show(Page.PLAY)


## Solo is a match with nobody else in it: same roster, same spawn, AI
## seats filled in. A host starts for everyone; a client waits.
func _on_play() -> void:
	if not Net.is_online():
		Net.leave()
		Net.start_match()
	elif Net.is_host():
		Net.start_match()
	else:
		_deny("Waiting for the host to start.")


func _refresh_home() -> void:
	var stats := GameConfig.get_monkey(Net.local_monkey)
	if _home_stage.monkey_id != Net.local_monkey:
		_home_stage.set_monkey(Net.local_monkey)
	_home_name.text = stats.display_name.to_upper()
	_home_skill.text = "SKILL  %s" % _skill_name(stats)
	var face := _pages[Page.HOME].find_child("ProfileFace", true, false) as TextureRect
	if face != null:
		face.texture = MonkeyPortrait.texture(Net.local_monkey)
	var races := int(Profile.get_stat("races", 0))
	var wins := int(Profile.get_stat("race_wins", 0)) + int(Profile.get_stat("hoard_wins", 0))
	var rounds := races + int(Profile.get_stat("hoards", 0))
	_profile_line.text = "%d ROUNDS   %d WINS" % [rounds, wins]
	# A level every three rounds, wins count double: enough to feel like
	# progress on the first evening without a progression system behind it.
	var xp := rounds + wins
	_level_badge.text = "LV %d" % (1 + xp / 3)
	_xp_bar.value = float(xp % 3) / 3.0
	_banana_count.text = str(int(Profile.get_stat("bananas", 0)))
	_shop_badge.visible = not Purchases.has_premium()

	var mode_name: String = GameConfig.MODE_NAMES[Net.mode]
	var map_name: String = GameConfig.MAP_NAMES.get(Net.map_id, String(Net.map_id))
	var icon := _mode_card.find_child("CardIcon", true, false) as ModeIcon
	icon.mode = Net.mode
	icon.colour = MODE_COLOURS[Net.mode]
	icon.queue_redraw()
	(_mode_card.find_child("CardMode", true, false) as Label).text = mode_name.to_upper()
	(_mode_card.find_child("CardDetail", true, false) as Label).text = map_name.to_upper()
	(_mode_card.find_child("CardHint", true, false) as Label).text = _opponent_summary().to_upper()

	if not Net.is_online():
		_play_button.text = "PLAY"
		_play_button.disabled = false
	elif Net.is_host():
		_play_button.text = "START"
		_play_button.disabled = false
	else:
		_play_button.text = "WAITING..."
		_play_button.disabled = true

	for child in _party_strip.get_children():
		child.queue_free()
	if Net.is_online():
		for id in Net.roster.keys():
			if int(id) == Net.local_id() or int(id) < 0:
				continue
			_party_strip.add_child(_seat_card(Net.roster[id]["monkey"], "FRIEND", 3, Color.WHITE))


func _opponent_summary() -> String:
	if Net.mode == GameConfig.Mode.SLAP:
		return "2v2   AI %s" % GameConfig.BOT_SKILL_NAMES[Net.bot_skill]
	if Net.bot_count <= 0:
		return "no AI"
	return "%d AI %s" % [Net.bot_count, GameConfig.BOT_SKILL_NAMES[Net.bot_skill]]


# --- Monkeys -------------------------------------------------------

func _build_monkeys() -> Control:
	var root := _page_root("MONKEYS")
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_top = 100.0
	row.offset_left = 30.0
	row.offset_right = -30.0
	row.offset_bottom = -24.0
	row.add_theme_constant_override(&"separation", 24)
	root.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(left)
	var stage_row := HBoxContainer.new()
	stage_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stage_row.add_theme_constant_override(&"separation", 18)
	left.add_child(stage_row)
	stage_row.add_child(_arrow("<", func() -> void: _view_monkey(_view_index - 1), Vector2(84, 110)))
	_monkey_stage = MonkeyStage.new()
	_monkey_stage.pixel_scale = 8
	_monkey_stage.custom_minimum_size = Vector2(320, 390)
	stage_row.add_child(_monkey_stage)
	stage_row.add_child(_arrow(">", func() -> void: _view_monkey(_view_index + 1), Vector2(84, 110)))
	_monkey_dots = HBoxContainer.new()
	_monkey_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_monkey_dots.add_theme_constant_override(&"separation", 10)
	left.add_child(_monkey_dots)

	var card := PanelContainer.new()
	card.theme_type_variation = &"Glass"
	card.custom_minimum_size = Vector2(520, 0)
	row.add_child(card)
	var info := VBoxContainer.new()
	info.add_theme_constant_override(&"separation", 10)
	card.add_child(info)
	_monkey_name = _label("", &"DisplayBig", 52)
	info.add_child(_monkey_name)
	_monkey_blurb = _label("", &"Value", 17)
	_monkey_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_monkey_blurb.custom_minimum_size = Vector2(480, 0)
	info.add_child(_monkey_blurb)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 14)
	grid.add_theme_constant_override(&"v_separation", 8)
	info.add_child(grid)
	for axis in STAT_AXES:
		var caption := _label(String(axis["name"]).to_upper(), &"Subheading", 15)
		caption.custom_minimum_size = Vector2(90, 0)
		grid.add_child(caption)
		var bar := ProgressBar.new()
		bar.theme_type_variation = &"StatBar"
		bar.show_percentage = false
		bar.max_value = STAT_MAX
		bar.custom_minimum_size = Vector2(0, 16)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = axis["color"]
		fill.set_corner_radius_all(6)
		bar.add_theme_stylebox_override(&"fill", fill)
		grid.add_child(bar)
		_stat_bars[axis["field"]] = bar
	_monkey_skill = _label("", &"Heading", 20)
	info.add_child(_monkey_skill)

	info.add_child(_label("HAT", &"Subheading", 15))
	var hats := HBoxContainer.new()
	hats.add_theme_constant_override(&"separation", 8)
	info.add_child(hats)
	for id in GameConfig.hat_ids():
		var hat_button := _button(GameConfig.get_hat(id)["name"], &"ChoiceButton", Vector2(0, 54), _on_hat.bind(id))
		hat_button.toggle_mode = true
		hat_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hats.add_child(hat_button)
		_hat_buttons[id] = hat_button

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(spacer)
	_pick_button = _button("SELECT", &"GoButton", Vector2(0, 84), _on_pick_viewed)
	info.add_child(_pick_button)
	return root


func _view_monkey(index: int) -> void:
	var ids := GameConfig.roster_ids()
	_view_index = posmod(index, ids.size())
	var id: StringName = ids[_view_index]
	var stats := GameConfig.get_monkey(id)
	var unlocked := GameConfig.is_unlocked(id)
	_monkey_stage.set_monkey(id, not unlocked)
	_monkey_name.text = stats.display_name.to_upper()
	_monkey_blurb.text = stats.blurb
	for field in _stat_bars.keys():
		var bar := _stat_bars[field] as ProgressBar
		var tween := create_tween()
		tween.tween_property(bar, "value", clampf(float(stats.get(field)), 0.0, STAT_MAX), 0.25).set_ease(Tween.EASE_OUT)
	_monkey_skill.text = "SKILL   %s" % _skill_name(stats)
	for child in _monkey_dots.get_children():
		child.queue_free()
	for i in ids.size():
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(28 if i == _view_index else 12, 12)
		dot.color = UiTheme.BANANA if i == _view_index else Color(1, 1, 1, 0.35)
		_monkey_dots.add_child(dot)
	_refresh_pick_button()


func _refresh_pick_button() -> void:
	var id: StringName = GameConfig.roster_ids()[_view_index]
	if not GameConfig.is_unlocked(id):
		_pick_button.text = "UNLOCK IN SHOP"
		_pick_button.theme_type_variation = &"PrimaryButton"
		_pick_button.disabled = false
	elif id == Net.local_monkey:
		_pick_button.text = "SELECTED"
		_pick_button.theme_type_variation = &"GoButton"
		_pick_button.disabled = true
	else:
		_pick_button.text = "SELECT"
		_pick_button.theme_type_variation = &"GoButton"
		_pick_button.disabled = false
	for key in _hat_buttons.keys():
		var hat_button := _hat_buttons[key] as Button
		hat_button.button_pressed = key == Net.local_hat
		hat_button.modulate = Color.WHITE if GameConfig.is_hat_unlocked(key) else Color(0.6, 0.6, 0.6)


func _on_pick_viewed() -> void:
	var id: StringName = GameConfig.roster_ids()[_view_index]
	if not GameConfig.is_unlocked(id):
		_show(Page.SHOP)
		return
	_pick_monkey(id)
	_monkey_stage.cheer()
	Sfx.play(&"ui_select")
	_refresh_pick_button()


func _on_hat(id: StringName) -> void:
	if not GameConfig.is_hat_unlocked(id):
		_deny("%s comes with the premium unlock." % GameConfig.get_hat(id)["name"])
		_refresh_pick_button()
		return
	Net.set_local_hat(id)
	_refresh_pick_button()


# --- Play setup: mode, map, opponents ------------------------------

func _build_play() -> Control:
	var root := _page_root("PLAY")
	var pills := HBoxContainer.new()
	pills.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pills.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pills.offset_top = 92.0
	pills.add_theme_constant_override(&"separation", 26)
	root.add_child(pills)
	for text in ["1  MODE", "2  MAP", "3  OPPONENTS"]:
		var pill := _label(text, &"Display", 22)
		pills.add_child(pill)
		_step_pills.append(pill)

	_step_body = Control.new()
	_step_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_step_body.offset_top = 150.0
	_step_body.offset_bottom = -120.0
	_step_body.offset_left = 40.0
	_step_body.offset_right = -40.0
	_step_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_step_body)

	_next_button = _button("NEXT", &"GoButton", Vector2(300, 88), _on_next_step)
	_next_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_next_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_next_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_next_button.offset_right = -30.0
	_next_button.offset_bottom = -22.0
	root.add_child(_next_button)
	return root


func _set_step(step: int) -> void:
	_step = step
	for i in _step_pills.size():
		_step_pills[i].modulate = Color.WHITE if i == step else Color(1, 1, 1, 0.35)
		_step_pills[i].add_theme_color_override(&"font_color", UiTheme.BANANA if i == step else UiTheme.INK)
	for child in _step_body.get_children():
		child.queue_free()
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 22)
	_step_body.add_child(row)
	match step:
		0:
			for mode in [GameConfig.Mode.SLAP, GameConfig.Mode.RACE, GameConfig.Mode.HOARD, GameConfig.Mode.FREE_PLAY]:
				row.add_child(_mode_tile(mode))
		1:
			for id in GameConfig.maps_for_mode(Net.mode):
				row.add_child(_map_tile(id))
		2:
			row.add_child(_opponent_panel())
	_next_button.text = "DONE" if step == 2 else "NEXT"


func _on_next_step() -> void:
	if _step >= 2:
		_show(Page.HOME)
		return
	_set_step(_step + 1)


func _mode_tile(mode: int) -> Button:
	var tile := _tile(Net.mode == mode, Vector2(280, 400))
	var box := _tile_box(tile)
	var icon := ModeIcon.new()
	icon.mode = mode
	icon.colour = MODE_COLOURS[mode]
	icon.custom_minimum_size = Vector2(0, 150)
	box.add_child(icon)
	var name_label := _label(String(GameConfig.MODE_NAMES[mode]).to_upper(), &"Display", 26)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	var blurb := _label(MODE_BLURBS[mode], &"Value", 16)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(blurb)
	tile.pressed.connect(func() -> void:
		# Keep the map if this mode can use it, otherwise its first map.
		var maps := GameConfig.maps_for_mode(mode)
		var map: StringName = Net.map_id if maps.has(Net.map_id) else maps[0]
		Net.set_match_config(map, mode)
		_advance_after_pick())
	return tile


func _map_tile(id: StringName) -> Button:
	var tile := _tile(Net.map_id == id, Vector2(470, 360))
	var box := _tile_box(tile)
	var preview := MapPreview.new()
	preview.custom_minimum_size = Vector2(0, 230)
	preview.show_map(id)
	box.add_child(preview)
	var name_label := _label(String(GameConfig.MAP_NAMES.get(id, id)).to_upper(), &"Display", 28)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	var best := Profile.best_time(id)
	var sub := _label("BEST  %.2fs" % best if best > 0.0 else "NO BEST TIME YET", &"Subheading", 15)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	tile.pressed.connect(func() -> void:
		Net.set_match_config(id, Net.mode)
		_advance_after_pick())
	return tile


func _opponent_panel() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	if Net.mode == GameConfig.Mode.SLAP:
		# Teams are fixed at two a side; only how hard the AI plays is open.
		column.add_child(_label("TEAMS", &"Display", 24))
		column.add_child(_label("YOU + AI PARTNER  VS  2 AI.  FRIENDS IN YOUR PARTY TAKE THE AI SEATS.", &"Value", 17))
		column.add_child(_skill_row())
		return column
	column.add_child(_label("AI OPPONENTS", &"Display", 24))
	var counts := HBoxContainer.new()
	counts.add_theme_constant_override(&"separation", 14)
	column.add_child(counts)
	for count in range(GameConfig.NET_MAX_PLAYERS):
		var text := "SOLO" if count == 0 else "%d AI" % count
		var button := _button(text, &"TileButton", Vector2(200, 90), func() -> void:
			Net.set_bot_count(count)
			_set_step(2))
		button.toggle_mode = true
		button.button_pressed = Net.bot_count == count
		button.add_theme_font_size_override(&"font_size", 26)
		counts.add_child(button)
	var note := _label("In a party, seats nobody takes are filled with AI - up to this many.", &"Subheading", 15)
	column.add_child(note)

	column.add_child(_skill_row())
	return column


func _skill_row() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	column.add_child(_label("DIFFICULTY", &"Display", 24))
	var skills := HBoxContainer.new()
	skills.add_theme_constant_override(&"separation", 14)
	column.add_child(skills)
	for skill in GameConfig.BOT_SKILL_NAMES.keys():
		var tile := _tile(Net.bot_skill == skill, Vector2(290, 150))
		tile.disabled = Net.bot_count == 0 and Net.mode != GameConfig.Mode.SLAP
		var box := _tile_box(tile)
		var name_label := _label(String(GameConfig.BOT_SKILL_NAMES[skill]).to_upper(), &"Display", 26)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(name_label)
		var blurb := _label(SKILL_BLURBS[skill], &"Value", 15)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(blurb)
		tile.pressed.connect(func() -> void:
			Net.set_bot_skill(skill)
			_set_step(2))
		skills.add_child(tile)
	return column


## A tap picks and moves on, the way a console menu does. The short delay
## is long enough to see the card go green, which is the confirmation.
func _advance_after_pick() -> void:
	Sfx.play(&"ui_select")
	var from := _step
	_set_step(from)
	get_tree().create_timer(0.22).timeout.connect(func() -> void:
		if _step == from and _page == Page.PLAY:
			_set_step(from + 1))


func _tile(selected: bool, min_size: Vector2) -> Button:
	var tile := Button.new()
	tile.theme_type_variation = &"TileButton"
	tile.toggle_mode = true
	tile.button_pressed = selected
	tile.custom_minimum_size = min_size
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.clip_contents = true
	return tile


func _tile_box(tile: Button) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 10)
	margin.add_child(box)
	tile.add_child(margin)
	return box


# --- Party ---------------------------------------------------------

func _build_party() -> Control:
	var root := _page_root("PARTY")
	_party_body = VBoxContainer.new()
	_party_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_party_body.offset_top = 110.0
	_party_body.offset_left = 40.0
	_party_body.offset_right = -40.0
	_party_body.offset_bottom = -30.0
	_party_body.add_theme_constant_override(&"separation", 16)
	root.add_child(_party_body)
	_ip_field = LineEdit.new()
	_ip_field.placeholder_text = "Host IP, e.g. 192.168.1.20"
	_ip_field.custom_minimum_size = Vector2(0, 64)
	_ip_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hosts_list = VBoxContainer.new()
	_hosts_list.add_theme_constant_override(&"separation", 8)
	return root


func _refresh_party() -> void:
	# The field and the host list survive rebuilds so a half-typed address
	# is not wiped every time a beacon arrives.
	for keep in [_ip_field, _hosts_list]:
		if keep.get_parent() != null:
			keep.get_parent().remove_child(keep)
	for child in _party_body.get_children():
		child.queue_free()
	if Net.is_online():
		_build_room()
	else:
		_build_party_choice()


func _build_party_choice() -> void:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override(&"separation", 24)
	_party_body.add_child(row)

	var host := PanelContainer.new()
	host.theme_type_variation = &"Glass"
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(host)
	var host_box := VBoxContainer.new()
	host_box.add_theme_constant_override(&"separation", 14)
	host.add_child(host_box)
	host_box.add_child(_label("HOST A ROOM", &"Display", 32))
	var host_blurb := _label("Friends on the same wifi join your room. Seats nobody takes are filled with AI when you start.", &"Value", 17)
	host_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host_box.add_child(host_blurb)
	var preview := HBoxContainer.new()
	preview.alignment = BoxContainer.ALIGNMENT_CENTER
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.add_theme_constant_override(&"separation", 6)
	host_box.add_child(preview)
	for i in GameConfig.NET_MAX_PLAYERS:
		var seat := MonkeyStage.new()
		seat.pixel_scale = 3
		seat.rim = GameConfig.tint_for_index(i)
		seat.custom_minimum_size = Vector2(120, 160)
		seat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		preview.add_child(seat)
		seat.set_monkey(Net.local_monkey, i > 0)
	host_box.add_child(_button("HOST", &"GoButton", Vector2(0, 90), _on_host))

	var join := PanelContainer.new()
	join.theme_type_variation = &"Glass"
	join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(join)
	var join_box := VBoxContainer.new()
	join_box.add_theme_constant_override(&"separation", 12)
	join.add_child(join_box)
	join_box.add_child(_label("JOIN A ROOM", &"Display", 32))
	join_box.add_child(_label("ROOMS NEARBY", &"Subheading", 15))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	join_box.add_child(scroll)
	_hosts_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_hosts_list)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override(&"separation", 10)
	join_box.add_child(join_row)
	join_row.add_child(_ip_field)
	join_row.add_child(_button("JOIN", &"NavButton", Vector2(150, 64), _on_join_typed))
	_refresh_hosts()


func _build_room() -> void:
	var seats := HBoxContainer.new()
	seats.alignment = BoxContainer.ALIGNMENT_CENTER
	seats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	seats.add_theme_constant_override(&"separation", 18)
	_party_body.add_child(seats)
	var people: Array = []
	for id in Net.roster.keys():
		if int(id) > 0:
			people.append(int(id))
	people.sort()
	for id in people:
		var tag := "YOU" if id == Net.local_id() else ("HOST" if id == 1 else "FRIEND")
		seats.add_child(_seat_card(Net.roster[id]["monkey"], tag, 5, GameConfig.tint_for_index(int(Net.roster[id]["slot"]))))
	var ai := mini(Net.bot_count, GameConfig.NET_MAX_PLAYERS - people.size())
	for i in GameConfig.NET_MAX_PLAYERS - people.size():
		seats.add_child(_seat_card(&"", "AI" if i < ai else "OPEN", 5, Color(1, 1, 1, 0.3)))

	var info := _label("", &"Value", 17)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if Net.is_host():
		info.text = "Room open on %s. Friends on the same wifi see it under Join.%s" % [
			Net.local_ip_hint(), "\n" + _public_address if not _public_address.is_empty() else ""]
	else:
		info.text = "In the room. The host picks the match and starts it."
	_party_body.add_child(info)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 16)
	_party_body.add_child(buttons)
	buttons.add_child(_button("LEAVE", &"DangerButton", Vector2(200, 80), _on_leave))
	if Net.is_host():
		var internet := _button("OPEN TO INTERNET", &"QuietButton", Vector2(280, 80), _on_open_to_internet)
		internet.disabled = PortMap.busy
		buttons.add_child(internet)
		buttons.add_child(_button("MATCH SETUP", &"NavButton", Vector2(240, 80), _show.bind(Page.PLAY)))
		buttons.add_child(_button("START", &"PlayButton", Vector2(240, 80), _on_play))


func _seat_card(monkey: StringName, tag: String, pixel: int, rim: Color) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Glass"
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(box)
	var stage := MonkeyStage.new()
	stage.pixel_scale = pixel
	stage.rim = rim
	stage.custom_minimum_size = Vector2(pixel * 34, pixel * 40)
	box.add_child(stage)
	if monkey != &"":
		stage.set_monkey(monkey)
		box.add_child(_centered(GameConfig.get_monkey(monkey).display_name.to_upper(), &"Display", 20))
	else:
		box.add_child(_centered("?", &"DisplayBig", 40))
	var tag_label := _centered(tag, &"Heading", 16)
	box.add_child(tag_label)
	return card


func _refresh_hosts() -> void:
	if _hosts_list == null:
		return
	for child in _hosts_list.get_children():
		child.queue_free()
	if Discovery.hosts.is_empty():
		var empty := _label("Looking for rooms on this wifi... Type an IP if none show up.", &"Subheading", 15)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_hosts_list.add_child(empty)
		return
	for ip in Discovery.hosts.keys():
		var entry: Dictionary = Discovery.hosts[ip]
		var text := "%s   %d IN ROOM   %s" % [ip, int(entry["players"]), String(entry["mode"]).to_upper()]
		_hosts_list.add_child(_button(text, &"QuietButton", Vector2(0, 64), _join_address.bind(String(ip), int(entry["port"]))))


func _on_host() -> void:
	var error := Net.host_game()
	if error.is_empty():
		Discovery.start_advertising()
		toast("Room open. Waiting for friends.")
	else:
		toast(error)
	_refresh()


func _on_join_typed() -> void:
	var address := _ip_field.text.strip_edges()
	if address.is_empty():
		_deny("Type the host's IP, or tap a room in the list.")
		return
	_join_address(address, GameConfig.NET_DEFAULT_PORT)


func _join_address(address: String, port: int) -> void:
	var error := Net.join_game(address, port)
	toast("Joining %s..." % address if error.is_empty() else error)
	_refresh()


func _on_leave() -> void:
	Net.leave()
	PortMap.close()
	_public_address = ""
	Discovery.stop_advertising()
	Discovery.start_listening()
	toast("Left the room.")
	_refresh()


## Optional and host only. It fails on plenty of networks by design, so the
## menu says what happened instead of pretending it worked.
func _on_open_to_internet() -> void:
	_public_address = "Asking the router..."
	PortMap.try_open(GameConfig.NET_DEFAULT_PORT)
	_refresh()


func _on_port_mapped(address: String, error: String) -> void:
	if error.is_empty():
		_public_address = "Open to the internet: friends elsewhere join %s" % address
	else:
		_public_address = error
		toast("Could not open the port. See docs/MULTIPLAYER.md.")
	_refresh()


# --- Shop ----------------------------------------------------------

func _build_shop() -> Control:
	var root := _page_root("SHOP")
	var card := PanelContainer.new()
	card.theme_type_variation = &"Glass"
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.offset_top = 40.0
	card.custom_minimum_size = Vector2(760, 0)
	root.add_child(card)
	var box := VBoxContainer.new()
	box.name = "ShopBox"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 12)
	card.add_child(box)
	return root


func _refresh_shop() -> void:
	var box := _pages[Page.SHOP].find_child("ShopBox", true, false) as VBoxContainer
	for child in box.get_children():
		child.queue_free()
	var owned := Purchases.has_premium()
	box.add_child(_centered("PREMIUM PACK", &"DisplayBig", 48))
	var monkeys := HBoxContainer.new()
	monkeys.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(monkeys)
	for id in GameConfig.PREMIUM_MONKEYS:
		var stage := MonkeyStage.new()
		stage.pixel_scale = 6
		stage.custom_minimum_size = Vector2(220, 270)
		monkeys.add_child(stage)
		stage.set_monkey(id, not owned)
	var names: PackedStringArray = []
	for id in GameConfig.PREMIUM_MONKEYS:
		names.append(GameConfig.get_monkey(id).display_name.to_upper())
	var hats: PackedStringArray = []
	for id in GameConfig.hat_ids():
		var hat: Dictionary = GameConfig.get_hat(id)
		if bool(hat.get("premium", false)):
			hats.append(String(hat["name"]).to_upper())
	var detail := "%s%s" % [", ".join(names), ("  +  HATS: " + ", ".join(hats)) if not hats.is_empty() else ""]
	box.add_child(_centered(detail, &"Value", 18))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 14)
	box.add_child(buttons)
	var buy := _button("OWNED" if owned else "UNLOCK", &"PlayButton", Vector2(320, 96), func() -> void: Purchases.buy_premium())
	buy.disabled = owned
	buttons.add_child(buy)
	buttons.add_child(_button("RESTORE", &"QuietButton", Vector2(200, 96), func() -> void: Purchases.restore()))


func _on_purchase_finished(success: bool, message: String) -> void:
	toast("Premium unlocked!" if success else "Purchase did not complete: %s" % message)
	_refresh()


# --- Settings and controls -----------------------------------------

func _build_settings() -> Control:
	var root := _page_root("SETTINGS")
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_top = 104.0
	row.offset_left = 30.0
	row.offset_right = -30.0
	row.offset_bottom = -24.0
	row.add_theme_constant_override(&"separation", 20)
	root.add_child(row)

	var left := PanelContainer.new()
	left.theme_type_variation = &"Glass"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override(&"separation", 10)
	left.add_child(left_box)
	left_box.add_child(_label("KEYBOARD", &"Display", 28))
	for pair in KEYS:
		left_box.add_child(_key_row(pair[0], pair[1]))
	left_box.add_child(_label("VOLUME", &"Display", 24))
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = Sfx.get_volume()
	volume.custom_minimum_size = Vector2(0, 40)
	volume.value_changed.connect(func(value: float) -> void:
		Sfx.set_volume(value)
		Profile.set_stat("volume", value))
	volume.drag_ended.connect(func(_changed: bool) -> void: Sfx.play(&"ui_select"))
	left_box.add_child(volume)

	var right := PanelContainer.new()
	right.theme_type_variation = &"Glass"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var right_box := VBoxContainer.new()
	right_box.add_theme_constant_override(&"separation", 10)
	right.add_child(right_box)
	right_box.add_child(_label("TOUCH", &"Display", 28))
	for pair in TOUCH:
		right_box.add_child(_key_row(pair[0], pair[1]))
	right_box.add_child(_label("MOVES", &"Display", 24))
	var tips := _label("Jump into a vine to swing. Push left and right to pump, jump to let go - release at the bottom for the most speed.\nClimb any wall with ivy on it: hold jump or push up. To wall-jump, push away from the wall and jump. Springs throw you high. Every slap in 2v2 adds to your damage number: the higher it is, the further the next slap sends you.", &"Value", 16)
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_box.add_child(tips)
	return root


## One control, as a key chip and what it does.
func _key_row(key: String, action: String) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 14)
	var chip := PanelContainer.new()
	var chip_box := StyleBoxFlat.new()
	chip_box.bg_color = Color(0.94, 0.95, 0.92)
	chip_box.border_color = Color(0.13, 0.11, 0.10)
	chip_box.set_border_width_all(2)
	chip_box.border_width_bottom = 5
	chip_box.set_corner_radius_all(8)
	chip_box.set_content_margin_all(6)
	chip_box.content_margin_left = 12
	chip_box.content_margin_right = 12
	chip.add_theme_stylebox_override(&"panel", chip_box)
	chip.custom_minimum_size = Vector2(170, 0)
	var key_label := _label(key, &"Value", 15)
	key_label.add_theme_color_override(&"font_color", UiTheme.INK_DARK)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(key_label)
	line.add_child(chip)
	var what := _label(action.to_upper(), &"Value", 15)
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(what)
	return line


# --- Refresh -------------------------------------------------------

func _refresh() -> void:
	if not is_inside_tree():
		return
	_refresh_home()
	match _page:
		Page.MONKEYS:
			_refresh_pick_button()
		Page.PARTY:
			_refresh_party()
		Page.SHOP:
			_refresh_shop()


# --- Small builders ------------------------------------------------

func toast(text: String) -> void:
	_toast.text = text.to_upper()
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


func _deny(text: String) -> void:
	Sfx.play(&"ui_deny")
	toast(text)


func _button(text: String, variation: StringName, min_size: Vector2, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.custom_minimum_size = min_size
	button.pressed.connect(on_pressed)
	return button


func _arrow(text: String, on_pressed: Callable, min_size: Vector2 = Vector2(76, 100)) -> Button:
	var button := _button("", &"QuietButton", min_size, on_pressed)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon := ArrowIcon.new()
	icon.left = text == "<"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_bottom = -6.0
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	return button


func _label(text: String, variation: StringName, font_size: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font_size > 0:
		label.add_theme_font_size_override(&"font_size", font_size)
	return label


func _centered(text: String, variation: StringName, font_size: int = 0) -> Label:
	var label := _label(text, variation, font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _portrait(id: StringName, edge: int) -> TextureRect:
	var face := TextureRect.new()
	face.texture = MonkeyPortrait.texture(id)
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.custom_minimum_size = Vector2(edge, edge)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return face


func _skill_name(stats: MonkeyStats) -> String:
	if stats.skill_id == &"":
		return "NONE"
	return String(stats.skill_id).replace("_", " ").to_upper()


## Small drawn icons for buttons and the top bar. Chunky shapes with a dark
## outline, readable at thumb size, no icon font or texture needed.
class Glyph extends Control:
	var kind: StringName = &"monkey"

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var ink := Color8(33, 28, 26)
		match kind:
			&"monkey":
				for side in [-1.0, 1.0]:
					draw_circle(c + Vector2(side * r * 0.72, -r * 0.05), r * 0.3, ink)
					draw_circle(c + Vector2(side * r * 0.72, -r * 0.05), r * 0.2, Color8(214, 158, 142))
				draw_circle(c, r * 0.72, ink)
				draw_circle(c, r * 0.62, Color8(150, 106, 64))
				draw_circle(c + Vector2(0, r * 0.14), r * 0.44, Color8(236, 200, 170))
				for side in [-1.0, 1.0]:
					draw_circle(c + Vector2(side * r * 0.2, -r * 0.08), r * 0.08, ink)
			&"party":
				for i in 3:
					var at := c + Vector2((i - 1) * r * 0.62, (0.12 if i == 1 else 0.24) * r)
					draw_circle(at + Vector2(0, -r * 0.35), r * 0.26, ink)
					draw_circle(at + Vector2(0, -r * 0.35), r * 0.19, Color.WHITE)
					draw_circle(at + Vector2(0, r * 0.3), r * 0.36, ink)
					draw_circle(at + Vector2(0, r * 0.3), r * 0.28, Color.WHITE)
			&"cart":
				draw_rect(Rect2(c + Vector2(-r * 0.7, -r * 0.45), Vector2(r * 1.4, r * 0.8)), ink)
				draw_rect(Rect2(c + Vector2(-r * 0.58, -r * 0.33), Vector2(r * 1.16, r * 0.56)), Color.WHITE)
				draw_line(c + Vector2(-r * 0.95, -r * 0.7), c + Vector2(-r * 0.7, -r * 0.45), ink, r * 0.14)
				for side in [-1.0, 1.0]:
					draw_circle(c + Vector2(side * r * 0.42, r * 0.58), r * 0.17, ink)
			&"pad":
				draw_rect(Rect2(c + Vector2(-r * 0.9, -r * 0.45), Vector2(r * 1.8, r * 0.95)), ink)
				draw_rect(Rect2(c + Vector2(-r * 0.78, -r * 0.33), Vector2(r * 1.56, r * 0.71)), Color.WHITE)
				draw_rect(Rect2(c + Vector2(-r * 0.58, -r * 0.08), Vector2(r * 0.42, r * 0.14)), ink)
				draw_rect(Rect2(c + Vector2(-r * 0.44, -r * 0.22), Vector2(r * 0.14, r * 0.42)), ink)
				draw_circle(c + Vector2(r * 0.4, -r * 0.08), r * 0.1, Color8(240, 77, 96))
				draw_circle(c + Vector2(r * 0.58, r * 0.1), r * 0.1, Color8(62, 173, 229))
			&"cog":
				var points := PackedVector2Array()
				for i in 16:
					var rad := r * (0.95 if i % 2 == 0 else 0.72)
					points.append(c + Vector2.from_angle(TAU * i / 16.0) * rad)
				draw_colored_polygon(points, ink)
				draw_circle(c, r * 0.36, Color(0.9, 0.9, 0.88))
				draw_circle(c, r * 0.18, ink)
			&"banana":
				var arc := PackedVector2Array()
				for i in 9:
					var a := lerpf(0.2, 2.6, i / 8.0)
					arc.append(c + Vector2(cos(a) * r * 0.75, sin(a) * r * 0.75 - r * 0.35))
				draw_polyline(arc, ink, r * 0.5, true)
				draw_polyline(arc, Color8(255, 214, 40), r * 0.32, true)
			&"badge":
				draw_circle(c, r, ink)
				draw_circle(c, r * 0.8, Color8(240, 60, 70))
				draw_rect(Rect2(c + Vector2(-r * 0.12, -r * 0.5), Vector2(r * 0.24, r * 0.6)), Color.WHITE)
				draw_rect(Rect2(c + Vector2(-r * 0.12, r * 0.22), Vector2(r * 0.24, r * 0.22)), Color.WHITE)


class ArrowIcon extends Control:
	var left: bool = false

	func _draw() -> void:
		var c := size * 0.5
		var s := minf(size.x, size.y) * 0.24
		var d := -1.0 if left else 1.0
		var points := PackedVector2Array([c + Vector2(d * s, 0), c + Vector2(-d * s * 0.7, -s), c + Vector2(-d * s * 0.7, s)])
		draw_colored_polygon(points, UiTheme.INK_DARK)


## A mode drawn as a picture: a flag for a race, a banana bunch for the
## hoard, a vine for free play. Big shapes, readable from a thumbnail.
class ModeIcon extends Control:
	var mode: int = 0
	var colour: Color = Color.WHITE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.42
		draw_circle(c + Vector2(0, 5), r, Color(0, 0, 0, 0.3))
		draw_circle(c, r, colour.darkened(0.35))
		draw_circle(c, r * 0.9, colour)
		var ink := Color8(30, 26, 24)
		match mode:
			GameConfig.Mode.RACE:
				draw_rect(Rect2(c + Vector2(-r * 0.35, -r * 0.6), Vector2(r * 0.1, r * 1.25)), ink)
				for row in 3:
					for col in 4:
						var cell := Rect2(c + Vector2(-r * 0.25 + col * r * 0.16, -r * 0.6 + row * r * 0.16), Vector2(r * 0.16, r * 0.16))
						draw_rect(cell, ink if (row + col) % 2 == 0 else Color.WHITE)
			GameConfig.Mode.SLAP:
				# A palm and three motion lines: the slap, mid-swing.
				var palm := c + Vector2(r * 0.12, r * 0.05)
				draw_circle(palm, r * 0.34, ink)
				draw_circle(palm, r * 0.27, Color8(240, 200, 160))
				for i in 4:
					var finger := palm + Vector2(-r * 0.2 + i * r * 0.14, -r * 0.34)
					draw_line(finger, finger + Vector2(0, -r * 0.24), ink, r * 0.13)
					draw_line(finger, finger + Vector2(0, -r * 0.22), Color8(240, 200, 160), r * 0.07)
				for i in 3:
					var y := palm.y - r * 0.2 + i * r * 0.22
					draw_line(Vector2(c.x - r * 0.72, y), Vector2(c.x - r * 0.4, y), Color.WHITE, r * 0.08)
			GameConfig.Mode.HOARD:
				for i in 3:
					var a := -0.6 + i * 0.6
					var tip := c + Vector2.from_angle(a - PI * 0.5) * r * 0.62
					draw_line(c + Vector2(0, r * 0.35), tip, ink, r * 0.3)
					draw_line(c + Vector2(0, r * 0.35), tip, Color8(250, 220, 60), r * 0.2)
			_:
				var points := PackedVector2Array()
				for i in 12:
					var t := float(i) / 11.0
					points.append(c + Vector2(sin(t * PI * 2.0) * r * 0.2, -r * 0.7 + t * r * 1.3))
				draw_polyline(points, ink, r * 0.16)
				draw_polyline(points, Color8(92, 170, 78), r * 0.09)
