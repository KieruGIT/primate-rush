extends Node
## Boots the real game, then walks it: loading screen, controls page,
## ranked search, match start, and a forced match end, logging and saving a
## screenshot at each step to output/qa-handoff.

const SHOTS := "res://output/qa-handoff/shots/"
var _log: PackedStringArray = []


func _ready() -> void:
	var boot := (load("res://scenes/Boot.tscn") as PackedScene).instantiate()
	add_child(boot)
	await _wait(0.5)
	await _shot("live_splash")
	await _wait(4.5)
	var menu := _find(boot, "Menu")
	_say("menu found=%s" % (menu != null))
	if menu == null:
		_finish()
		return
	menu.call(&"_show", 5, false)
	await _wait(0.4)
	await _shot("live_controls")
	menu.call(&"_show", 0, false)
	menu.call(&"_set_queue", GameConfig.Queue.RANKED)
	await _wait(0.4)
	await _shot("live_home_ranked")
	menu.call(&"_on_play")
	await _wait(1.2)
	var mm: Node = menu.get_node_or_null(^"Matchmaker")
	_say("search stage=%s status='%s' queue=%d mode=%d" % [mm.get(&"stage"), mm.get(&"status"), Net.queue, Net.mode])
	await _shot("live_search")
	await _wait(4.0)
	if is_instance_valid(mm):
		_say("after listen stage=%s status='%s' link=%d searching=%s" % [mm.get(&"stage"), mm.get(&"status"), Net.link, Net.searching])
		await _shot("live_search_hosting")
	# Match should start once the wait runs out.
	var arena: Node = null
	for i in 40:
		await _wait(0.5)
		arena = get_tree().get_first_node_in_group(&"arena")
		if arena != null:
			break
	_say("arena started=%s roster=%d bots=%s skill=%d" % [arena != null, Net.roster.size(), str(Net.roster.keys()), Net.bot_skill])
	if arena == null:
		_finish()
		return
	await _wait(7.0)
	# Force the round to end the way a director does.
	var results: Array = []
	var ids: Array = (arena.get(&"players") as Dictionary).keys()
	for id in ids:
		results.append({"id": int(id), "time": 30.0, "finished": true, "score": 3})
	var rp_before := int(Profile.get_stat("rp", 0))
	arena.call(&"_on_match_over", results)
	var players: Dictionary = arena.get(&"players")
	var p0: Node2D = players.values()[1] if players.size() > 1 else players.values()[0]
	var before := p0.global_position
	await _wait(2.0)
	var moved := p0.global_position.distance_to(before)
	var disabled := 0
	for p in players.values():
		if (p as Node).process_mode == Node.PROCESS_MODE_DISABLED:
			disabled += 1
	_say("after end: frozen=%d/%d bot moved %.1f px  rp %d -> %d" % [disabled, players.size(), moved, rp_before, int(Profile.get_stat("rp", 0))])
	await _shot("live_results_ranked")
	# Undo the probe's ranked points so a test never changes the real career.
	Profile.set_stat("rp", rp_before)
	Net.queue = GameConfig.Queue.CLASSIC
	_finish()


func _find(root: Node, script_name: String) -> Node:
	for child in root.get_children():
		var s: Script = child.get_script()
		if s != null and s.resource_path.get_file().get_basename() == script_name:
			return child
	return null


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(SHOTS + name + ".png"))


func _say(text: String) -> void:
	print("MM PROBE ", text)
	_log.append(text)


func _finish() -> void:
	var f := FileAccess.open("res://output/qa-handoff/checks.log", FileAccess.READ_WRITE)
	if f != null:
		f.seek_end()
		for line in _log:
			f.store_line("%s  MM %s" % [Time.get_datetime_string_from_system(), line])
		f.store_line("%s  MM PROBE DONE" % Time.get_datetime_string_from_system())
		f.close()
	get_tree().quit()
