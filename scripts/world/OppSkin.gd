class_name OppSkin
extends Node2D

# ============================================================
# OPP SKIN - dresses a gray-box map in the Open Pixel Project jungle set.
#
# The alternative to LevelSkin, kept beside it rather than replacing it, so
# the two art directions can be rendered from the same map, the same camera
# and the same poses and compared honestly. Whichever wins, the loser gets
# deleted; until then neither is allowed to quietly become the other.
#
# The pack is CC0, 32 px, DB32 palette. Its ground pieces are 32 wide and
# *64 tall*: the lower half is the solid body and the upper half is grass
# overhanging above it. So a surface is drawn a whole tile higher than the
# collision top, which is what gives the platform its fringe - the thing the
# key art has and a flat capped tile cannot fake.
#
#   OVERHANG ->  ,,\,,,/,,     32 px of grass, above the collision line
#   collision -> ===========
#   body      -> |:.::o::.:|   32 px of solid dirt
#
# Everything else is the same contract as LevelSkin: read the collision
# rectangles back out of the map, hide the gray boxes, draw over the same
# footprint. A level edit stays one number in a .tscn.
# ============================================================

const PACK := "res://assets/opp_jungle/tiles/"
const SRC: int = 32
const SCALE: int = 2
const TILE: int = SRC * SCALE
## Grass rises this far above the collision surface.
const OVERHANG: int = SRC

# Regions inside the pack's sheets, measured off the sheets themselves.
# tile_jungle_tree_dark is 320x352: canopy blobs across the top, then one
# big trunk with branches filling the lower two thirds.
const TREE_TRUNK := Rect2(0, 96, 232, 256)
## tile_jungle_vegetation is a 256x32 strip of eight ground plants.
const VEG_CELLS: int = 8

@export var seed_value: int = 12345

var _ground: Texture2D
var _bottom: Texture2D
var _tree_dark: Texture2D
var _tree_light: Texture2D
var _plants: Texture2D
var _vines: Texture2D
var _vegetation: Texture2D
var _treelimb: Texture2D

var _solids: Array[Rect2] = []
var _columns: Array[Rect2] = []
var _thick: Array[Rect2] = []
var _thin: Array[Rect2] = []
var _decor: Array = []
var _bounds: Rect2 = Rect2()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = -5
	_ground = load(PACK + "tile_jungle_ground_brown.png")
	_bottom = load(PACK + "tile_jungle_bottom_brown.png")
	_tree_dark = load(PACK + "tile_jungle_tree_dark.png")
	_tree_light = load(PACK + "tile_jungle_tree_light.png")
	_plants = load(PACK + "tile_jungle_plants_objects.png")
	_vines = load(PACK + "tile_jungle_bg_vines.png")
	_vegetation = load(PACK + "tile_jungle_vegetation.png")
	_treelimb = load(PACK + "tile_jungle_treelimb.png")
	var map := get_parent()
	_collect(map)
	_hide_graybox(map)
	_build_backdrop()
	_plan_decor()
	queue_redraw()


# --- Reading the gray box ------------------------------------------

func _collect(map: Node) -> void:
	for body in map.find_children("*", "StaticBody2D", true, false):
		for child in body.get_children():
			var col := child as CollisionShape2D
			if col == null or not (col.shape is RectangleShape2D):
				continue
			if String(col.name).begins_with("ColBound"):
				continue
			var size: Vector2 = (col.shape as RectangleShape2D).size
			var rect := Rect2(to_local(col.global_position) - size * 0.5, size)
			_solids.append(rect)
			if rect.size.y >= rect.size.x * 3.0:
				_columns.append(rect)
			elif rect.size.y >= 60.0:
				_thick.append(rect)
			else:
				_thin.append(rect)
	if _solids.is_empty():
		return
	_bounds = _solids[0]
	for rect in _solids:
		_bounds = _bounds.merge(rect)


func _hide_graybox(map: Node) -> void:
	for node in map.find_children("*", "ColorRect", true, false):
		(node as CanvasItem).visible = false


# --- Drawing --------------------------------------------------------

func _draw() -> void:
	if _ground == null:
		return
	for item in _decor:
		if bool(item[2]):
			_draw_decor(item)
	for rect in _solids:
		_draw_body(rect)
	for rect in _thick:
		_draw_surface(rect)
	for rect in _columns:
		_draw_surface(rect)
	for rect in _thin:
		_draw_surface(rect)
	for item in _decor:
		if not bool(item[2]):
			_draw_decor(item)


## Solid dirt under the surface, from the pack's bottom sheet. Its top row
## is the only genuinely tiling dirt in the set; the rest of that sheet is
## tapered undersides for platforms that float.
func _draw_body(rect: Rect2) -> void:
	var y := rect.position.y
	var row := 0
	while y < rect.end.y:
		var x := rect.position.x
		var col := 0
		while x < rect.end.x:
			var w := minf(TILE, rect.end.x - x)
			var h := minf(TILE, rect.end.y - y)
			# Four dirt variants, picked by a hash of grid position rather
			# than in sequence, so the fill does not repeat on a diagonal.
			var variant := posmod(col * 7 + row * 13, 4)
			draw_texture_rect_region(
				_bottom, Rect2(Vector2(x, y), Vector2(w, h)),
				Rect2(variant * SRC, 0, w / SCALE, h / SCALE))
			x += TILE
			col += 1
		y += TILE
		row += 1


## The grass surface, three-sliced, drawn a tile high so the fringe hangs
## above the collision line.
func _draw_surface(rect: Rect2) -> void:
	var top := rect.position.y - OVERHANG * SCALE
	var height := float((SRC + OVERHANG) * SCALE)
	if rect.size.x <= TILE:
		_slice(1, rect.position.x, minf(TILE, rect.size.x), top, height)
		return
	_slice(0, rect.position.x, TILE, top, height)
	var cursor := rect.position.x + TILE
	var stop := rect.end.x - TILE
	while cursor < stop:
		_slice(1, cursor, minf(TILE, stop - cursor), top, height)
		cursor += TILE
	_slice(2, stop, TILE, top, height)


## One 32x64 piece of the ground sheet: `which` is 0 left, 1 middle, 2 right.
func _slice(which: int, x: float, width: float, y: float, height: float) -> void:
	draw_texture_rect_region(
		_ground, Rect2(Vector2(x, y), Vector2(width, height)),
		Rect2(which * SRC, 0, width / SCALE, height / SCALE))


# --- Decoration -----------------------------------------------------

## Trees on the grounds, undergrowth along them. Same seeded placement rule
## as LevelSkin so the two skins put scenery in the same places and the
## comparison is about the art rather than about the layout.
func _plan_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 5
	for rect in _thick:
		var x := rect.position.x + rng.randf_range(60.0, 200.0)
		while x < rect.end.x - 120.0:
			var roll := rng.randf()
			if roll < 0.32:
				_decor.append([&"tree", Vector2(x, rect.position.y), true, rng.randf() < 0.5])
				x += rng.randf_range(260.0, 420.0)
			else:
				_decor.append([&"plant", Vector2(x, rect.position.y), false, rng.randi() % VEG_CELLS])
				x += rng.randf_range(90.0, 200.0)


func _draw_decor(item: Array) -> void:
	var kind: StringName = item[0]
	var foot: Vector2 = item[1]
	match kind:
		&"tree":
			var sheet: Texture2D = _tree_light if bool(item[3]) else _tree_dark
			# Trunk and branches only. The sheet's canopy blobs are drawn to
			# sit on specific branch ends, not centred over a trunk, and
			# pasting one above the trunk leaves it floating in open sky.
			_blit(sheet, TREE_TRUNK, foot, TREE_TRUNK.size)
		&"plant":
			var cell: int = int(item[3])
			_blit(_vegetation, Rect2(cell * SRC, 0, SRC, SRC), foot, Vector2(SRC, SRC))


## Draws a source region with its foot on `at`, snapped to the art grid.
func _blit(texture: Texture2D, region: Rect2, at: Vector2, size: Vector2) -> void:
	var drawn := size * float(SCALE)
	var top_left := at - Vector2(drawn.x * 0.5, drawn.y)
	top_left = (top_left / float(SCALE)).round() * float(SCALE)
	draw_texture_rect_region(texture, Rect2(top_left, drawn), region)


# --- Backdrop -------------------------------------------------------

## The pack ships no parallax layers, so the backdrop is built from its own
## trunks, repeated and darkened by distance, over the flat sky its mockups
## use. That is a real gap between the two directions rather than an
## oversight: adopting OPP means drawing parallax art or buying it.
func _build_backdrop() -> void:
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -100
	add_child(sky_layer)
	var sky := ColorRect.new()
	sky.color = Color8(62, 174, 205)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky_layer.add_child(sky)

	var eye := _eye_level()
	# Spacing is wide on purpose. The pack's trunk is 232x256 source, which
	# is 464x512 on screen at 2x - a few hundred pixels apart they stop being
	# trees and become a wall with no sky in it.
	_trunk_band(Vector2(0.16, 0.10), eye + 40.0, -30, Color(0.30, 0.46, 0.50), 1050.0)
	_trunk_band(Vector2(0.40, 0.24), eye + 80.0, -22, Color(0.52, 0.64, 0.58), 1500.0)


func _eye_level() -> float:
	var map := get_parent()
	if map != null:
		var spawn: Variant = map.get(&"spawn_point")
		if spawn is Vector2 and not (spawn as Vector2).is_zero_approx():
			return (spawn as Vector2).y
	return _bounds.position.y


## One parallax plane of repeated trunks. Tinted rather than redrawn, which
## is the only depth cue available when a pack has no background art.
func _trunk_band(scroll: Vector2, base: float, z: int, tint: Color, spacing: float) -> void:
	var layer := Parallax2D.new()
	layer.scroll_scale = scroll
	layer.repeat_size = Vector2(spacing * 3.0, 0.0)
	layer.repeat_times = 16
	layer.z_index = z
	layer.z_as_relative = false
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(layer)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + z
	for i in 3:
		var sprite := Sprite2D.new()
		sprite.texture = _tree_dark if i % 2 == 0 else _tree_light
		sprite.region_enabled = true
		sprite.region_rect = TREE_TRUNK
		sprite.centered = false
		sprite.scale = Vector2.ONE * float(SCALE)
		sprite.position = Vector2(i * spacing + rng.randf_range(-90.0, 90.0), base - TREE_TRUNK.size.y * SCALE)
		sprite.modulate = tint
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		layer.add_child(sprite)
