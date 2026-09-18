extends CanvasLayer

# ============================================================
# RESULTS - placement at the end of a race.
#
# Everyone gets a placement, including the monkeys who never reached the
# line. In a game with no elimination, "did not finish" with a distance is
# still a result, and a blank row reads like the game lost track of you.
# ============================================================

@onready var _rows: VBoxContainer = %Rows
@onready var _button: Button = %BackButton
@onready var _again: Button = %AgainButton
@onready var _note: Label = %Note


func _ready() -> void:
	layer = 20
	_button.pressed.connect(func() -> void: Net.end_match())
	_again.pressed.connect(func() -> void: Net.start_match())
	# Only the host decides what happens next. A client that could would
	# yank three other people out of a screen they were still reading.
	var can_decide := not Net.is_online() or Net.is_host()
	_button.visible = can_decide
	_again.visible = can_decide
	_note.visible = not can_decide
	_note.text = "Waiting for the host to pick what happens next."


func show_results(results: Array) -> void:
	for child in _rows.get_children():
		child.queue_free()
	var place := 1
	for entry in results:
		if entry is Dictionary:
			_rows.add_child(_make_row(place, entry))
			place += 1


func _make_row(place: int, entry: Dictionary) -> Label:
	var row := Label.new()
	var id := int(entry.get("id", 0))
	# Race rows carry a time, hoard rows carry a score. One overlay serves
	# both rather than two near-identical scenes drifting apart.
	var detail := ""
	if entry.has("team"):
		var team := int(entry["team"])
		var verdict := "draw" if bool(entry.get("draw", false)) else ("WIN" if bool(entry.get("won", false)) else "lost")
		detail = "Team %s  %d KOs  %s" % [GameConfig.TEAM_NAMES[team], int(entry["score"]), verdict]
	elif entry.has("score"):
		detail = "%d bananas" % int(entry["score"])
	elif bool(entry.get("finished", false)):
		detail = "%.2fs" % float(entry.get("time", 0.0))
	else:
		detail = "did not finish"
	row.text = "%d.  %s  -  %s" % [place, _name_for(id), detail]
	if id == Net.local_id():
		row.modulate = Color(1.0, 0.92, 0.55)
	return row


func _name_for(player_id: int) -> String:
	var arena: Node = get_tree().get_first_node_in_group(&"arena")
	if arena != null:
		var table: Variant = arena.get(&"players")
		if table is Dictionary:
			var player := table.get(player_id) as Player
			if player != null:
				var suffix := "  (you)" if player_id == Net.local_id() else ""
				return "%s%s" % [player.display_label(), suffix]
	return "Player %d" % player_id
