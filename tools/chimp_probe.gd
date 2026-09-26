extends Node
## Dev only. Chimp's Banana Bandit end to end: hug, getaway, snack, peel,
## and a dummy walked onto the peel. Screenshots to output/qa/chimp_*.png,
## results to output/qa/chimp.log.

var _log: PackedStringArray = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://output/qa")
	Net.leave()
	Net.local_monkey = &"capuchin"
	Net.local_skin = &"natural"
	Net.mode = GameConfig.Mode.FREE_PLAY
	Net.map_id = &"map_a"
	Net.bot_count = 1
	Net.queue = GameConfig.Queue.CLASSIC
	Net.start_match()
	var arena := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(arena)
	# Bots off before they get a single think: a bot that fires its skill
	# in the first second ruins the measurement.
	await get_tree().process_frame
	arena.set(&"bots", {})
	await _wait(1.0)
	var players: Dictionary = arena.get(&"players")
	var me: Player = players.get(1)
	var dummy: Player = null
	for pid in players.keys():
		if int(pid) < 0:
			dummy = players[pid]
	me.facing = 1
	me.hit_taken.connect(func(attacker: int, force: Vector2) -> void: _say("chimp hit by %d force %s" % [attacker, force]))
	var forced := OS.get_environment("CHIMP_DUMMY")
	if FileAccess.file_exists("res://output/qa/chimp_dummy.txt"):
		forced = FileAccess.get_file_as_string("res://output/qa/chimp_dummy.txt").strip_edges()
	if forced != "":
		dummy.stats = GameConfig.get_monkey(StringName(forced))
	dummy.global_position = me.global_position + Vector2(100, 0)
	dummy.velocity = Vector2.ZERO
	for i in 8:
		await _wait(0.05)
		_say("pre t=%.2f chimp %s stun %.2f held_by %s dummy %s %s at %s vs me %s" % [i * 0.05, Player.State.keys()[me.state], me.stun_timer, me.get(&"_held_by"), dummy.stats.id, Player.State.keys()[dummy.state], dummy.global_position.round(), me.global_position.round()])
	var start := dummy.global_position
	GameInput.touch_press(InputFrame.Action.SKILL)
	var last := ""
	for i in 40:
		await _wait(0.05)
		var peels := 0
		for node in me.get_parent().get_children():
			if node.get_script() != null and node.get_script().resource_path.ends_with("BananaPeel.gd") and not node.is_queued_for_deletion():
				peels += 1
		var line := "%s/%s peels=%d dummy=%s" % [me.get(&"_dash_kind"), Player.State.keys()[me.state], peels, Player.State.keys()[dummy.state]]
		if line != last:
			var kind := String(me.get(&"_dash_kind"))
			if kind != "":
				await _shot("chimp_" + kind)
			_say("t=%.2f chimp %s at %s, dummy %s" % [i * 0.05, line, me.global_position.round(), Player.State.keys()[dummy.state]])
			last = line
	_say("dummy moved %.0f px" % dummy.global_position.distance_to(start))
	if false:
		await _wait(0.33)
		await _shot("chimp_hug")
		_say("hug: my kind %s, dummy state %s" % [me.get(&"_dash_kind"), Player.State.keys()[dummy.state]])
		await _wait(0.3)
		await _shot("chimp_dash")
		_say("dash: my kind %s, dummy moved %.0f px, state %s" % [me.get(&"_dash_kind"), dummy.global_position.distance_to(start), Player.State.keys()[dummy.state]])
		await _wait(0.35)
		await _shot("chimp_eat")
		_say("eat: my kind %s" % me.get(&"_dash_kind"))
	# Watch the peel: thrown, landed, and whether someone slips on it.
	var peel: Node2D = null
	var seen := false
	for i in 80:
		await _wait(0.05)
		var found: Node2D = null
		for node in me.get_parent().get_children():
			if node.get_script() != null and node.get_script().resource_path.ends_with("BananaPeel.gd") and not node.is_queued_for_deletion():
				found = node
		if found != null and not seen:
			seen = true
			peel = found
		if seen and found == null:
			_say("peel gone after slip: dummy state %s, velocity %s" % [Player.State.keys()[dummy.state], dummy.velocity])
			break
		if seen and i == 40 and found != null:
			await _shot("chimp_peel")
			_say("peel resting at %s; walking dummy onto it" % found.global_position)
			dummy.global_position = found.global_position + Vector2(0, -dummy.stats.body_size.y * 0.5 - 2.0)
	if not seen:
		_say("no peel thrown")
	var f := FileAccess.open("res://output/qa/chimp.log", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_NEAREST)
	img.save_png("res://output/qa/%s.png" % name)


func _say(text: String) -> void:
	print("CHIMP ", text)
	_log.append(text)
