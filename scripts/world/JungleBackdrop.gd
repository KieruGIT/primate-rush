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
const HEIGHT: int = 640
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
	var tint := JunglePalette.at_distance(JunglePalette.CANOPY_FAR, 0.62)
	var light := JunglePalette.at_distance(JunglePalette.LEAF_LIGHT, 0.78)
	var base: int = canopy_line(&"far")
	var far_crowns := base + 30
	# Trunks first so a crown always caps the one under it. Drawn the other
	# way round, a trunk whose crown was sparse stood in the sky like a post.
	var trunks: Array = []
	var x := -20
	while x < WIDTH + 20:
		var radius := rng.randi_range(24, 44)
		var y := base + rng.randi_range(-16, 12)
		trunks.append([x, y, radius])
		if rng.randf() < 0.35:
			canvas.trunk(x, y, HEIGHT, 3, JunglePalette.at_distance(JunglePalette.BARK, 0.72).lerp(tint, 0.7), tint)
		x += int(radius * rng.randf_range(0.85, 1.2))
	for entry in trunks:
		canvas.crown(entry[0], entry[1], entry[2], tint, light, 0.16, rng)
	canvas.fill_under_canopy(far_crowns + 40, tint)
	for i in 3:
		canvas.sunshaft(rng.randi_range(40, WIDTH - 40), rng.randi_range(50, 96), rng.randf_range(0.10, 0.18), JunglePalette.SUNSHAFT)


## The layer that carries the detail: whole trees with bark, crowns lit
## along their tops, and vines hanging between them.
static func _paint_mid(canvas: PixelCanvas, rng: RandomNumberGenerator) -> void:
	var tint := JunglePalette.at_distance(JunglePalette.CANOPY_MID, 0.26)
	var light := JunglePalette.at_distance(JunglePalette.LEAF_LIGHT, 0.34)
	# Pushed most of the way to the canopy colour. A trunk back here only has
	# to say "there is a tree"; drawn at its own contrast it reads as a post
	# standing in front of the jungle instead of inside it.
	var bark := JunglePalette.at_distance(JunglePalette.BARK, 0.26).lerp(tint, 0.55)
	var base: int = canopy_line(&"mid")
	var mid_crowns := base + 40
	var trees: Array = []
	var x := -16
	while x < WIDTH + 16:
		var radius := rng.randi_range(26, 46)
		var y := base + rng.randi_range(-24, 16)
		canvas.trunk(x, y, HEIGHT, rng.randi_range(5, 9), bark, tint)
		trees.append([x, y, radius])
		x += int(radius * rng.randf_range(0.80, 1.12))
	for entry in trees:
		canvas.crown(entry[0], entry[1], entry[2], tint, light, 0.40, rng)
	# Vines hang out of the crowns, never out of open sky.
	for entry in trees:
		if rng.randf() < 0.45:
			canvas.vine(entry[0] + rng.randi_range(-entry[2] / 2, entry[2] / 2), entry[1] + entry[2] / 2, rng.randi_range(30, 90), tint, light)
	canvas.fill_under_canopy(mid_crowns + 50, tint)


## The near frame: a dark canopy hanging into the top of the screen with
## fronds dropping out of it, and unlit undergrowth along the bottom that
## the level stands in front of. Flat and dark on purpose - this is the
## inside of the frame, not scenery to read.
static func _paint_near(canvas: PixelCanvas, rng: RandomNumberGenerator) -> void:
	var tint := JunglePalette.CANOPY_FRAME
	var light := JunglePalette.CANOPY_NEAR
	var x := -30
	while x < WIDTH + 30:
		var radius := rng.randi_range(30, 54)
		canvas.crown(x, canopy_line(&"near") + rng.randi_range(-30, 4), radius, tint, light, 0.22, rng)
		x += int(radius * rng.randf_range(0.66, 0.96))
	for i in 11:
		canvas.frond(rng.randi_range(0, WIDTH), rng.randi_range(8, 44), rng.randi_range(26, 74), tint, light, rng)
	for i in 7:
		canvas.vine(rng.randi_range(0, WIDTH), rng.randi_range(0, 30), rng.randi_range(40, 120), tint, light)
	# Undergrowth along the bottom, tall enough to sit behind a ground but
	# never so tall it reaches a platform the player has to read.
	var u := -20
	while u < WIDTH + 20:
		var radius := rng.randi_range(22, 40)
		canvas.crown(u, HEIGHT - rng.randi_range(0, 18), radius, tint, light, 0.18, rng)
		u += int(radius * rng.randf_range(0.7, 1.0))
