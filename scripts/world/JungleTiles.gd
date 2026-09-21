class_name JungleTiles
extends RefCounted

# ============================================================
# JUNGLE TILES - the terrain atlas.
#
# The pixels live in JungleTileArt, drawn by hand, one character each. This
# file only lays them into an atlas and hands it to LevelSkin.
#
# It used to bake them procedurally - speckle here, dither there - and the
# result was texture rather than ground: evenly scattered noise with no
# forms in it. Rock is a cluster with a lit top and a dark underside, and a
# seeded random number generator does not place those, a person does.
#
# The platform anatomy the art bible specifies is drawn into the tiles
# themselves:
#
#     ____________________   one dark outline pixel
#    |====================|  lit grass cap, brightest on its top row
#    |,,,,,,\,,,,,,,/,,,,,|  grass teeth biting down into the soil
#    |::::.::::::.::..::::|  soil with rocks and roots, never flat noise
#    |____________________|  dark underside
#       \|/   \|/    \|/     moss clumps hanging off the lip
#
# Same 18 px grid and same three-slice rows as before, so LevelSkin's
# geometry - which caps a row left and right and repeats the middle - did
# not have to change.
# ============================================================

const SRC: int = JungleTileArt.SIZE
const COLUMNS: int = 8

# Row 0: ground caps. Row 1: bodies. Row 2: thin ledges and trunks.
const GRASS: Array[int] = [0, 1, 2]
const GRASS_SOLO: int = 3
const DIRT: Array[int] = [8, 9, 10]
const DIRT_DEEP: int = 11
## Soil tiles in cycle order, so a wide ground does not repeat one tile.
const DIRT_VARIANTS: Array[int] = JungleTileArt.DIRT_VARIANTS
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
	for index: int in JungleTileArt.BY_INDEX:
		_paint(canvas, index, JungleTileArt.BY_INDEX[index])
	_atlas = canvas.texture()
	return _atlas


## Where tile `index` starts in the atlas, in pixels.
static func origin(index: int) -> Vector2:
	return Vector2((index % COLUMNS) * SRC, (index / COLUMNS) * SRC)


## Lays one hand-drawn tile into the atlas. A ragged row is a typo in the
## art, not a colour that happens to be missing, so it fails loudly rather
## than painting a tile that is silently a pixel short.
static func _paint(canvas: PixelCanvas, index: int, art: Array) -> void:
	assert(art.size() == SRC, "tile %d has %d rows, expected %d" % [index, art.size(), SRC])
	var at := origin(index)
	for y in art.size():
		var line: String = art[y]
		assert(line.length() == SRC, "tile %d row %d is %d wide, expected %d" % [index, y, line.length(), SRC])
		for x in line.length():
			var ink := JungleTileArt.ink(line[x])
			if ink.a <= 0.0:
				continue
			canvas.put(int(at.x) + x, int(at.y) + y, ink)


# --- Props ---------------------------------------------------------
# Trees and undergrowth. The pixels are in JungleFoliageArt, drawn by hand;
# this only turns them into textures. They were generated from stamped
# ellipses before, and a crown built that way is a blob however many passes
# you put over it - foliage reads as foliage because someone decided where
# each clump goes.

static var _props: Dictionary = {}


static func prop(name: StringName) -> ImageTexture:
	if _props.has(name):
		return _props[name]
	var art: Array = JungleFoliageArt.BY_NAME.get(name, [])
	if art.is_empty():
		push_warning("JungleTiles.prop: no art named %s" % name)
		return null
	var canvas := PixelCanvas.new(String(art[0]).length(), art.size())
	for y in art.size():
		var line: String = art[y]
		assert(line.length() == canvas.width, "%s row %d is ragged" % [name, y])
		for x in line.length():
			var ink := JungleFoliageArt.ink(line[x])
			if ink.a > 0.0:
				canvas.put(x, y, ink)
	_props[name] = canvas.texture()
	return _props[name]
