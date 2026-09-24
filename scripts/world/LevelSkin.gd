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
# Art: 18 px tiles baked by JungleTiles, drawn at 2x. The monkeys are 2x
# pixel art too, so level, props and characters share one pixel size.
#
# Art direction is the key art: a moonlit jungle. The tiles are daylight art,
# so the terrain is baked by JungleTiles to the art bible's platform anatomy
# instead: lit grass cap, dark underside, one shared outline, moss fringe.
# That is what makes a standable surface readable at a glance in a four-way
# race, and no amount of tinting a flat tile gets there.
# Every colour in here comes from JunglePalette; nothing defines its own.
#
# Shape decides the look, never a name:
#   tall and narrow  -> an ivy-covered earth pillar (the climb walls)
#   thick            -> grass over dirt, running down into the water
#   thin             -> a one-tile grass ledge
# ============================================================

const CLIMBABLE_SCENE := preload("res://scenes/Climbable.tscn")
const SRC: int = JungleTiles.SRC
const SCALE: int = 2
const TILE: int = SRC * SCALE
const COLUMNS: int = JungleTiles.COLUMNS

## How far apart torches stand along a ground, in world pixels.
const TORCH_SPACING := Vector2(420.0, 760.0)
## Grab-tree branch reach, world pixels.
const BRANCH_LENGTH: float = 96.0
## Low-detail branch: levels are painted in the Primate Rush mock style
## (scripts/world/MockSkin.gd) instead of the jungle tile art.
const LOW_DETAIL: bool = true
## How far the water surface sits under the top of the lowest ground.
const WATER_BELOW_GROUND: float = 140.0
const Mock = preload("res://scripts/world/MockSkin.gd")
const MockLayers = preload("res://scripts/world/MockLayers.gd")
const RectBake = preload("res://scripts/world/RectBake.gd")
const PANORAMA := "res://assets/environment/simple/backdrop-px.png"

## Seed for decoration placement, so every machine in a match - and every
## run of the capture tool - grows the same trees in the same places.
@export var seed_value: int = 7
## Kept so MapData can keep passing it; the Kenney set has one grass.
@export var palette: int = 3

var _tiles: Texture2D
var _solids: Array[Rect2] = []
var _columns: Array[Rect2] = []
var _thick: Array[Rect2] = []
var _thin: Array[Rect2] = []
var _decor: Array = []         # [tile, world position, flip]
var _bounds: Rect2 = Rect2()
var _water_y: float = 0.0
var _back_layer: CanvasLayer = null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = -5
	# The tile atlas is only the high-detail art; the low-detail skin paints
	# its own blocks, so it skips the bake entirely (a slow startup step).
	if not LOW_DETAIL:
		_tiles = JungleTiles.atlas()
	var map := get_parent()
	_collect(map)
	_hide_graybox(map)
	_restyle_props(map)
	_build_backdrop()
	_plan_decor()
	# Low detail: the canopy frame already carries the fireflies, so only
	# the vignette is added, not a second layer of per-frame motes.
	Atmosphere.install(self, seed_value, not LOW_DETAIL)
	if LOW_DETAIL:
		_build_pieces()
	queue_redraw()


## Low detail: every platform, tree and bush is its own small node instead
## of one giant drawing. Godot skips nodes that are off screen, so a long
## level only sends what the camera can see to the GPU (it was sending all
## ~11,000 blocks every frame). Order matches the old single drawing.
func _build_pieces() -> void:
	for item in _decor:
		if bool(item[3]):
			_piece(func(c) -> void: _draw_decor(item, c))
	# Water stays a live drawing: it is a few wide bands, and it is the one
	# piece with see-through glints that a bake would flatten.
	var water := Piece.new()
	water.painter = _draw_water.bind(false)
	add_child(water)
	# Glints are their own node so they can be switched off on their own.
	var glints := Piece.new()
	glints.painter = func(c) -> void: _draw_surface_glints(_water_left(), _water_right(), c)
	add_child(glints)
	PerfOverlay.track(glints, &"water_glints")
	for rect in _thick:
		_piece(func(c) -> void: Mock.ground(c, rect))
	for rect in _columns:
		var bottom := rect.end.y if _rests_on_ground(rect) else maxf(rect.end.y, _water_y + TILE)
		_piece(func(c) -> void: Mock.column(c, rect, bottom))
	for i in _thin.size():
		var rect: Rect2 = _thin[i]
		_piece(func(c) -> void: Mock.ledge(c, rect, i))
	for item in _decor:
		if not bool(item[3]):
			_piece(func(c) -> void: _draw_decor(item, c))


## Each piece is baked into one texture (see RectBake): one quad on screen
## instead of hundreds of blocks, and still skipped when off screen.
func _piece(painter: Callable) -> void:
	add_child(RectBake.bake(painter))


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
			var rect := snap_rect(Rect2(to_local(col.global_position) - size * 0.5, size))
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
	# Just under the lowest ground (grounds are 100 deep), so islands sit in
	# the water instead of floating over a band of empty backdrop.
	var lowest_top := -INF
	for rect in _thick:
		lowest_top = maxf(lowest_top, rect.position.y)
	for rect in _thin:
		lowest_top = maxf(lowest_top, rect.position.y)
	_water_y = (lowest_top if lowest_top > -INF else _bounds.end.y) + WATER_BELOW_GROUND
	# A fall ends at the splash, not a long way under the surface.
	if map is MapData:
		(map as MapData).kill_depth = minf((map as MapData).kill_depth, _water_y + 110.0)


## Rounds a rectangle onto the art grid.
##
## Maps are authored in whole world pixels, but an art pixel is SCALE of
## those, so a platform centred on an odd coordinate starts on an odd one -
## and then every tile edge along it lands between two screen pixels. Half a
## world pixel is nothing to a collision box and everything to a tile.
static func snap_rect(rect: Rect2) -> Rect2:
	var grid := float(SCALE)
	var start := (rect.position / grid).round() * grid
	var stop := (rect.end / grid).round() * grid
	return Rect2(start, stop - start)


## Rounds a position onto the art grid.
static func snap(at: Vector2) -> Vector2:
	var grid := float(SCALE)
	return (at / grid).round() * grid


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
	if LOW_DETAIL or _tiles == null:
		# Low detail draws through the Piece children (see _build_pieces).
		return
	for item in _decor:
		if bool(item[3]):
			_draw_decor(item)
	_draw_water()
	if LOW_DETAIL:
		for rect in _thick:
			Mock.ground(self, rect)
		for rect in _columns:
			Mock.column(self, rect, rect.end.y if _rests_on_ground(rect) else maxf(rect.end.y, _water_y + TILE))
		for i in _thin.size():
			Mock.ledge(self, _thin[i], i)
		for item in _decor:
			if not bool(item[3]):
				_draw_decor(item)
		return
	# Projected side/bottom faces sit behind the playable collision surface.
	# They do not change the map, but stop platforms reading as paper cutouts.
	for rect in _solids:
		_draw_depth_extrusion(rect)
	for rect in _thick:
		_draw_ground(rect)
	for rect in _columns:
		_draw_column(rect)
	for rect in _thin:
		_draw_ledge(rect)
	for item in _decor:
		if not bool(item[3]):
			_draw_decor(item)


func _draw_depth_extrusion(rect: Rect2) -> void:
	# Side-view rock silhouettes, in whole art pixels. No extruded 3D plane.
	if rect.size.y >= 60.0 or rect.size.y >= rect.size.x * 3.0:
		return
	var x := rect.position.x + 8.0
	while x < rect.end.x - 12.0:
		var tooth := 10.0 + float(posmod(int(x / 2.0), 5)) * 2.0
		draw_rect(Rect2(x, rect.position.y + 16.0, 16.0, tooth), JunglePalette.DIRT_DARK)
		draw_rect(Rect2(x + 2.0, rect.position.y + 16.0, 6.0, tooth - 2.0), JunglePalette.ROCK_COOL)
		x += 28.0


func _draw_ground(rect: Rect2) -> void:
	# Keep the real collision silhouette: the reference uses suspended rock
	# islands, so do not stretch every island into a solid wall down to water.
	var bottom := rect.end.y
	_row(JungleTiles.GRASS, rect.position.x, rect.size.x, rect.position.y)
	var y := rect.position.y + TILE
	var depth := 1
	while y < bottom:
		var shade := Color.WHITE.lerp(JunglePalette.DEPTH_TINT, clampf(depth * 0.11, 0.0, 0.7))
		_row(JungleTiles.DIRT, rect.position.x, rect.size.x, y, minf(TILE, bottom - y), shade, JungleTiles.DIRT_VARIANTS)
		y += TILE
		depth += 1
	_scatter_soil(rect, bottom)
	_scatter_grass(rect)
	_hanging_moss(rect)
	draw_rect(Rect2(rect.position.x, bottom - 4.0, rect.size.x, 4.0), JunglePalette.OUTLINE)
	var root_x := rect.position.x + 16.0
	while root_x < rect.end.x - 16.0:
		var root_length := 10 + posmod(int(root_x) * 3, 27)
		for i in root_length:
			var at := snap(Vector2(root_x + (2.0 if i > 9 else 0.0), bottom + i * 2.0))
			draw_rect(Rect2(at, Vector2(4, 2)), JunglePalette.BARK_DARK)
			if i < root_length - 3:
				draw_rect(Rect2(at, Vector2(2, 2)), JunglePalette.MOSS)
		root_x += 74.0


## Tufts standing up off a ground's grass line, at spacings unrelated to the
## tile grid. The baked cap gives the surface its colour and its outline;
## this is what stops forty tiles of it reading as a ruled green stripe.
func _scatter_grass(rect: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 977 + int(rect.position.x) * 17
	var x := rect.position.x + rng.randf_range(4.0, 40.0)
	while x < rect.end.x - 8.0:
		var blades := rng.randi_range(2, 4)
		var lean := -1.0 if rng.randf() < 0.5 else 1.0
		for b in blades:
			var height := float(rng.randi_range(2, 5) * SCALE)
			var at := snap(Vector2(x + float(b * SCALE), rect.position.y))
			# A blade is a stepped column, two art pixels wide, leaning one
			# pixel at the tip. Never a line: a line would antialias.
			draw_rect(Rect2(at.x, at.y - height, float(SCALE), height), JunglePalette.GRASS_DARK)
			draw_rect(Rect2(at.x + lean * float(SCALE), at.y - height - float(SCALE), float(SCALE), float(SCALE)), JunglePalette.GRASS_SUN)
		x += rng.randf_range(26.0, 90.0)


## Rocks and roots thrown across a ground's soil at sizes and spacings that
## are nothing to do with the tile grid. An 18 px tile repeated forty times
## is visibly forty copies of one tile, however well grained it is; the only
## fix is detail that does not share the grid's period.
func _scatter_soil(rect: Rect2, bottom: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 613 + int(rect.position.x) * 31 + int(rect.position.y)
	var top := rect.position.y + TILE
	var count := int((rect.size.x / TILE) * maxf((bottom - top) / TILE, 1.0) * 0.16)
	for i in count:
		var at := Vector2(
			rng.randf_range(rect.position.x + 6.0, rect.end.x - 18.0),
			rng.randf_range(top + 8.0, maxf(bottom - 14.0, top + 10.0))
		)
		# Snapped to the art grid, like every other pixel in the level.
		at = snap(at)
		var fade := clampf(1.0 - (at.y - top) / maxf(bottom - top, 1.0), 0.25, 1.0)
		if rng.randf() < 0.62:
			_pebble(at, rng.randi_range(2, 4) * SCALE, fade)
		else:
			_root(at, rng.randi_range(5, 11) * SCALE, rng.randf() < 0.5, fade)


## A rounded stone: dark body, one lit pixel row on the sun side.
func _pebble(at: Vector2, size: float, fade: float) -> void:
	var body := JunglePalette.DIRT_DARK
	var lit := JunglePalette.DIRT_LIGHT
	draw_rect(Rect2(at, Vector2(size, size)), Color(body, 0.85 * fade))
	draw_rect(Rect2(at, Vector2(size, float(SCALE))), Color(lit, 0.55 * fade))
	draw_rect(Rect2(at, Vector2(float(SCALE), size)), Color(lit, 0.35 * fade))


## A root running through the soil: a stepped line, because a diagonal drawn
## as a line antialiases and a root made of blocks does not.
func _root(at: Vector2, length: float, downward: bool, fade: float) -> void:
	var tone := Color(JunglePalette.BARK_DARK, 0.7 * fade)
	var step := float(SCALE)
	var x := at.x
	var y := at.y
	var run := int(length / step)
	for i in run:
		draw_rect(Rect2(x, y, step * 2.0, step), tone)
		x += step * 2.0
		if i % 2 == 0:
			y += step if downward else -step


## A climb wall is a tree, so it is bark all the way down with a crown of
## leaves on top - never a pillar of soil standing in the air.
func _draw_column(rect: Rect2) -> void:
	var bottom := rect.end.y
	if not _rests_on_ground(rect):
		bottom = maxf(bottom, _water_y + TILE)
	var y := rect.position.y
	while y < bottom:
		_row(JungleTiles.TRUNK, rect.position.x, rect.size.x, y, minf(TILE, bottom - y))
		y += TILE


func _draw_ledge(rect: Rect2) -> void:
	if rect.size.x < TILE:
		_blit(JungleTiles.LEDGE_SOLO, 0.0, rect.size.x / SCALE, SRC, Vector2(rect.position.x, rect.position.y))
		return
	_row(JungleTiles.LEDGE, rect.position.x, rect.size.x, rect.position.y)
	_scatter_grass(rect)
	_hanging_moss(rect)


## Long moss fingers break the rock silhouette below the landing surface.
func _hanging_moss(rect: Rect2) -> void:
	var x := rect.position.x + 12.0
	while x < rect.end.x - 8.0:
		var run := 7 + posmod(int(x / 2.0) * 7, 19)
		for i in run:
			var at := snap(Vector2(x + (2.0 if i > run / 2 else 0.0), rect.position.y + 8.0 + i * 2.0))
			var width := 6.0 if i < run / 2 else 4.0
			draw_rect(Rect2(at, Vector2(width, 2)), JunglePalette.GRASS_DARK)
			draw_rect(Rect2(at, Vector2(2, 2)), JunglePalette.MOSS if i > 4 else JunglePalette.GRASS)
			if i % 6 == 2:
				draw_rect(Rect2(at - Vector2(2, 0), Vector2(4, 2)), JunglePalette.GRASS)
		x += 42.0 + float(posmod(int(x), 3)) * 8.0


## A three-slice row: left cap, repeated middle, right cap. Narrower than two
## tiles, the caps are cut and butted together so both outlines survive.
func _row(tiles: Array[int], x: float, width: float, y: float, height: float = TILE, shade: Color = Color.WHITE, pool: Array[int] = []) -> void:
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
		# Middles come from `pool` when one is given, chosen by a hash of the
		# tile's own grid position. Deterministic, so every machine in a match
		# draws the same ground, and not a straight cycle, which would put the
		# same tile down every fourth column in a visible diagonal.
		var tile: int = tiles[1]
		if not pool.is_empty():
			var col := int(roundf((cursor - x) / TILE))
			var line := int(roundf(y / TILE))
			tile = pool[posmod(col * 7 + line * 13, pool.size())]
		_blit(tile, 0.0, w / SCALE, src_h, Vector2(cursor, y), shade)
		cursor += TILE
	_blit(tiles[2], 0.0, SRC, src_h, Vector2(stop, y), shade)


## Draws part of one tile: `src_x` and `src_w` are in source pixels, from
## the tile's left edge, which is how a cut cap keeps its outer outline.
func _blit(tile: int, src_x: float, src_w: float, src_h: float, at: Vector2, shade: Color = Color.WHITE) -> void:
	var origin := JungleTiles.origin(tile) + Vector2(src_x, 0.0)
	# No blanket tint: the atlas is authored in the jungle palette already.
	# `shade` is depth only - a tile further underground, or further away.
	draw_texture_rect_region(_tiles, Rect2(at, Vector2(src_w, src_h) * SCALE), Rect2(origin, Vector2(src_w, src_h)), shade)


func _rests_on_ground(rect: Rect2) -> bool:
	for other in _thick:
		if absf(other.position.y - rect.end.y) < 24.0 and other.position.x < rect.end.x and other.end.x > rect.position.x:
			return true
	return false


func _water_left() -> float:
	return floorf((_bounds.position.x - 3000.0) / TILE) * TILE


func _water_right() -> float:
	return _bounds.end.x + 3000.0


func _draw_water(canvas: CanvasItem = null, glints: bool = true) -> void:
	if canvas == null:
		canvas = self
	# The Kenney water tiles are a flat cyan that fights the jungle greens, so
	# the surface is drawn instead: a lit rim, a ramp into the depths, and a
	# scatter of glints where light through the canopy breaks on it.
	var left := floorf((_bounds.position.x - 3000.0) / TILE) * TILE
	var right := _bounds.end.x + 3000.0
	var width := right - left

	canvas.draw_rect(Rect2(left, _water_y, width, 6.0), Color(JunglePalette.WATER_GLINT, 0.55))
	for band in 20:
		var tone := JunglePalette.WATER.lerp(JunglePalette.WATER_DEEP, float(band) / 19.0)
		canvas.draw_rect(Rect2(left, _water_y + 6.0 + band * 32.0, width, 32.0), tone)
	canvas.draw_rect(Rect2(left, _water_y + 620.0, width, 4000.0), JunglePalette.WATER_DEEP)
	if glints:
		_draw_surface_glints(left, right, canvas)


## Light broken on the surface: a column of glints down the middle of the
## level, brightest at the top. Seeded, so it is the same on every machine in
## a match and never flickers between two clients.
func _draw_surface_glints(left: float, right: float, canvas: CanvasItem = null) -> void:
	if canvas == null:
		canvas = self
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 977 + 41
	var centre := (_bounds.position.x + _bounds.end.x) * 0.5
	var rows := 14
	for row in rows:
		var y := _water_y + 8.0 + row * 9.0
		var fade := 1.0 - float(row) / float(rows)
		var spread := 40.0 + row * 16.0
		for i in 3:
			var w := rng.randf_range(16.0, 70.0) * fade
			var x := centre + rng.randf_range(-spread, spread) - w * 0.5
			if x + w < left or x > right:
				continue
			canvas.draw_rect(snap_rect(Rect2(x, y, w, 2.0)), Color(JunglePalette.WATER_GLINT, 0.30 * fade))


# --- Decoration ----------------------------------------------------

## Trees on the grounds, shrubs on anything wide enough. Placed once from a
## seed; drawn in _draw as plain tiles, so a long level costs nothing extra.
func _plan_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 5
	for rect in _thick:
		_light_ground(rect, rng)
	for rect in _thick:
		var x := rect.position.x + rng.randf_range(60.0, 200.0)
		while x < rect.end.x - 120.0:
			var roll := rng.randf()
			if roll < 0.62:
				# Grab trees: real world-space anchors in the swing system,
				# spaced inside one arm-swing of each other so they chain.
				var foot := Vector2(x, rect.position.y)
				var height := TILE * float(rng.randi_range(4, 6))
				var side := -1.0 if rng.randf() < 0.5 else 1.0
				_decor.append([&"tree", foot, rng.randf() < 0.5, true, side, height])
				_add_tree_climbable(foot, height, TILE * 0.8)
				_add_branch_climbable(foot, height, side)
				# The leafy crown too: anything you can see, you can grab.
				_add_grab("Crown", foot - Vector2(0.0, height + TILE * 0.4), Vector2(TILE * 2.4, TILE * 1.4))
				x += rng.randf_range(180.0, 280.0)
			elif roll < 0.68:
				var foot := Vector2(x, rect.position.y)
				_decor.append([&"palm", foot, rng.randf() < 0.5, true])
				_add_tree_climbable(foot, TILE * 5.8, TILE * 0.7)
				_add_grab("Crown", foot - Vector2(0.0, TILE * 5.9), Vector2(TILE * 2.2, TILE * 1.2))
				x += rng.randf_range(160.0, 260.0)
			else:
				# Undergrowth sits in front of the player's feet, so it is
				# drawn late and never hides a platform edge. Not a hand-hold:
				# bushes (and torches) snagged every low jump.
				_decor.append([&"fern" if rng.randf() < 0.70 else &"shrub", Vector2(x, rect.position.y), rng.randf() < 0.5, false])
				x += rng.randf_range(90.0, 200.0)
	# Wide ledges get a grab tree of their own now and then, so the
	# climbable trees are not only on the big grounds.
	for rect in _thin:
		if rect.size.x >= 260.0 and rng.randf() < 0.5:
			var foot := Vector2(snappedf(rng.randf_range(rect.position.x + 60.0, rect.end.x - 60.0), TILE), rect.position.y)
			var height := TILE * float(rng.randi_range(3, 5))
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			_decor.append([&"tree", foot, rng.randf() < 0.5, true, side, height])
			_add_tree_climbable(foot, height, TILE * 0.8)
			_add_branch_climbable(foot, height, side)
			_add_grab("Crown", foot - Vector2(0.0, height + TILE * 0.4), Vector2(TILE * 2.4, TILE * 1.4))
		elif rect.size.x >= 180.0 and rng.randf() < 0.6:
			var at := Vector2(rng.randf_range(rect.position.x + 30.0, rect.end.x - 60.0), rect.position.y)
			_decor.append([&"fern", at, rng.randf() < 0.5, false])
	_add_level_grabs()


## Everything else in the play layer becomes a hand-hold: the edge of every
## ledge and the lip of every cliff (grab it from below or beside and swing
## round), and the ropes a hanging plank hangs from. The arm's rules still
## apply - it reaches up, never down, and not through solid rock.
func _add_level_grabs() -> void:
	for i in _thin.size():
		var rect: Rect2 = _thin[i]
		_add_grab("Ledge", rect.get_center(), rect.size + Vector2(8.0, 8.0))
		if LOW_DETAIL and i % 3 == 2:
			# Same index rule MockSkin.ledge uses to hang a plank on ropes.
			for rx in [rect.position.x + 14.0, rect.end.x - 14.0]:
				_add_grab("Rope", Vector2(rx, rect.position.y - 90.0), Vector2(16.0, 180.0))
	for rect in _thick:
		_add_grab("Lip", Vector2(rect.get_center().x, rect.position.y + 10.0), Vector2(rect.size.x, 20.0))


func _add_grab(kind: String, center: Vector2, size: Vector2) -> void:
	var climbable := CLIMBABLE_SCENE.instantiate() as Climbable
	climbable.name = "%sGrab%d" % [kind, get_child_count()]
	climbable.position = snap(center)
	climbable.size = size
	climbable.draw_debug_face = false
	add_child(climbable)


## Torches at intervals along a ground. Warm accents on a shaded jungle
## floor, and signposting with it: the spacing is loose enough that a player
## running a dim stretch is always heading toward the next one.
func _light_ground(rect: Rect2, rng: RandomNumberGenerator) -> void:
	var x := rect.position.x + rng.randf_range(80.0, 200.0)
	while x < rect.end.x - 60.0:
		var torch := Torch.new()
		torch.name = "Torch%d" % get_child_count()
		torch.position = snap(Vector2(x, rect.position.y))
		torch.phase = rng.randf_range(0.0, 6.0)
		torch.reach = rng.randf_range(150.0, 200.0)
		add_child(torch)
		x += rng.randf_range(TORCH_SPACING.x, TORCH_SPACING.y)


func _add_tree_climbable(foot: Vector2, height: float, width: float) -> void:
	var climbable := CLIMBABLE_SCENE.instantiate() as Climbable
	climbable.name = "TreeClimbable%d" % get_child_count()
	climbable.position = snap(foot - Vector2(0.0, height * 0.5))
	climbable.size = Vector2(width, height)
	climbable.draw_debug_face = false
	add_child(climbable)


## A branch sticking out near the top of a grab tree. Horizontal Climbable,
## so the existing trunk-grab reach finds a hand-hold out over the gap.
func _add_branch_climbable(foot: Vector2, height: float, side: float) -> void:
	var climbable := CLIMBABLE_SCENE.instantiate() as Climbable
	climbable.name = "BranchClimbable%d" % get_child_count()
	climbable.position = snap(Vector2(foot.x + side * BRANCH_LENGTH * 0.5, foot.y - height + TILE * 1.5))
	climbable.size = Vector2(BRANCH_LENGTH, 20.0)
	climbable.draw_debug_face = false
	add_child(climbable)


## Bark arm with gold grip knots: the knots are the "you can grab this"
## signal, never used on background canopy, so real anchors read at a glance.
func _draw_branch(foot: Vector2, height: float, side: float) -> void:
	var y := foot.y - height + TILE * 1.5
	var x0 := foot.x if side > 0.0 else foot.x - BRANCH_LENGTH
	var body := Rect2(snap(Vector2(x0, y - 6.0)), Vector2(BRANCH_LENGTH, 12.0))
	draw_rect(body.grow(float(SCALE)), JunglePalette.OUTLINE)
	draw_rect(body, JunglePalette.BARK)
	draw_rect(Rect2(body.position, Vector2(body.size.x, float(SCALE) * 2.0)), JunglePalette.BARK_LIGHT)
	draw_rect(Rect2(body.position + Vector2(0.0, body.size.y - float(SCALE)), Vector2(body.size.x, float(SCALE))), JunglePalette.BARK_DARK)
	for k in [0.45, 0.9]:
		var at := snap(Vector2(foot.x + side * BRANCH_LENGTH * k, y) - Vector2(4.0, 6.0))
		draw_rect(Rect2(at - Vector2(float(SCALE), float(SCALE)), Vector2(12.0, 16.0)), JunglePalette.OUTLINE)
		draw_rect(Rect2(at, Vector2(8.0, 12.0)), JunglePalette.BANANA_DARK)
		draw_rect(Rect2(at, Vector2(8.0, 4.0)), JunglePalette.BANANA)
	_prop(&"fern", Vector2(foot.x + side * BRANCH_LENGTH, y + 4.0), side < 0.0)


func _draw_decor(item: Array, canvas: Variant = null) -> void:
	if canvas == null:
		canvas = self
	var kind: StringName = item[0]
	var foot: Vector2 = item[1]
	var flip: bool = bool(item[2])
	if LOW_DETAIL:
		match kind:
			&"tree":
				var height: float = float(item[5]) if item.size() > 5 else TILE * 3.0
				var side: float = float(item[4]) if item.size() > 4 else 0.0
				Mock.tree(canvas, foot, height, side, BRANCH_LENGTH, foot.y - height + TILE * 1.5)
			&"palm":
				Mock.tree(canvas, foot, TILE * 5.5, 0.0, 0.0, 0.0)
			_:
				Mock.bush(canvas, foot, kind == &"shrub")
		return
	match kind:
		&"tree":
			var height: float = float(item[5]) if item.size() > 5 else TILE * 3.0
			_trunk_column(foot, height)
			_draw_climb_marks(foot, height)
			if item.size() > 4:
				_draw_branch(foot, height, float(item[4]))
			_prop(&"crown_big", foot - Vector2(0.0, height), flip)
			_prop(&"fern", foot - Vector2(0.0, height - 16.0), flip)
			_prop(&"fern", foot + Vector2(22.0, 0.0), not flip, 1.0)
		&"palm":
			var tall := TILE * 5.5
			_trunk_column(foot, tall)
			_draw_climb_marks(foot, tall)
			_prop(&"fern", foot - Vector2(0.0, tall), flip)
			_prop(&"fern", foot - Vector2(8.0, tall - 10.0), not flip)
		_:
			_prop(kind, foot, flip, 1.0)


## A stack of trunk tiles from the ground up to `height`.
func _trunk_column(foot: Vector2, height: float) -> void:
	var y := foot.y - TILE
	while y > foot.y - height:
		_row(JungleTiles.TRUNK, foot.x - TILE * 0.5, TILE, y)
		y -= TILE
	_row(JungleTiles.TRUNK, foot.x - TILE * 0.5, TILE, foot.y - height)


## Draws a baked prop with its foot on `at`, at the shared 2x art scale.
## `anchor` 0 hangs it by its middle, 1 stands it on its bottom edge.
func _prop(kind: StringName, at: Vector2, flip: bool, anchor: float = 0.5) -> void:
	var texture := JungleTiles.prop(kind)
	if texture == null:
		return
	var size := Vector2(texture.get_size()) * float(SCALE)
	var top_left := at - Vector2(size.x * 0.5, size.y * anchor)
	# Snapped to the art grid: half a pixel of offset is a blurred sprite.
	top_left = snap(top_left)
	var region := Rect2(Vector2.ZERO, texture.get_size())
	if flip:
		region.position.x = texture.get_size().x
		region.size.x = -texture.get_size().x
	draw_texture_rect_region(texture, Rect2(top_left, size), region)


func _draw_climb_marks(foot: Vector2, height: float) -> void:
	# A few bright ivy hooks teach the player that the trunk is gameplay.
	# Stepped blocks, not lines. draw_line takes float endpoints and puts a
	# diagonal across the pixel grid; a climb mark is meant to read as the
	# same art as the tile it is on.
	var green := Color(JunglePalette.LEAF_LIGHT, 0.95)
	var step := float(SCALE)
	var y := foot.y - 24.0
	while y > foot.y - height:
		for i in 4:
			draw_rect(Rect2(snap(Vector2(foot.x - 6.0 + i * step * 1.5, y - i * step)), Vector2(step * 2.0, step)), green)
		draw_rect(Rect2(snap(Vector2(foot.x + 6.0, y - step * 4.0)), Vector2(step * 2.0, step * 2.0)), green.lightened(0.18))
		y -= 30.0


# --- Backdrop ------------------------------------------------------

## Four planes of jungle, back to front: hazy air, a far wall of canopy, the
## detailed middle distance, and a dark near frame. Each one is baked pixel
## art from JungleBackdrop rather than drawn here, so the background is made
## of the same size pixels as the tiles and the monkeys.
func _build_backdrop() -> void:
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -100
	add_child(sky_layer)
	sky_layer.add_child(_sky())
	# Every parallax plane lives in screen space. They used to be world
	# nodes that chased the camera each frame, and reading a smoothed camera
	# a frame late made the painted treetops bob up and down whenever the
	# monkey jumped or fell. Here nothing but the sideways scroll moves.
	_back_layer = CanvasLayer.new()
	_back_layer.layer = -50
	add_child(_back_layer)

	# Anchored to where the camera actually looks, not to the water line.
	# Water is derived from a map's lowest ground, which says nothing about
	# where the play is: on the arena map it sits far below the fighting and
	# put the whole canopy off the top of the screen, leaving a forest of
	# trunks standing in bare sky.
	var eye := _eye_level()
	# How much world the camera shows above the player. A map that zooms out
	# to fit an arena sees more sky, so its canopy has to hang higher.
	var reach := 360.0 / maxf(_camera_zoom(), 0.2)
	# Fractions of that reach, all inside the frame: a canopy placed a whole
	# reach up sits exactly on the top edge and disappears the moment a map
	# zooms out, which is how the arena ended up as a forest of bare trunks.
	# The approved painted panorama (baked to the art grid) is the far
	# distance when present; the procedural far canopy is the fallback.
	var has_panorama := _panorama_band(eye, reach)
	if not has_panorama:
		_band(&"far", Vector2(0.14, 0.0), eye - reach * 0.95, -30)
		# The painted panorama already carries the middle distance; the teal
		# procedural mid layer only fights its night palette.
		_band(&"mid", Vector2(0.34, 0.0), eye - reach * 1.10, -24)
	if LOW_DETAIL:
		_mock_layers(eye)
		return
	_band(&"near", Vector2(0.62, 0.0), eye - reach * 1.28, -18)


## Mock "Detailed pass" parallax: dark jungle silhouettes sliding at about
## a third of the camera, and a leaf-and-vine canopy frame over the top of
## the screen sliding at nearly the camera's speed. Decoration only.
func _mock_layers(eye: float) -> void:
	var plane := SnappedParallax.new()
	plane.scroll_scale = Vector2(0.35, 0.0)
	plane.span = 1600.0
	plane.anchor_y = eye
	plane.z_index = -24
	plane.z_as_relative = false
	_back_layer.add_child(plane)
	PerfOverlay.track(plane, &"bg_trees")
	var trees := MockLayers.Silhouettes.new()
	trees.span = 1600.0
	trees.ground_y = eye + 140.0
	trees.seed_value = seed_value
	plane.add_child(trees)
	var frame := CanvasLayer.new()
	frame.layer = 1
	add_child(frame)
	var canopy := MockLayers.Canopy.new()
	canopy.seed_value = seed_value
	frame.add_child(canopy)


## Eye level: the spawn point if the map declares one, since that is where
## the camera opens and where the race is fought. Falls back to the highest
## ground, then to the water line, so a map with neither still gets a sky.
func _eye_level() -> float:
	var map := get_parent()
	if map != null:
		var spawn: Variant = map.get(&"spawn_point")
		if spawn is Vector2 and not (spawn as Vector2).is_zero_approx():
			return (spawn as Vector2).y
	if not _solids.is_empty():
		return _bounds.position.y
	return _water_y - 300.0


func _camera_zoom() -> float:
	var map := get_parent()
	if map == null:
		return 1.0
	var zoom: Variant = map.get(&"camera_zoom")
	return float(zoom) if zoom != null else 1.0


## The approved jungle panorama, tiled as mirrored pairs so the seams match.
## Scenery only: nothing here is collision or a grab anchor.
func _panorama_band(eye: float, reach: float) -> bool:
	var texture := MonkeySprite.load_art(PANORAMA)
	if texture == null:
		return false
	var zoom := float(JungleBackdrop.ZOOM)
	var width := texture.get_size().x * zoom
	var plane := SnappedParallax.new()
	plane.scroll_scale = Vector2(0.08, 0.0)
	plane.span = width * 2.0
	plane.anchor_y = eye
	plane.z_index = -31
	plane.z_as_relative = false
	_back_layer.add_child(plane)
	PerfOverlay.track(plane, &"panorama")
	# Painted part starts ~0.6 reach above eye; the dark pad above covers
	# zoomed-out arena cameras.
	var top := eye - reach * 0.6 - 420.0 * zoom
	for i in range(-2, 4):
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.flip_h = posmod(i, 2) == 1
		sprite.scale = Vector2.ONE * zoom
		sprite.position = snap(Vector2(i * width, top))
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		plane.add_child(sprite)
	return true


## One parallax plane carrying one baked layer, tiled across the level.
## `canopy_y` is where that layer's canopy line should sit in world space;
## the sprite's own top edge is worked back from it.
func _band(kind: StringName, scroll: Vector2, canopy_y: float, z: int) -> void:
	var texture := JungleBackdrop.layer(kind, seed_value)
	var span := float(JungleBackdrop.WIDTH * JungleBackdrop.ZOOM)
	var plane := SnappedParallax.new()
	plane.scroll_scale = scroll
	plane.span = span
	plane.anchor_y = _eye_level()
	plane.z_index = z
	plane.z_as_relative = false
	_back_layer.add_child(plane)
	# Four copies side by side: enough to cover a 1280 screen at any offset,
	# once the plane has wrapped itself to a whole multiple of the span.
	var top := canopy_y - float(JungleBackdrop.canopy_line(kind) * JungleBackdrop.ZOOM)
	for i in 4:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.scale = Vector2.ONE * float(JungleBackdrop.ZOOM)
		sprite.position = snap(Vector2((i - 1) * span, top))
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		plane.add_child(sprite)


## A parallax plane that lands on the art grid.
##
## This positions itself rather than using Parallax2D. Parallax2D offsets a
## layer by -camera * scroll_scale internally, and 0.14 times any camera
## position is a fraction; that offset cannot be rounded from outside, and
## feeding a correction back through scroll_offset does not reach it.
## Measured on a frame, the backdrop sat exactly one screen pixel off the
## grid - 59% of its edges on odd columns - while the terrain in the same
## shot measured 100%.
##
## A layer at depth d belongs at camera * (1 - scroll_scale), which puts it
## at -camera * scroll_scale relative to the camera. That is one line, it
## rounds cleanly, and wrapping to a whole multiple of the span keeps the
## tiled copies on the grid too.
## One part of the level art, drawn once by a painter callback and culled
## by Godot when it is off screen.
class Piece extends Node2D:
	var painter: Callable

	func _draw() -> void:
		painter.call(self)


class SnappedParallax extends Node2D:
	var scroll_scale: Vector2 = Vector2.ONE
	var span: float = 1280.0
	var anchor_y: float = 0.0

	## Screen space (the plane sits in a CanvasLayer): the world point
	## anchor_y is pinned to the middle of the screen vertically, and only
	## the sideways scroll follows the camera.
	func _process(_delta: float) -> void:
		var half := get_viewport().get_visible_rect().size * 0.5
		var eye_x := 0.0
		var camera := get_viewport().get_camera_2d()
		if camera != null:
			eye_x = camera.get_screen_center_position().x
		# Keep copies near the camera while retaining each layer's scroll
		# phase. Rounding the offset to a whole span erased the parallax and
		# eventually left long maps outside the four copies altogether.
		var base := Vector2(half.x - fposmod(eye_x * scroll_scale.x, span), half.y - anchor_y)
		position = LevelSkin.snap(base)


## The air behind everything. A flat wash under the baked layers: the sky
## layer of the backdrop carries the banding and the light shafts, this is
## only there so no gap in the canopy shows the clear colour behind it.
func _sky() -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, JunglePalette.SKY_HIGH)
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, JunglePalette.at_distance(JunglePalette.CANOPY_FAR, 0.5))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = Vector2(0.0, 1.0)
	texture.width = 1
	texture.height = 64

	var sky := TextureRect.new()
	sky.texture = texture
	# A 4 px gradient stretched across 1280 with the default filter is a
	# smooth horizontal ramp, which puts a colour boundary on almost every
	# column - half of them odd. NEAREST turns it back into four flat bands.
	sky.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return sky


## Hanging ivy for a climbable face: a few strands, a leaf every so often,
## always the same leaves for the same wall. Square pixels, 2x, to match.
class Ivy extends Node2D:
	var size: Vector2 = Vector2(48.0, 400.0)

	func _draw() -> void:
		var stem := JunglePalette.LEAF_DARK.darkened(0.25)
		var leaf := JunglePalette.LEAF
		var leaf_dark := JunglePalette.LEAF_DARK
		var outline := JunglePalette.BARK_DARK
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
