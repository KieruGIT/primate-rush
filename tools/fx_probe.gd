extends Node
## Dev only. Equips legendary effects, runs the local monkey right while
## punching, and screenshots the trail and punch; then shows the results
## screen as a winner for the WIN effect. Saves res://output/qa/fx_*.png.

const ARENA := preload("res://scenes/Main.tscn")
const RESULTS := preload("res://scenes/Results.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var keep := Loot.equipped.duplicate()
	for id in [&"trail_fire", &"punch_thunder", &"climb_gold", &"win_fireworks"]:
		Loot.owned[id] = true
		Loot.equipped[Loot.item(id)["slot"]] = id
	Net.leave()
	Net.local_monkey = &"gibbon"
	Net.set_match_config(&"map_d", GameConfig.Mode.FREE_PLAY)
	Net.set_bot_count(0)
	Net.start_match()
	var arena := ARENA.instantiate()
	add_child(arena)
	await get_tree().create_timer(1.2).timeout
	Input.action_press(&"move_right")
	Input.action_press(&"sprint")
	await get_tree().create_timer(0.9).timeout
	Input.action_press(&"attack")
	await get_tree().create_timer(0.14).timeout
	_shot("run")
	Input.action_release(&"attack")
	Input.action_release(&"move_right")
	Input.action_release(&"sprint")
	arena.queue_free()
	await get_tree().create_timer(0.3).timeout
	var results := RESULTS.instantiate()
	add_child(results)
	results.call(&"show_results", [{"id": Net.local_id(), "finished": true, "time": 42.0}])
	await get_tree().create_timer(1.6).timeout
	_shot("win")
	Loot.equipped = keep
	get_tree().quit()


func _shot(key: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://output/qa/fx_%s.png" % key)
