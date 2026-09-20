extends CanvasLayer

# ============================================================
# HUD - connection state, monkey, movement state, race state.
#
# The movement state readout stays in the shipped build. In a game with five
# states and no animation yet, "why did that happen" is only answerable if
# you can see which state you were in when it happened.
# ============================================================

const GO_FLASH_SECONDS: float = 0.9

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


func _ready() -> void:
	layer = 5
	_center.text = ""
	_build_card()
	_build_board_card()
	if not OS.has_feature("mobile"):
		_build_key_strip()
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
	_board.reparent(_board_card)
	_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_board_card.visible = false


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
	for pair in [["A D", "MOVE"], ["SPACE / W", "JUMP + CLIMB"], ["SHIFT", "SPRINT"], ["L", "DASH"], ["LEFT CLICK", "SLAP"], ["E", "SKILL"], ["ESC", "PAUSE"]]:
		var item := HBoxContainer.new()
		item.add_theme_constant_override(&"separation", 6)
		var chip := PanelContainer.new()
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.94, 0.95, 0.92)
		box.border_color = Color(0.13, 0.11, 0.10)
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
		key.add_theme_color_override(&"font_color", Color(0.15, 0.13, 0.12))
		chip.add_child(key)
		item.add_child(chip)
		var what := Label.new()
		what.text = pair[1]
		what.theme_type_variation = &"HudLabel"
		what.add_theme_font_size_override(&"font_size", 14)
		item.add_child(what)
		strip.add_child(item)
	add_child(strip)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_toggle"):
		_debug = not _debug


func _process(delta: float) -> void:
	_bind()

	if _center_timer > 0.0:
		_center_timer -= delta
		if _center_timer <= 0.0:
			_center.text = ""

	_update_board()

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
		parts.append("%.1fs" % _race.elapsed)
		parts.append("place %d of %d" % [_live_place(), _field_size()])
	if _slap != null and _slap.is_running() and _player.team >= 0:
		parts.append("TEAM %s" % GameConfig.TEAM_NAMES[_player.team].to_upper())
		parts.append("%d DMG" % int(_player.slap_damage))
		parts.append("%d:%02d" % [int(_slap.time_left) / 60, int(_slap.time_left) % 60])
	if _hoard != null and _hoard.is_running():
		parts.append("%d bananas" % _player.bananas)
		parts.append("%d:%02d left" % [int(_hoard.time_left) / 60, int(_hoard.time_left) % 60])
		if _player.ability != &"":
			parts.append("%s %.1fs" % [String(_player.ability).replace("_", " "), _player.ability_timer])
	return parts


## Live standings. Sorted every frame rather than cached, because both
## orders change constantly: that is what hitting people is for.
func _update_board() -> void:
	var rows := _board_rows()
	if rows.is_empty():
		_board.text = ""
		_board_card.visible = false
		return
	_board_card.visible = true
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["sort"] > b["sort"])
	var lines: PackedStringArray = []
	for index in rows.size():
		var row: Dictionary = rows[index]
		lines.append("%d. %s  %s" % [index + 1, row["name"], row["detail"]])
	_board.text = "\n".join(lines)


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
			{"name": "TEAM %s" % GameConfig.TEAM_NAMES[0].to_upper(), "sort": 1.0, "detail": str(_slap.scores[0])},
			{"name": "TEAM %s" % GameConfig.TEAM_NAMES[1].to_upper(), "sort": 0.0, "detail": str(_slap.scores[1])},
		]
	if not hoard_running and not race_running:
		return []

	var rows: Array = []
	for id in (table as Dictionary).keys():
		var player := (table as Dictionary)[id] as Player
		if player == null:
			continue
		var label: String = player.display_label()
		if int(id) == Net.local_id():
			label += " (you)"
		if hoard_running:
			rows.append({"name": label, "sort": float(player.bananas), "detail": "%d" % player.bananas})
		else:
			var progress := _race.progress_of(int(id))
			rows.append({"name": label, "sort": progress, "detail": ""})
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
func _on_slap_scores(scores: Array) -> void:
	_center.text = "%d  -  %d" % [scores[0], scores[1]]
	_center_timer = 1.1
	Sfx.play(&"finish")


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
	return "?"
