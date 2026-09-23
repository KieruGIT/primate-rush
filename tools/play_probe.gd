extends Node
## Opens a real arena (free play, Jungle Run) and takes screenshots of the
## punch, a skill firing, the grab marker, a swing and a platform drop.

const SHOTS := "res://output/qa-handoff/shots/"
var _log: PackedStringArray = []


func _ready() -> void:
	Net.leave()
	Net.local_monkey = &"capuchin"
	Net.mode = GameConfig.Mode.FREE_PLAY
	Net.map_id = &"map_a"
	Net.bot_count = 1
	Net.queue = GameConfig.Queue.CLASSIC
	Net.start_match()
	get_window().theme = UiTheme.shared()
	var arena := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	arena.set(&"force_touch_controls", true)
	add_child(arena)
	await _wait(1.2)
	var players: Dictionary = arena.get(&"players")
	var me: Player = players.get(1)
	var bot: Player = null
	for id in players.keys():
		if int(id) < 0:
			bot = players[id]
	arena.set(&"bots", {})  # hold the bot still as a punching bag
	# 1. Punch a monkey standing in front.
	me.facing = 1
	bot.global_position = me.global_position + Vector2(96, 0)
	await _wait(0.5)
	GameInput.touch_press(InputFrame.Action.ATTACK)
	await _wait(0.1)
	await _shot("play_punch")
	_say("punch: bot vx %.0f state %s" % [bot.velocity.x, Player.State.keys()[bot.state]])
	await _wait(0.9)
	# 2. Skill: capuchin snatch (always fires).
	GameInput.touch_press(InputFrame.Action.SKILL)
	await _wait(0.12)
	await _shot("play_skill")
	_say("skill timer %.1f" % me.skill_timer)
	await _wait(0.6)
	await _shot("play_skill_cooldown")
	# 3. Grab marker and swing near a tree branch.
	var branch: Node2D = null
	for node in arena.find_children("*", "Climbable", true, false):
		if String(node.name).begins_with("BranchClimbable"):
			branch = node
			break
	if branch != null:
		me.respawn_at(branch.global_position + Vector2(-20.0, 120.0))
		await _wait(0.15)
		await _shot("play_grab_marker")
		_say("grab marker at %s" % str(me.get(&"_grab_preview")))
		GameInput.touch_grab_held = true
		GameInput.touch_move = Vector2(1, 0)
		await _wait(0.5)
		await _shot("play_swing")
		_say("swing state %s on %s" % [Player.State.keys()[me.state], str((me.get(&"_swing_node") as Node).name) if me.get(&"_swing_node") != null else "-"])
		GameInput.touch_grab_held = false
		GameInput.touch_move = Vector2.ZERO
	# 4. A ledge: stand on it, then drop through.
	var ledge_top := INF
	var ledge_x := 0.0
	var platforms := arena.find_child("Platforms", true, false)
	_say("platform body found=%s shapes=%d" % [platforms != null, platforms.get_child_count() if platforms != null else 0])
	if platforms != null and platforms.get_child_count() > 0:
		var col := platforms.get_child(0) as CollisionShape2D
		var size: Vector2 = (col.shape as RectangleShape2D).size
		ledge_top = col.global_position.y - size.y * 0.5
		ledge_x = col.global_position.x
		me.respawn_at(Vector2(ledge_x, ledge_top - 60.0))
		await _wait(0.8)
		_say("on ledge: y %.0f top %.0f floor %s platform %s" % [me.global_position.y, ledge_top, me.is_on_floor(), me.get(&"_on_platform")])
		await _shot("play_on_ledge")
		GameInput.touch_move = Vector2(0, 1)
		await _wait(0.5)
		GameInput.touch_move = Vector2.ZERO
		_say("after down: y %.0f (below top: %s)" % [me.global_position.y, me.global_position.y > ledge_top])
	_finish()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(SHOTS + name + ".png"))


func _say(text: String) -> void:
	print("PLAY PROBE ", text)
	_log.append(text)


func _finish() -> void:
	var f := FileAccess.open("res://output/qa-handoff/checks.log", FileAccess.READ_WRITE)
	if f != null:
		f.seek_end()
		for line in _log:
			f.store_line("%s  PLAY %s" % [Time.get_datetime_string_from_system(), line])
		f.store_line("%s  PLAY PROBE DONE" % Time.get_datetime_string_from_system())
		f.close()
	get_tree().quit()
