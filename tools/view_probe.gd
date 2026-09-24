extends Node
## Dev only. Opens each map, parks the local monkey at a few spots (spawn,
## high above it, low near the water, far right) and saves a screenshot of
## each to res://output/qa/view_<map>_<n>.png, for checking the backdrop,
## the water line and the canopy without playing.

const ARENA := preload("res://scenes/Main.tscn")

var _hold: Vector2 = Vector2.INF
var _player: Node2D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute("res://output/qa")
	var lines: PackedStringArray = []
	var maps: Array = GameConfig.MAP_PATHS.keys()
	for map_id in maps:
		Net.leave()
		Net.local_monkey = &"gibbon"
		Net.set_match_config(map_id, GameConfig.Mode.FREE_PLAY)
		Net.set_bot_count(0)
		Net.start_match()
		var arena := ARENA.instantiate()
		add_child(arena)
		await get_tree().create_timer(0.6).timeout
		var players: Dictionary = arena.get("players")
		_player = players.values()[0]
		var skin: Node = arena.find_child("LevelSkin", true, false)
		var water: float = float(skin.get("_water_y")) if skin != null else 900.0
		var bounds: Rect2 = skin.get("_bounds") if skin != null else Rect2()
		var spawn: Vector2 = _player.global_position
		var spots := [spawn, spawn + Vector2(0, -420), Vector2(bounds.get_center().x, water - 180.0), Vector2(bounds.end.x - 400.0, spawn.y - 60.0)]
		for i in spots.size():
			_hold = spots[i]
			await get_tree().create_timer(1.3).timeout
			var img := get_viewport().get_texture().get_image()
			img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_NEAREST)
			img.save_png("res://output/qa/view_%s_%d.png" % [map_id, i])
			lines.append("%s spot %d at %s water %.0f" % [map_id, i, spots[i], water])
		_hold = Vector2.INF
		arena.queue_free()
		await get_tree().create_timer(0.3).timeout
	preload("res://tools/qa_log.gd").write("view", lines)
	get_tree().quit()


func _physics_process(_delta: float) -> void:
	if _hold != Vector2.INF and is_instance_valid(_player):
		_player.global_position = _hold
		_player.set(&"velocity", Vector2.ZERO)
