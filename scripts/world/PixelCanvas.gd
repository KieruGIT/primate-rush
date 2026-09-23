class_name PixelCanvas
extends RefCounted

# ============================================================
# PIXEL CANVAS - an Image you can draw pixel art into.
#
# Everything the game bakes - backdrop layers, terrain tiles, tree crowns -
# is built through this one object, for the reason the art bible gives:
# Godot's draw_* calls are vector calls, they antialias, and a single
# antialiased curve next to an 18 px tile is instantly visible as "the AI
# background". A leaf here is pixels. A trunk edge is one pixel of light and
# one of dark. Nothing is ever half a pixel.
#
# It also keeps one bounds check in one place. Every primitive below writes
# through `put`, so a shape that runs off the edge of a tile clips instead
# of wrapping to the far side, which is the bug that makes baked atlases
# bleed into each other.
#
# What is left is deliberately small. Everything that wanted an artist's
# judgement - leaf crowns, terrain tiles, undergrowth - was moved out to
# JungleTileArt and JungleFoliageArt and drawn by hand, because a procedural
# crown is a blob however many passes go over it. These are the pieces that
# genuinely are mechanical: a trunk of uniform bark, a vine that hangs, a
# wash of light, and `stamp_art`, which places the drawn pixels.
# ============================================================

## Sun direction, as a rule rather than a parameter: light comes from up and
## to the left, in every layer, every tile and every prop. The moment two
## pieces disagree about this the scene stops reading as one place.
const LIT_SIDE: int = -1

var image: Image
var width: int
var height: int


func _init(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))


func texture() -> ImageTexture:
	return ImageTexture.create_from_image(image)


# --- Primitives ----------------------------------------------------

func put(x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	image.set_pixel(x, y, color)


func get_at(x: int, y: int) -> Color:
	if x < 0 or y < 0 or x >= width or y >= height:
		return Color(0, 0, 0, 0)
	return image.get_pixel(x, y)


## Alpha-blends onto what is already there. For haze and light shafts, which
## sit over a layer rather than replacing it.
func blend(x: int, y: int, color: Color, alpha: float) -> void:
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	image.set_pixel(x, y, get_at(x, y).lerp(color, clampf(alpha, 0.0, 1.0)))


func band(x: int, y: int, run: int, color: Color) -> void:
	for i in run:
		put(x + i, y, color)


func rect(x: int, y: int, w: int, h: int, color: Color) -> void:
	for row in h:
		band(x, y + row, w, color)


## A filled ellipse. The building block of everything leafy.
func disc(cx: int, cy: int, rx: int, ry: int, color: Color) -> void:
	for y in range(-ry, ry + 1):
		# Integer span per row: this is what gives the disc a stepped pixel
		# edge rather than an antialiased one.
		var t := 1.0 - float(y * y) / float(maxi(ry * ry, 1))
		if t <= 0.0:
			continue
		var half := int(sqrt(t) * float(rx))
		band(cx - half, cy + y, half * 2 + 1, color)


## Fills downward from whatever is already drawn, column by column, so the
## fill's top edge is the underside of the canopy above it rather than a
## ruled line. The first version of the backdrop used a flat fill_below and
## put a visible seam straight across the screen; there is no colour that
## rescues a straight horizontal edge in a jungle.
func fill_under_canopy(scan_to: int, color: Color) -> void:
	for x in width:
		var deepest := -1
		for y in range(0, mini(scan_to, height)):
			if get_at(x, y).a > 0.5:
				deepest = y
		var start := deepest + 1 if deepest >= 0 else scan_to
		for y in range(maxi(start, 0), height):
			put(x, y, color)


# --- Jungle shapes -------------------------------------------------

## Stamps a hand-drawn character grid, every pixel pushed toward `blend_to`
## by `amount`. That is how one authored crown serves the foreground at full
## contrast and a far parallax layer washed most of the way into the haze,
## without drawing it twice or letting the two drift apart.
func stamp_art(x: int, y: int, art: Array, ink: Callable, blend_to: Color, amount: float) -> void:
	for dy in art.size():
		var line: String = art[dy]
		for dx in line.length():
			var col: Color = ink.call(line[dx])
			if col.a <= 0.0:
				continue
			put(x + dx, y + dy, col.lerp(blend_to, clampf(amount, 0.0, 1.0)))


## A trunk: solid bark, a lit edge on the sun side, a dark one opposite,
## and notches that never line up into a column.
func trunk(cx: int, top: int, bottom: int, thickness: int, bark: Color, behind: Color, notched: bool = true) -> void:
	var light := bark.lightened(0.22) if notched else bark.lerp(behind, 0.16)
	var dark := bark.darkened(0.3) if notched else bark.darkened(0.10)
	var left := cx - thickness / 2
	for y in range(maxi(top, 0), mini(bottom, height)):
		band(left, y, thickness, bark)
		put(left, y, light)
		put(left + thickness - 1, y, dark)
		# Notches are foreground detail. On a backdrop layer, where the trunk
		# is already pushed most of the way to the canopy colour, they read as
		# a dashed line rather than as bark.
		if notched and (y + cx) % 9 == 0:
			put(left + 2, y, dark)
			put(left + 3, y, behind.lerp(dark, 0.6))


## A hanging vine with leaf pairs. Sways on a sine so a row of them is never
## a row of straight lines.
func vine(x: int, top: int, length: int, stem: Color, light: Color) -> void:
	var dark := stem.darkened(0.25)
	for i in length:
		var y := top + i
		var sway := int(sin(float(i) * 0.14 + float(x)) * 2.0)
		put(x + sway, y, dark)
		put(x + sway + 1, y, stem)
		if i % 11 == 5:
			# One small leaf, alternating sides. A pair every seven pixels
			# turned a vine into a dashed line across the sky.
			var side := 1 if (i / 11) % 2 == 0 else -1
			for k in 2:
				put(x + sway + (2 + k) * side, y, stem)
				put(x + sway + (2 + k) * side, y + 1, dark)
			put(x + sway + 2 * side, y - 1, light)


## A single big leaf hanging point-down, ribbed along its spine.
func frond(x: int, top: int, length: int, base: Color, light: Color, rng: RandomNumberGenerator) -> void:
	var lean := rng.randf_range(-0.28, 0.28)
	for i in length:
		var t := float(i) / float(maxi(length, 1))
		# Widest a third of the way down, pinched at the tip.
		var half := int(sin(t * PI * 0.9) * 9.0) + 1
		var cx := x + int(lean * float(i))
		var y := top + i
		band(cx - half, y, half * 2 + 1, base)
		put(cx, y, base.lerp(light, 0.5))
		if i % 4 == 0:
			put(cx - half, y, light.lerp(base, 0.3))


## A shaft of light through a gap in the canopy: a soft-edged diagonal wedge,
## blended rather than drawn, widening as it falls.
func sunshaft(x: int, thickness: int, strength: float, tint: Color) -> void:
	for y in height:
		var t := float(y) / float(maxi(height, 1))
		var half := int(float(thickness) * (0.4 + t * 0.6)) / 2
		var cx := x + int(t * 70.0)
		for i in range(-half, half + 1):
			var across := 1.0 - absf(float(i) / float(maxi(half, 1)))
			blend(cx + i, y, tint, strength * across * (1.0 - t * 0.75))
