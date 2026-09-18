class_name LevelSkin
extends Node2D

# ============================================================
# LEVEL SKIN - dresses a gray-box map in pixel art at runtime.
#
# The maps stay what they are: collision rectangles with ColorRects on top.
# This node reads the rectangles back out, hides the ColorRects, and tiles
# grass and dirt over the same footprint, so a level edit is still one
# number in a .tscn and the art follows it rather than drifting from it.
#
# Art: Kenney's Pixel Platformer (CC0), 18 px tiles drawn at 2x. The monkeys
# are 2x pixel art too, so level and characters share one pixel size.
#
# Shape decides the look, never a name:
#   tall and narrow  -> an ivy-covered earth pillar (the climb walls)
#   thick            -> grass over dirt, running down into the water
#   thin             -> a one-tile grass ledge
# ============================================================

const PACK := "res://assets/kenney_pixel-platformer/"
const SRC: int = 18
const SCALE: int = 2
const TILE: int = SRC * SCALE
const COLUMNS: int = 20        # tiles per row in tilemap_packed.png

# Tile indices, left / middle / right.
const LEDGE: Array[int] = [1, 2, 3]
const LEDGE_SOLO: int = 0
const TOP: Array[int] = [21, 22, 23]
const FILL: Array[int] = [121, 122, 123]
const WATER_TOP: int = 33
const WATER_FILL: int = 53
const CANOPY: Array = [[17, 18, 19], [37, 38, 39], [57, 58, 59]]
const TRUNK: Array[int] = [97, 117, 137]
const THIN_TREE: Array[int] = [36, 56, 76, 96, 116, 136]
const SHRUBS: Array[int] = [124, 125, 126, 128]
const CLOUD: Array[int] = [153, 154, 155]

const SKY_TOP := Color8(96, 190, 236)
const SKY_BOTTOM := Color8(196, 244, 214)
const WATER := Color8(44, 197, 246)
const WATER_DEEP := Color8(22, 70, 120)
const DEPTH_SHADE := Color8(120, 110, 130)

## Seed for decoration placement, so every machine in a match - and every
## run of the capture tool - grows the same trees in the same places.
@export var seed_value: int = 7
## Kept so MapData can keep passing it; the Kenney set has one grass.
@export var palette: int = 3

var _tiles: Texture2D
var _backdrops: Texture2D
var _solids: Array[Rect2] = []
var _columns: Array[Rect2] = []
var _thick: Array[Rect2] = []
var _thin: Array[Rect2] = []
var _decor: Array = []         # [tile, world position, flip]
var _bounds: Rect2 = Rect2()
var _water_y: float = 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = -5
	_tiles = load(PACK + "tilemap_packed.png")
	_backdrops = load(PACK + "tilemap-backgrounds_packed.png")
	var map := get_parent()
	_collect(map)
	_hide_graybox(map)
	_restyle_props(map)
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
			# Bounds are the invisible walls at the ends of a level.
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
	# Water under the lowest ground, so a missed jump reads as a splash
	# rather than as falling out of the world.
	var lowest_top := -INF
	for rect in _thick:
		lowest_top = maxf(lowest_top, rect.position.y)
	_water_y = (lowest_top if lowest_top > -INF else _bounds.end.y) + 260.0


func _hide_graybox(map: Node) -> void:
	for node in map.find_children("*", "ColorRect", true, false):
		(node as CanvasItem).visible = false


## Climbables keep their shape but draw as ivy on the pillar they grip.
func _restyle_props(map: Node) -> void:
	for node in map.find_children("*", "Climbable", true, false):
		node.set(&"draw_debug_face", false)
		var ivy := Ivy.new()
		ivy.size = node.get(&"size")
		node.add_child(ivy)


# --- Terrain -------------------------------------------------------

func _draw() -> void:
	if _tiles == null:
		return
	for item in _decor:
		if bool(item[3]):
			_draw_decor(item)
	_draw_water()
	for rect in _thick:
		_draw_ground(rect)
	for rect in _columns:
		_draw_column(rect)
	for rect in _thin:
		_draw_ledge(rect)
	for item in _decor:
		if not bool(item[3]):
			_draw_decor(item)


func _draw_ground(rect: Rect2) -> void:
	# Grounds run down into the water so none floats in the sky.
	var bottom := maxf(rect.end.y, _water_y + TILE)
	_row(TOP, rect.position.x, rect.size.x, rect.position.y)
	var y := rect.position.y + TILE
	var depth := 1
	while y < bottom:
		var shade := Color.WHITE.lerp(DEPTH_SHADE, clampf(depth * 0.09, 0.0, 0.55))
		_row(FILL, rect.position.x, rect.size.x, y, minf(TILE, bottom - y), shade)
		y += TILE
		depth += 1


func _draw_column(rect: Rect2) -> void:
	var bottom := rect.end.y
	if not _rests_on_ground(rect):
		bottom = maxf(bottom, _water_y + TILE)
	_row(TOP, rect.position.x, rect.size.x, rect.position.y)
	var y := rect.position.y + TILE
	while y < bottom:
		_row(FILL, rect.position.x, rect.size.x, y, minf(TILE, bottom - y))
		y += TILE


func _draw_ledge(rect: Rect2) -> void:
	if rect.size.x < TILE:
		_blit(LEDGE_SOLO, 0.0, rect.size.x / SCALE, SRC, Vector2(rect.position.x, rect.position.y))
		return
	_row(LEDGE, rect.position.x, rect.size.x, rect.position.y)


## A three-slice row: left cap, repeated middle, right cap. Narrower than two
## tiles, the caps are cut and butted together so both outlines survive.
func _row(tiles: Array[int], x: float, width: float, y: float, height: float = TILE, shade: Color = Color.WHITE) -> void:
	var src_h := height / SCALE
	if width < TILE * 2:
		var left := floorf(width * 0.5)
		var right := width - left
		_blit(tiles[0], 0.0, left / SCALE, src_h, Vector2(x, y), shade)
		_blit(tiles[2], SRC - right / SCALE, right / SCALE, src_h, Vector2(x + left, y), shade)
		return
	_blit(tiles[0], 0.0, SRC, src_h, Vector2(x, y), shade)
	var cursor := x + TILE
	var stop := x + width - TILE
	while cursor < stop:
		var w := minf(TILE, stop - cursor)
		_blit(tiles[1], 0.0, w / SCALE, src_h, Vector2(cursor, y), shade)
		cursor += TILE
	_blit(tiles[2], 0.0, SRC, src_h, Vector2(stop, y), shade)


## Draws part of one tile: `src_x` and `src_w` are in source pixels, from
## the tile's left edge, which is how a cut cap keeps its outer outline.
func _blit(tile: int, src_x: float, src_w: float, src_h: float, at: Vector2, shade: Color = Color.WHITE) -> void:
	var origin := Vector2((tile % COLUMNS) * SRC + src_x, (tile / COLUMNS) * SRC)
	draw_texture_rect_region(_tiles, Rect2(at, Vector2(src_w, src_h) * SCALE), Rect2(origin, Vector2(src_w, src_h)), shade)


func _rests_on_ground(rect: Rect2) -> bool:
	for other in _thick:
		if absf(other.position.y - rect.end.y) < 24.0 and other.position.x < rect.end.x and other.end.x > rect.position.x:
			return true
	return false


func _draw_water() -> void:
	var left := floorf((_bounds.position.x - 3000.0) / TILE) * TILE
	var right := _bounds.end.x + 3000.0
	var x := left
	while x < right:
		_blit(WATER_TOP, 0.0, SRC, SRC, Vector2(x, _water_y))
		_blit(WATER_FILL, 0.0, SRC, SRC, Vector2(x, _water_y + TILE))
		x += TILE
	var deep_top := _water_y + TILE * 2
	draw_polygon(
		PackedVector2Array([Vector2(left, deep_top), Vector2(right, deep_top), Vector2(right, deep_top + 900.0), Vector2(left, deep_top + 900.0)]),
		PackedColorArray([WATER, WATER, WATER_DEEP, WATER_DEEP])
	)
	draw_rect(Rect2(left, deep_top + 900.0, right - left, 4000.0), WATER_DEEP)


# --- Decoration ----------------------------------------------------

## Trees on the grounds, shrubs on anything wide enough. Placed once from a
## seed; drawn in _draw as plain tiles, so a long level costs nothing extra.
func _plan_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 5
	for rect in _thick:
		var x := rect.position.x + rng.randf_range(60.0, 200.0)
		while x < rect.end.x - 120.0:
			var roll := rng.randf()
			if roll < 0.35:
				_decor.append([&"tree", Vector2(x, rect.position.y), rng.randf() < 0.5, true])
				x += rng.randf_range(260.0, 420.0)
			elif roll < 0.55:
				_decor.append([&"thin_tree", Vector2(x, rect.position.y), false, true])
				x += rng.randf_range(160.0, 260.0)
			else:
				_decor.append([SHRUBS[rng.randi() % SHRUBS.size()], Vector2(x, rect.position.y), rng.randf() < 0.5, false])
				x += rng.randf_range(90.0, 200.0)
	for rect in _thin:
		if rect.size.x >= 180.0 and rng.randf() < 0.6:
			var at := Vector2(rng.randf_range(rect.position.x + 30.0, rect.end.x - 60.0), rect.position.y)
			_decor.append([SHRUBS[rng.randi() % SHRUBS.size()], at, rng.randf() < 0.5, false])


func _draw_decor(item: Array) -> void:
	var kind: Variant = item[0]
	var foot: Vector2 = item[1]
	if kind is StringName and kind == &"tree":
		# Three-by-three canopy on a three-tile trunk, the trunk centred.
		var trunk_x := foot.x - TILE * 0.5
		for i in TRUNK.size():
			_blit(TRUNK[i], 0.0, SRC, SRC, Vector2(trunk_x, foot.y - TILE * (TRUNK.size() - i)))
		var canopy_top := foot.y - TILE * (TRUNK.size() + 3) + 6.0
		for row in 3:
			for col in 3:
				_blit(CANOPY[row][col], 0.0, SRC, SRC, Vector2(trunk_x - TILE + col * TILE, canopy_top + row * TILE))
	elif kind is StringName and kind == &"thin_tree":
		var x := foot.x - TILE * 0.5
		for i in THIN_TREE.size():
			_blit(THIN_TREE[i], 0.0, SRC, SRC, Vector2(x, foot.y - TILE * (THIN_TREE.size() - i)))
	else:
		_blit(int(kind), 0.0, SRC, SRC, foot - Vector2(TILE * 0.5, TILE))


# --- Backdrop ------------------------------------------------------

func _build_backdrop() -> void:
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -100
	add_child(sky_layer)
	var gradient := Gradient.new()
	gradient.set_color(0, SKY_TOP)
	gradient.set_color(1, SKY_BOTTOM)
	var sky_texture := GradientTexture2D.new()
	sky_texture.gradient = gradient
	sky_texture.fill_to = Vector2(0.0, 1.0)
	sky_texture.width = 4
	sky_texture.height = 256
	var sky := TextureRect.new()
	sky.texture = sky_texture
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky_layer.add_child(sky)

	# Horizon a little under the average ground height, where the eye is.
	var horizon := _water_y - 260.0
	var clouds := _parallax(Vector2(0.1, 0.06), 1728.0, -30)
	clouds.autoscroll = Vector2(-12.0, 0.0)
	clouds.add_child(Clouds.new(_tiles, horizon - 520.0, seed_value))
	# Kenney's backdrop strips: pale far hills, then the green tree line.
	_parallax(Vector2(0.2, 0.15), 1728.0, -25).add_child(Strip.new(_backdrops, [0, 1, 2, 3], horizon - 120.0, 3))
	_parallax(Vector2(0.45, 0.35), 1728.0, -20).add_child(Strip.new(_backdrops, [6, 7], horizon + 40.0, 3))


func _parallax(scroll: Vector2, repeat: float, z: int) -> Parallax2D:
	var layer := Parallax2D.new()
	layer.scroll_scale = scroll
	layer.repeat_size = Vector2(repeat, 0.0)
	layer.repeat_times = 4
	layer.z_index = z
	layer.z_as_relative = false
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(layer)
	return layer


## One of Kenney's 24 px backdrop columns (sky, horizon, fill) repeated
## across a parallax repeat width, the fill carried on far below.
class Strip extends Node2D:
	var texture: Texture2D
	var columns: Array
	var top: float
	var zoom: int

	func _init(p_texture: Texture2D, p_columns: Array, p_top: float, p_zoom: int) -> void:
		texture = p_texture
		columns = p_columns
		top = p_top
		zoom = p_zoom

	func _draw() -> void:
		var cell := 24.0 * zoom
		var count := int(ceilf(1728.0 / cell))
		for i in count:
			var col: int = columns[i % columns.size()]
			var x := i * cell
			draw_texture_rect_region(texture, Rect2(x, top, cell, cell), Rect2(col * 24, 24, 24, 24))
			draw_texture_rect_region(texture, Rect2(x, top + cell, cell, 3000.0), Rect2(col * 24, 48, 24, 1))


class Clouds extends Node2D:
	var texture: Texture2D
	var base: float
	var seed_value: int

	func _init(p_texture: Texture2D, p_base: float, p_seed: int) -> void:
		texture = p_texture
		base = p_base
		seed_value = p_seed

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var x := 40.0
		while x < 1600.0:
			var width := rng.randi_range(1, 3)
			var y := base + rng.randf_range(-160.0, 160.0)
			var tiles: Array[int] = [153]
			for i in width:
				tiles.append(154)
			tiles.append(155)
			for i in tiles.size():
				var tile: int = tiles[i]
				var origin := Vector2((tile % 20) * 18, (tile / 20) * 18)
				draw_texture_rect_region(texture, Rect2(x + i * 54.0, y, 54.0, 54.0), Rect2(origin, Vector2(18, 18)), Color(1, 1, 1, 0.95))
			x += tiles.size() * 54.0 + rng.randf_range(120.0, 320.0)


## Hanging ivy for a climbable face: a few strands, a leaf every so often,
## always the same leaves for the same wall. Square pixels, 2x, to match.
class Ivy extends Node2D:
	var size: Vector2 = Vector2(48.0, 400.0)

	func _draw() -> void:
		var stem := Color8(34, 96, 64)
		var leaf := Color8(54, 227, 119)
		var leaf_dark := Color8(46, 176, 130)
		var outline := Color8(38, 43, 68)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(size.x * 7 + size.y)
		var strands := maxi(2, int(size.x / 18.0))
		for s in strands:
			var x := roundf((-size.x * 0.5 + (s + 0.5) * size.x / strands) / 2.0) * 2.0
			var y := -size.y * 0.5 + 8.0
			while y < size.y * 0.5 - 6.0:
				var sway := 2.0 if int(y / 16.0 + s) % 2 == 0 else 0.0
				draw_rect(Rect2(x + sway, y, 4.0, 10.0), stem)
				if rng.randf() < 0.6:
					var side := -8.0 if rng.randf() < 0.5 else 6.0
					draw_rect(Rect2(x + sway + side - 2.0, y - 2.0, 10.0, 8.0), outline)
					draw_rect(Rect2(x + sway + side, y, 6.0, 4.0), leaf if rng.randf() < 0.6 else leaf_dark)
				y += 10.0
