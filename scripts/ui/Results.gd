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
@onready var _note: Label = %Note


func _ready() -> void:
	layer = 20
	_button.pressed.connect(func() -> void: Net.end_match())
	# Only the host can end the match. A client that could would yank three
	# other people out of a race they were still running.
	var can_end := not Net.is_online() or Net.is_host()
	_button.visible = can_end
	_note.visible = not can_end
	_note.text = "Waiting for the host to return to the lobby."


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
	var finished := bool(entry.get("finished", false))
	var detail := "%.2fs" % float(entry.get("time", 0.0)) if finished else "did not finish"
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
				return "%s%s" % [player.stats.display_name, suffix]
	return "Player %d" % player_id
