extends Node

# ============================================================
# ART MOCK - dev only. One framed shot of the real game art: a dressed map,
# a monkey mid-stride, a monkey mid-slap and the one taking it.
#
#   godot --rendering-driver opengl3 res://tools/ArtMock.tscn -- \
#       --out=DIR --skin=drawn|opp
#
# Exists to compare art directions honestly. Both sides of a comparison have
# to be the same scene, the same camera, the same poses and the same species,
# or the shot is measuring framing rather than art. So the scene is fixed
# here and only the skin underneath it changes: --skin=drawn dresses the map
# with LevelSkin (hand-drawn), --skin=opp with OppSkin (Open Pixel Project),
# and the two PNGs go side by side.
#
# Poses are set by frame index rather than played, and _process is turned
# off on each sprite, so the shot is deterministic - an animation left
# running gives a different frame every time it is run.
# ============================================================

const MAP := "res://scenes/maps/MapA.tscn"
const SIZE := Vector2i(1280, 720)
## Long enough for the map to dress itself and the torches to light.
const SETTLE_FRAMES: int = 20

## Species, pose, and offset from the framing point. Chosen to read left to
## right as a sentence: walking in, winding up, taking it.
const CAST := [
	{"id": &"macaque", "pose": &"run_1", "at": Vector2(-210.0, 0.0), "flip": false},
	{"id": &"gorilla", "pose": &"punch_2", "at": Vector2(30.0, 0.0), "flip": false},
	{"id": &"capuchin", "pose": &"stun_1", "at": Vector2(150.0, 0.0), "flip": true},
]


func _ready() -> void:
	var out := "user://"
	var skin := "drawn"
	var zoom := 1.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
		elif argument.begins_with("--skin="):
			skin = argument.trim_prefix("--skin=")
		elif argument.begins_with("--zoom="):
			zoom = float(argument.trim_prefix("--zoom="))
	await _shoot(out, skin, zoom)
	get_tree().quit()


func _shoot(out: String, skin: String, zoom: float) -> void:
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var map := (load(MAP) as PackedScene).instantiate()
	# The map dresses itself on _ready; turn that off and add the skin under
	# test instead, so both runs differ only in which skin drew the level.
	map.set(&"dressed", false)
	viewport.add_child(map)
	var dress: Node2D = OppSkin.new() if skin == "opp" else LevelSkin.new()
	dress.name = "Skin"
	map.add_child(dress)
	map.move_child(dress, 0)

	# Feet go on the real collision surface. spawn_point is where a player
	# drops in from, which is above the ground, so using it left every monkey
	# hanging in the air.
	var ground := _stage(map)
	for entry in CAST:
		var sprite := MonkeySprite.new()
		sprite.setup(entry["id"])
		sprite.set_process(false)          # no animation clock: same shot every run
		sprite.frame = MonkeySprite.POSES.keys().find(entry["pose"])
		sprite.flip_h = bool(entry["flip"])
		sprite.position = _snap(ground + (entry["at"] as Vector2))
		sprite.z_index = 10
		viewport.add_child(sprite)

	var camera := Camera2D.new()
	# Snapped to the art grid. A camera at a fractional world position shifts
	# the whole frame by part of a pixel, and then no art pixel lands on a
	# whole screen pixel however clean the zoom is - which is what made the
	# 2x shot score *below* chance on the grid audit.
	camera.position = _snap(ground + Vector2(0.0, -150.0))
	camera.zoom = Vector2.ONE * maxf(roundf(zoom), 1.0)
	viewport.add_child(camera)
	camera.make_current()

	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	var file := "%s/shot_art_%s_z%d.png" % [out.trim_suffix("/"), skin, int(zoom)]
	var error := viewport.get_texture().get_image().save_png(file)
	print("art mock -> %s (%d)" % [file, error])


## The widest ground in the map, and the point on top of it to stage on.
## Read from the collision shapes rather than from any exported hint, so it
## is the surface a monkey would actually land on.
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
	return _snap(Vector2(best.position.x + best.size.x * 0.38, best.position.y))


## Rounds a world position onto the art grid: one art pixel is SCALE world
## pixels, so anything between two of them is half a pixel of blur.
func _snap(at: Vector2) -> Vector2:
	var grid := float(LevelSkin.SCALE)
	return (at / grid).round() * grid
