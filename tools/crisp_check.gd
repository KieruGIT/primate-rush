extends Node

# ============================================================
# CRISP CHECK - dev only. Renders the real map with all five crisp-baked
# monkeys (tools/art/pixel_bake.py), a short punch arm and a long grab arm,
# and writes two PNGs:
#   output/monkey-animation-prototype/integration/crisp-ingame.png   (1x)
#   output/monkey-animation-prototype/integration/crisp-closeup.png  (3x)
# Needs no command-line args, so it can be launched as a plain scene run.
# Poses are set directly and processing is off: same shot every run.
# ============================================================

const MAP := "res://scenes/maps/MapA.tscn"
const SIZE := Vector2i(1280, 720)
const SETTLE_FRAMES: int = 24
const OUT := "res://output/monkey-animation-prototype/integration"

const CAST := [
	{"id": &"macaque", "pose": &"run_2", "at": Vector2(-330.0, 0.0), "flip": false},
	{"id": &"capuchin", "pose": &"idle_0", "at": Vector2(-210.0, 0.0), "flip": false},
	{"id": &"gorilla", "pose": &"punch_2", "at": Vector2(-60.0, 0.0), "flip": false, "punch": true},
	{"id": &"orangutan", "pose": &"stun_1", "at": Vector2(70.0, 0.0), "flip": true},
	{"id": &"gibbon", "pose": &"swing_1", "at": Vector2(230.0, -70.0), "flip": false, "grab": Vector2(120.0, -150.0)},
]


class ArmLayer extends Node2D:
	var arms: Array = []

	func _draw() -> void:
		for arm in arms:
			MonkeyArm.draw_arm(self, arm["id"], arm["from"], arm["to"], arm["grip"], arm["facing"])


func _ready() -> void:
	var dir := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	await _shoot(dir + "/crisp-ingame.png", 1.0)
	await _shoot(dir + "/crisp-closeup.png", 3.0)
	get_tree().quit()


func _shoot(file: String, zoom: float) -> void:
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var map := (load(MAP) as PackedScene).instantiate()
	viewport.add_child(map)
	var ground := _stage(map)

	var layer := ArmLayer.new()
	layer.z_index = 11
	for entry in CAST:
		var sprite := MonkeySprite.new()
		sprite.setup(entry["id"])
		sprite.set_process(false)
		sprite.flip_h = bool(entry["flip"])
		sprite._show(entry["pose"])
		sprite.position = _snap(ground + (entry["at"] as Vector2))
		sprite.z_index = 10
		viewport.add_child(sprite)
		var shoulder: Vector2 = sprite.position + sprite.shoulder_position()
		var facing := -1 if sprite.flip_h else 1
		if entry.get("punch", false):
			# Punch: horizontal only, toward the facing side, short reach.
			layer.arms.append({"id": entry["id"], "from": shoulder, "to": shoulder + Vector2(56.0 * facing, 0.0), "grip": true, "facing": facing})
		if entry.has("grab"):
			layer.arms.append({"id": entry["id"], "from": shoulder, "to": shoulder + (entry["grab"] as Vector2), "grip": true, "facing": facing})
	viewport.add_child(layer)
	layer.queue_redraw()

	var camera := Camera2D.new()
	var focus := Vector2(-40.0, -90.0) if zoom > 1.5 else Vector2(0.0, -150.0)
	camera.position = _snap(ground + focus)
	camera.zoom = Vector2.ONE * zoom
	viewport.add_child(camera)
	camera.make_current()

	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	var error := viewport.get_texture().get_image().save_png(file)
	print("crisp check -> %s (%d)" % [file, error])
	viewport.queue_free()
	await get_tree().process_frame


func _stage(map: Node) -> Vector2:
	var best := Rect2()
	for body in map.find_children("*", "StaticBody2D", true, false):
		for child in body.get_children():
			var col := child as CollisionShape2D
			if col == null or not (col.shape is RectangleShape2D):
				continue
			if String(col.name).begins_with("ColBound"):
				continue
			var size: Vector2 = (col.shape as RectangleShape2D).size
			if size.y < 60.0 or size.x < best.size.x:
				continue
			best = Rect2(col.global_position - size * 0.5, size)
	if best.size.x <= 0.0:
		return map.get(&"spawn_point")
	return _snap(Vector2(best.position.x + best.size.x * 0.42, best.position.y))


func _snap(at: Vector2) -> Vector2:
	var grid := float(LevelSkin.SCALE)
	return (at / grid).round() * grid
