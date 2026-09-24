extends Node
## Plays a 4-monkey match (bots) on each map and logs where frame time goes.

var _log: PackedStringArray = []


func _ready() -> void:
	get_window().theme = UiTheme.shared()
	for map_id in [&"map_a", &"map_b", &"map_c"]:
		await _measure(map_id, 3)
	await _measure(&"map_a", 0)
	var f := FileAccess.open("res://output/qa-handoff/checks.log", FileAccess.READ_WRITE)
	if f != null:
		f.seek_end()
		for line in _log:
			f.store_line("%s  PERF %s" % [Time.get_datetime_string_from_system(), line])
		f.close()
	get_tree().quit()


func _measure(map_id: StringName, bots: int) -> void:
	Net.leave()
	Net.local_monkey = &"gorilla"
	Net.mode = GameConfig.Mode.FREE_PLAY
	Net.map_id = map_id
	Net.bot_count = bots
	Net.start_match()
	var arena := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	arena.set(&"force_touch_controls", true)
	add_child(arena)
	await get_tree().create_timer(2.0).timeout
	var frames := 0
	var proc := 0.0
	var phys := 0.0
	var draws := 0
	var worst := 0.0
	var t0 := Time.get_ticks_usec()
	var last := t0
	while Time.get_ticks_usec() - t0 < 4000000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		draws += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var secs := (Time.get_ticks_usec() - t0) / 1e6
	_log.append("%s bots=%d: %.0f fps, process %.2f ms, physics %.2f ms, draw calls %d, worst frame %.1f ms, nodes %d, objects %d" % [
		map_id, bots, frames / secs, proc / frames * 1000.0, phys / frames * 1000.0, draws / frames, worst,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))])
	print("PERF ", _log[-1])
	arena.queue_free()
	await get_tree().create_timer(0.3).timeout
