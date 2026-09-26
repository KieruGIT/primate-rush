extends Node
## PLAY from the lobby: no search screen, straight to the pick, then a match.

func _ready() -> void:
	get_window().theme = UiTheme.shared()
	Net.leave()
	var menu := (load("res://scenes/Menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _wait(0.8)
	menu.call(&"_on_play")
	await _wait(0.4)
	_shot("play_pick")
	var mm: Node = menu.get(&"_mm")
	print("PLAYPROBE stage after play: ", mm.get(&"stage"), " status: ", mm.get(&"status"))
	menu.call(&"_on_pick_ready")
	await _wait(2.5)
	_shot("play_started")
	print("PLAYPROBE stage after pick: ", mm.get(&"stage") if is_instance_valid(mm) else "menu gone", " scene: ", get_tree().current_scene.name)
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name_key: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://output/qa/ui_%s.png" % name_key)
