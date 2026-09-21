class_name JungleTiles
extends RefCounted

# ============================================================
# JUNGLE TILES - the terrain atlas, baked as pixel art.
#
# Kenney's Pixel Platformer got the game to a playable look, but it cannot
# reach the key art, and the reason is anatomy rather than colour. Every
# platform in the reference is built the same way:
#
#     ____________________   <- one dark outline pixel
#    |====================|  <- lit grass cap, brightest on its top row
#    |,,,,,,,,,,,,,,,,,,,,|  <- grass falling into dirt
#    |::::.::::::.::..::::|  <- dirt body, grained, never a flat fill
#    |____________________|  <- dark underside, two pixels
#       \|/   \|/    \|/     <- moss fringe hanging off the lip
#
# That is what the art bible means by "bright top edge, dark underside,
# clear outline": it is not decoration, it is how a player reads where the
# standable surface is at a glance in a four-way race. So the tiles are
# baked here to that spec instead of borrowed.
#
# Same 18 px grid and same three-slice rows as before, so LevelSkin's
# geometry - which caps a row left and right and repeats the middle - did
# not have to change to use them.
# ============================================================

const SRC: int = 18
const COLUMNS: int = 8

# Row 0: ground caps. Row 1: bodies. Row 2: thin ledges and trunks.
const GRASS: Array[int] = [0, 1, 2]
const GRASS_SOLO: int = 3
const DIRT: Array[int] = [8, 9, 10]
const DIRT_DEEP: int = 11
const LEDGE: Array[int] = [16, 17, 18]
const LEDGE_SOLO: int = 19
const TRUNK: Array[int] = [20, 21, 22]

static var _atlas: ImageTexture = null


## The terrain atlas. Baked once for the whole game - the tiles do not vary
## per level, only what is built out of them does.
static func atlas() -> ImageTexture:
	if _atlas != null:
		return _atlas
	var canvas := PixelCanvas.new(COLUMNS * SRC, 3 * SRC)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260921      # fixed: the tiles must be identical everywhere

	for i in 3:
		_grass_cap(canvas, GRASS[i], i - 1, rng)
	_grass_cap(canvas, GRASS_SOLO, 2, rng)
	for i in 3:
		_dirt_body(canvas, DIRT[i], i - 1, rng)
	_dirt_body(canvas, DIRT_DEEP, 2, rng)
	for i in 3:
		_ledge(canvas, LEDGE[i], i - 1, rng)
	_ledge(canvas, LEDGE_SOLO, 2, rng)
	for i in 3:
		_trunk(canvas, TRUNK[i], i - 1, rng)

	_atlas = canvas.texture()
	return _atlas


## Where tile `index` starts in the atlas, in pixels.
static func origin(index: int) -> Vector2:
	return Vector2((index % COLUMNS) * SRC, (index / COLUMNS) * SRC)


# --- Tiles ---------------------------------------------------------
# `edge` is -1 for a left cap, 0 for the repeating middle, 1 for a right
# cap, 2 for a tile that is both edges at once.

static func _outline_sides(canvas: PixelCanvas, x: int, y: int, edge: int, color: Color) -> void:
	if edge == -1 or edge == 2:
		for row in SRC:
			canvas.put(x, y + row, color)
	if edge == 1 or edge == 2:
		for row in SRC:
			canvas.put(x + SRC - 1, y + row, color)


## The top of a thick ground: outline, lit cap, grass into dirt, then body.
static func _grass_cap(canvas: PixelCanvas, index: int, edge: int, rng: RandomNumberGenerator) -> void:
	var at := origin(index)
	var x := int(at.x)
	var y := int(at.y)
	var outline := JunglePalette.OUTLINE

	canvas.rect(x, y, SRC, SRC, JunglePalette.DIRT)
	canvas.speckle(x, y + 7, SRC, SRC - 7, JunglePalette.DIRT_DARK, 0.07, rng)
	canvas.speckle(x, y + 8, SRC, SRC - 8, JunglePalette.DIRT_LIGHT, 0.03, rng)
	# Grass: brightest on row 1, falling to the dark line that separates it
	# from the soil. Four rows, because three reads as a stripe and five
	# starts to look like a lawn.
	canvas.band(x, y + 1, SRC, JunglePalette.GRASS_SUN)
	canvas.band(x, y + 2, SRC, JunglePalette.GRASS)
	canvas.band(x, y + 3, SRC, JunglePalette.GRASS)
	canvas.band(x, y + 4, SRC, JunglePalette.GRASS_DARK)
	# Grass teeth biting down into the dirt, so the boundary is not a ruled
	# line. This is the single most "hand-drawn" pixel in the tile.
	for i in range(0, SRC, 2):
		var depth := rng.randi_range(0, 2)
		for d in depth:
			canvas.put(x + i, y + 5 + d, JunglePalette.GRASS_DARK)
	canvas.band(x, y, SRC, outline)
	_outline_sides(canvas, x, y, edge, outline)


## The body of a ground: grained soil, darkening downward, with the odd
## pebble and root so a tall stack never tiles visibly.
static func _dirt_body(canvas: PixelCanvas, index: int, edge: int, rng: RandomNumberGenerator) -> void:
	var at := origin(index)
	var x := int(at.x)
	var y := int(at.y)
	canvas.rect(x, y, SRC, SRC, JunglePalette.DIRT)
	for row in SRC:
		# A gentle vertical ramp into the dark, dithered so it does not band.
		var t := float(row) / float(SRC)
		for col in SRC:
			if float(PixelCanvas.BAYER[row % 4][col % 4]) / 16.0 < t * 0.45:
				canvas.put(x + col, y + row, JunglePalette.DIRT_DARK)
	canvas.speckle(x, y, SRC, SRC, JunglePalette.DIRT_DARK, 0.06, rng)
	canvas.speckle(x, y, SRC, SRC, JunglePalette.DIRT_LIGHT, 0.03, rng)
	for i in 2:
		var px := rng.randi_range(2, SRC - 4)
		var py := rng.randi_range(2, SRC - 3)
		canvas.band(x + px, y + py, 2, JunglePalette.DIRT_LIGHT)
		canvas.band(x + px, y + py + 1, 2, JunglePalette.DIRT_DARK)
	_outline_sides(canvas, x, y, edge, JunglePalette.OUTLINE)


## A thin platform: cap, a couple of rows of soil, dark underside, and moss
## hanging off the bottom. The whole thing is six pixels tall inside an
## 18 px tile - the rest is the fringe, which must not be collidable-looking.
static func _ledge(canvas: PixelCanvas, index: int, edge: int, rng: RandomNumberGenerator) -> void:
	var at := origin(index)
	var x := int(at.x)
	var y := int(at.y)
	var outline := JunglePalette.OUTLINE

	canvas.band(x, y, SRC, outline)
	canvas.band(x, y + 1, SRC, JunglePalette.GRASS_SUN)
	canvas.band(x, y + 2, SRC, JunglePalette.GRASS)
	canvas.band(x, y + 3, SRC, JunglePalette.GRASS_DARK)
	canvas.band(x, y + 4, SRC, JunglePalette.DIRT)
	canvas.band(x, y + 5, SRC, JunglePalette.DIRT_DARK)
	canvas.band(x, y + 6, SRC, outline)
	canvas.speckle(x, y + 4, SRC, 2, JunglePalette.DIRT_LIGHT, 0.06, rng)
	canvas.grass_fringe(x, y + 7, SRC, JunglePalette.MOSS, JunglePalette.GRASS_SUN, rng)
	_outline_sides(canvas, x, y, edge, outline)
	if edge == -1 or edge == 2:
		for row in range(0, 7):
			canvas.put(x, y + row, outline)
	if edge == 1 or edge == 2:
		for row in range(0, 7):
			canvas.put(x + SRC - 1, y + row, outline)


## A climbable trunk face: bark with a lit left edge, grain, and knots.
static func _trunk(canvas: PixelCanvas, index: int, edge: int, rng: RandomNumberGenerator) -> void:
	var at := origin(index)
	var x := int(at.x)
	var y := int(at.y)
	canvas.rect(x, y, SRC, SRC, JunglePalette.BARK)
	for row in SRC:
		canvas.put(x + 1, y + row, JunglePalette.BARK_LIGHT)
		canvas.put(x + 2, y + row, JunglePalette.BARK_LIGHT)
		canvas.put(x + SRC - 2, y + row, JunglePalette.BARK_DARK)
	# Grain: short vertical dashes, offset per column.
	for col in range(3, SRC - 2, 3):
		var start := rng.randi_range(0, 6)
		for row in range(start, SRC, rng.randi_range(6, 10)):
			canvas.put(x + col, y + row, JunglePalette.BARK_DARK)
			canvas.put(x + col, y + row + 1, JunglePalette.BARK_DARK)
	_outline_sides(canvas, x, y, edge, JunglePalette.OUTLINE)


# --- Props ---------------------------------------------------------
# Trees and undergrowth, baked as whole sprites rather than assembled from
# grid tiles. A 3x3 block of canopy tiles is a square, and a square is what
# the first pass at this looked like; a crown wants to be one irregular
# silhouette wider than its trunk, which a grid cannot give you.

const PROP_SIZES := {
	&"crown_big": Vector2i(112, 84),
	&"crown_small": Vector2i(76, 58),
	&"fern": Vector2i(44, 30),
	&"shrub": Vector2i(38, 24),
}

static var _props: Dictionary = {}


static func prop(name: StringName) -> ImageTexture:
	if _props.has(name):
		return _props[name]
	var size: Vector2i = PROP_SIZES.get(name, Vector2i(32, 32))
	var canvas := PixelCanvas.new(size.x, size.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(name.hash())
	match name:
		&"crown_big": _crown_prop(canvas, rng, 3)
		&"crown_small": _crown_prop(canvas, rng, 2)
		&"fern": _fern_prop(canvas, rng)
		&"shrub": _shrub_prop(canvas, rng)
	# The dark keyline that separates a prop from whatever is behind it.
	# Backdrop layers deliberately do not get this; foreground props all do.
	canvas.outline_silhouette(JunglePalette.OUTLINE)
	_props[name] = canvas.texture()
	return _props[name]


## A tree crown: a wide dark mass, a second lighter pass raised and offset
## toward the sun, then hanging leaf tips along the underside.
static func _crown_prop(canvas: PixelCanvas, rng: RandomNumberGenerator, tiers: int) -> void:
	var cx := canvas.width / 2
	var cy := canvas.height / 2
	var radius := int(float(canvas.width) * 0.42)
	# Three tiers, each smaller, raised, and shifted toward the sun. Dark
	# underneath and light on top is the only reason a crown reads as a
	# volume rather than as a flat sticker of a tree.
	canvas.crown(cx, cy + 4, radius, JunglePalette.CANOPY_FRAME, JunglePalette.LEAF_DARK, 0.30, rng)
	canvas.crown(cx + PixelCanvas.LIT_SIDE * 3, cy - 1, int(radius * 0.88), JunglePalette.LEAF_DARK, JunglePalette.LEAF, 0.55, rng)
	if tiers > 2:
		canvas.crown(cx + PixelCanvas.LIT_SIDE * 6, cy - 9, int(radius * 0.56), JunglePalette.LEAF, JunglePalette.LEAF_SUN, 0.85, rng)
	# Shadow pockets between the lit lobes. Without them the tiers read as
	# three flat stickers stacked up; with them the crown has gaps that the
	# light does not reach, which is what foliage actually looks like.
	for i in 5:
		var angle := rng.randf_range(0.0, TAU)
		var reach := float(radius) * rng.randf_range(0.35, 0.72)
		canvas.disc(
			cx + int(cos(angle) * reach), cy + int(sin(angle) * reach * 0.55) + 4,
			rng.randi_range(3, 7), rng.randi_range(2, 5), JunglePalette.CANOPY_FRAME)
	# Leaf tips dropping out of the underside, so the crown does not end on
	# a clean curve. Found by walking up from the bottom of each column.
	for x in range(2, canvas.width - 2, 3):
		var y := canvas.height - 1
		while y > 0 and canvas.get_at(x, y).a < 0.5:
			y -= 1
		if y <= 0:
			continue
		for d in rng.randi_range(1, 4):
			canvas.put(x, y + d, JunglePalette.LEAF_DARK)


## A fern: blades fanning up and out from one root, each one ribbed.
static func _fern_prop(canvas: PixelCanvas, rng: RandomNumberGenerator) -> void:
	var root := Vector2i(canvas.width / 2, canvas.height - 1)
	for i in 7:
		var spread := lerpf(-1.05, 1.05, float(i) / 6.0)
		var length := rng.randi_range(14, int(canvas.height * 0.92))
		var dir := Vector2(sin(spread), -cos(spread))
		var tone := JunglePalette.LEAF if i % 2 == 0 else JunglePalette.LEAF_DARK
		for step in length:
			var at := Vector2i(root) + Vector2i((dir * float(step)).round())
			var half := 1 if step > length / 2 else 2
			canvas.band(at.x - half, at.y, half * 2 + 1, tone)
			if step % 3 == 0:
				canvas.put(at.x, at.y, JunglePalette.LEAF_LIGHT)


## A shrub: two low mounds with a lit top edge. Undergrowth, nothing more -
## it must never read as something a monkey can stand on.
static func _shrub_prop(canvas: PixelCanvas, rng: RandomNumberGenerator) -> void:
	var base := canvas.height - 1
	canvas.crown(canvas.width / 2, base - 5, int(canvas.width * 0.40), JunglePalette.LEAF_DARK, JunglePalette.LEAF, 0.5, rng)
	canvas.crown(canvas.width / 3, base - 3, int(canvas.width * 0.26), JunglePalette.LEAF, JunglePalette.LEAF_LIGHT, 0.7, rng)
	# Flat off at the ground line: a shrub sits on the soil, it does not
	# float over it.
	for x in canvas.width:
		for y in range(base + 1, canvas.height):
			canvas.put(x, y, Color(0, 0, 0, 0))
