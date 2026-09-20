extends CanvasLayer

# ============================================================
# RESULTS - a readable end cap for the whole match loop.
#
# Results are player cards rather than a block of text: face, name, monkey,
# placement and outcome can be read in that order from across a phone. The
# local row is highlighted and the host-only decision remains unchanged.
# ============================================================

@onready var _panel: PanelContainer = %Panel
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _rows: VBoxContainer = %Rows
@onready var _button: Button = %BackButton
@onready var _again: Button = %AgainButton
@onready var _note: Label = %Note
@onready var _summary: Label = %Summary


func _ready() -> void:
	layer = 20
	_button.pressed.connect(func() -> void: Net.end_match())
	_again.pressed.connect(func() -> void: Net.start_match())
	# Only the host decides what happens next. A client that could would yank
	# three other people out of a screen they were still reading.
	var can_decide := not Net.is_online() or Net.is_host()
	_button.visible = can_decide
	_again.visible = can_decide
	_note.visible = not can_decide
	_note.text = "WAITING FOR THE HOST TO CHOOSE WHAT HAPPENS NEXT"
	_subtitle.text = "%s   ·   %s" % [
		String(GameConfig.MODE_NAMES[Net.mode]).to_upper(),
		String(GameConfig.MAP_NAMES.get(Net.map_id, String(Net.map_id))).to_upper(),
	]
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.97, 0.97)
	_panel.pivot_offset = Vector2(460.0, 320.0)
	var intro := create_tween().set_parallel(true)
	intro.tween_property(_panel, "modulate:a", 1.0, 0.2)
	intro.tween_property(_panel, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func show_results(results: Array) -> void:
	for child in _rows.get_children():
		child.queue_free()

	var local_place := -1
	var local_entry: Dictionary = {}
	for index in results.size():
		var entry: Variant = results[index]
		if not entry is Dictionary:
			continue
		_rows.add_child(_make_row(index + 1, entry))
		if int(entry.get("id", 0)) == Net.local_id():
			local_place = index + 1
			local_entry = entry

	_set_verdict(local_place, local_entry)


func _set_verdict(place: int, entry: Dictionary) -> void:
	if place < 0:
		_title.text = "ROUND COMPLETE"
		_title.add_theme_color_override(&"font_color", UiTheme.BANANA)
		_summary.text = "THE JUNGLE KEEPS THE SCORE. READY FOR ANOTHER ROUND?"
		return

	if Net.mode == GameConfig.Mode.SLAP:
		if bool(entry.get("draw", false)):
			_title.text = "DRAW!"
			_title.add_theme_color_override(&"font_color", UiTheme.SKY)
		elif bool(entry.get("won", false)):
			_title.text = "YOUR TEAM WINS!"
			_title.add_theme_color_override(&"font_color", UiTheme.LEAF)
		else:
			_title.text = "GOOD FIGHT!"
			_title.add_theme_color_override(&"font_color", UiTheme.CORAL)
		_summary.text = "TEAM %s FINISHED WITH %d KNOCKOUTS" % [
			String(GameConfig.TEAM_NAMES[int(entry.get("team", 0))]).to_upper(),
			int(entry.get("score", 0)),
		]
	elif place == 1:
		_title.text = "YOU WIN!"
		_title.add_theme_color_override(&"font_color", UiTheme.BANANA)
		_summary.text = _personal_result(entry)
	else:
		_title.text = "%d%s PLACE" % [place, _ordinal_suffix(place).to_upper()]
		_title.add_theme_color_override(&"font_color", UiTheme.INK)
		_summary.text = _personal_result(entry)


func _personal_result(entry: Dictionary) -> String:
	if entry.has("score"):
		return "%d BANANAS BANKED THIS ROUND" % int(entry.get("score", 0))
	if bool(entry.get("finished", false)):
		return "FINISH TIME  %.2f SECONDS" % float(entry.get("time", 0.0))
	return "KEEP MOVING — THE NEXT FINISH LINE IS YOURS"


func _make_row(place: int, entry: Dictionary) -> Control:
	var player_id := int(entry.get("id", 0))
	var is_you := player_id == Net.local_id()
	var row := PanelContainer.new()
	row.theme_type_variation = &"CardHighlight" if is_you else &"Glass"
	row.custom_minimum_size = Vector2(0.0, 72.0)
	row.modulate.a = 0.0
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 14)
	row.add_child(line)

	var place_label := Label.new()
	place_label.text = "#%d" % place
	place_label.theme_type_variation = &"Display"
	place_label.custom_minimum_size = Vector2(64.0, 0.0)
	place_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	place_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	place_label.add_theme_font_size_override(&"font_size", 28)
	place_label.add_theme_color_override(&"font_color", _place_colour(place))
	line.add_child(place_label)

	var monkey_id := _monkey_for(player_id)
	var face := TextureRect.new()
	face.custom_minimum_size = Vector2(56.0, 56.0)
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if monkey_id != &"":
		face.texture = MonkeyPortrait.texture(monkey_id)
	line.add_child(face)

	var identity := VBoxContainer.new()
	identity.alignment = BoxContainer.ALIGNMENT_CENTER
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(identity)
	var name := Label.new()
	name.text = _name_for(player_id).to_upper()
	name.theme_type_variation = &"Display"
	name.add_theme_font_size_override(&"font_size", 22)
	identity.add_child(name)
	var species := Label.new()
	species.text = (String(GameConfig.get_monkey(monkey_id).display_name).to_upper() if monkey_id != &"" else "MONKEY") + ("   ·   YOU" if is_you else "")
	species.theme_type_variation = &"Subheading"
	identity.add_child(species)

	var detail := Label.new()
	detail.text = _result_detail(entry)
	detail.theme_type_variation = &"Display"
	detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	detail.add_theme_font_size_override(&"font_size", 21)
	line.add_child(detail)

	# Staggering the rows makes the result order land one place at a time.
	var reveal := create_tween()
	reveal.tween_interval(0.08 * float(place - 1))
	reveal.tween_property(row, "modulate:a", 1.0, 0.18)
	return row


func _result_detail(entry: Dictionary) -> String:
	if entry.has("team"):
		return "TEAM %s   %d KOs" % [
			String(GameConfig.TEAM_NAMES[int(entry.get("team", 0))]).to_upper(),
			int(entry.get("score", 0)),
		]
	if entry.has("score"):
		return "%d BANANAS" % int(entry.get("score", 0))
	if bool(entry.get("finished", false)):
		return "%.2fs" % float(entry.get("time", 0.0))
	return "DID NOT FINISH"


func _place_colour(place: int) -> Color:
	match place:
		1:
			return UiTheme.BANANA
		2:
			return Color(0.78, 0.84, 0.86)
		3:
			return Color(0.86, 0.54, 0.25)
	return UiTheme.INK_DIM


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
	return "YOU" if player_id == Net.local_id() else "PLAYER %d" % player_id


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
