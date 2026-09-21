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
# ============================================================

## Sun direction, as a rule rather than a parameter: light comes from up and
## to the left, in every layer, every tile and every prop. The moment two
## pieces disagree about this the scene stops reading as one place.
const LIT_SIDE: int = -1

## 4x4 ordered dither. Used on colour transitions, because a smooth ramp
## bands visibly and a dithered one reads as deliberate - it is what the era
## this art is quoting actually did.
const BAYER: Array = [
	[0, 8, 2, 10],
	[12, 4, 14, 6],
	[3, 11, 1, 9],
	[15, 7, 13, 5],
]

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


func fill_below(y: int, color: Color) -> void:
	for row in range(maxi(y, 0), height):
		band(0, row, width, color)


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


## Draws `color` on every transparent pixel touching an opaque one: the dark
## keyline the key art puts round every foreground object. Orthogonal
## neighbours only - including diagonals fattens it to two pixels on curves.
func outline_silhouette(color: Color) -> void:
	var source := image.duplicate() as Image
	for y in height:
		for x in width:
			if source.get_pixel(x, y).a > 0.1:
				continue
			var touching := false
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + offset.x
				var ny: int = y + offset.y
				if nx < 0 or ny < 0 or nx >= width or ny >= height:
					continue
				if source.get_pixel(nx, ny).a > 0.5:
					touching = true
					break
			if touching:
				put(x, y, color)


## A ramp quantised to `steps` flat bands, dithered between each pair.
func dither_gradient(top: Color, bottom: Color, steps: int) -> void:
	for y in height:
		var level := float(y) / float(maxi(height - 1, 1)) * float(steps)
		var index := int(level)
		var frac := level - float(index)
		var near := top.lerp(bottom, clampf(float(index) / float(steps), 0.0, 1.0))
		var next := top.lerp(bottom, clampf(float(index + 1) / float(steps), 0.0, 1.0))
		for x in width:
			put(x, y, next if frac > float(BAYER[y % 4][x % 4]) / 16.0 else near)


## Speckle: scattered single pixels, for dirt grain and stone pitting. The
## cheapest detail there is and the one that stops a fill reading as a fill.
func speckle(x: int, y: int, w: int, h: int, color: Color, density: float, rng: RandomNumberGenerator) -> void:
	var count := int(float(w * h) * density)
	for i in count:
		put(x + rng.randi_range(0, maxi(w - 1, 0)), y + rng.randi_range(0, maxi(h - 1, 0)), color)


# --- Jungle shapes -------------------------------------------------

## A leaf crown: overlapping lobes, then light run along the silhouette's
## own top edge.
##
## The first version lit each lobe separately, stepping every second pixel
## around its arc, and the result was chains of dots floating in the sky -
## lobes that had been buried under later lobes were still drawing their
## highlight. Lighting the finished silhouette instead means the light can
## only ever land on a pixel that is actually the top of the crown.
func crown(cx: int, cy: int, radius: int, base: Color, light: Color, lit: float, rng: RandomNumberGenerator) -> void:
	var lobes := 4 + radius / 14
	var left := width
	var right := 0
	for i in lobes:
		var angle := TAU * float(i) / float(lobes) + rng.randf_range(-0.3, 0.3)
		var reach := float(radius) * rng.randf_range(0.30, 0.62)
		var at := Vector2i(cx + int(cos(angle) * reach), cy + int(sin(angle) * reach * 0.62))
		var r := int(float(radius) * rng.randf_range(0.42, 0.66))
		disc(at.x, at.y, r, int(r * 0.78), base)
		left = mini(left, at.x - r)
		right = maxi(right, at.x + r)
	_light_top_edge(left, right, cy - radius - 2, cy + radius + 2, base, light, lit)


## Runs a lit edge along the top of whatever is opaque in a column range.
## `lit` fades the light out toward the shaded side, so a crown is brightest
## where it faces the sun rather than evenly outlined.
func _light_top_edge(from_x: int, to_x: int, from_y: int, to_y: int, base: Color, light: Color, lit: float) -> void:
	var span := maxi(to_x - from_x, 1)
	for x in range(maxi(from_x, 0), mini(to_x + 1, width)):
		var top := -1
		for y in range(maxi(from_y, 0), mini(to_y + 1, height)):
			if get_at(x, y).a > 0.5:
				top = y
				break
		if top < 0:
			continue
		# Full strength on the sun side, falling off across the crown.
		var across := float(x - from_x) / float(span)
		var strength := lit * (1.0 - across * 0.75) if LIT_SIDE < 0 else lit * (0.25 + across * 0.75)
		if strength <= 0.04:
			continue
		put(x, top, base.lerp(light, clampf(strength * 1.6, 0.0, 1.0)))
		put(x, top + 1, base.lerp(light, clampf(strength * 0.7, 0.0, 1.0)))


## A trunk: solid bark, a lit edge on the sun side, a dark one opposite,
## and notches that never line up into a column.
func trunk(cx: int, top: int, bottom: int, thickness: int, bark: Color, behind: Color) -> void:
	var light := bark.lightened(0.22)
	var dark := bark.darkened(0.3)
	var left := cx - thickness / 2
	for y in range(maxi(top, 0), mini(bottom, height)):
		band(left, y, thickness, bark)
		put(left, y, light)
		put(left + thickness - 1, y, dark)
		if (y + cx) % 9 == 0:
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


## Grass blades standing up off a surface, and the moss fringe that hangs
## under its front lip. Both are what make a platform look grown rather than
## cut, and the fringe is half the key art's platform silhouette.
func grass_fringe(x: int, y: int, run: int, base: Color, light: Color, rng: RandomNumberGenerator) -> void:
	var i := 0
	while i < run:
		var drop := rng.randi_range(1, 4)
		for d in drop:
			put(x + i, y + d, base if d < drop - 1 else base.darkened(0.2))
		if drop >= 3:
			put(x + i, y, light)
		i += rng.randi_range(1, 3)


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
