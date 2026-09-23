class_name JunglePalette
extends RefCounted

# ============================================================
# JUNGLE PALETTE - one colour language for the whole game.
#
# The look is the key art: deep jungle in daylight. Not a night scene - the
# frames are dark because the canopy is thick and the player is *under* it,
# which is a different thing and a warmer one. Light comes down through the
# leaves in shafts, the foliage reads teal-green in shade and yellow-green
# where the sun reaches it, and the wood is warm brown. Torches still burn,
# because the jungle floor is dim, but they are accents now rather than the
# only light in the frame.
#
# Kept as one table rather than as constants scattered through LevelSkin,
# Pickup and Vine, because the moment two files each own "jungle green" the
# jungle stops being one jungle.
# ============================================================

# --- Sky and air ---------------------------------------------------
## What little sky shows through the canopy: hazy, bright, washed out.
const SKY_HIGH := Color8(19, 57, 83)
const SKY_LOW := Color8(66, 139, 155)
## The haze the far jungle sits in. Everything distant fades toward this.
const HAZE := Color8(48, 111, 137)
## A shaft of sun coming down through a gap in the leaves.
const SUNSHAFT := Color8(139, 193, 190)

# --- Foliage, back to front ----------------------------------------
# Four depths. Each one is darker, greener and more detailed than the one
# behind it - that progression is the whole illusion of a deep jungle.
const CANOPY_FAR := Color8(31, 87, 112)
const CANOPY_MID := Color8(21, 65, 76)
const CANOPY_NEAR := Color8(16, 45, 48)
const CANOPY_FRAME := Color8(7, 24, 31)

const LEAF := Color8(70, 125, 57)
const LEAF_DARK := Color8(30, 72, 49)
const LEAF_LIGHT := Color8(133, 174, 63)
## Where sun catches the very top of a leaf cluster.
const LEAF_SUN := Color8(190, 210, 95)

const BARK := Color8(78, 57, 50)
const BARK_LIGHT := Color8(136, 99, 64)
const BARK_DARK := Color8(42, 34, 40)

# --- Terrain -------------------------------------------------------
# The platform palette, top to bottom. Read the list downward and you have
# the anatomy the art bible specifies: lit cap, grass, dark seam, soil,
# darker soil, outline.

## The one dark line that goes round every solid thing in the game. A single
## shared outline colour is most of what makes a tileset look like a set.
const OUTLINE := Color8(12, 20, 29)

const GRASS_SUN := Color8(194, 214, 91)
const GRASS := Color8(116, 158, 54)
const GRASS_DARK := Color8(49, 99, 52)
## The fringe hanging under a platform's lip.
const MOSS := Color8(70, 123, 57)

const DIRT := Color8(84, 60, 66)
const DIRT_LIGHT := Color8(137, 99, 72)
const DIRT_DARK := Color8(44, 35, 49)
const ROCK_MID := Color8(103, 76, 78)
const ROCK_COOL := Color8(61, 53, 72)


## Multiplied over the Kenney tiles. Barely tinted: this is shade, not night,
## so the tiles keep their own colour and only lose a little of the sun.
const SHADE_TINT := Color(0.82, 0.90, 0.84)
## Deeper underground, away from the light coming through the canopy.
const DEPTH_TINT := Color(0.42, 0.44, 0.46)
## The lit top edge of a ledge, where light through the leaves lands.
const SUN_RIM := Color8(198, 236, 152)

# --- Water ---------------------------------------------------------
const WATER := Color8(37, 105, 130)
const WATER_DEEP := Color8(12, 37, 59)
const WATER_GLINT := Color8(143, 205, 210)

# --- Light ---------------------------------------------------------
# The warm end of the palette. A flame is drawn as three stacked circles -
# core, body, glow - and these are those three, in order.
const FLAME_CORE := Color8(255, 243, 186)
const FLAME := Color8(255, 168, 56)
const FLAME_GLOW := Color8(255, 116, 24)
const EMBER := Color8(255, 190, 96)

const BANANA := Color8(255, 210, 51)
const BANANA_LIGHT := Color8(255, 237, 154)
const BANANA_DARK := Color8(196, 134, 20)
## Pollen and insects drifting in the light shafts.
const MOTE := Color8(226, 248, 168)

## World pixels per art pixel. The one number the whole look depends on:
## every position, radius and size in the game is a whole multiple of it.
const ART_PIXEL: int = 2

## The corners of the frame. The key art vignettes every panel, but gently -
## it is shade closing in, not a spotlight.
const VIGNETTE := Color8(8, 26, 22)


## Atmospheric perspective: pushes `color` toward the haze as `distance` goes
## 0 (underfoot) to 1 (on the skyline). One function, so every far layer
## fades by the same rule and they read as one depth.
static func at_distance(color: Color, distance: float) -> Color:
	return color.lerp(HAZE, clampf(distance, 0.0, 1.0) * 0.72)


## A warm pool of torchlight, for drawing over the jungle floor.
## `strength` 0..1 fades it out at the edge of its reach.
static func torchlight(strength: float) -> Color:
	var warm := FLAME_GLOW
	return Color(warm.r, warm.g, warm.b, clampf(strength, 0.0, 1.0) * 0.5)


# --- Glow ----------------------------------------------------------
# Every light in the game - torch, flame, banana, finish line - is this one
# texture, tinted and scaled.
#
# It is deliberately tiny and deliberately banded. A smooth 128 px gradient
# stretched over a torch looks like a lens flare pasted onto pixel art, and
# a grid audit of a frame full of them shows it: a quarter of every colour
# edge on screen lands between pixels instead of on one. Real pixel art
# lights in steps - a few rings of flat colour - so the ramp here has five
# stops, the texture is 16 px, and it is drawn NEAREST at a whole multiple
# of the art pixel. The rings are the point, not an artefact.

## Art pixels across the glow texture. Small: each texel becomes a visible
## step of light at the size a torch is actually drawn.
const GLOW_TEXELS: int = 16

static var _glow: Texture2D = null


static func glow_texture() -> Texture2D:
	if _glow != null:
		return _glow
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(1, 1, 1, 1.0))
	gradient.add_point(0.30, Color(1, 1, 1, 0.66))
	gradient.add_point(0.52, Color(1, 1, 1, 0.38))
	gradient.add_point(0.74, Color(1, 1, 1, 0.16))
	gradient.set_offset(gradient.get_point_count() - 1, 1.0)
	gradient.set_color(gradient.get_point_count() - 1, Color(1, 1, 1, 0.0))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = GLOW_TEXELS
	texture.height = GLOW_TEXELS
	_glow = texture
	return _glow


## Draws a stepped light of `radius` centred on `at`, in `tint`'s colour and
## alpha. Both the centre and the radius are snapped to the art grid, so the
## rings land on whole pixels rather than smearing across them.
static func draw_glow(on: CanvasItem, at: Vector2, radius: float, tint: Color) -> void:
	var grid := float(ART_PIXEL)
	# A whole number of texels per art pixel keeps the steps even.
	var texel := maxf(roundf(radius * 2.0 / float(GLOW_TEXELS) / grid), 1.0) * grid
	var size := texel * float(GLOW_TEXELS)
	var centre := (at / grid).round() * grid
	on.draw_texture_rect(glow_texture(), Rect2(centre - Vector2(size, size) * 0.5, Vector2(size, size)), false, tint)
