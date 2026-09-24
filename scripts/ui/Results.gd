extends CanvasLayer

## Preloaded rather than used by class name, so a fresh checkout runs before
## the editor has rebuilt its class list.
const RankBadgeUI = preload("res://scripts/ui/RankBadge.gd")
const COSMETIC_FX = preload("res://scripts/player/CosmeticFx.gd")

# ============================================================
# RESULTS - the match-over screen from the Primate Rush mock.
#
# Night sky, the top three standing on a stone podium (1 in the middle,
# crowned), MATCH OVER and your place big on the left, and a YOUR MATCH
# panel on the right with your numbers, rank progress, HOME and AGAIN.
# Only the host decides what happens next; clients see a waiting note.
# The scene's original nodes are kept: the old panel is hidden and its two
# buttons are moved into the new layout, so every hook keeps working.
# ============================================================

const MockGround = preload("res://scripts/ui/MockGround.gd")

@onready var _panel: PanelContainer = %Panel
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _rows: VBoxContainer = %Rows
@onready var _button: Button = %BackButton
@onready var _again: Button = %AgainButton
@onready var _note: Label = %Note
@onready var _summary: Label = %Summary

var _stage: Control = null
var _place_label: Label = null
var _over_label: Label = null
var _podium: Control = null
var _stats: VBoxContainer = null
var _rank_label: Label = null
var _rank_gain: Label = null
var _rank_bar: ProgressBar = null
var _rank_note: Label = null
var _rank_badge: RankBadgeUI = null


func _ready() -> void:
	layer = 20
	UiTheme.ensure(self)
	_button.pressed.connect(func() -> void: Net.end_match())
	_again.pressed.connect(func() -> void: Net.start_match())
	var can_decide := not Net.is_online() or Net.is_host()
	_panel.visible = false
	_build()
	_button.visible = can_decide
	_again.visible = can_decide
	_note.visible = not can_decide
	_note.text = "WAITING FOR THE HOST"
	_stage.modulate.a = 0.0
	create_tween().tween_property(_stage, "modulate:a", 1.0, 0.25)


func _build() -> void:
	var root: Control = _panel.get_parent()
	var dim := root.get_parent().get_node_or_null(^"Dim") as ColorRect
	if dim != null:
		dim.color = Color(0.02, 0.03, 0.08, 1.0)
	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stage)
	var sky := MenuBackdrop.new()
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(sky)
	var ground := MockGround.new()
	ground.torches = [0.05, 0.54]
	ground.ground_height = 88.0
	_stage.add_child(ground)

	# MATCH OVER / 2ND PLACE, left of centre.
	var heading := VBoxContainer.new()
	heading.position = Vector2(150, 126)
	heading.custom_minimum_size = Vector2(500, 0)
	heading.add_theme_constant_override(&"separation", 14)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(heading)
	_over_label = _text("MATCH OVER", 14, UiTheme.INK)
	_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_child(_over_label)
	_place_label = _text("", 42, UiTheme.BANANA)
	_place_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place_label.add_theme_color_override(&"font_shadow_color", Color8(150, 78, 10))
	_place_label.add_theme_constant_override(&"shadow_offset_x", 4)
	_place_label.add_theme_constant_override(&"shadow_offset_y", 4)
	heading.add_child(_place_label)
	var sub := _text("", 11, UiTheme.INK_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.text = "%s · %s" % [
		String(GameConfig.MODE_NAMES[Net.mode]).to_upper(),
		String(GameConfig.MAP_NAMES.get(Net.map_id, String(Net.map_id))).to_upper(),
	]
	heading.add_child(sub)

	_podium = Control.new()
	_podium.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_podium.position = Vector2(110, 0)
	_stage.add_child(_podium)

	# YOUR MATCH panel, right.
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Glass"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -470.0
	panel.offset_right = -50.0
	panel.offset_top = 80.0
	panel.offset_bottom = 590.0
	_stage.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	panel.add_child(box)
	box.add_child(_text("YOUR MATCH", 11, UiTheme.INK))
	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override(&"separation", 0)
	box.add_child(_stats)
	var rank_row := HBoxContainer.new()
	box.add_child(rank_row)
	_rank_badge = RankBadgeUI.new()
	_rank_badge.custom_minimum_size = Vector2(32, 38)
	_rank_badge.visible = false
	rank_row.add_child(_rank_badge)
	_rank_label = _text("", 13, UiTheme.INK)
	_rank_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank_row.add_child(_rank_label)
	_rank_gain = _text("", 13, Color8(126, 217, 87))
	rank_row.add_child(_rank_gain)
	_rank_bar = ProgressBar.new()
	_rank_bar.show_percentage = false
	_rank_bar.max_value = 1.0
	_rank_bar.custom_minimum_size = Vector2(0, 16)
	var back := StyleBoxFlat.new()
	back.bg_color = UiTheme.NAVY_BTN
	_rank_bar.add_theme_stylebox_override(&"background", back)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.BANANA
	_rank_bar.add_theme_stylebox_override(&"fill", fill)
	box.add_child(_rank_bar)
	_rank_note = Label.new()
	_rank_note.theme_type_variation = &"Subheading"
	box.add_child(_rank_note)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 16)
	box.add_child(actions)
	_button.reparent(actions)
	_again.reparent(actions)
	_button.text = "HOME"
	_button.theme_type_variation = &"NavyButton"
	_again.text = "AGAIN"
	_again.theme_type_variation = &"PrimaryButton"
	for b in [_button, _again]:
		b.custom_minimum_size = Vector2(0, 78)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.reparent(box)


func show_results(results: Array) -> void:
	var entries: Array = []
	for entry in results:
		if entry is Dictionary:
			entries.append(entry)
	var place := -1
	var mine: Dictionary = {}
	for index in entries.size():
		if int(entries[index].get("id", 0)) == Net.local_id():
			place = index + 1
			mine = entries[index]
	_place_label.text = _verdict(place, mine)
	_build_podium(entries)
	_fill_stats(place, mine, entries.size())
	_fill_rank(place)
	# Your equipped WIN effect, over everything, when you won.
	var won := place == 1 or bool(mine.get("won", false))
	if won and not bool(mine.get("draw", false)):
		var host := Node2D.new()
		host.z_index = 50
		add_child(host)
		COSMETIC_FX.play_win(host, Loot.equipped_in(&"win"), get_viewport().get_visible_rect().size)


func _verdict(place: int, entry: Dictionary) -> String:
	if Net.mode == GameConfig.Mode.SLAP and not entry.is_empty():
		if bool(entry.get("draw", false)):
			return "DRAW!"
		return "TEAM WINS!" if bool(entry.get("won", false)) else "GOOD FIGHT!"
	if place == 1:
		return "YOU WIN!"
	if place < 0:
		return "ROUND OVER"
	return "%d%s PLACE" % [place, _ordinal_suffix(place).to_upper()]


## The top three on stone blocks: 2 left, 1 centre and tallest, 3 right.
func _build_podium(entries: Array) -> void:
	for child in _podium.get_children():
		child.queue_free()
	var view_h: float = _stage.get_viewport_rect().size.y
	var floor_y := view_h - 88.0
	var layout := [[1, 150.0, 0.0], [0, 196.0, 150.0], [2, 104.0, 300.0]]
	for spot in layout:
		var index: int = spot[0]
		if index >= entries.size():
			continue
		var entry: Dictionary = entries[index]
		var height: float = spot[1]
		var x: float = spot[2]
		var block := PanelContainer.new()
		var box := StyleBoxFlat.new()
		box.bg_color = Color8(90, 96, 122) if index == 0 else Color8(78, 84, 112)
		box.border_color = UiTheme.OUTLINE
		box.set_border_width_all(3)
		box.border_width_top = 6
		box.border_color = UiTheme.OUTLINE
		box.anti_aliasing = false
		block.add_theme_stylebox_override(&"panel", box)
		block.position = Vector2(x, floor_y - height)
		block.size = Vector2(136, height)
		block.custom_minimum_size = Vector2(136, height)
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_podium.add_child(block)
		var column := VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override(&"separation", 10)
		block.add_child(column)
		var number := _text(str(index + 1), 40 if index == 0 else 30, [UiTheme.BANANA, Color8(214, 222, 240), Color8(214, 150, 90)][index])
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(number)
		var who := _text("%s · %s" % [_name_for(int(entry.get("id", 0))).to_upper(), _short_detail(entry)], 9, UiTheme.BANANA if int(entry.get("id", 0)) == Net.local_id() else UiTheme.INK)
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		who.clip_text = true
		column.add_child(who)
		var monkey := _monkey_for(int(entry.get("id", 0)))
		if monkey != &"":
			var stage := MonkeyStage.new()
			stage.pixel_scale = 4
			stage.pedestal = false
			stage.position = Vector2(x, floor_y - height - 150.0)
			stage.size = Vector2(136, 146)
			stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_podium.add_child(stage)
			stage.set_monkey(monkey)
			if index == 0:
				var crown := Crown.new()
				crown.position = Vector2(x + 48.0, floor_y - height - 4.0 - float(MonkeyFrames.HEIGHTS.get(monkey, 46)) * 2.0 * float(MonkeySprite.MENU_SIZE.get(monkey, 1.0)) - 26.0)
				crown.size = Vector2(40, 28)
				_podium.add_child(crown)
				stage.cheer()


func _fill_stats(place: int, entry: Dictionary, field: int) -> void:
	for child in _stats.get_children():
		child.queue_free()
	var rows: Array = []
	if entry.has("team"):
		rows.append(["Team", String(GameConfig.TEAM_NAMES[int(entry.get("team", 0))]), UiTheme.BANANA])
		rows.append(["Rounds won", str(int(entry.get("score", 0))), UiTheme.BANANA])
	elif entry.has("score"):
		rows.append(["Bananas collected", str(int(entry.get("score", 0))), UiTheme.BANANA])
	elif bool(entry.get("finished", false)):
		rows.append(["Finish time", "%.2fs" % float(entry.get("time", 0.0)), UiTheme.BANANA])
	else:
		rows.append(["Finish time", "DNF", UiTheme.CORAL])
	if place > 0:
		rows.append(["Place", "%d of %d" % [place, field], UiTheme.INK])
	rows.append(["Monkey", String(GameConfig.get_monkey(_monkey_for(Net.local_id())).display_name) if _monkey_for(Net.local_id()) != &"" else "-", UiTheme.INK])
	if Loot.last_reward > 0:
		rows.append(["Bananas earned", "+%d" % Loot.last_reward, UiTheme.BANANA])
	for row in rows:
		var line := HBoxContainer.new()
		line.custom_minimum_size = Vector2(0, 46)
		var what := Label.new()
		what.text = row[0]
		what.theme_type_variation = &"Body"
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		what.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(what)
		var value := _text(String(row[1]).to_upper(), 14, row[2])
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(value)
		_stats.add_child(line)
		var rule := ColorRect.new()
		rule.color = Color8(34, 42, 76)
		rule.custom_minimum_size = Vector2(0, 2)
		_stats.add_child(rule)


## Rank progress with the same level formula as the title screen.
func _fill_rank(place: int) -> void:
	if Net.queue == GameConfig.Queue.RANKED:
		# Ranked: the bar is your division and the gain is this match's points.
		var rp := int(Profile.get_stat("rp", 0))
		var rank: Dictionary = GameConfig.rank_for(rp)
		var delta := int(Profile.get_stat("rp_last", 0))
		var before: Dictionary = GameConfig.rank_for(maxi(rp - delta, 0))
		var moved := String(before["name"]) != String(rank["name"])
		_rank_badge.visible = true
		_rank_badge.set_rp(rp)
		_rank_label.text = String(rank["name"])
		if moved:
			# A new division is the moment worth shouting about.
			_rank_label.text = "%s  %s" % ["PROMOTED!" if delta > 0 else "DOWN TO", String(rank["name"])]
		_rank_gain.text = "%+d RP" % delta
		_rank_gain.add_theme_color_override(&"font_color", UiTheme.LEAF if delta >= 0 else UiTheme.CORAL)
		_rank_bar.value = float(rank["progress"])
		_rank_note.text = "%d RP" % rp if int(rank["next"]) < 0 else "%d / %d RP to next division" % [rp, int(rank["next"])]
		return
	var races := int(Profile.get_stat("races", 0))
	var wins := int(Profile.get_stat("race_wins", 0)) + int(Profile.get_stat("hoard_wins", 0))
	var xp := races + int(Profile.get_stat("hoards", 0)) + wins
	var level := 1 + xp / 3
	var tiers := ["BRONZE", "SILVER", "GOLD", "JUNGLE"]
	var tier := mini((level - 1) / 3, tiers.size() - 1)
	var division := 3 - ((level - 1) % 3)
	_rank_label.text = "%s %s" % [tiers[tier], ["I", "II", "III"][division - 1]]
	_rank_gain.text = "+%d XP" % (2 if place == 1 else 1)
	_rank_bar.value = float(xp % 3) / 3.0
	_rank_note.text = "%d / 3 to level %d" % [xp % 3, level + 1]


func _short_detail(entry: Dictionary) -> String:
	if entry.has("team"):
		return "%d KO" % int(entry.get("score", 0))
	if entry.has("score"):
		return str(int(entry.get("score", 0)))
	if bool(entry.get("finished", false)):
		return "%.1fs" % float(entry.get("time", 0.0))
	return "DNF"


func _text(value: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.theme_type_variation = &"Display"
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _monkey_for(player_id: int) -> StringName:
	var arena := get_tree().get_first_node_in_group(&"arena")
	if arena != null:
		var table: Variant = arena.get(&"players")
		if table is Dictionary:
			var player := table.get(player_id) as Player
			if player != null:
				return player.stats.id
	if Net.roster.has(player_id):
		return StringName(Net.roster[player_id].get("monkey", &""))
	return &""


func _name_for(player_id: int) -> String:
	if player_id == Net.local_id():
		return "YOU"
	var arena := get_tree().get_first_node_in_group(&"arena")
	if arena != null:
		var table: Variant = arena.get(&"players")
		if table is Dictionary:
			var player := table.get(player_id) as Player
			if player != null:
				return player.display_label()
	if Net.roster.has(player_id):
		var entry: Dictionary = Net.roster[player_id]
		var label := String(entry.get("name", ""))
		if not label.is_empty():
			return label
	return "PLAYER %d" % player_id


func _ordinal_suffix(place: int) -> String:
	if place % 100 in [11, 12, 13]:
		return "th"
	match place % 10:
		1:
			return "st"
		2:
			return "nd"
		3:
			return "rd"
	return "th"


## Pixel crown for the winner: gold with red gems and an ink edge.
class Crown extends Control:
	func _draw() -> void:
		var p := size.x / 10.0
		var rows := ["Y.YY.YY.Y", "YYYYYYYYY", "YRYYRYYRY", "YYYYYYYYY"]
		for y in rows.size():
			for x in rows[y].length():
				var ch: String = rows[y][x]
				if ch == ".":
					continue
				draw_rect(Rect2(x * p - 2.0, y * p * 1.4 - 2.0, p + 4.0, p * 1.4 + 4.0), UiTheme.OUTLINE)
		for y in rows.size():
			for x in rows[y].length():
				var ch: String = rows[y][x]
				if ch == ".":
					continue
				draw_rect(Rect2(x * p, y * p * 1.4, p, p * 1.4), Color8(255, 216, 74) if ch == "Y" else Color8(217, 59, 59))
