extends Control

## Preloaded rather than used by class name, so a fresh checkout runs before
## the editor has rebuilt its class list.
const RankBadgeUI = preload("res://scripts/ui/RankBadge.gd")
const BananaIconUI = preload("res://scripts/ui/BananaIcon.gd")
const ItemPreviewUI = preload("res://scripts/ui/ItemPreview.gd")

# ============================================================
# MENU - the home screen and everything one tap away from it.
#
# Low-detail branch: Title, Lobby and Hero select follow the Primate Rush
# mock boards (title screen, solo lobby, hero select).
#
# Built like a phone game, not a settings page. Home is your monkey, big,
# on a stage, with the PLAY button where a right thumb rests and the match
# it will start written on the card above it. Everything else is a page you
# visit and come back from:
#
#   MONKEYS  swipe through the roster with arrows, pick one, pick a hat
#   PLAY     CLASSIC or RANKED: searches the network for players first and
#            fills the empty seats with AI when nobody turns up
#   SETUP    (the match card) mode, then map, then opponents
#   PARTY    host or join a room; seats nobody takes are filled with AI
#   SHOP     the premium unlock
#
# Built in code, like the theme and the old lobby before it: a sixth monkey
# or a third map is a dictionary entry, never a .tscn edit.
# ============================================================

# SETTINGS is last so the capture tool's page numbers stay put.
enum Page { HOME, MONKEYS, PLAY, PARTY, SHOP, SETTINGS, STYLE, RANKS }

## What every key does, in the order a new player needs them.
const KEYS: Array = [
	["A  D", "Move"], ["SPACE", "Tap to jump, again in the air to double jump"],
	["RIGHT CLICK  or  L", "Hold to grab and swing. Let go to release"],
	["W  S", "Climb up / down, pull the arm in / out"],
	["S  or  DOWN", "Drop through a platform. Slide when running fast"],
	["LEFT CLICK  or  J", "Punch"], ["E  or  K", "Monkey skill"], ["ESC", "Pause"],
]
const TOUCH: Array = [
	["LEFT THUMB", "Drag anywhere on the left half: move and climb"],
	["STICK DOWN", "Drop through a platform"],
	["JUMP", "Tap to jump; tap again in the air to double jump"],
	["GRAB", "Hold to grab anything in reach and swing. Let go to release"],
	["PUNCH", "Punch"], ["SKILL", "Monkey skill (the ring shows the cooldown)"],
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
	GameConfig.Mode.HOARD: "First to 30 bananas wins. Race for the few that spawn, or hit a carrier to steal one.",
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

## Mock names for the modes on the title card and lobby.
const MOCK_MODE_NAMES: Dictionary = {
	GameConfig.Mode.HOARD: "BANANA RUSH",
	GameConfig.Mode.RACE: "RACE",
	GameConfig.Mode.SLAP: "2V2 SLAP",
	GameConfig.Mode.FREE_PLAY: "FREE PLAY",
}
const MOCK_MODE_SHORT: Dictionary = {
	GameConfig.Mode.HOARD: "BANANA",
	GameConfig.Mode.RACE: "RACE",
	GameConfig.Mode.SLAP: "2V2",
	GameConfig.Mode.FREE_PLAY: "FREE",
}
const MockGround = preload("res://scripts/ui/MockGround.gd")
const AbilityPreview = preload("res://scripts/ui/AbilityPreview.gd")
const SkillFx = preload("res://scripts/player/SkillFx.gd")
const MonkeySkins = preload("res://scripts/player/MonkeySkins.gd")
const Matchmaker = preload("res://scripts/ui/Matchmaker.gd")

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
var _rank_name: Label
var _setup_card: Button
var _setup_tag: Label
var _lineup: HBoxContainer
var _lineup_stages: Dictionary = {}
var _lineup_markers: Dictionary = {}
var _lineup_state: Dictionary = {}
var _hero_cards: Dictionary = {}
var _hero_stages: Dictionary = {}
var _lobby_title: Label
var _lobby_sub: Label
var _seat_grid: GridContainer
var _mode_buttons: Dictionary = {}
var _map_row: HBoxContainer
var _fill_toggle: Button
var _fill_note: Label
var _skill_buttons: Dictionary = {}
var _skill_note: Label
var _start_button: Button

# Matchmaking
var _mm: Node = null
var _queue_buttons: Dictionary = {}
var _search_layer: Control
var _search_title: Label
var _search_line: Label
var _search_timer: Label
var _search_status: Label
var _search_seats: HBoxContainer
var _search_box: VBoxContainer
var _stake_button: Button
var _stake_label: Label
var _effect_buttons: Dictionary = {}
var _home_rank_badge: RankBadgeUI
var _home_rank_name: Label
var _ranks_cards: Array = []
var _ranks_you: Label
var _ranks_bar: ProgressBar
var _ranks_note: Label
var _pick_box: VBoxContainer
var _pick_timer: Label
var _pick_buttons: Dictionary = {}
var _pick_ready: Button

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
var _preview: Node = null
var _detail_name: Label
var _detail_skill: Label
var _detail_desc: Label
var _detail_cd: Label
var _detail_icon: Control
var _style_stage: MonkeyStage
var _style_name: Label
var _skin_buttons: Dictionary = {}
var _fx_view: Control = null
var _fx_view_name: Label = null
var _fx_view_id: StringName = &"" 
var _style_hat_buttons: Dictionary = {}

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
	UiTheme.ensure(self)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())
	Sfx.play_music(&"lobby")
	if not GameConfig.is_unlocked(Net.local_monkey):
		Net.local_monkey = GameConfig.roster_ids()[0]
	# The saved look: this monkey's skin and the chosen accessory.
	Net.local_skin = Profile.skin_for(Net.local_monkey)
	Net.local_hat = Profile.accessory()
	if not GameConfig.is_skin_unlocked(Net.local_skin):
		Net.local_skin = &"natural"
	if not GameConfig.is_hat_unlocked(Net.local_hat):
		Net.local_hat = &"none"

	_pages[Page.HOME] = _build_home()
	_pages[Page.MONKEYS] = _build_monkeys()
	_pages[Page.PLAY] = _build_play()
	_pages[Page.PARTY] = _build_party()
	_pages[Page.SHOP] = _build_shop()
	_pages[Page.SETTINGS] = _build_settings()
	_pages[Page.STYLE] = _build_style()
	_pages[Page.RANKS] = _build_ranks()
	for page in _pages.values():
		add_child(page)

	_mm = Matchmaker.new()
	_mm.name = "Matchmaker"
	add_child(_mm)
	_mm.connect(&"changed", _refresh_search)
	_search_layer = _build_search()
	add_child(_search_layer)

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
	if _mm != null and _mm.call(&"is_active"):
		_cancel_search()
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
	_level_badge = _label("LV 1", &"Display", 14)
	_level_badge.add_theme_color_override(&"font_color", UiTheme.BANANA)
	name_row.add_child(_level_badge)
	name_row.add_child(_label("PLAYER", &"Display", 14))
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
	# Rank chip: your badge and division, and the way into the ranks screen.
	var rank_chip := _button("", &"QuietButton", Vector2(172, 66), _show.bind(Page.RANKS))
	var rank_row := HBoxContainer.new()
	rank_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rank_row.offset_left = 8.0
	rank_row.offset_right = -8.0
	rank_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rank_row.add_theme_constant_override(&"separation", 8)
	rank_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rank_chip.add_child(rank_row)
	_home_rank_badge = RankBadgeUI.new()
	_home_rank_badge.custom_minimum_size = Vector2(36, 44)
	rank_row.add_child(_home_rank_badge)
	_home_rank_name = _label("BRONZE III", &"Display", 10)
	_home_rank_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home_rank_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank_row.add_child(_home_rank_name)
	corner.add_child(rank_chip)
	var wallet := PanelContainer.new()
	wallet.theme_type_variation = &"Glass"
	var wallet_row := HBoxContainer.new()
	wallet_row.add_theme_constant_override(&"separation", 8)
	wallet.add_child(wallet_row)
	var banana := Glyph.new()
	banana.kind = &"banana"
	banana.custom_minimum_size = Vector2(34, 34)
	wallet_row.add_child(banana)
	_banana_count = _label("0", &"Display", 16)
	wallet_row.add_child(_banana_count)
	corner.add_child(wallet)
	var cog := _button("", &"QuietButton", Vector2(66, 66), _open_settings)
	cog.add_child(_glyph_fill(&"cog"))
	corner.add_child(cog)

	# No title on the lobby: the splash already said the name, and the top
	# centre is clearer empty.

	# Navigation, down the left edge where a left thumb reaches.
	var nav := VBoxContainer.new()
	nav.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	nav.grow_vertical = Control.GROW_DIRECTION_BOTH
	nav.offset_left = 24.0
	nav.add_theme_constant_override(&"separation", 14)
	nav.add_child(_nav_button("MONKEYS", &"monkey", &"NavButton", _show.bind(Page.MONKEYS)))
	nav.add_child(_nav_button("STYLE", &"hanger", &"NavButton", _show.bind(Page.STYLE)))
	nav.add_child(_nav_button("PARTY", &"party", &"NavButton", _show.bind(Page.PARTY)))
	var shop := _nav_button("SHOP", &"cart", &"DangerButton", _show.bind(Page.SHOP))
	_shop_badge = Glyph.new()
	_shop_badge.kind = &"badge"
	_shop_badge.size = Vector2(30, 30)
	_shop_badge.position = Vector2(206, -8)
	_shop_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop.add_child(_shop_badge)
	nav.add_child(shop)
	nav.add_child(_nav_button("GUIDE", &"pad", &"NavButton", _open_guide.bind("CONTROLS")))
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
	_home_name = _label("", &"Display", 26)
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
	# Ranked only: how many bananas you put on yourself. Tap to raise it.
	_stake_button = _button("", &"ChoiceButton", Vector2(0, 54), _cycle_stake)
	var stake_row := HBoxContainer.new()
	stake_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stake_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stake_row.add_theme_constant_override(&"separation", 10)
	stake_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stake_button.add_child(stake_row)
	var stake_icon := BananaIconUI.new()
	stake_icon.custom_minimum_size = Vector2(34, 28)
	stake_row.add_child(stake_icon)
	_stake_label = _label("", &"Display", 14)
	_stake_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stake_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stake_row.add_child(_stake_label)
	play_column.add_child(_stake_button)
	var queue_row := HBoxContainer.new()
	queue_row.add_theme_constant_override(&"separation", 8)
	play_column.add_child(queue_row)
	for q in [GameConfig.Queue.CLASSIC, GameConfig.Queue.RANKED]:
		var qb := _button(String(GameConfig.QUEUE_NAMES[q]).to_upper(), &"ChoiceButton", Vector2(0, 58), _set_queue.bind(q))
		qb.toggle_mode = true
		qb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		queue_row.add_child(qb)
		_queue_buttons[q] = qb
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
	var card_mode := _label("", &"Display", 17)
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


func _xp(min_size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = min_size
	bar.max_value = 1.0
	var back := StyleBoxFlat.new()
	back.bg_color = UiTheme.NAVY_BTN
	bar.add_theme_stylebox_override(&"background", back)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.BANANA
	bar.add_theme_stylebox_override(&"fill", fill)
	return bar


## Rank from level: three divisions per tier, like the mock's BRONZE II.
func _rank_for(level: int) -> String:
	var tiers := ["BRONZE", "SILVER", "GOLD", "JUNGLE"]
	var tier := mini((level - 1) / 3, tiers.size() - 1)
	var division := 3 - ((level - 1) % 3)
	return "%s %s" % [tiers[tier], ["I", "II", "III"][division - 1]]


func _pick_lineup(id: StringName) -> void:
	if not GameConfig.is_unlocked(id):
		_deny("%s comes with the premium unlock." % GameConfig.get_monkey(id).display_name)
		return
	Sfx.play(&"ui_select")
	_pick_monkey(id)


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
	var label := _label(text, &"Display", 15)
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
	if Net.is_online() and not Net.is_host():
		_deny("Waiting for the host to start.")
		return
	if Net.queue == GameConfig.Queue.RANKED and not GameConfig.RANKED_MODES.has(Net.mode):
		_set_lobby_mode(GameConfig.Mode.SLAP)
	# No searching the network for strangers: playing with friends goes
	# through the CONNECT tab. PLAY goes straight to the monkey pick, with
	# AI in every empty seat (and any friends already in your room).
	# Matchmaker.begin() still exists for when online matchmaking returns.
	_mm.call(&"start_now")
	_refresh_search()


## Next stake up the ladder, skipping what you cannot afford.
func _cycle_stake() -> void:
	var options: Array[int] = []
	for amount in Loot.STAKES:
		if amount <= Loot.bananas:
			options.append(amount)
	var at := options.find(Loot.stake)
	Loot.set_stake(options[(at + 1) % options.size()])
	Sfx.play(&"ui_select")
	if Loot.stake > 0:
		toast("Stake %d: 1st x3, 2nd x1.5, 3rd x0.5, 4th loses it" % Loot.stake)
	_refresh()


func _set_queue(q: int) -> void:
	Sfx.play(&"ui_select")
	if Net.is_online() and not Net.is_host():
		_deny("The host picks the match.")
		_refresh()
		return
	Net.set_queue(q)
	if q == GameConfig.Queue.RANKED and not GameConfig.RANKED_MODES.has(Net.mode):
		# Free play has nobody to rank against.
		_set_lobby_mode(GameConfig.Mode.SLAP)
	_refresh()


func _cancel_search() -> void:
	_mm.call(&"cancel")
	Sfx.play(&"ui_back")
	_refresh_search()
	_refresh()


# --- Ranks ---------------------------------------------------------

## Every rank from Bronze to Apex with the points each starts at, which one
## you are in, how far to the next division, and what each finishing place
## is worth in a ranked match.
func _build_ranks() -> Control:
	var root := _page_root("RANKS")
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_top = 112.0
	column.offset_left = 40.0
	column.offset_right = -40.0
	column.offset_bottom = -24.0
	column.add_theme_constant_override(&"separation", 16)
	root.add_child(column)

	var ladder := HBoxContainer.new()
	ladder.alignment = BoxContainer.ALIGNMENT_CENTER
	ladder.add_theme_constant_override(&"separation", 14)
	column.add_child(ladder)
	for index in GameConfig.RANK_TIERS.size():
		var card := PanelContainer.new()
		card.theme_type_variation = &"Glass"
		card.custom_minimum_size = Vector2(200, 250)
		ladder.add_child(card)
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override(&"separation", 8)
		card.add_child(box)
		var badge := RankBadgeUI.new()
		badge.custom_minimum_size = Vector2(96, 112)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		badge.set_rank(index, -1 if index == GameConfig.RANK_TIERS.size() - 1 else 2)
		box.add_child(badge)
		box.add_child(_centered(String(GameConfig.RANK_TIERS[index][0]), &"Display", 18))
		var from := int(GameConfig.RANK_TIERS[index][1])
		var note := _centered("%d+ RP" % from if index < GameConfig.RANK_TIERS.size() - 1 else "%d+ RP  TOP" % from, &"Subheading", 14)
		box.add_child(note)
		var you := _centered("", &"Display", 14)
		you.add_theme_color_override(&"font_color", UiTheme.BANANA)
		box.add_child(you)
		_ranks_cards.append({"card": card, "badge": badge, "you": you})

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override(&"separation", 18)
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(bottom)

	var mine := PanelContainer.new()
	mine.theme_type_variation = &"Glass"
	mine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(mine)
	var mine_box := VBoxContainer.new()
	mine_box.alignment = BoxContainer.ALIGNMENT_CENTER
	mine_box.add_theme_constant_override(&"separation", 10)
	mine.add_child(mine_box)
	_ranks_you = _label("", &"Display", 22)
	mine_box.add_child(_ranks_you)
	_ranks_bar = ProgressBar.new()
	_ranks_bar.show_percentage = false
	_ranks_bar.max_value = 1.0
	_ranks_bar.custom_minimum_size = Vector2(0, 18)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.BANANA
	_ranks_bar.add_theme_stylebox_override(&"fill", fill)
	mine_box.add_child(_ranks_bar)
	_ranks_note = _label("", &"Body", 16)
	mine_box.add_child(_ranks_note)

	var table := PanelContainer.new()
	table.theme_type_variation = &"Glass"
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(table)
	var table_box := VBoxContainer.new()
	table_box.add_theme_constant_override(&"separation", 6)
	table.add_child(table_box)
	table_box.add_child(_label("RANKED POINTS PER PLACE", &"Display", 16))
	var places := GameConfig.ranked_placement_table()
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	table_box.add_child(row)
	var medal_colors := [UiTheme.BANANA, Color8(214, 222, 240), Color8(214, 150, 90), UiTheme.INK_DIM]
	for i in places.size():
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var place := _centered("%d%s" % [i + 1, ["ST", "ND", "RD", "TH"][mini(i, 3)]], &"Display", 18)
		place.add_theme_color_override(&"font_color", medal_colors[mini(i, 3)])
		cell.add_child(place)
		var delta := int(places[i])
		var points := _centered("%+d RP" % delta, &"Display", 14)
		points.add_theme_color_override(&"font_color", UiTheme.LEAF if delta > 0 else (UiTheme.CORAL if delta < 0 else UiTheme.INK))
		cell.add_child(points)
		row.add_child(cell)
	table_box.add_child(_label("2V2 SLAP:  WIN +25   LOSS -12   DRAW 0", &"Body", 15))
	table_box.add_child(_label("Only RANKED matches move your rank. It never drops below 0.", &"Body", 14))
	return root


func _refresh_ranks() -> void:
	var rp := int(Profile.get_stat("rp", 0))
	var rank: Dictionary = GameConfig.rank_for(rp)
	var current := int(rank["tier"])
	for index in _ranks_cards.size():
		var entry: Dictionary = _ranks_cards[index]
		var badge := entry["badge"] as RankBadgeUI
		badge.dim = index > current
		badge.set_rank(index, int(rank["division"]) if index == current else (-1 if index == _ranks_cards.size() - 1 else 2))
		(entry["you"] as Label).text = "YOU ARE HERE" if index == current else ("DONE" if index < current else "")
		(entry["card"] as Control).modulate = Color.WHITE if index <= current else Color(0.75, 0.75, 0.75)
	_ranks_you.text = "%s   %d RP" % [String(rank["name"]), rp]
	_ranks_bar.value = float(rank["progress"])
	var played := int(Profile.get_stat("ranked_matches", 0))
	if int(rank["next"]) < 0:
		_ranks_note.text = "Top rank. %d ranked %s played." % [played, "match" if played == 1 else "matches"]
	else:
		_ranks_note.text = "%d RP to the next division.  %d ranked %s played." % [int(rank["next"]) - rp, played, "match" if played == 1 else "matches"]


# --- Search overlay ------------------------------------------------

## The monkey pick: ten seconds after the room is settled, every owned
## monkey on one row. Whatever is picked when the clock hits zero plays.
func _build_pick() -> VBoxContainer:
	_pick_box = VBoxContainer.new()
	_pick_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_pick_box.add_theme_constant_override(&"separation", 14)
	_pick_box.visible = false
	_pick_box.add_child(_centered("PICK YOUR MONKEY", &"DisplayBig", 30))
	_pick_timer = _centered("10", &"DisplayBig", 44)
	_pick_timer.add_theme_color_override(&"font_color", UiTheme.BANANA)
	_pick_box.add_child(_pick_timer)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 10)
	_pick_box.add_child(row)
	for id in GameConfig.roster_ids():
		var b := _button("", &"ChoiceButton", Vector2(118, 150), _on_pick_press.bind(id))
		b.toggle_mode = true
		var inside := VBoxContainer.new()
		inside.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inside.alignment = BoxContainer.ALIGNMENT_CENTER
		inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(inside)
		var face := TextureRect.new()
		face.texture = MonkeyPortrait.texture(id)
		face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.custom_minimum_size = Vector2(0, 84)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not GameConfig.is_unlocked(id):
			face.modulate = Color(0.3, 0.3, 0.3)
		inside.add_child(face)
		var caption := _centered(GameConfig.get_monkey(id).display_name.to_upper(), &"Display", 10)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inside.add_child(caption)
		row.add_child(b)
		_pick_buttons[id] = b
	var ready_row := HBoxContainer.new()
	ready_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_pick_box.add_child(ready_row)
	_pick_ready = _button("READY", &"PrimaryButton", Vector2(240, 64), _on_pick_ready)
	ready_row.add_child(_pick_ready)
	return _pick_box


func _on_pick_press(id: StringName) -> void:
	if not GameConfig.is_unlocked(id):
		_deny("%s is locked." % GameConfig.get_monkey(id).display_name)
		_refresh_pick()
		return
	if _pick_ready.disabled:
		_refresh_pick()
		return
	Sfx.play(&"ui_select")
	_pick_monkey(id)
	_refresh_pick()


## Locks your pick. Solo, it also ends the countdown, since nobody else is
## choosing.
func _on_pick_ready() -> void:
	Sfx.play(&"ui_select")
	_pick_ready.disabled = true
	_pick_ready.text = "LOCKED IN"
	if not Net.is_online() or _mm.call(&"people") <= 1:
		_mm.call(&"finish_pick")
	_refresh_pick()


func _refresh_pick() -> void:
	_pick_timer.text = str(ceili(float(_mm.get(&"pick_left"))))
	for key in _pick_buttons.keys():
		var b := _pick_buttons[key] as Button
		b.set_pressed_no_signal(key == Net.local_monkey)
		b.modulate = Color.WHITE if GameConfig.is_unlocked(key) else Color(0.55, 0.55, 0.55)


func _build_search() -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 20
	layer.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.08, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"Glass"
	card.custom_minimum_size = Vector2(620, 0)
	center.add_child(card)
	var stack := VBoxContainer.new()
	card.add_child(stack)
	stack.add_child(_build_pick())
	var box := VBoxContainer.new()
	_search_box = box
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 16)
	stack.add_child(box)
	_search_title = _centered("SEARCHING", &"DisplayBig", 30)
	box.add_child(_search_title)
	_search_line = _centered("", &"Display", 14)
	_search_line.add_theme_color_override(&"font_color", UiTheme.INK_DIM)
	box.add_child(_search_line)
	_search_seats = HBoxContainer.new()
	_search_seats.alignment = BoxContainer.ALIGNMENT_CENTER
	_search_seats.add_theme_constant_override(&"separation", 14)
	box.add_child(_search_seats)
	_search_timer = _centered("0:10", &"Display", 40)
	_search_timer.add_theme_color_override(&"font_color", UiTheme.BANANA)
	box.add_child(_search_timer)
	_search_status = _centered("", &"Body", 20)
	box.add_child(_search_status)
	var cancel_row := HBoxContainer.new()
	cancel_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(cancel_row)
	cancel_row.add_child(_button("CANCEL", &"DangerButton", Vector2(240, 72), _cancel_search))
	return layer


func _refresh_search() -> void:
	if _search_layer == null or _mm == null:
		return
	var active: bool = _mm.call(&"is_active")
	_search_layer.visible = active
	if not active:
		return
	var stage: int = _mm.get(&"stage")
	var picking := stage == Matchmaker.Stage.PICKING
	_pick_box.visible = picking
	_search_box.visible = not picking
	if picking:
		_refresh_pick()
		return
	var found: int = _mm.call(&"people")
	_search_title.text = "MATCH FOUND" if stage == 5 else "SEARCHING"
	var map_name: String = GameConfig.MAP_NAMES.get(Net.map_id, String(Net.map_id))
	_search_line.text = "%s   %s   %s" % [String(GameConfig.QUEUE_NAMES[Net.queue]).to_upper(), String(MOCK_MODE_NAMES.get(Net.mode, "PLAY")), map_name.to_upper()]
	var left: float = _mm.get(&"time_left")
	# A client in someone else's room does not know the host's clock.
	var joined := stage == 2 or stage == 3
	_search_timer.text = "..." if joined else "0:%02d" % ceili(left)
	_search_status.text = "%s\n%d of %d players found. Empty seats are filled with AI." % [String(_mm.get(&"status")), found, GameConfig.NET_MAX_PLAYERS]
	if _search_seats.get_child_count() != GameConfig.NET_MAX_PLAYERS:
		for child in _search_seats.get_children():
			child.queue_free()
		for i in GameConfig.NET_MAX_PLAYERS:
			var seat := Panel.new()
			seat.custom_minimum_size = Vector2(64, 64)
			_search_seats.add_child(seat)
	var index := 0
	for seat in _search_seats.get_children():
		var box := StyleBoxFlat.new()
		var filled := index < found
		box.bg_color = UiTheme.LEAF if filled else UiTheme.PANEL_HI
		box.border_color = UiTheme.OUTLINE
		box.set_border_width_all(3)
		box.anti_aliasing = false
		(seat as Panel).add_theme_stylebox_override(&"panel", box)
		index += 1


func _refresh_home() -> void:
	var stats := GameConfig.get_monkey(Net.local_monkey)
	# The look picked on the Style page (skin and accessory) shows here too.
	if _home_stage.monkey_id != Net.local_monkey or _home_stage.skin_id != Net.local_skin or _home_stage.hat_id != Net.local_hat:
		_home_stage.set_monkey(Net.local_monkey, false, Net.local_skin, Net.local_hat)
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
	_banana_count.text = str(Loot.bananas)
	var rp := int(Profile.get_stat("rp", 0))
	_home_rank_badge.set_rp(rp)
	_home_rank_name.text = String(GameConfig.rank_for(rp)["name"])
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
	for q in _queue_buttons.keys():
		(_queue_buttons[q] as Button).set_pressed_no_signal(q == Net.queue)
	_stake_button.visible = Net.queue == GameConfig.Queue.RANKED
	if Loot.stake > Loot.bananas:
		Loot.set_stake(0)
	_stake_label.text = "STAKE  %d" % Loot.stake if Loot.stake > 0 else "NO STAKE  (TAP TO BET)"

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
	if Net.queue == GameConfig.Queue.RANKED:
		var rp := int(Profile.get_stat("rp", 0))
		var rank: Dictionary = GameConfig.rank_for(rp)
		return "%s   %d RP" % [rank["name"], rp]
	if Net.mode == GameConfig.Mode.SLAP:
		return "2v2   AI %s" % GameConfig.BOT_SKILL_NAMES[Net.bot_skill]
	if Net.bot_count <= 0:
		return "no AI"
	return "%d AI %s" % [Net.bot_count, GameConfig.BOT_SKILL_NAMES[Net.bot_skill]]


func _grouped(value: int) -> String:
	var text := str(value)
	var out := ""
	while text.length() > 3:
		out = "," + text.substr(text.length() - 3) + out
		text = text.substr(0, text.length() - 3)
	return text + out


# --- Monkeys -------------------------------------------------------

func _build_monkeys() -> Control:
	var root := _page_root("")
	var head := VBoxContainer.new()
	head.position = Vector2(40, 22)
	head.add_theme_constant_override(&"separation", 6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_label("CHOOSE YOUR MONKEY", &"DisplayBig", 30))
	head.add_child(_label("Same punch for everyone. Body, stats and skill change.", &"Body", 17))
	root.add_child(head)

	var actions := HBoxContainer.new()
	actions.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	actions.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	actions.offset_right = -40.0
	actions.offset_top = 22.0
	actions.add_theme_constant_override(&"separation", 12)
	root.add_child(actions)
	actions.add_child(_button("BACK", &"NavyButton", Vector2(130, 62), _go_back))
	_pick_button = _button("CONFIRM", &"PrimaryButton", Vector2(200, 62), _show.bind(Page.HOME))
	actions.add_child(_pick_button)

	var cards := HBoxContainer.new()
	cards.set_anchors_preset(Control.PRESET_TOP_WIDE)
	cards.offset_left = 40.0
	cards.offset_right = -40.0
	cards.offset_top = 104.0
	cards.offset_bottom = 104.0 + 250.0
	cards.add_theme_constant_override(&"separation", 14)
	root.add_child(cards)
	for id in GameConfig.roster_ids():
		cards.add_child(_hero_card(id))

	# The selected monkey's skill: a live demo on the left, what it does on
	# the right.
	var detail := PanelContainer.new()
	detail.theme_type_variation = &"Glass"
	detail.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	detail.offset_left = 40.0
	detail.offset_right = -40.0
	detail.offset_top = -348.0
	detail.offset_bottom = -20.0
	root.add_child(detail)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 22)
	detail.add_child(row)
	var screen := PanelContainer.new()
	var screen_box := StyleBoxFlat.new()
	screen_box.bg_color = Color8(20, 34, 60)
	screen_box.border_color = UiTheme.OUTLINE
	screen_box.set_border_width_all(4)
	screen.add_theme_stylebox_override(&"panel", screen_box)
	screen.custom_minimum_size = Vector2(560, 0)
	screen.clip_contents = true
	row.add_child(screen)
	_preview = AbilityPreview.new()
	_preview.custom_minimum_size = Vector2(552, 296)
	screen.add_child(_preview)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override(&"separation", 10)
	row.add_child(text)
	_detail_name = _label("", &"Display", 16)
	_detail_name.add_theme_color_override(&"font_color", UiTheme.INK_DIM)
	text.add_child(_detail_name)
	var skill_row := HBoxContainer.new()
	skill_row.add_theme_constant_override(&"separation", 14)
	text.add_child(skill_row)
	_detail_icon = SkillIcon.new()
	_detail_icon.custom_minimum_size = Vector2(64, 64)
	skill_row.add_child(_detail_icon)
	_detail_skill = _label("", &"DisplayBig", 26)
	_detail_skill.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail_skill.size_flags_vertical = Control.SIZE_FILL
	skill_row.add_child(_detail_skill)
	_detail_desc = _label("", &"Body", 20)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_detail_desc)
	_detail_cd = _label("", &"Body", 17)
	_detail_cd.add_theme_color_override(&"font_color", UiTheme.INK_DIM)
	text.add_child(_detail_cd)
	var hint := _label("Live preview: this is exactly what the SKILL button does.", &"Body", 15)
	hint.add_theme_color_override(&"font_color", UiTheme.INK_DIM)
	text.add_child(hint)
	return root


## One hero-select card: the monkey (in its saved skin), name and role,
## and speed / power / climb pips.
func _hero_card(id: StringName) -> Button:
	var stats := GameConfig.get_monkey(id)
	var card := _tile(id == Net.local_monkey, Vector2(0, 0))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_FILL
	card.pressed.connect(_on_hero_card.bind(id))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 6)
	margin.add_child(box)

	var top := Control.new()
	top.custom_minimum_size = Vector2(0, 128)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var sky := ColorRect.new()
	sky.color = UiTheme.PANEL_HI
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sky)
	var stage := MonkeyStage.new()
	stage.pixel_scale = 4
	stage.pedestal = false
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.offset_bottom = -8.0
	top.add_child(stage)
	stage.set_monkey(id, not GameConfig.is_unlocked(id), Profile.skin_for(id))
	var grass := ColorRect.new()
	grass.color = Color8(79, 154, 58)
	grass.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	grass.offset_top = -8.0
	grass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(grass)
	_hero_stages[id] = stage

	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_row)
	var name_label := _label(stats.display_name.to_upper(), &"Display", 12)
	name_label.add_theme_constant_override(&"shadow_offset_x", 0)
	name_label.add_theme_constant_override(&"shadow_offset_y", 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	var role: Array = _role_of(stats)
	var role_label := _label(role[0], &"Display", 9)
	role_label.add_theme_color_override(&"font_color", role[1])
	role_label.add_theme_constant_override(&"shadow_offset_x", 0)
	role_label.add_theme_constant_override(&"shadow_offset_y", 0)
	role_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	role_label.size_flags_vertical = Control.SIZE_FILL
	name_row.add_child(role_label)

	for pip in [["SPEED", "speed", Color8(126, 217, 87)], ["POWER", "power", Color8(255, 107, 90)], ["CLIMB", "climb", Color8(90, 180, 255)]]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 4)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var caption := _label(pip[0], &"Display", 8)
		caption.add_theme_color_override(&"font_color", UiTheme.INK_DIM)
		caption.add_theme_constant_override(&"shadow_offset_x", 0)
		caption.add_theme_constant_override(&"shadow_offset_y", 0)
		caption.custom_minimum_size = Vector2(52, 0)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(caption)
		var filled := clampi(roundi(float(stats.get(pip[1])) / STAT_MAX * 5.0), 1, 5)
		for i in 5:
			var cell := ColorRect.new()
			cell.custom_minimum_size = Vector2(0, 10)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cell.color = pip[2] if i < filled else UiTheme.NAVY_BTN
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(cell)
		box.add_child(line)
	var skill_line := HBoxContainer.new()
	skill_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_line.add_theme_constant_override(&"separation", 6)
	box.add_child(skill_line)
	var icon := SkillIcon.new()
	icon.skill_id = stats.skill_id
	icon.custom_minimum_size = Vector2(22, 22)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_line.add_child(icon)
	var skill_label := _label(SkillFx.name_of(stats.skill_id), &"Display", 8)
	skill_label.add_theme_color_override(&"font_color", SkillFx.colour_of(stats.skill_id))
	skill_label.add_theme_constant_override(&"shadow_offset_x", 0)
	skill_label.add_theme_constant_override(&"shadow_offset_y", 0)
	skill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	skill_label.size_flags_vertical = Control.SIZE_FILL
	skill_line.add_child(skill_label)
	if not GameConfig.is_unlocked(id):
		role_label.text = "LOCKED"
		role_label.add_theme_color_override(&"font_color", UiTheme.CORAL)
	_hero_cards[id] = card
	return card


## A one-word role from the stats, like the mock's HEAVY / SWINGER / THIEF.
func _role_of(stats: MonkeyStats) -> Array:
	if stats.skill_id == &"snatch":
		return ["THIEF", UiTheme.INK_DIM]
	var axes := {"HEAVY": maxf(stats.weight, stats.power), "QUICK": stats.speed, "CLIMBER": stats.climb, "SWINGER": stats.swing}
	var best := "ALL-ROUND"
	var top := 1.15
	for key in axes.keys():
		if float(axes[key]) > top:
			top = float(axes[key])
			best = key
	var colour: Color = UiTheme.BANANA if best == "HEAVY" else UiTheme.INK_DIM
	return [best, colour]


func _on_hero_card(id: StringName) -> void:
	if not GameConfig.is_unlocked(id):
		_deny("%s comes with the premium unlock." % GameConfig.get_monkey(id).display_name)
		_refresh_pick_button()
		return
	_pick_monkey(id)
	var stage: MonkeyStage = _hero_stages.get(id)
	if stage != null:
		stage.cheer()
	Sfx.play(&"ui_select")
	_refresh_pick_button()


func _view_monkey(_index: int) -> void:
	_refresh_pick_button()


func _refresh_pick_button() -> void:
	for id in _hero_cards.keys():
		(_hero_cards[id] as Button).button_pressed = id == Net.local_monkey
	_refresh_detail()
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
	Profile.set_accessory(id)
	Sfx.play(&"ui_select")
	_refresh_pick_button()
	_refresh_style()
	if _style_stage != null:
		_style_stage.cheer()


func _refresh_detail() -> void:
	if _preview == null:
		return
	var id := Net.local_monkey
	var stats := GameConfig.get_monkey(id)
	var colour := SkillFx.colour_of(stats.skill_id)
	_detail_name.text = "%s  -  SKILL" % stats.display_name.to_upper()
	_detail_skill.text = SkillFx.name_of(stats.skill_id)
	_detail_skill.add_theme_color_override(&"font_color", colour)
	(_detail_icon as SkillIcon).skill_id = stats.skill_id
	_detail_icon.queue_redraw()
	_detail_desc.text = SkillFx.description_of(stats.skill_id)
	_detail_cd.text = "Cooldown %.1f s   -   E / K on keyboard, SKILL on a phone" % stats.skill_cooldown
	_preview.call(&"show_monkey", id, Profile.skin_for(id))


# --- Style: skins and accessories ----------------------------------

func _build_style() -> Control:
	var root := _page_root("STYLE")
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_top = 108.0
	row.offset_left = 30.0
	row.offset_right = -30.0
	row.offset_bottom = -24.0
	row.add_theme_constant_override(&"separation", 22)
	root.add_child(row)

	# Left: the monkey wearing it, big, with arrows to change monkey.
	var left := PanelContainer.new()
	left.theme_type_variation = &"Glass"
	left.custom_minimum_size = Vector2(420, 0)
	row.add_child(left)
	var left_box := VBoxContainer.new()
	left_box.alignment = BoxContainer.ALIGNMENT_CENTER
	left_box.add_theme_constant_override(&"separation", 8)
	left.add_child(left_box)
	var stage_row := HBoxContainer.new()
	stage_row.alignment = BoxContainer.ALIGNMENT_CENTER
	left_box.add_child(stage_row)
	stage_row.add_child(_arrow("<", _style_cycle.bind(-1), Vector2(64, 90)))
	_style_stage = MonkeyStage.new()
	_style_stage.pixel_scale = 6
	_style_stage.custom_minimum_size = Vector2(260, 290)
	stage_row.add_child(_style_stage)
	stage_row.add_child(_arrow(">", _style_cycle.bind(1), Vector2(64, 90)))
	_style_name = _centered("", &"Display", 22)
	left_box.add_child(_style_name)
	# Effect viewer: the effect you point at or tap, playing for real.
	var viewer := PanelContainer.new()
	viewer.theme_type_variation = &"Glass"
	viewer.custom_minimum_size = Vector2(360, 150)
	viewer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left_box.add_child(viewer)
	_fx_view = Control.new()
	_fx_view.custom_minimum_size = Vector2(360, 150)
	_fx_view.clip_contents = true
	viewer.add_child(_fx_view)
	_fx_view_name = _centered("POINT AT AN EFFECT TO SEE IT", &"Display", 13)
	left_box.add_child(_fx_view_name)

	# Right: skins (per monkey) and accessories (worn by any monkey).
	var right := PanelContainer.new()
	right.theme_type_variation = &"Glass"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var right_box := VBoxContainer.new()
	right_box.add_theme_constant_override(&"separation", 12)
	right.add_child(right_box)
	right_box.add_child(_label("SKIN", &"Display", 22))
	right_box.add_child(_label("Each monkey keeps its own skin.", &"Body", 16))
	# Flow containers wrap to the panel's real width. Fixed 4 and 5 column
	# grids were wider than the panel on some screens, so the last column
	# hung off the right edge.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_box.add_child(scroll)
	var lists := VBoxContainer.new()
	lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.add_theme_constant_override(&"separation", 12)
	scroll.add_child(lists)
	var skins := HFlowContainer.new()
	skins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skins.add_theme_constant_override(&"h_separation", 10)
	skins.add_theme_constant_override(&"v_separation", 10)
	lists.add_child(skins)
	for id in GameConfig.skin_ids():
		var b := _swatch_button(String(GameConfig.get_skin(id)["name"]), MonkeySkins.swatch(id), _on_skin.bind(id))
		skins.add_child(b)
		_skin_buttons[id] = b
	lists.add_child(_label("ACCESSORY", &"Display", 22))
	var hats := HFlowContainer.new()
	hats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hats.add_theme_constant_override(&"h_separation", 10)
	hats.add_theme_constant_override(&"v_separation", 10)
	lists.add_child(hats)
	for id in GameConfig.hat_ids():
		var hat: Dictionary = GameConfig.get_hat(id)
		var b := _swatch_button(String(hat["name"]), hat["color"] if id != &"none" else UiTheme.NAVY_BTN, _on_hat.bind(id), HatIcon.new(id))
		hats.add_child(b)
		_style_hat_buttons[id] = b
	# Effect slots: whatever the Banana Pull has given you, one per slot.
	for slot in Loot.SLOTS:
		lists.add_child(_label("%s EFFECT" % Loot.SLOT_NAMES[slot], &"Display", 18))
		var flow := HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override(&"h_separation", 10)
		flow.add_theme_constant_override(&"v_separation", 10)
		lists.add_child(flow)
		for id in Loot.items_in(slot):
			var entry := Loot.item(id)
			var label := String(entry["name"]) + (" +" if bool(entry["plus"]) else "")
			var b := _effect_tile(id, label)
			b.mouse_entered.connect(_show_fx_view.bind(id))
			flow.add_child(b)
			_effect_buttons[id] = b
	right_box.add_child(_label("Gold-edged items come with Monkey Plus. Effects come from the Banana Pull.", &"Body", 15))
	return root


## A toggle with a colour chip (or a picture of the item) and a name: one
## skin or accessory. Fixed width so a flow container can wrap them.
func _swatch_button(text: String, chip: Color, on_pressed: Callable, icon: Control = null) -> Button:
	var b := _button("", &"ChoiceButton", Vector2(168, 64), on_pressed)
	b.toggle_mode = true
	b.clip_contents = true
	var inner := HBoxContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 10.0
	inner.offset_bottom = -6.0
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override(&"separation", 8)
	b.add_child(inner)
	if icon != null:
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(icon)
	else:
		var dot := ColorRect.new()
		dot.color = chip
		dot.custom_minimum_size = Vector2(22, 22)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(dot)
	var label := _label(text.to_upper(), &"Display", 10)
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(label)
	return b


## The viewer on the Style page: one live preview at a time, swapped out.
func _show_fx_view(id: StringName) -> void:
	if _fx_view == null or _fx_view_id == id:
		return
	_fx_view_id = id
	for child in _fx_view.get_children():
		child.queue_free()
	var preview: Control = ItemPreviewUI.new(id, Vector2(360, 150))
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_view.add_child(preview)
	var entry := Loot.item(id)
	var rarity := int(entry["rarity"])
	_fx_view_name.text = "%s  -  %s%s" % [String(entry["name"]).to_upper(), Loot.RARITY_NAMES[rarity], "" if Loot.owns(id) else "  (LOCKED)"]
	_fx_view_name.add_theme_color_override(&"font_color", Loot.RARITY_COLORS[rarity])


## A gallery card for one effect: the effect itself playing, its name
## under it, and a rarity-coloured strip along the bottom.
func _effect_tile(id: StringName, label: String) -> Button:
	var entry := Loot.item(id)
	var colour: Color = Loot.RARITY_COLORS[int(entry["rarity"])]
	var b := _button("", &"ChoiceButton", Vector2(168, 128), _on_effect.bind(id))
	b.toggle_mode = true
	b.clip_contents = true
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 6.0
	box.offset_right = -6.0
	box.offset_top = 6.0
	box.offset_bottom = -10.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 2)
	b.add_child(box)
	var preview: Control = ItemPreviewUI.new(id, Vector2(150, 80))
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(preview)
	var name_label := _centered(label, &"Display", 10)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	var strip := ColorRect.new()
	strip.color = colour
	strip.custom_minimum_size = Vector2(0, 4)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(strip)
	return b


func _on_effect(id: StringName) -> void:
	_show_fx_view(id)
	if not Loot.owns(id):
		_deny("%s comes from the Banana Pull in the SHOP." % Loot.item(id)["name"])
		_refresh_style()
		return
	Loot.equip(id)
	Sfx.play(&"ui_select")
	_refresh_style()


func _style_cycle(step: int) -> void:
	_cycle_home(step)
	_refresh_style()


func _on_skin(id: StringName) -> void:
	if not GameConfig.is_skin_unlocked(id):
		_deny("%s comes with the premium unlock." % GameConfig.get_skin(id)["name"])
		_refresh_style()
		return
	Profile.set_skin_for(Net.local_monkey, id)
	Net.set_local_skin(id)
	Sfx.play(&"ui_select")
	var stage: MonkeyStage = _hero_stages.get(Net.local_monkey)
	if stage != null:
		stage.set_monkey(Net.local_monkey, false, id)
	_refresh_style()
	_style_stage.cheer()


func _refresh_style() -> void:
	if _style_stage == null:
		return
	var id := Net.local_monkey
	_style_stage.set_monkey(id, false, Net.local_skin, Net.local_hat)
	_style_name.text = "%s  -  %s" % [GameConfig.get_monkey(id).display_name.to_upper(), String(GameConfig.get_skin(Net.local_skin)["name"]).to_upper()]
	for key in _skin_buttons.keys():
		var b := _skin_buttons[key] as Button
		b.set_pressed_no_signal(key == Net.local_skin)
		b.modulate = Color.WHITE if GameConfig.is_skin_unlocked(key) else Color(0.6, 0.6, 0.6)
	for key in _style_hat_buttons.keys():
		var b := _style_hat_buttons[key] as Button
		b.set_pressed_no_signal(key == Net.local_hat)
		b.modulate = Color.WHITE if GameConfig.is_hat_unlocked(key) else Color(0.6, 0.6, 0.6)
	for key in _effect_buttons.keys():
		var b := _effect_buttons[key] as Button
		var slot: StringName = Loot.item(key)["slot"]
		b.set_pressed_no_signal(Loot.equipped_in(slot) == key)
		b.modulate = Color.WHITE if Loot.owns(key) else Color(0.45, 0.45, 0.45)


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
		var pill := _label(text, &"Display", 16)
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


func _small_back() -> Button:
	var back := _button("BACK", &"NavyButton", Vector2(150, 62), _go_back)
	back.position = Vector2(30, 22)
	back.z_index = 10
	return back


func _caption(text: String, colour: Color = UiTheme.INK_DIM) -> Label:
	var label := _label(text, &"Display", 13)
	label.add_theme_color_override(&"font_color", colour)
	label.add_theme_constant_override(&"shadow_offset_x", 0)
	label.add_theme_constant_override(&"shadow_offset_y", 0)
	return label


func _set_lobby_mode(mode: int) -> void:
	var maps := GameConfig.maps_for_mode(mode)
	var map: StringName = Net.map_id if maps.has(Net.map_id) else maps[0]
	Net.set_match_config(map, mode)
	Sfx.play(&"ui_select")
	_refresh_lobby()


func _set_lobby_map(id: StringName) -> void:
	Net.set_match_config(id, Net.mode)
	Sfx.play(&"ui_select")
	_refresh_lobby()


func _set_lobby_skill(skill: int) -> void:
	Net.set_bot_skill(skill)
	Sfx.play(&"ui_select")
	_refresh_lobby()


func _refresh_lobby() -> void:
	if _seat_grid == null:
		return
	var decides := not Net.is_online() or Net.is_host()
	var slap := Net.mode == GameConfig.Mode.SLAP
	var map_name: String = GameConfig.MAP_NAMES.get(Net.map_id, String(Net.map_id))
	_lobby_title.text = MOCK_MODE_NAMES.get(Net.mode, "PLAY")
	var seats := _lobby_seats()
	var filled := 0
	for seat in seats:
		if not bool(seat["empty"]):
			filled += 1
	_lobby_sub.text = "%s · %d MONKEYS · %s" % ["PARTY" if Net.is_online() else "SOLO", filled, map_name.to_upper()]
	for child in _seat_grid.get_children():
		child.queue_free()
	for seat in seats:
		_seat_grid.add_child(_lobby_seat(seat))
	for mode in _mode_buttons.keys():
		var button := _mode_buttons[mode] as Button
		button.set_pressed_no_signal(mode == Net.mode)
		button.disabled = not decides
	for child in _map_row.get_children():
		child.queue_free()
	for id in GameConfig.maps_for_mode(Net.mode):
		var button := _button(String(GameConfig.MAP_NAMES.get(id, id)).to_upper(), &"ChoiceButton", Vector2(0, 46), _set_lobby_map.bind(id))
		button.toggle_mode = true
		button.set_pressed_no_signal(id == Net.map_id)
		button.disabled = not decides
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override(&"font_size", 10)
		_map_row.add_child(button)
	_fill_toggle.set_pressed_no_signal(slap or Net.bot_count > 0)
	_fill_toggle.text = "ON" if _fill_toggle.button_pressed else "OFF"
	_fill_toggle.disabled = slap or not decides
	var bots := 3 if slap else Net.bot_count
	_fill_note.text = "2v2: bots take the empty seats" if slap else ("%d bots join you" % bots if bots > 0 else "Just you on the map")
	for skill in _skill_buttons.keys():
		var button := _skill_buttons[skill] as Button
		button.set_pressed_no_signal(skill == Net.bot_skill)
		button.disabled = not decides or (not slap and Net.bot_count == 0)
	_skill_note.text = SKILL_BLURBS.get(Net.bot_skill, "")
	_start_button.text = "START" if decides else "WAITING..."
	_start_button.disabled = not decides


## Who sits where: you first, then friends in a party, then bots, then
## empty seats up to the match size.
func _lobby_seats() -> Array:
	var seats: Array = []
	var slap := Net.mode == GameConfig.Mode.SLAP
	if Net.is_online():
		var ids := Net.roster.keys()
		ids.sort_custom(func(a, b) -> bool: return int(Net.roster[a].get("slot", 0)) < int(Net.roster[b].get("slot", 0)))
		for id in ids:
			var entry: Dictionary = Net.roster[id]
			var mine := int(id) == Net.local_id()
			seats.append({"monkey": entry.get("monkey", &"macaque"), "name": "YOU" if mine else String(entry.get("name", "FRIEND")).to_upper(),
				"tag": "HOST" if (mine and Net.is_host()) or int(id) == 1 else ("BOT" if bool(entry.get("bot", false)) else "FRIEND"), "you": mine, "empty": false})
	else:
		seats.append({"monkey": Net.local_monkey, "name": "YOU", "tag": "HOST", "you": true, "empty": false})
	var bots := 3 if slap else Net.bot_count
	var pool: Array[StringName] = []
	for id in GameConfig.roster_ids():
		if not GameConfig.PREMIUM_MONKEYS.has(id):
			pool.append(id)
	var skill_name := String(["EASY", "NORMAL", "HARD"][int(Net.bot_skill)])
	var index := 0
	while seats.size() < GameConfig.NET_MAX_PLAYERS and index < bots:
		seats.append({"monkey": pool[index % pool.size()], "name": GameConfig.BOT_NAMES[index % GameConfig.BOT_NAMES.size()].to_upper(),
			"tag": "BOT · %s" % skill_name, "you": false, "empty": false})
		index += 1
	while seats.size() < GameConfig.NET_MAX_PLAYERS:
		seats.append({"monkey": &"", "name": "OPEN SEAT", "tag": "EMPTY", "you": false, "empty": true})
	return seats


func _lobby_seat(seat: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardHighlight" if bool(seat["you"]) else &"Glass"
	card.custom_minimum_size = Vector2(346, 244)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 8)
	card.add_child(box)
	if not bool(seat["empty"]):
		var stage := MonkeyStage.new()
		stage.pixel_scale = 4
		stage.pedestal = false
		stage.custom_minimum_size = Vector2(0, 146)
		box.add_child(stage)
		stage.set_monkey(StringName(seat["monkey"]), false, StringName(seat.get("skin", &"natural")), StringName(seat.get("hat", &"none")))
	else:
		card.modulate = Color(1, 1, 1, 0.45)
		var dash := _centered("+", &"DisplayBig", 36)
		dash.custom_minimum_size = Vector2(0, 146)
		dash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(dash)
	var name_label := _centered(String(seat["name"]), &"Display", 18)
	box.add_child(name_label)
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var chip_box := StyleBoxFlat.new()
	chip_box.bg_color = UiTheme.PANEL_HI
	chip_box.content_margin_left = 10
	chip_box.content_margin_right = 10
	chip_box.content_margin_top = 6
	chip_box.content_margin_bottom = 6
	chip.add_theme_stylebox_override(&"panel", chip_box)
	var tag := _label(String(seat["tag"]), &"Display", 11)
	tag.add_theme_color_override(&"font_color", UiTheme.BANANA if bool(seat["you"]) else UiTheme.INK_DIM)
	tag.add_theme_constant_override(&"shadow_offset_x", 0)
	tag.add_theme_constant_override(&"shadow_offset_y", 0)
	chip.add_child(tag)
	box.add_child(chip)
	return card


func _mode_tile(mode: int) -> Button:
	var tile := _tile(Net.mode == mode, Vector2(280, 400))
	var box := _tile_box(tile)
	var icon := ModeIcon.new()
	icon.mode = mode
	icon.colour = MODE_COLOURS[mode]
	icon.custom_minimum_size = Vector2(0, 150)
	box.add_child(icon)
	var name_label := _label(String(GameConfig.MODE_NAMES[mode]).to_upper(), &"Display", 15)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	var blurb := _label(MODE_BLURBS[mode], &"Value", 16)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(blurb)
	if Net.queue == GameConfig.Queue.RANKED and not GameConfig.RANKED_MODES.has(mode):
		tile.disabled = true
		tile.tooltip_text = "Not in ranked"
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
	var name_label := _label(String(GameConfig.MAP_NAMES.get(id, id)).to_upper(), &"Display", 18)
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
		column.add_child(_label("TEAMS", &"Display", 18))
		column.add_child(_label("YOU + AI PARTNER  VS  2 AI.  FRIENDS IN YOUR PARTY TAKE THE AI SEATS.", &"Value", 17))
		column.add_child(_skill_row())
		return column
	column.add_child(_label("AI OPPONENTS", &"Display", 18))
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
		button.add_theme_font_size_override(&"font_size", 18)
		counts.add_child(button)
	var note := _label("In a party, seats nobody takes are filled with AI - up to this many.", &"Subheading", 15)
	column.add_child(note)

	column.add_child(_skill_row())
	return column


func _skill_row() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	column.add_child(_label("DIFFICULTY", &"Display", 18))
	var skills := HBoxContainer.new()
	skills.add_theme_constant_override(&"separation", 14)
	column.add_child(skills)
	for skill in GameConfig.BOT_SKILL_NAMES.keys():
		var tile := _tile(Net.bot_skill == skill, Vector2(290, 150))
		tile.disabled = Net.bot_count == 0 and Net.mode != GameConfig.Mode.SLAP
		var box := _tile_box(tile)
		var name_label := _label(String(GameConfig.BOT_SKILL_NAMES[skill]).to_upper(), &"Display", 17)
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
		if i == 0:
			seat.set_monkey(Net.local_monkey, false, Net.local_skin, Net.local_hat)
		else:
			seat.set_monkey(Net.local_monkey, true)
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
	# Two tabs: things you buy, and the gacha you spend bananas on.
	var tabs := HBoxContainer.new()
	tabs.name = "ShopTabs"
	tabs.position = Vector2(24, 104)
	tabs.add_theme_constant_override(&"separation", 10)
	root.add_child(tabs)
	for index in 2:
		var tab := _button(["STORE", "BANANA PULL"][index], &"ChoiceButton", Vector2(230, 56), _set_shop_tab.bind(index))
		tab.toggle_mode = true
		tabs.add_child(tab)
		_shop_tab_buttons.append(tab)
	var wallet := HBoxContainer.new()
	wallet.name = "ShopWallet"
	wallet.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	wallet.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	wallet.offset_right = -28.0
	wallet.offset_top = 110.0
	wallet.add_theme_constant_override(&"separation", 8)
	root.add_child(wallet)
	var coin := BananaIconUI.new()
	coin.custom_minimum_size = Vector2(44, 38)
	wallet.add_child(coin)
	var count := _label("0", &"Display", 22)
	count.name = "ShopWalletCount"
	count.add_theme_color_override(&"font_color", UiTheme.BANANA)
	wallet.add_child(count)
	var body := Control.new()
	body.name = "ShopBody"
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_top = 172.0
	body.offset_left = 24.0
	body.offset_right = -24.0
	body.offset_bottom = -16.0
	root.add_child(body)
	Purchases.prices_changed.connect(func() -> void:
		if _page == Page.SHOP:
			_refresh_shop())
	Loot.wallet_changed.connect(func(_b: int) -> void: _refresh_home())
	return root


var _shop_tab: int = 0
var _shop_tab_buttons: Array[Button] = []
var _last_pull: Array = []


func _set_shop_tab(index: int) -> void:
	_shop_tab = index
	Sfx.play(&"ui_select")
	_refresh_shop()


## A reward tile: a live picture of the thing, and a two-word caption.
func _reward_tile(picture: Control, caption: String, colour: Color = UiTheme.INK) -> VBoxContainer:
	var tile := VBoxContainer.new()
	tile.add_theme_constant_override(&"separation", 4)
	var frame := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color8(20, 26, 50)
	box.border_color = colour.darkened(0.2)
	box.set_border_width_all(3)
	box.anti_aliasing = false
	frame.add_theme_stylebox_override(&"panel", box)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(frame)
	picture.custom_minimum_size = Vector2(88, 80)
	frame.add_child(picture)
	var label := _centered(caption, &"Display", 10)
	label.add_theme_color_override(&"font_color", colour)
	tile.add_child(label)
	return tile


func _banana_picture(count: int) -> Control:
	var icon := BananaIconUI.new()
	icon.count = count
	return icon


func _portrait_picture(monkey: StringName) -> Control:
	var face := TextureRect.new()
	face.texture = MonkeyPortrait.texture(monkey)
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return face


func _offer_card(title: String, subtitle: String, colour: Color, tiles: Array, price: String, owned: bool, on_buy: Callable) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Glass"
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	card.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var heading := _label(title, &"Display", 22)
	heading.add_theme_color_override(&"font_color", colour)
	titles.add_child(heading)
	var sub := _label(subtitle, &"Body", 14)
	sub.add_theme_color_override(&"font_color", UiTheme.INK_DIM)
	titles.add_child(sub)
	var buy := _button("OWNED" if owned else price, &"QuietButton" if owned else &"PlayButton", Vector2(150, 66), on_buy)
	buy.disabled = owned or Purchases.is_busy()
	head.add_child(buy)
	var row := HFlowContainer.new()
	row.add_theme_constant_override(&"h_separation", 10)
	row.add_theme_constant_override(&"v_separation", 8)
	column.add_child(row)
	for tile in tiles:
		row.add_child(tile)
	return card


func _refresh_shop() -> void:
	var page: Control = _pages[Page.SHOP]
	for index in _shop_tab_buttons.size():
		_shop_tab_buttons[index].set_pressed_no_signal(index == _shop_tab)
	(page.find_child("ShopWalletCount", true, false) as Label).text = str(Loot.bananas)
	var body := page.find_child("ShopBody", true, false) as Control
	for child in body.get_children():
		child.queue_free()
	if _shop_tab == 1:
		_build_gacha_tab(body)
		return
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", 16)
	body.add_child(row)

	# Left: Monkey Plus, everything it gives shown as pictures.
	var plus_tiles: Array = [
		_reward_tile(_portrait_picture(&"macaque"), "MACAQUE", UiTheme.BANANA),
		_reward_tile(ItemPreviewUI.new(&"skin_golden"), "ALL SKINS", UiTheme.BANANA),
		_reward_tile(ItemPreviewUI.new(&"hat_crown"), "ALL HATS", UiTheme.BANANA),
		_reward_tile(ItemPreviewUI.new(&"trail_rainbow"), "PLUS POOL", UiTheme.BANANA),
		_reward_tile(_banana_picture(1), "FREE DAILY PULL", UiTheme.BANANA),
		_reward_tile(_banana_picture(6), "+%d" % Loot.PLUS_BANANAS, UiTheme.BANANA),
	]
	var plus := _offer_card("MONKEY PLUS", "One purchase, yours forever.", UiTheme.BANANA, plus_tiles,
		Purchases.price_of(Purchases.PRODUCT_PLUS), Purchases.has_plus(),
		func() -> void: Purchases.buy(Purchases.PRODUCT_PLUS))
	plus.custom_minimum_size = Vector2(610, 0)
	row.add_child(plus)

	# Right: the Starter Pack, the banana packs, restore.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 12)
	row.add_child(right)
	var starter_tiles: Array = [
		_reward_tile(ItemPreviewUI.new(&"skin_midnight"), "MIDNIGHT", UiTheme.LEAF),
		_reward_tile(ItemPreviewUI.new(&"trail_leaves"), "LEAF TRAIL", UiTheme.LEAF),
		_reward_tile(_banana_picture(3), "+%d" % Loot.STARTER_BANANAS, UiTheme.LEAF),
	]
	right.add_child(_offer_card("STARTER PACK", "Once per player.", UiTheme.LEAF, starter_tiles,
		Purchases.price_of(Purchases.PRODUCT_STARTER), Purchases.has_starter(),
		func() -> void: Purchases.buy(Purchases.PRODUCT_STARTER)))
	var packs := HBoxContainer.new()
	packs.add_theme_constant_override(&"separation", 10)
	right.add_child(packs)
	for entry in [[Purchases.PRODUCT_BANANAS_S, 1], [Purchases.PRODUCT_BANANAS_M, 3], [Purchases.PRODUCT_BANANAS_L, 6]]:
		var id: String = entry[0]
		var pack := PanelContainer.new()
		pack.theme_type_variation = &"Glass"
		pack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		packs.add_child(pack)
		var column := VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override(&"separation", 4)
		pack.add_child(column)
		var picture := _banana_picture(int(entry[1]))
		picture.custom_minimum_size = Vector2(0, 72)
		column.add_child(picture)
		var amount := _centered(str(int(Purchases.BANANA_PACKS[id])), &"Display", 20)
		amount.add_theme_color_override(&"font_color", UiTheme.BANANA)
		column.add_child(amount)
		var buy := _button(Purchases.price_of(id), &"PrimaryButton", Vector2(0, 50), func() -> void: Purchases.buy(id))
		buy.disabled = Purchases.is_busy()
		column.add_child(buy)
	var restore_row := HBoxContainer.new()
	restore_row.add_theme_constant_override(&"separation", 10)
	right.add_child(restore_row)
	restore_row.add_child(_button("RESTORE", &"QuietButton", Vector2(170, 48), func() -> void: Purchases.restore()))
	var note := _label("Test Store: no real money is charged.", &"Body", 13)
	note.add_theme_color_override(&"font_color", UiTheme.INK_DIM)
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	restore_row.add_child(note)


## One gacha result: the item playing in a frame the colour of its rarity.
func _result_card(result: Dictionary, big: bool) -> VBoxContainer:
	var item := Loot.item(result["id"])
	var rarity := int(result["rarity"])
	var colour: Color = Loot.RARITY_COLORS[rarity]
	var picture := ItemPreviewUI.new(result["id"], Vector2(150, 140) if big else Vector2(88, 80))
	var tile := _reward_tile(picture, String(item.get("name", "?")).to_upper(), colour)
	(tile.get_child(0).get_child(0) as Control).custom_minimum_size = Vector2(150, 140) if big else Vector2(88, 80)
	var tag := _centered("%s  %s" % [Loot.RARITY_NAMES[rarity], "NEW!" if bool(result.get("new", false)) else "+%d" % int(result.get("refund", 0))], &"Display", 10 if not big else 13)
	tag.add_theme_color_override(&"font_color", colour)
	tile.add_child(tag)
	return tile


func _build_gacha_tab(body: Control) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", 16)
	body.add_child(row)
	var machine := PanelContainer.new()
	machine.theme_type_variation = &"Glass"
	machine.custom_minimum_size = Vector2(420, 0)
	row.add_child(machine)
	var controls := VBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override(&"separation", 12)
	machine.add_child(controls)
	var heap := _banana_picture(6)
	heap.custom_minimum_size = Vector2(0, 110)
	controls.add_child(heap)
	controls.add_child(_centered("BANANA PULL", &"DisplayBig", 30))
	var one := _button("PULL x1   %d" % Loot.PULL_COST, &"PlayButton", Vector2(380, 70), _on_pull.bind(1, false))
	one.disabled = not Loot.can_pull(1)
	controls.add_child(one)
	var ten := _button("PULL x10   %d" % Loot.TEN_PULL_COST, &"PrimaryButton", Vector2(380, 62), _on_pull.bind(10, false))
	ten.disabled = not Loot.can_pull(10)
	controls.add_child(ten)
	if Purchases.has_plus():
		var free := _button("FREE DAILY PULL" if Loot.has_free_pull() else "FREE PULL TOMORROW", &"GoButton", Vector2(380, 52), _on_pull.bind(1, true))
		free.disabled = not Loot.has_free_pull()
		controls.add_child(free)
	var anim_on := bool(Profile.get_stat("pull_anim", true))
	controls.add_child(_button("PULL ANIMATION: %s" % ("ON" if anim_on else "OFF"), &"QuietButton", Vector2(380, 44), func() -> void:
		Profile.set_stat("pull_anim", not bool(Profile.get_stat("pull_anim", true)))
		Sfx.play(&"ui_select")
		_refresh_shop()))
	controls.add_child(_centered("COMMON %d%%   RARE %d%%   LEGENDARY %d%%   MYTHIC %d%%" % [int(Loot.ODDS[0]), int(Loot.ODDS[1]), int(Loot.ODDS[2]), int(Loot.ODDS[3])], &"Display", 11))
	var fine := _centered("x10 guarantees a rare or better.\nDuplicates return %d / %d / %d / %d bananas.%s" % [
		Loot.DUPLICATE_REFUND[0], Loot.DUPLICATE_REFUND[1], Loot.DUPLICATE_REFUND[2], Loot.DUPLICATE_REFUND[3],
		"" if Purchases.has_plus() else "\nGold-edged items drop only with Monkey Plus."], &"Body", 13)
	controls.add_child(fine)

	var stage := PanelContainer.new()
	stage.theme_type_variation = &"Glass"
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(stage)
	var reveal := VBoxContainer.new()
	reveal.alignment = BoxContainer.ALIGNMENT_CENTER
	reveal.add_theme_constant_override(&"separation", 10)
	stage.add_child(reveal)
	if _last_pull.is_empty():
		# Nothing pulled yet: show off the legendaries in the pool.
		reveal.add_child(_centered("MYTHICS AND LEGENDARIES IN THE POOL", &"Display", 18))
		var showcase := HFlowContainer.new()
		showcase.alignment = FlowContainer.ALIGNMENT_CENTER
		showcase.add_theme_constant_override(&"h_separation", 12)
		showcase.add_theme_constant_override(&"v_separation", 12)
		reveal.add_child(showcase)
		for id in [&"skin_night_swinger", &"skin_molten_titan", &"trail_fire", &"punch_thunder", &"win_fireworks", &"skin_golden"]:
			showcase.add_child(_result_card({"id": id, "rarity": int(Loot.item(id)["rarity"]), "new": false, "refund": 0}, false))
		return
	reveal.add_child(_centered("YOU GOT", &"Display", 18))
	var grid := HFlowContainer.new()
	grid.alignment = FlowContainer.ALIGNMENT_CENTER
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 10)
	reveal.add_child(grid)
	for result in _last_pull:
		grid.add_child(_result_card(result, _last_pull.size() == 1))
	reveal.add_child(_centered("New effects are equipped for you. Change them in STYLE.", &"Body", 14))


func _on_pull(count: int, free: bool) -> void:
	var results := Loot.pull(count, free)
	if results.is_empty():
		_deny("Not enough bananas. Win matches or grab a banana pack.")
		return
	var best := 0
	for r in results:
		best = maxi(best, int(r["rarity"]))
	_last_pull = results
	_refresh_shop()
	_refresh_home()
	if bool(Profile.get_stat("pull_anim", true)):
		_start_pull_show(results, best)
	else:
		Sfx.play(&"finish" if best >= Loot.Rarity.LEGENDARY else &"ui_select")


# --- Pull reveal -----------------------------------------------------
#
# The lucky-box reel (PullReel): items race past, slow and land on each
# result in turn, with bananas raining behind. Results were decided by
# Loot.pull before it starts; the reel only shows them.

const PULL_REEL = preload("res://scripts/ui/PullReel.gd")
var _pull_show: Control = null


func _start_pull_show(results: Array, _best: int) -> void:
	_end_pull_show()
	var reel: Control = PULL_REEL.new()
	reel.set(&"results", results)
	reel.set(&"card_maker", _result_card)
	reel.z_index = 40
	add_child(reel)
	_pull_show = reel
	reel.connect(&"closed", func() -> void: _pull_show = null)


func _pull_skip() -> void:
	if _pull_show != null and is_instance_valid(_pull_show):
		_pull_show.call(&"_skip")


func _end_pull_show() -> void:
	if _pull_show != null and is_instance_valid(_pull_show):
		_pull_show.queue_free()
	_pull_show = null


func _on_purchase_finished(success: bool, message: String) -> void:
	if success:
		toast(message)
	elif message != "Cancelled":
		toast("Purchase did not complete: %s" % message)
	_refresh()


# --- Settings and controls -----------------------------------------

func _build_settings() -> Control:
	var root := _page_root("GUIDE")
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_top = 104.0
	column.offset_left = 30.0
	column.offset_right = -30.0
	column.offset_bottom = -20.0
	column.add_theme_constant_override(&"separation", 12)
	root.add_child(column)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 10)
	column.add_child(tabs)
	for tab in GUIDE_TABS:
		var b := _button(tab, &"ChoiceButton", Vector2(0, 54), _set_guide_tab.bind(tab))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
		_guide_tab_buttons[tab] = b
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Glass"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_guide_body = VBoxContainer.new()
	_guide_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_guide_body.add_theme_constant_override(&"separation", 14)
	scroll.add_child(_guide_body)
	_set_guide_tab.call_deferred(_guide_tab)
	return root


const GUIDE_TABS: Array[String] = ["CONTROLS", "MOVING", "FIGHTING", "MODES", "MONKEYS"]
var _guide_tab: String = "CONTROLS"
var _guide_body: VBoxContainer = null
var _guide_tab_buttons: Dictionary = {}


## The cog: a settings pop-up over whatever page you are on. The GUIDE
## button is the other thing, the how-to-play pages.
func _open_settings() -> void:
	_close_settings()
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 35
	add_child(layer)
	_settings_popup = layer
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.08, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_close_settings())
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"Glass"
	card.custom_minimum_size = Vector2(560, 0)
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 14)
	card.add_child(box)
	box.add_child(_centered("SETTINGS", &"DisplayBig", 30))
	box.add_child(_label("VOLUME", &"Display", 18))
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
	box.add_child(volume)
	box.add_child(_label("BANANA PULL", &"Display", 18))
	var anim := Button.new()
	anim.theme_type_variation = &"ChoiceButton"
	anim.custom_minimum_size = Vector2(0, 54)
	anim.toggle_mode = true
	var refresh_anim := func() -> void:
		var on := bool(Profile.get_stat("pull_anim", true))
		anim.set_pressed_no_signal(on)
		anim.text = "ROLL ANIMATION: %s" % ("ON" if on else "OFF")
	refresh_anim.call()
	anim.pressed.connect(func() -> void:
		Profile.set_stat("pull_anim", not bool(Profile.get_stat("pull_anim", true)))
		Sfx.play(&"ui_select")
		refresh_anim.call())
	box.add_child(anim)
	var perf := _button("PERFORMANCE OVERLAY", &"QuietButton", Vector2(0, 54), func() -> void:
		_close_settings()
		if PerfOverlay.has_method(&"toggle"):
			PerfOverlay.call(&"toggle"))
	box.add_child(perf)
	box.add_child(_button("CLOSE", &"PrimaryButton", Vector2(0, 58), _close_settings))


func _close_settings() -> void:
	if _settings_popup != null and is_instance_valid(_settings_popup):
		_settings_popup.queue_free()
	_settings_popup = null


var _settings_popup: Control = null


## Open the guide on a tab.
func _open_guide(tab: String) -> void:
	_guide_tab = tab
	_show(Page.SETTINGS)
	_set_guide_tab(tab)


func _set_guide_tab(tab: String) -> void:
	_guide_tab = tab
	for key in _guide_tab_buttons.keys():
		(_guide_tab_buttons[key] as Button).set_pressed_no_signal(key == tab)
	if _guide_body == null:
		return
	for child in _guide_body.get_children():
		child.queue_free()
	match tab:
		"CONTROLS":
			_guide_controls()
		"MOVING":
			_guide_section("GETTING AROUND", "The jungle is built to be climbed, swung through and fallen out of.")
			_guide_grid([
				["DOUBLE JUMP", "Tap SPACE to jump, tap again in the air for a second jump. Swinging gives the double jump back.", &"jump", UiTheme.BANANA],
				["GRAB AND SWING", "Hold RIGHT CLICK near a vine, rope, tree or the edge of a ledge. Push left and right to pump, let go to fly off with the speed.", &"swing", UiTheme.LEAF],
				["CLIMB UP FOR FREE", "Caught the lip of the ground or a ledge? Hold toward where you are holding and you pop up and over without spending a jump.", &"hop", UiTheme.SKY],
				["PASS-THROUGH GROUND", "Dirt islands and stone ledges are solid only from above. Jump or climb straight up through them from below.", &"through", Color8(160, 110, 70)],
				["DROP AND SLIDE", "Hold S on a wooden platform to drop through it. Hold S while running fast to slide.", &"drop", UiTheme.CORAL],
				["AUTO CLIMB", "Climbing a trunk into something solid? The monkey hops out to the clear side and keeps going.", &"climb", UiTheme.LEAF],
			])
		"FIGHTING":
			_guide_section("HOW HITS WORK", "Every hit is knockback. Nobody has health: you lose by flying off the island.")
			_guide_grid([
				["PUNCH", "LEFT CLICK. Small monkeys punch fast, big ones punch hard. Long arms (orangutan, gibbon) reach further.", &"punch", UiTheme.CORAL],
				["COMBO", "Hits that keep coming, from anyone, stack up to 6. Each one sends the target further. Stop hitting for a moment and it resets. The hit flash goes from pale to bright red as it climbs.", &"combo", Color8(255, 70, 60)],
				["WEIGHT", "Heavy monkeys fly less far and get stunned for less time. Light monkeys fly further but move and hit faster.", &"weight", UiTheme.INK_DIM],
				["SAVE YOURSELF", "Knocked into the air? Press JUMP a moment later to break out of the stun with your double jump. SAVED! Only in the air, and only if your double jump is still unused.", &"saved", UiTheme.LEAF],
				["STUN CHAINS", "Every hit restarts your stun. A gorilla slam holds you, then stuns you on the ground where you cannot jump out, so a follow-up hit keeps you stuck. Keep your distance from gorillas.", &"chain", Color8(255, 120, 80)],
				["STEER", "While flying from a hit, hold a direction to drift a little. Aim back at the island.", &"steer", UiTheme.SKY],
				["BANANA PEEL", "Step on a chimp's peel and you skid, stunned, and for a moment every hit sends you further.", &"peel", UiTheme.BANANA],
			])
			_guide_section("BIG HITS STAY BIG, BUT FAIR", "Speed from a hit ends with the stun, so it never turns into a runaway slide. Races and Banana Hoard use gentler knockback than 2v2 Slap.")
		"MODES":
			_guide_section("MODES", "2v2 Slap is where the chaos lives. The others are for racing and farming.")
			_guide_grid([
				["2V2 SLAP", "Two teams on Slap Island. Knock both enemies off to win the round. One life per round, best of three.", &"slap", UiTheme.CORAL],
				["RACE", "First to the flag wins. Knock the leader off the route on your way past.", &"race", UiTheme.BANANA],
				["BANANA HOARD", "First to 30 bananas wins. One or two bananas appear at a time, in different spots: race for them. Every hit on a carrier steals one into your hands and knocks one loose.", &"hoard", UiTheme.LEAF],
				["RANKED AND STAKES", "Ranked matches move your rank. Stake bananas before a match: win big, or lose the stake.", &"ranked", UiTheme.SKY],
			])
		"MONKEYS":
			_guide_section("THE MONKEYS", "Five monkeys, five skills. Press E to use yours.")
			_guide_monkeys()
		"SETTINGS":
			_guide_settings()


func _guide_section(title: String, text: String) -> void:
	_guide_body.add_child(_label(title, &"Display", 22))
	var line := _label(text, &"Body", 16)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_color_override(&"font_color", UiTheme.INK_DIM)
	_guide_body.add_child(line)


## Cards two to a row: a little picture of the idea, a title in its colour,
## and two lines of plain words.
func _guide_grid(cards: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 14)
	grid.add_theme_constant_override(&"v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_guide_body.add_child(grid)
	for card in cards:
		grid.add_child(_guide_card(card[0], card[1], card[2], card[3]))


func _guide_card(title: String, text: String, art: StringName, accent: Color) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	card.add_child(row)
	var picture := GuideArt.new()
	picture.kind = art
	picture.accent = accent
	picture.custom_minimum_size = Vector2(112, 96)
	row.add_child(picture)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(words)
	var head := _label(title, &"Display", 16)
	head.add_theme_color_override(&"font_color", accent)
	words.add_child(head)
	var body := _label(text, &"Body", 15)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(body)
	return card


func _guide_controls() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 20)
	_guide_body.add_child(row)
	for block in [["KEYBOARD AND MOUSE", KEYS], ["TOUCH", TOUCH]]:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override(&"separation", 10)
		row.add_child(box)
		box.add_child(_label(block[0], &"Display", 22))
		for pair in block[1]:
			box.add_child(_key_row(pair[0], pair[1]))


func _guide_monkeys() -> void:
	for id in [&"gorilla", &"orangutan", &"macaque", &"gibbon", &"capuchin"]:
		var stats := GameConfig.get_monkey(id)
		var card := PanelContainer.new()
		card.theme_type_variation = &"Card"
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 16)
		card.add_child(row)
		var face := _portrait_picture(id)
		face.custom_minimum_size = Vector2(84, 84)
		row.add_child(face)
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(words)
		var head := HBoxContainer.new()
		head.add_theme_constant_override(&"separation", 12)
		words.add_child(head)
		head.add_child(_label(stats.display_name.to_upper(), &"Display", 18))
		var skill := _label(SkillFx.name_of(stats.skill_id), &"Display", 14)
		skill.add_theme_color_override(&"font_color", SkillFx.colour_of(stats.skill_id))
		head.add_child(skill)
		var cooldown := _label("%.1fs%s" % [stats.skill_cooldown, "  x%d" % stats.skill_charges if stats.skill_charges > 1 else ""], &"Body", 14)
		cooldown.add_theme_color_override(&"font_color", UiTheme.INK_DIM)
		head.add_child(cooldown)
		var text := _label(SkillFx.description_of(stats.skill_id), &"Body", 15)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.add_child(text)
		var icon := GuideArt.new()
		icon.kind = &"skill"
		icon.skill_id = stats.skill_id
		icon.accent = SkillFx.colour_of(stats.skill_id)
		icon.custom_minimum_size = Vector2(80, 80)
		row.add_child(icon)
		_guide_body.add_child(card)


func _guide_settings() -> void:
	_guide_body.add_child(_label("VOLUME", &"Display", 22))
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
	_guide_body.add_child(volume)
	var anim_on := bool(Profile.get_stat("pull_anim", true))
	_guide_body.add_child(_label("BANANA PULL", &"Display", 22))
	_guide_body.add_child(_button("PULL ANIMATION: %s" % ("ON" if anim_on else "OFF"), &"QuietButton", Vector2(360, 54), func() -> void:
		Profile.set_stat("pull_anim", not bool(Profile.get_stat("pull_anim", true)))
		Sfx.play(&"ui_select")
		_set_guide_tab("SETTINGS")))


## The little pictures on the guide cards. Pixel blocks, same palette as
## the game, one idea each: an arc for a jump, a rope for a swing, a bar
## of reds for a combo.
class GuideArt extends Control:
	const SkillFxArt = preload("res://scripts/player/SkillFx.gd")
	const PeelArt = preload("res://scripts/world/BananaPeel.gd")
	const BananaArt = preload("res://scripts/ui/BananaIcon.gd")
	var kind: StringName = &"jump"
	var accent: Color = Color.WHITE
	var skill_id: StringName = &""
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _block(at: Vector2, size: Vector2, c: Color) -> void:
		draw_rect(Rect2((at / 2.0).floor() * 2.0, size), c)

	func _monkey(at: Vector2, c: Color = Color8(150, 106, 64)) -> void:
		# A chunky little monkey: body, head, face.
		_block(at + Vector2(-9, -26), Vector2(18, 18), c)
		_block(at + Vector2(-7, -10), Vector2(14, 12), c.darkened(0.15))
		_block(at + Vector2(-5, -22), Vector2(10, 8), Color8(236, 196, 150))
		_block(at + Vector2(-3, -20), Vector2(2, 2), Color8(30, 20, 14))
		_block(at + Vector2(1, -20), Vector2(2, 2), Color8(30, 20, 14))

	func _arrow(from: Vector2, to: Vector2, c: Color) -> void:
		draw_line(from, to, c, 4.0)
		var dir := (to - from).normalized()
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([to + dir * 8.0, to - dir * 4.0 + side * 7.0, to - dir * 4.0 - side * 7.0]), c)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var ground := h - 14.0
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.14, 0.6))
		var bob := sin(_t * 3.0)
		match kind:
			&"jump":
				_block(Vector2(0, ground), Vector2(w, 14), Color8(79, 154, 58))
				var k := fmod(_t, 1.6) / 1.6
				var x := lerpf(20.0, w - 20.0, k)
				var y := ground - (sin(k * PI * 2.0) * 0.5 + 0.5 * absf(sin(k * PI * 2.0))) * 50.0
				_monkey(Vector2(x, y))
				_arrow(Vector2(16, ground - 40), Vector2(w * 0.5, ground - 64), accent)
			&"swing":
				var anchor := Vector2(w * 0.5, 10)
				var angle := sin(_t * 2.4) * 0.9
				var hand := anchor + Vector2(sin(angle), cos(angle)) * 62.0
				draw_line(anchor, hand, Color8(58, 120, 46), 4.0)
				_block(anchor - Vector2(4, 4), Vector2(8, 8), Color8(107, 68, 36))
				_monkey(hand + Vector2(0, 26))
			&"hop":
				_block(Vector2(w * 0.5, ground - 36), Vector2(w * 0.5, 50), Color8(92, 58, 34))
				_block(Vector2(w * 0.5, ground - 36), Vector2(w * 0.5, 6), Color8(79, 154, 58))
				_monkey(Vector2(w * 0.38, ground + 6 - 10.0 * absf(bob)))
				_arrow(Vector2(w * 0.38, ground - 40), Vector2(w * 0.62, ground - 56), accent)
			&"through":
				_block(Vector2(10, 36), Vector2(w - 20, 26), Color8(92, 58, 34))
				_block(Vector2(10, 36), Vector2(w - 20, 6), Color8(79, 154, 58))
				var k2 := fmod(_t, 1.4) / 1.4
				_monkey(Vector2(w * 0.5, lerpf(h + 20.0, 30.0, k2)))
				_arrow(Vector2(w * 0.8, h - 6), Vector2(w * 0.8, 20), accent)
			&"drop":
				_block(Vector2(14, 40), Vector2(w - 28, 8), Color8(138, 90, 46))
				var k3 := fmod(_t, 1.4) / 1.4
				_monkey(Vector2(w * 0.5, lerpf(40.0, h + 10.0, k3)))
				_arrow(Vector2(w * 0.82, 24), Vector2(w * 0.82, h - 10), accent)
			&"climb":
				_block(Vector2(w * 0.3, 0), Vector2(18, h), Color8(107, 68, 36))
				_block(Vector2(w * 0.3 - 30, 22), Vector2(54, 10), Color8(90, 96, 122))
				_monkey(Vector2(w * 0.3 + 24, 70 + bob * 4.0))
				_arrow(Vector2(w * 0.3 + 30, 60), Vector2(w * 0.3 + 44, 18), accent)
			&"punch":
				_monkey(Vector2(w * 0.3, ground))
				var reach := 26.0 + 16.0 * absf(sin(_t * 5.0))
				_block(Vector2(w * 0.3 + 8, ground - 22), Vector2(reach, 6), Color8(150, 106, 64))
				_block(Vector2(w * 0.3 + 8 + reach, ground - 26), Vector2(12, 12), Color8(236, 196, 150))
				_monkey(Vector2(w * 0.82, ground), Color8(120, 120, 140))
			&"combo":
				for i in 6:
					var heat := float(i + 1) / 6.0
					var c := Color(1.0, lerpf(0.82, 0.18, heat), lerpf(0.78, 0.12, heat))
					var lit := int(fmod(_t * 3.0, 8.0)) > i
					var bar_h := 14.0 + i * 11.0
					_block(Vector2(10 + i * 16, h - 12 - bar_h), Vector2(12, bar_h), c if lit else Color(c, 0.25))
			&"weight":
				_block(Vector2(8, ground), Vector2(w - 16, 4), Color8(79, 154, 58))
				_monkey(Vector2(26, ground), Color8(90, 84, 90))
				_monkey(Vector2(26, ground - 44), Color8(200, 160, 110))
				_arrow(Vector2(42, ground - 14), Vector2(62, ground - 14), accent)
				_arrow(Vector2(42, ground - 58), Vector2(w - 8, ground - 58), accent)
			&"chain":
				_block(Vector2(0, ground), Vector2(w, 14), Color8(79, 154, 58))
				_monkey(Vector2(w * 0.5, ground), Color8(120, 120, 140))
				_monkey(Vector2(18, ground), Color8(80, 76, 84))
				_monkey(Vector2(w - 18, ground), Color8(80, 76, 84))
				# A hit every half second, and the stun bar refilling each time.
				var beat := fmod(_t, 0.5) / 0.5
				var side := -1.0 if int(_t * 2.0) % 2 == 0 else 1.0
				if beat < 0.3:
					var star := Vector2(w * 0.5 + side * 14.0, ground - 22.0)
					for i in 4:
						var d := Vector2.from_angle(TAU * i / 4.0 + 0.4) * (6.0 + beat * 20.0)
						_block(star + d, Vector2(4, 4), accent)
				var bar := 1.0 - beat
				_block(Vector2(w * 0.5 - 20, ground - 42), Vector2(40, 6), Color(0, 0, 0, 0.5))
				_block(Vector2(w * 0.5 - 20, ground - 42), Vector2(40.0 * bar, 6), accent)
			&"saved":
				var k4 := fmod(_t, 1.6) / 1.6
				_monkey(Vector2(w * 0.5, lerpf(h, 40.0, k4) + 20.0))
				draw_string(get_theme_default_font(), Vector2(w * 0.5 - 26, 18), "SAVED!", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, accent)
			&"steer":
				var k5 := fmod(_t, 1.6) / 1.6
				var p := Vector2(lerpf(w - 16.0, 30.0, k5), 30.0 + sin(k5 * PI) * -10.0 + k5 * 40.0)
				_monkey(p + Vector2(0, 20))
				_arrow(Vector2(w - 10, 20), Vector2(24, 70), Color(accent, 0.5))
				_arrow(p + Vector2(12, 0), p + Vector2(-14, -14), accent)
			&"peel":
				_block(Vector2(0, ground), Vector2(w, 14), Color8(79, 154, 58))
				var art: Array = PeelArt.ART
				for yy in art.size():
					var line: String = art[yy]
					for xx in line.length():
						if PeelArt.COLORS.has(line[xx]):
							_block(Vector2(w * 0.5 - 12 + xx * 2, ground - 14 + yy * 2), Vector2(2, 2), PeelArt.COLORS[line[xx]])
				var k6 := fmod(_t, 1.6) / 1.6
				_monkey(Vector2(lerpf(10.0, w - 10.0, k6), ground - (8.0 if k6 > 0.5 else 0.0)))
			&"slap":
				_block(Vector2(20, ground), Vector2(w - 40, 14), Color8(92, 58, 34))
				_block(Vector2(20, ground), Vector2(w - 40, 4), Color8(79, 154, 58))
				_monkey(Vector2(w * 0.35, ground), Color8(230, 90, 80))
				var k7 := fmod(_t, 1.6) / 1.6
				_monkey(Vector2(w * 0.62 + k7 * 50.0, ground - k7 * 40.0), Color8(90, 140, 230))
			&"race":
				_block(Vector2(w * 0.6, 10), Vector2(4, 70), Color8(220, 220, 220))
				for i in 4:
					_block(Vector2(w * 0.6 + 4 + (i % 2) * 10, 10 + (i / 2) * 10), Vector2(10, 10), Color8(30, 30, 30) if (i + int(i / 2)) % 2 == 0 else Color8(240, 240, 240))
				_monkey(Vector2(lerpf(10.0, w * 0.55, fmod(_t, 2.0) / 2.0), ground))
			&"hoard":
				BananaArt.draw_bunch(self, Rect2(8, 8, w - 16, h - 16), 4)
			&"ranked":
				var c2 := accent
				draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, 10), Vector2(w * 0.5 + 30, 30), Vector2(w * 0.5 + 22, h - 14), Vector2(w * 0.5 - 22, h - 14), Vector2(w * 0.5 - 30, 30)]), c2)
				BananaArt.draw_bunch(self, Rect2(w * 0.5 - 16, 30, 32, 28), 1)
			&"skill":
				SkillFxArt.draw_icon(self, skill_id, size * 0.5, minf(w, h) * 0.32, accent)


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
	var key_label := _label(key, &"Body", 16)
	key_label.add_theme_color_override(&"font_color", UiTheme.INK_DARK)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(key_label)
	line.add_child(chip)
	var what := _label(action, &"Body", 17)
	what.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
		Page.STYLE:
			_refresh_style()
		Page.PLAY:
			_refresh_lobby()
		Page.PARTY:
			_refresh_party()
		Page.SHOP:
			_refresh_shop()
		Page.RANKS:
			_refresh_ranks()


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
	# The skill's display name (BANANA BANDIT, not SNATCH).
	return SkillFx.name_of(stats.skill_id)


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
				BananaIconUI.draw_bunch(self, Rect2(Vector2.ZERO, size), 1)
			&"pointer":
				var tip := PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x * 0.5, size.y)])
				draw_colored_polygon(tip, ink)
				var inner := PackedVector2Array([Vector2(4, 3), Vector2(size.x - 4, 3), Vector2(size.x * 0.5, size.y - 5)])
				draw_colored_polygon(inner, Color8(255, 216, 74))
			&"hanger":
				# A shirt: the wardrobe.
				var shirt := PackedVector2Array([
					c + Vector2(-r * 0.35, -r * 0.7), c + Vector2(-r * 0.95, -r * 0.35), c + Vector2(-r * 0.7, r * 0.05),
					c + Vector2(-r * 0.5, -r * 0.1), c + Vector2(-r * 0.5, r * 0.8), c + Vector2(r * 0.5, r * 0.8),
					c + Vector2(r * 0.5, -r * 0.1), c + Vector2(r * 0.7, r * 0.05), c + Vector2(r * 0.95, -r * 0.35),
					c + Vector2(r * 0.35, -r * 0.7), c + Vector2(0, -r * 0.45)])
				var closed := shirt.duplicate()
				closed.append(shirt[0])
				draw_colored_polygon(shirt, Color8(255, 110, 200))
				draw_polyline(closed, ink, r * 0.14)
				draw_rect(Rect2(c + Vector2(-r * 0.5, r * 0.25), Vector2(r, r * 0.14)), Color.WHITE)
			&"badge":
				draw_circle(c, r, ink)
				draw_circle(c, r * 0.8, Color8(240, 60, 70))
				draw_rect(Rect2(c + Vector2(-r * 0.12, -r * 0.5), Vector2(r * 0.24, r * 0.6)), Color.WHITE)
				draw_rect(Rect2(c + Vector2(-r * 0.12, r * 0.22), Vector2(r * 0.24, r * 0.22)), Color.WHITE)


## A skill's pixel icon in its colour, on a dark tile.
class SkillIcon extends Control:
	var skill_id: StringName = &""

	func _draw() -> void:
		var r := minf(size.x, size.y)
		var box := Rect2((size - Vector2(r, r)) * 0.5, Vector2(r, r))
		draw_rect(box, Color8(26, 15, 10))
		draw_rect(box.grow(-maxf(r * 0.06, 2.0)), Color8(22, 34, 74))
		var tint: Color = (SkillFx.INFO.get(skill_id, ["", Color.WHITE]) as Array)[1]
		SkillFx.draw_icon(self, skill_id, size * 0.5, r * 0.3, tint)


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


## The accessory itself, drawn by the same Headwear the monkeys wear, on a
## small head so shades and headphones read as what they are.
class HatIcon extends Control:
	var hat_id: StringName = &"none"

	func _init(id: StringName) -> void:
		hat_id = id
		custom_minimum_size = Vector2(44, 44)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _ready() -> void:
		var info: Dictionary = GameConfig.get_hat(hat_id)
		var hat := Headwear.new()
		hat.apply(info["style"], info["color"], 22.0)
		hat.position = Vector2(22.0, 20.0)
		add_child(hat)

	func _draw() -> void:
		# A plain head for the hat to sit on: fur, face, two eyes.
		var fur := Color(0.45, 0.30, 0.20)
		draw_rect(Rect2(11, 20, 22, 20), fur)
		draw_rect(Rect2(14, 27, 16, 11), Color(0.85, 0.68, 0.52))
		draw_rect(Rect2(16, 30, 3, 3), Color(0.1, 0.07, 0.05))
		draw_rect(Rect2(25, 30, 3, 3), Color(0.1, 0.07, 0.05))
