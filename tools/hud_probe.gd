extends Node

# ============================================================
# HUD PROBE - dev only. Starts a real match per mode and logs what the
# low-detail HUD shows (timer plank, carrying count) to checks.log.
# ============================================================

const Log = preload("res://tools/check_log.gd")
const ARENA := preload("res://scenes/Main.tscn")


func _ready() -> void:
	for mode in [GameConfig.Mode.HOARD, GameConfig.Mode.RACE, GameConfig.Mode.SLAP]:
		await _probe(mode)
	Log.line("HUD PROBE DONE")
	get_tree().quit()


func _probe(mode: int) -> void:
	Net.mode = mode
	Net.map_id = &"map_c" if mode == GameConfig.Mode.SLAP else &"map_a"
	Net.roster.clear()
	var cast: Array[StringName] = [&"macaque", &"gorilla", &"capuchin", &"orangutan"]
	for slot in cast.size():
		Net.roster[slot + 1] = {"monkey": cast[slot], "hat": &"none", "slot": slot, "bot": slot > 0, "name": ["", "Mango", "Kiwi", "Pip"][slot]}
	var arena := ARENA.instantiate()
	add_child(arena)
	for i in 300:
		await get_tree().process_frame
	var hud: Node = null
	for node in arena.find_children("*", "CanvasLayer", true, false):
		if node.get(&"_plank") != null:
			hud = node
	if hud == null:
		for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
			if node.get(&"_plank") != null:
				hud = node
	if hud == null:
		Log.line("HUD mode=%d no hud found" % mode)
	else:
		var plank: Control = hud.get(&"_plank")
		var carry: Control = hud.get(&"_carry")
		Log.line("HUD mode=%d plank=%s '%s %s' at %s size %s carry=%s '%s' running hoard=%s race=%s" % [
			mode, plank.visible, (hud.get(&"_plank_mode") as Label).text, (hud.get(&"_plank_time") as Label).text,
			plank.global_position, plank.size, carry.visible, (hud.get(&"_carry_count") as Label).text,
			(arena.get(&"hoard") as Node).call(&"is_running"), (arena.get(&"race") as Node).call(&"is_running")])
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	shot.save_png(ProjectSettings.globalize_path("res://output/qa-handoff/shots/hud_mode%d.png" % mode))
	arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
