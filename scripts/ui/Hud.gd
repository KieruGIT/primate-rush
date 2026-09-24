extends CanvasLayer

# ============================================================
# HUD - connection state, monkey, movement state, race state.
#
# The movement state readout stays in the shipped build. In a game with five
# states and no animation yet, "why did that happen" is only answerable if
# you can see which state you were in when it happened.
# ============================================================

const GO_FLASH_SECONDS: float = 0.9
const SkillFx = preload("res://scripts/player/SkillFx.gd")

@onready var _title: Label = %Title
@onready var _info: Label = %Info
@onready var _center: Label = %Center
@onready var _board: Label = %Board

var _player: Player = null
var _race: RaceDirector = null
var _hoard: HoardDirector = null
var _slap: SlapDirector = null
var _center_timer: float = 0.0
## F1 shows the movement-state readout. Off by default: it is a tuning aid,
## and on a phone it covers the part of the screen you jump into.
var _debug: bool = false
var _portrait: TextureRect = null
var _portrait_for: StringName = &""
var _board_card: PanelContainer = null
## Mock HUD: wood plank timer top-centre, banana count top-left.
var _plank: PanelContainer = null
var _plank_mode: Label = null
var _plank_time: Label = null
var _carry: PanelContainer = null
var _carry_count: Label = null
var _card: PanelContainer = null
var _board_list: VBoxContainer = null
var _board_sig: String = ""
## Skill card, bottom right on keyboard: name, key, cooldown bar and seconds.
var _skill_card: PanelContainer = null
var _skill_name: Label = null
var _skill_state: Label = null
var _skill_bar: ProgressBar = null
var _skill_fill: StyleBoxFlat = null
var _skill_was_cooling: bool = false
var _skill_style_id: StringName = &""
var _skill_style_cooling: int = -1
var _board_refresh_left: float = 0.0


func _ready() -> void:
	layer = 5
	UiTheme.ensure(self)
	_center.text = ""
	_build_card()
	_build_board_card()
	_build_plank()
	_build_carry()
	if not OS.has_feature("mobile"):
		_build_key_strip()
		# Phones show the cooldown on the SKILL button itself.
		_build_skill_card()
	_center.theme_type_variation = &"HudBig"
	_center.add_theme_font_size_override(&"font_size", 88)
	# Above the monkeys, who stand in the middle of the screen.
	_center.offset_top -= 190.0
	_center.offset_bottom -= 190.0
	_board.theme_type_variation = &"HudLabel"


## Standings need a stable dark surface: on Map A their old outlined text
## disappeared into the clouds, while on Map B it disappeared into the bark.
func _build_board_card() -> void:
	var root := _board.get_parent() as Control
	_board_card = PanelContainer.new()
	_board_card.theme_type_variation = &"Glass"
	_board_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_board_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_board_card.offset_left = -330.0
	_board_card.offset_top = 96.0
	_board_card.offset_right = -20.0
	_board_card.custom_minimum_size = Vector2(310.0, 0.0)
	root.add_child(_board_card)
	_board_card.offset_top = 16.0
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	_board_card.add_child(column)
	var header := Label.new()
	header.text = "LEADERBOARD"
	header.add_theme_font_override(&"font", UiTheme._font(UiTheme.FONT_DISPLAY))
	header.add_theme_font_size_override(&"font_size", 11)
	header.add_theme_color_override(&"font_color", UiTheme.INK_DIM)
	column.add_child(header)
	_board_list = VBoxContainer.new()
	_board_list.add_theme_constant_override(&"separation", 4)
	column.add_child(_board_list)
	_board.reparent(column)
	_board.visible = false
	_board_card.visible = false


## The match timer on a carved wood sign, top centre, as in the mock.
func _build_plank() -> void:
	_plank = PanelContainer.new()
	var box: StyleBoxTexture = UiTheme.pixel_button(UiTheme.WOOD, Color8(92, 58, 28)).duplicate()
	box.content_margin_left = 34
	box.content_margin_right = 34
	box.content_margin_top = 10
	box.content_margin_bottom = 14
	_plank.add_theme_stylebox_override(&"panel", box)
	_plank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plank.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_plank.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_plank.offset_top = 10.0
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 0)
	_plank.add_child(column)
	_plank_mode = Label.new()
	_plank_mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plank_mode.add_theme_font_override(&"font", UiTheme._font(UiTheme.FONT_DISPLAY))
	_plank_mode.add_theme_font_size_override(&"font_size", 11)
	_plank_mode.add_theme_color_override(&"font_color", Color8(244, 233, 207, 200))
	column.add_child(_plank_mode)
	_plank_time = Label.new()
	_plank_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plank_time.theme_type_variation = &"HudValue"
	_plank_time.add_theme_font_size_override(&"font_size", 32)
	_plank_time.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0))
	_plank_time.add_theme_color_override(&"font_shadow_color", Color8(26, 15, 10))
	_plank_time.add_theme_constant_override(&"shadow_offset_x", 3)
	_plank_time.add_theme_constant_override(&"shadow_offset_y", 3)
	column.add_child(_plank_time)
	add_child(_plank)
	_plank.visible = false


## Bananas you are carrying, big and gold, top left under your card.
func _build_carry() -> void:
	_carry = PanelContainer.new()
	_carry.theme_type_variation = &"Glass"
	_carry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_carry.position = Vector2(20.0, 16.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	_carry.add_child(row)
	var banana := BananaIcon.new()
	banana.custom_minimum_size = Vector2(40, 40)
	banana.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(banana)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	row.add_child(column)
	_carry_count = Label.new()
	_carry_count.theme_type_variation = &"HudValue"
	_carry_count.add_theme_font_size_override(&"font_size", 30)
	_carry_count.add_theme_color_override(&"font_color", UiTheme.BANANA)
	column.add_child(_carry_count)
	var word := Label.new()
	word.text = "CARRYING"
	word.add_theme_font_override(&"font", UiTheme._font(UiTheme.FONT_DISPLAY))
	word.add_theme_font_size_override(&"font_size", 10)
	word.add_theme_color_override(&"font_color", UiTheme.INK)
	column.add_child(word)
	add_child(_carry)
	_carry.visible = false


## The mock's pixel banana: a stepped crescent with an ink edge.
class BananaIcon extends Control:
	func _draw() -> void:
		var p := size.x / 10.0
		var cells := [[7, 0], [8, 0], [6, 1], [7, 1], [5, 2], [6, 2], [4, 3], [5, 3], [2, 4], [3, 4], [4, 4],
			[0, 5], [1, 5], [2, 5], [3, 5], [1, 6], [2, 6]]
		for c in cells:
			draw_rect(Rect2(c[0] * p - 2.0, c[1] * p + p - 2.0, p + 4.0, p + 4.0), UiTheme.OUTLINE)
		for c in cells:
			draw_rect(Rect2(c[0] * p, c[1] * p + p, p, p), Color8(247, 201, 72))
		for c in [[7, 0], [6, 1], [5, 2], [4, 3], [2, 4]]:
			draw_rect(Rect2(c[0] * p, c[1] * p + p, p, p * 0.5), Color8(255, 243, 176))


func _update_plank() -> void:
	# Shown from the countdown on, so the sign is up before GO.
	var mode := ""
	var seconds := -1.0
	match Net.mode:
		GameConfig.Mode.HOARD:
			if _hoard != null:
				mode = "BANANA RUSH"
				seconds = _hoard.time_left if _hoard.is_running() else _hoard.round_seconds
		GameConfig.Mode.SLAP:
			if _slap != null:
				mode = "2V2 SLAP"
				var left: Variant = _slap.get(&"time_left")
				seconds = float(left) if left != null else 0.0
		GameConfig.Mode.RACE:
			if _race != null:
				mode = "RACE"
				seconds = _race.elapsed
	_plank.visible = seconds >= 0.0
	if _plank.visible:
		_plank_mode.text = mode
		_plank_time.text = "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]
	var carrying := _player != null and is_instance_valid(_player) and Net.mode == GameConfig.Mode.HOARD and _hoard != null
	_carry.visible = carrying
	if _card != null:
		_card.visible = not carrying
	if carrying:
		_carry_count.text = str(_player.bananas)


## Wraps the scene's Title and Info labels in a card with the monkey's face,
## so who you are is a picture first and a word second.
func _build_card() -> void:
	var top: Control = _title.get_parent()
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.position = Vector2(20.0, 16.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	card.add_child(row)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(56, 56)
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_portrait)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	_title.reparent(text)
	_info.reparent(text)
	_title.theme_type_variation = &"HudValue"
	_info.theme_type_variation = &"HudLabel"
	top.get_parent().add_child(card)
	_card = card
	top.queue_free()


## Keyboard players get the controls along the bottom edge, always. The
## touch layout draws its own; a keyboard has nothing on screen to learn
## from, which is how "where are the controls" gets asked.
func _build_key_strip() -> void:
	var strip := HBoxContainer.new()
	strip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	strip.offset_left = 18.0
	strip.offset_bottom = -14.0
	strip.add_theme_constant_override(&"separation", 14)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.modulate = Color(1, 1, 1, 0.85)
	for pair in [["A D", "MOVE"], ["SPACE", "JUMP x2"], ["SHIFT", "GRAB / SWING"], ["S", "DROP / SLIDE"], ["LEFT CLICK", "PUNCH"], ["E", "SKILL"], ["ESC", "PAUSE"]]:
		var item := HBoxContainer.new()
		item.add_theme_constant_override(&"separation", 6)
		var chip := PanelContainer.new()
		var box := StyleBoxFlat.new()
		box.bg_color = UiTheme.PANEL_HI
		box.border_color = UiTheme.EDGE
		box.set_border_width_all(2)
		box.border_width_bottom = 4
		box.set_corner_radius_all(6)
		box.content_margin_left = 8
		box.content_margin_right = 8
		box.content_margin_top = 2
		box.content_margin_bottom = 2
		chip.add_theme_stylebox_override(&"panel", box)
		var key := Label.new()
		key.text = pair[0]
		key.add_theme_font_size_override(&"font_size", 13)
		key.add_theme_color_override(&"font_color", UiTheme.BANANA)
		chip.add_child(key)
		item.add_child(chip)
		var what := Label.new()
		what.text = pair[1]
		what.theme_type_variation = &"HudLabel"
		what.add_theme_font_size_override(&"font_size", 14)
		item.add_child(what)
		strip.add_child(item)
	add_child(strip)


func _build_skill_card() -> void:
	_skill_card = PanelContainer.new()
	_skill_card.theme_type_variation = &"Card"
	_skill_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skill_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_skill_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_skill_card.offset_right = -18.0
	_skill_card.offset_bottom = -52.0
	_skill_card.custom_minimum_size = Vector2(250, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	_skill_card.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 8)
	box.add_child(top)
	var key := Label.new()
	key.text = "E"
	var icon := _SkillIcon.new()
	icon.custom_minimum_size = Vector2(26, 26)
	icon.name = "SkillIcon"
	top.add_child(icon)
	key.theme_type_variation = &"HudValue"
	key.add_theme_font_size_override(&"font_size", 14)
	key.add_theme_color_override(&"font_color", UiTheme.BANANA)
	top.add_child(key)
	_skill_name = Label.new()
	_skill_name.theme_type_variation = &"HudValue"
	_skill_name.add_theme_font_size_override(&"font_size", 14)
	_skill_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_skill_name)
	_skill_state = Label.new()
	_skill_state.theme_type_variation = &"HudValue"
	_skill_state.add_theme_font_size_override(&"font_size", 14)
	top.add_child(_skill_state)
	_skill_bar = ProgressBar.new()
	_skill_bar.show_percentage = false
	_skill_bar.max_value = 1.0
	_skill_bar.custom_minimum_size = Vector2(0, 12)
	var back := StyleBoxFlat.new()
	back.bg_color = UiTheme.PANEL_HI
	back.border_color = UiTheme.OUTLINE
	back.set_border_width_all(2)
	_skill_bar.add_theme_stylebox_override(&"background", back)
	_skill_fill = StyleBoxFlat.new()
	_skill_fill.bg_color = UiTheme.BANANA
	_skill_bar.add_theme_stylebox_override(&"fill", _skill_fill)
	box.add_child(_skill_bar)
	add_child(_skill_card)


## Fills as the skill recharges, in the skill's own colour, and pops when
## it is ready again.
func _update_skill_card() -> void:
	if _skill_card == null:
		return
	_skill_card.visible = _player != null and is_instance_valid(_player) and _player.stats.skill_id != &""
	if not _skill_card.visible:
		return
	var id := _player.stats.skill_id
	var colour := SkillFx.colour_of(id)
	_skill_name.text = SkillFx.name_of(id)
	var icon := _skill_card.find_child("SkillIcon", true, false)
	if icon != null and icon.get(&"skill_id") != id:
		icon.set(&"skill_id", id)
		icon.queue_redraw()
	if _skill_style_id != id:
		_skill_style_id = id
		_skill_name.add_theme_color_override(&"font_color", colour)
		_skill_fill.bg_color = colour
	var left := _player.skill_timer
	var total := maxf(_player.stats.skill_cooldown, left)
	var cooling := left > 0.0
	_skill_bar.value = 1.0 - (left / total if cooling and total > 0.0 else 0.0)
	_skill_state.text = "%.1fs" % left if cooling else "READY"
	if _skill_style_cooling != int(cooling):
		_skill_style_cooling = int(cooling)
		_skill_state.add_theme_color_override(&"font_color", UiTheme.INK_DIM if cooling else UiTheme.LEAF)
	_skill_card.modulate = Color(1, 1, 1, 0.8) if cooling else Color.WHITE
	if _skill_was_cooling and not cooling:
		_skill_card.pivot_offset = _skill_card.size * 0.5
		var pop := _skill_card.create_tween()
		pop.tween_property(_skill_card, "scale", Vector2.ONE * 1.12, 0.08)
		pop.tween_property(_skill_card, "scale", Vector2.ONE, 0.16)
	_skill_was_cooling = cooling


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_toggle"):
		_debug = not _debug


func _process(delta: float) -> void:
	_bind()

	if _center_timer > 0.0:
		_center_timer -= delta
		if _center_timer <= 0.0:
			_center.text = ""

	_board_refresh_left -= delta
	if _board_refresh_left <= 0.0:
		_board_refresh_left = 0.1
		_update_board()
	_update_plank()
	_update_skill_card()

	if _player == null or not is_instance_valid(_player):
		_title.text = "Monkey"
		_info.text = "waiting for spawn"
		return

	_title.text = _player.stats.display_name
	if _portrait_for != _player.stats.id:
		_portrait_for = _player.stats.id
		_portrait.texture = MonkeyPortrait.texture(_portrait_for)
	var parts := _info_parts()
	_info.text = "   ".join(parts)
	_info.visible = not parts.is_empty()


func _info_parts() -> PackedStringArray:
	var parts: PackedStringArray = []
	if _debug:
		parts.append_array([_mode_text(), _state_text(_player.state), "%d px/s" % int(_player.velocity.length()), _skill_text()])
	if _race != null and _race.is_running():
		parts.append("place %d of %d" % [_live_place(), _field_size()])
	if _slap != null and _slap.is_running() and _player.team >= 0:
		parts.append("TEAM %s" % GameConfig.TEAM_NAMES[_player.team].to_upper())
		parts.append("%d DMG" % int(_player.slap_damage))
	if _hoard != null and _hoard.is_running():
		if _player.ability != &"":
			parts.append("%s %.1fs" % [String(_player.ability).replace("_", " "), _player.ability_timer])
	return parts


## Live standings sampled at 10 Hz; player simulation remains at full rate.
func _update_board() -> void:
	var rows := _board_rows()
	if rows.is_empty():
		_board_card.visible = false
		_board_sig = ""
		return
	_board_card.visible = true
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["sort"] > b["sort"])
	var sig := ""
	for row in rows:
		sig += "%s|%s|%s;" % [row["name"], row["detail"], row.get("you", false)]
	if sig == _board_sig:
		return
	_board_sig = sig
	for child in _board_list.get_children():
		child.queue_free()
	for index in rows.size():
		_board_list.add_child(_board_row(index + 1, rows[index]))


## One leaderboard line from the mock: rank chip, name, BOT tag, count.
func _board_row(place: int, row: Dictionary) -> Control:
	var you := bool(row.get("you", false))
	var line := PanelContainer.new()
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.08) if you else Color(0, 0, 0, 0)
	back.content_margin_left = 4
	back.content_margin_right = 6
	back.content_margin_top = 3
	back.content_margin_bottom = 3
	line.add_theme_stylebox_override(&"panel", back)
	line.custom_minimum_size = Vector2(290, 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 10)
	line.add_child(h)
	var chip := PanelContainer.new()
	var chip_box := StyleBoxFlat.new()
	chip_box.bg_color = UiTheme.BANANA if place == 1 else UiTheme.NAVY_BTN
	chip_box.content_margin_left = 7
	chip_box.content_margin_right = 7
	chip_box.content_margin_top = 4
	chip_box.content_margin_bottom = 4
	chip.add_theme_stylebox_override(&"panel", chip_box)
	chip.add_child(_display(str(place), 11, UiTheme.INK_DARK if place == 1 else UiTheme.INK))
	h.add_child(chip)
	var name_label := _display(String(row["name"]).to_upper(), 13, UiTheme.BANANA if you else UiTheme.INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	h.add_child(name_label)
	if bool(row.get("bot", false)):
		var tag := PanelContainer.new()
		var tag_box := StyleBoxFlat.new()
		tag_box.bg_color = Color8(36, 52, 110)
		tag_box.content_margin_left = 5
		tag_box.content_margin_right = 5
		tag_box.content_margin_top = 3
		tag_box.content_margin_bottom = 3
		tag.add_theme_stylebox_override(&"panel", tag_box)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tag.add_child(_display("BOT", 8, UiTheme.INK_DIM))
		h.add_child(tag)
	var count := _display(String(row["detail"]), 13, UiTheme.BANANA)
	count.custom_minimum_size = Vector2(40, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(count)
	return line


func _is_bot(id: int) -> bool:
	if id < 0:
		return true
	var entry: Variant = Net.roster.get(id)
	return entry is Dictionary and bool((entry as Dictionary).get("bot", false))


func _display(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override(&"font", UiTheme._font(UiTheme.FONT_DISPLAY))
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", colour)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _board_rows() -> Array:
	var arena: Node = get_tree().get_first_node_in_group(&"arena")
	if arena == null:
		return []
	var table: Variant = arena.get(&"players")
	if not (table is Dictionary):
		return []
	var hoard_running := _hoard != null and _hoard.is_running()
	var race_running := _race != null and _race.is_running()
	if _slap != null and _slap.is_running():
		return [
			{"name": "TEAM %s" % GameConfig.TEAM_NAMES[0].to_upper(), "sort": 1.0, "detail": str(_slap.scores[0]), "you": _player != null and _player.team == 0},
			{"name": "TEAM %s" % GameConfig.TEAM_NAMES[1].to_upper(), "sort": 0.0, "detail": str(_slap.scores[1]), "you": _player != null and _player.team == 1},
		]
	if not hoard_running and not race_running:
		return []

	var rows: Array = []
	for id in (table as Dictionary).keys():
		var player := (table as Dictionary)[id] as Player
		if player == null:
			continue
		var you := int(id) == Net.local_id()
		var label: String = "YOU" if you else player.display_label()
		if hoard_running:
			rows.append({"name": label, "sort": float(player.bananas), "detail": "%d" % player.bananas, "you": you, "bot": _is_bot(int(id))})
		else:
			var progress := _race.progress_of(int(id))
			rows.append({"name": label, "sort": progress, "detail": "", "you": you, "bot": _is_bot(int(id))})
	return rows


func _skill_text() -> String:
	if _player.stats.skill_id == &"":
		return "no skill"
	var label := String(_player.stats.skill_id).replace("_", " ")
	if _player.skill_timer > 0.0:
		return "%s %.1fs" % [label, _player.skill_timer]
	return "%s ready" % label


func _bind() -> void:
	var arena: Node = get_tree().get_first_node_in_group(&"arena")
	if arena == null:
		_player = null
		_race = null
		return

	if _player == null or not is_instance_valid(_player):
		var table: Variant = arena.get(&"players")
		if table is Dictionary:
			_player = table.get(Net.local_id()) as Player

	if _race == null or not is_instance_valid(_race):
		_race = arena.get(&"race") as RaceDirector
		if _race != null:
			_race.countdown_changed.connect(_on_countdown)
			_race.race_began.connect(_on_race_began)
			_race.player_finished.connect(_on_player_finished)

	if _hoard == null or not is_instance_valid(_hoard):
		_hoard = arena.get(&"hoard") as HoardDirector
		if _hoard != null:
			_hoard.countdown_changed.connect(_on_countdown)
			_hoard.hoard_began.connect(_on_race_began)

	if _slap == null or not is_instance_valid(_slap):
		_slap = arena.get(&"slap") as SlapDirector
		if _slap != null:
			_slap.countdown_changed.connect(_on_countdown)
			_slap.slap_began.connect(_on_race_began)
			_slap.scores_changed.connect(_on_slap_scores)
			_slap.round_won.connect(_on_slap_round_won)
			_slap.round_reset.connect(_on_slap_round_reset)
			_slap.player_out.connect(_on_slap_out)


## Live placement is recomputed rather than stored: it changes every time
## anyone gets knocked backwards, which is the entire point of hitting people.
func _live_place() -> int:
	if _race == null or _player == null:
		return 1
	var mine := _race.progress_of(_player.player_id)
	var arena: Node = get_tree().get_first_node_in_group(&"arena")
	var table: Variant = arena.get(&"players") if arena != null else null
	if not (table is Dictionary):
		return 1
	var ahead := 1
	for id in table.keys():
		if int(id) == _player.player_id:
			continue
		if _race.progress_of(int(id)) > mine:
			ahead += 1
	return ahead


func _field_size() -> int:
	var arena: Node = get_tree().get_first_node_in_group(&"arena")
	if arena == null:
		return 1
	var table: Variant = arena.get(&"players")
	return (table as Dictionary).size() if table is Dictionary else 1


## The team score flashed big after every knock-out: the only number in a
## 2v2 that anybody needs mid-fight.
func _on_slap_scores(_scores: Array) -> void:
	pass


func _on_slap_round_won(team: int, scores: Array) -> void:
	var head := "DRAW - REPLAY" if team < 0 else "TEAM %s TAKES THE ROUND" % GameConfig.TEAM_NAMES[team].to_upper()
	_center.text = "%s\n%d  -  %d" % [head, scores[0], scores[1]]
	_center_timer = 2.4
	Sfx.play(&"finish")


func _on_slap_round_reset(round_number: int) -> void:
	_center.text = "ROUND %d" % round_number
	_center_timer = 1.4


func _on_slap_out(player_id: int) -> void:
	if player_id != Net.local_id():
		return
	_center.text = "YOU'RE OUT\nWATCHING YOUR TEAMMATE"
	_center_timer = 1.8


func _on_countdown(value: int) -> void:
	_center.text = str(value) if value > 0 else "GO"
	_center_timer = GO_FLASH_SECONDS if value <= 0 else 2.0
	Sfx.play(&"beep" if value > 0 else &"go")


func _on_race_began() -> void:
	_center.text = "GO"
	_center_timer = GO_FLASH_SECONDS
	Sfx.play(&"go")


func _on_player_finished(player_id: int, place: int, seconds: float) -> void:
	if player_id != Net.local_id():
		return
	_center.text = "FINISHED  %d%s  -  %.2fs" % [place, _ordinal_suffix(place), seconds]
	_center_timer = 3.0
	Sfx.play(&"finish")


func _ordinal_suffix(place: int) -> String:
	match place:
		1:
			return "st"
		2:
			return "nd"
		3:
			return "rd"
	return "th"


func _mode_text() -> String:
	if not Net.is_online():
		return "local"
	return "host %d players" % Net.roster.size() if Net.is_host() else "client"


func _state_text(state: int) -> String:
	match state:
		Player.State.GROUND:
			return "ground"
		Player.State.AIR:
			return "air"
		Player.State.CLIMB:
			return "climb"
		Player.State.SWING:
			return "swing"
		Player.State.STUN:
			return "stunned"
		Player.State.SLIDE:
			return "slide"
	return "?"


class _SkillIcon extends Control:
	var skill_id: StringName = &""

	func _draw() -> void:
		var r := minf(size.x, size.y)
		SkillFx.draw_icon(self, skill_id, size * 0.5, r * 0.34, SkillFx.colour_of(skill_id))
