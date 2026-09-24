extends Node
## Map A match with bots; turns each kind of node off in turn and logs how
## much frame time that saves, so the lag has a name.

var _log: PackedStringArray = []


func _ready() -> void:
	get_window().theme = UiTheme.shared()
	Net.leave()
	Net.local_monkey = &"gorilla"
	Net.mode = GameConfig.Mode.FREE_PLAY
	Net.map_id = &"map_a"
	Net.bot_count = 3
	Net.start_match()
	var arena := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	arena.set(&"force_touch_controls", true)
	add_child(arena)
	await get_tree().create_timer(2.0).timeout
	var base := await _sample()
	_log.append("baseline: process %.2f ms, physics %.2f ms, primitives %d" % base)
	var groups: Dictionary = {}
	for node in get_tree().root.find_children("*", "", true, false):
		var s: Script = node.get_script()
		var key := ""
		if s != null:
			key = s.resource_path.get_file()
			if key.is_empty():
				key = "inner:" + str(s.get_instance_id())
		if key.is_empty() or key in ["perf_split.gd", "Main.gd"]:
			continue
		if not groups.has(key):
			groups[key] = []
		groups[key].append(node)
	for key: String in groups.keys():
		var nodes: Array = groups[key]
		var label: String = str(key)
		if key.begins_with("inner:"):
			label = "%s(%s)" % [nodes[0].get_class(), nodes[0].name]
		for n in nodes:
			n.process_mode = Node.PROCESS_MODE_DISABLED
			if n is CanvasItem:
				(n as CanvasItem).visible = false
		var t := await _sample()
		for n in nodes:
			n.process_mode = Node.PROCESS_MODE_INHERIT
			if n is CanvasItem:
				(n as CanvasItem).visible = true
		var saved: float = base[0] - t[0]
		var saved_p: float = base[1] - t[1]
		if saved > 0.8 or saved_p > 0.8 or base[2] - t[2] > 1000:
			_log.append("%s x%d: saves process %.2f ms, physics %.2f ms, primitives %d" % [label, nodes.size(), saved, saved_p, base[2] - t[2]])
	var f := FileAccess.open("res://output/qa-handoff/checks.log", FileAccess.READ_WRITE)
	f.seek_end()
	for line in _log:
		f.store_line("%s  PERF %s" % [Time.get_datetime_string_from_system(), line])
		print("PERF ", line)
	f.close()
	get_tree().quit()


func _sample() -> Array:
	await get_tree().create_timer(0.3).timeout
	var frames := 0
	var proc := 0.0
	var phys := 0.0
	var prims := 0
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 1500000:
		await get_tree().process_frame
		frames += 1
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		prims += int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	return [proc / frames * 1000.0, phys / frames * 1000.0, prims / frames]
