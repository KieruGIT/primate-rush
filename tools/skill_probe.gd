extends Node
## For every monkey: a free-play arena, a dummy in front, press SKILL, log
## what happened to the dummy and screenshot the move. Then the Monkeys and
## Style pages of the menu.

const SHOTS := "res://output/qa-handoff/shots/"
var _log: PackedStringArray = []


func _ready() -> void:
	get_window().theme = UiTheme.shared()
	for id in [&"gorilla", &"orangutan", &"macaque", &"gibbon", &"capuchin"]:
		await _try_monkey(id)
	await _menu_pages()
	_finish()


func _try_monkey(id: StringName) -> void:
	Net.leave()
	Net.local_monkey = id
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
	var gap := 110.0
	if id == &"orangutan":
		gap = 300.0
	dummy.global_position = me.global_position + Vector2(gap, 0)
	dummy.velocity = Vector2.ZERO
	await _wait(0.4)
	var start := dummy.global_position
	GameInput.touch_press(InputFrame.Action.SKILL)
	var shot_at := {&"gorilla": 0.45, &"orangutan": 0.42, &"macaque": 0.12, &"gibbon": 0.1, &"capuchin": 0.1}
	await _wait(float(shot_at.get(id, 0.2)))
	await _shot("skill_%s" % id)
	var peak_state: String = str(Player.State.keys()[dummy.state])
	await _wait(0.8)
	_say("%s: dummy moved %.0f px, state then %s, my skill timer %.1f" % [id, dummy.global_position.distance_to(start), peak_state, me.skill_timer])
	if id == &"gibbon":
		# The swing should run at one speed from the ground and the air.
		dummy.global_position += Vector2(2000, 0)
		await _wait(1.2)
		await _measure_swoop(me, "ground")
		await _wait(4.5)
		me.global_position += Vector2(-300, -220)
		me.velocity = Vector2.ZERO
		await get_tree().physics_frame
		await _measure_swoop(me, "air")
	arena.queue_free()
	await _wait(0.2)
	Net.leave()


func _measure_swoop(me: Player, label: String) -> void:
	GameInput.touch_press(InputFrame.Action.SKILL)
	await get_tree().physics_frame
	var speeds: Array = []
	var last := me.global_position
	for i in 60:
		await get_tree().physics_frame
		if me.state != Player.State.DASH:
			break
		speeds.append(me.global_position.distance_to(last) * Engine.physics_ticks_per_second)
		last = me.global_position
	if speeds.size() > 2:
		speeds = speeds.slice(1, speeds.size() - 1)
	var lo := 99999.0
	var hi := 0.0
	for v in speeds:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	_say("gibbon swing %s: %d frames, speed %.0f..%.0f px/s" % [label, speeds.size(), lo, hi])


func _menu_pages() -> void:
	Net.local_monkey = &"gorilla"
	var menu := (load("res://scenes/Menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _wait(0.6)
	menu.call(&"_show", 1, false)
	await _wait(1.6)
	await _shot("menu_monkeys")
	menu.call(&"_show", 6, false)
	menu.call(&"_on_skin", &"lava")
	menu.call(&"_on_hat", &"shades")
	await _wait(0.8)
	await _shot("menu_style")
	# Put the look back the way it was.
	menu.call(&"_on_skin", &"natural")
	menu.call(&"_on_hat", &"none")
	menu.call(&"_show", 0, false)
	await _wait(0.5)
	await _shot("menu_home")
	menu.queue_free()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(SHOTS + name + ".png"))


func _say(text: String) -> void:
	print("SKILL PROBE ", text)
	_log.append(text)


func _finish() -> void:
	var f := FileAccess.open("res://output/qa-handoff/checks.log", FileAccess.READ_WRITE)
	if f != null:
		f.seek_end()
		for line in _log:
			f.store_line("%s  SKILL %s" % [Time.get_datetime_string_from_system(), line])
		f.store_line("%s  SKILL PROBE DONE" % Time.get_datetime_string_from_system())
		f.close()
	get_tree().quit()
