class_name JungleBackdrop
extends RefCounted

# ============================================================
# JUNGLE BACKDROP - the parallax layers, baked as actual pixel art.
#
# The first pass at this drew the background with draw_circle and
# draw_colored_polygon, and it was wrong for a reason worth writing down:
# those are vector calls, they antialias, and a smooth canopy behind a level
# made of hard 18 px tiles reads instantly as two different pictures. So
# nothing here draws to the screen - each layer is rasterised through
# PixelCanvas and handed to a Parallax2D at NEAREST and a whole-number zoom.
#
# The foliage itself is the hand-drawn crown from JungleFoliageArt, the same
# one the foreground trees use, washed toward the haze by however far back
# the layer sits. One drawing, four distances - which is also why the near
# layer and the trees in front of it never disagree about what a leaf is.
#
# The layers obey the art bible's hierarchy, and it is the hierarchy rather
# than the detail that makes a background work: back layers lose saturation
# and contrast toward the haze, front layers gain darkness, and *none* of
# them carries a bright edge, because a bright edge back here competes with
# the platform the player is trying to land on.
#
#   far   pale, low contrast, no interior detail
#   mid   the readable middle distance: trunks, crowns, vines
#   near  dark, almost flat, framing the top of the screen
#
# Every layer is full height and overlaps the one behind it. Nothing ends on
# a horizontal line - the first pass had a visible seam straight across the
# screen where a fill started, which no amount of colour work can rescue.
#
# Baked once per layer per seed and cached: it is a few hundred thousand
# pixel writes and a match must not pay for it twice.
# ============================================================

## Art-pixel size of a layer. One screen is 640x360 of these at ZOOM 2,
## which is the same art-pixel size the monkeys and the tiles use.
const WIDTH: int = 640
## Tall enough to cover a zoomed-out arena camera, not just a race camera.
## At 440 the arena maps showed bare sky above the canopy, because they are
## framed wider than the race maps are.
const HEIGHT: int = 960
## World pixels per art pixel. Whole number, always - a fractional zoom is
## how pixel art gets uneven pixels, and there is no fixing it downstream.
const ZOOM: int = 2

## Where each layer's canopy sits in art pixels from the top of its canvas.
## LevelSkin places a layer by this line rather than by its top edge, so the
## canopy lands where it is wanted on screen and the canvas height is free to
## change without every offset needing to be re-guessed.
const CANOPY_LINE := {
	&"far": 200,
	&"mid": 300,
	&"near": 20,
}

static var _cache: Dictionary = {}


static func canopy_line(kind: StringName) -> int:
	return int(CANOPY_LINE.get(kind, 0))


## An ImageTexture for one layer. `kind` is &"far", &"mid" or &"near"; they
## are meant to be stacked in that order.
## Stamps one authored crown, centred on (x, y), washed toward `blend_to`.
static func _crown(canvas: PixelCanvas, x: int, y: int, art: Array, blend_to: Color, amount: float) -> void:
	var w := String(art[0]).length()
	canvas.stamp_art(x - w / 2, y - art.size() / 2, art, JungleFoliageArt.ink, blend_to, amount)


static func layer(kind: StringName, seed_value: int) -> ImageTexture:
	var key := "%s:%d" % [kind, seed_value]
	if _cache.has(key):
		return _cache[key]
	var canvas := PixelCanvas.new(WIDTH, HEIGHT)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + int(kind.hash())
	match kind:
		&"far": _paint_far(canvas, rng)
		&"mid": _paint_mid(canvas, rng)
		&"near": _paint_near(canvas, rng)
	var texture := canvas.texture()
	_cache[key] = texture
	return texture


# --- Layers --------------------------------------------------------

## The far wall of jungle: one pale mass with a scalloped top, ghost trunks
## in the haze, and a couple of light shafts coming down through the gap.
## Almost no interior detail - a far layer that competes flattens the scene.
static func _paint_far(canvas: PixelCanvas, rng: RandomNumberGenerator) -> void:
	var air := JunglePalette.HAZE
	var tint := JunglePalette.CANOPY_FAR.lerp(air, 0.35)
	var base := canopy_line(&"far")
	# Giant trunks continue through the view. Gaps preserve the blue air.
	for i in 16:
		var x := i * 44 + rng.randi_range(-14, 14)
		var y := base + rng.randi_range(-75, 80)
		var width := rng.randi_range(7, 18)
		canvas.trunk(x, y, HEIGHT, width, tint, air, false)
		for tier in 4:
			_crown(canvas, x + (tier % 2 * 2 - 1) * 14, y + tier * 15, JungleFoliageArt.CROWN_BIG, tint, 0.94)
	# A distant stepped temple, deliberately lower contrast than terrain.
	var stone := tint.lerp(JunglePalette.SKY_HIGH, 0.22)
	for tier in 7:
		var half := 10 + tier * 9
		canvas.rect(438 - half, base + 55 + tier * 12, half * 2, 13, stone)
		canvas.band(438 - half, base + 55 + tier * 12, half * 2, stone.lerp(air, 0.22))
	canvas.rect(433, base + 38, 10, 18, stone)
	canvas.rect(437, base + 29, 3, 9, JunglePalette.BANANA_DARK.lerp(air, 0.7))
	# Distant waterfall ribbons, stepped and subdued in the haze.
	for fall: Vector2i in [Vector2i(174, 335), Vector2i(505, 393)]:
		canvas.rect(fall.x - 23, fall.y - 5, 54, 9, tint)
		for strand in 5:
			var x: int = fall.x + strand * 3
			var water := JunglePalette.WATER_GLINT.lerp(air, 0.73 + strand * 0.035)
			canvas.rect(x, fall.y, 2, HEIGHT - fall.y, water)
			for y in range(fall.y + strand * 11, HEIGHT, 39):
				canvas.rect(x, y, 2, 7, air)


static func _paint_mid(canvas: PixelCanvas, rng: RandomNumberGenerator) -> void:
	var tint := JunglePalette.CANOPY_MID
	var bark := JunglePalette.BARK.lerp(tint, 0.78)
	var base := canopy_line(&"mid")
	# Sparse ancient trees, rather than a horizontal hedge of little crowns.
	for i in 6:
		var x := i * 123 + rng.randi_range(-24, 24)
		var top := base - rng.randi_range(20, 100)
		var width := rng.randi_range(19, 32)
		canvas.trunk(x, top, HEIGHT, width, bark, tint, false)
		for bark_y in range(top, HEIGHT, 18):
			canvas.stamp_art(x - width / 2 + 2, bark_y, JungleTileArt.TRUNK_M, JungleTileArt.ink, tint, 0.88)
		for seam in 3:
			var sx := x - width / 2 + 4 + seam * 7
			canvas.rect(sx, top + seam * 17, 2, HEIGHT - top, bark.lerp(tint, 0.5))
		# Branches taper in pixel steps and carry foliage at their ends.
		for branch in 3:
			var y := top + 30 + branch * 99
			var side := -1 if (i + branch) % 2 == 0 else 1
			for step in 24:
				canvas.rect(x + side * step * 2, y - step / 2, 3, maxi(2, 8 - step / 4), bark)
			_crown(canvas, x + side * 39, y - 9, JungleFoliageArt.CROWN_BIG, tint, 0.84)
			canvas.vine(x + side * 41, y, 45 + branch * 15, tint, JunglePalette.CANOPY_FAR)
		for offset in [-26, 0, 27]:
			_crown(canvas, x + offset, top + absi(offset) / 2, JungleFoliageArt.CROWN_BIG, tint, 0.82)
		canvas.vine(x - width / 2, top + 16, 150, tint, JunglePalette.LEAF_DARK)


static func _paint_near(canvas: PixelCanvas, rng: RandomNumberGenerator) -> void:
	var tint := JunglePalette.CANOPY_FRAME
	var light := JunglePalette.CANOPY_NEAR
	var x := -30
	while x < WIDTH + 30:
		_crown(canvas, x, canopy_line(&"near") + rng.randi_range(-6, 18), JungleFoliageArt.CROWN_BIG, tint, 0.92)
		x += rng.randi_range(34, 50)
	for i in 9:
		canvas.frond(rng.randi_range(0, WIDTH), rng.randi_range(8, 30), rng.randi_range(18, 48), tint, light, rng)
	for i in 6:
		canvas.vine(rng.randi_range(0, WIDTH), 10, rng.randi_range(50, 100), tint, light)
