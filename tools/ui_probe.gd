extends Node
## Dev only. Screenshots of the style page, the monkey pick countdown and
## the performance overlay, saved to res://output/qa/ui_<name>.png.

const MENU := preload("res://scenes/Menu.tscn")
const ARENA := preload("res://scenes/Main.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute("res://output/qa")
	var menu := MENU.instantiate()
	add_child(menu)
	await _wait(0.8)
	Loot.add_bananas(1000)
	menu.call(&"_show", 4, false)
	await _wait(0.9)
	_shot("shop")
	menu.call(&"_set_shop_tab", 1)
	await _wait(0.9)
	_shot("gacha_idle")
	menu.call(&"_on_pull", 10, false)
	await _wait(1.2)
	_shot("gacha")
	menu.call(&"_show", 6, false)
	await _wait(0.8)
	_shot("style")
	menu.call(&"_show", 7, false)
	await _wait(0.8)
	_shot("ranks")
	Net.queue = GameConfig.Queue.RANKED
	Loot.set_stake(100)
	menu.call(&"_show", 0, false)
	await _wait(0.8)
	_shot("home")
	Net.queue = GameConfig.Queue.CLASSIC
	Loot.set_stake(0)
	menu.call(&"_show", 0, false)
	var mm: Node = menu.get(&"_mm")
	mm.set(&"stage", 6)
	mm.set(&"pick_left", 9.0)
	menu.call(&"_refresh_search")
	await _wait(0.8)
	_shot("pick")
	mm.set(&"stage", 0)
	menu.queue_free()
	await _wait(0.3)
	Net.leave()
	Net.local_monkey = &"gibbon"
	Net.set_match_config(&"map_d", GameConfig.Mode.FREE_PLAY)
	Net.set_bot_count(3)
	Net.start_match()
	var arena := ARENA.instantiate()
	arena.set(&"force_touch_controls", true)
	add_child(arena)
	await _wait(1.5)
	PerfOverlay.toggle()
	await _wait(1.2)
	_shot("overlay")
	PerfOverlay.toggle()
	await _wait(0.5)
	_shot("touch")
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name_key: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://output/qa/ui_%s.png" % name_key)
