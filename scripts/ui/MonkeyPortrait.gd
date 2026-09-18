class_name MonkeyPortrait
extends RefCounted

# ============================================================
# MONKEY PORTRAIT - a 24x24 pixel face per monkey, built at runtime.
#
# Drawn from an ASCII template rather than shipped as five PNGs, for the same
# reason Sfx synthesises its waveforms: the art is then a diff anyone can
# read, and a recolour is one line rather than a round trip through an image
# editor. Twenty-four rows of twelve characters is a small enough sprite that
# the source and the picture are the same thing.
#
# Only the left half is written out. Everything mirrors, which halves the
# template and makes a crooked face impossible rather than merely unlikely.
#
# Drawn with nearest filtering wherever it is used, so scaling it up to a
# selection card keeps the pixels square instead of smearing them.
# ============================================================

const SIZE: int = 24

## o outline   f fur   d fur shade   m face   n nose and mouth
## e eye white   p pupil   . transparent
const HALF: Array[String] = [
	"............",
	".......ooooo",
	".....oofffff",
	"....offfffff",
	".oooffffffff",
	"offoffffffff",
	"ofmoffffffff",
	"offofmmmmmmm",
	".ooofmmmmmmm",
	"...ofmeppmmm",
	"...ofmpppmmm",
	"...ofmmmmmmm",
	"...ofmmmmmmn",
	"...ofmmmmmmm",
	"...ofmmmmnnn",
	"...offmmmmmm",
	"....offfffff",
	".....offffff",
	"......oooooo",
	".......ooddd",
	".....oodffff",
	"...oodffffff",
	"..odffffffff",
	"..oooooooooo",
]

## Fur, fur shade, face and nose per monkey. The outline, the eye white and
## the pupil are shared: five monkeys with five different blacks would read
## as five different lighting conditions rather than five species.
const OUTLINE := Color8(22, 18, 16)
const EYE := Color8(248, 248, 244)
const PUPIL := Color8(20, 16, 14)

const PALETTES: Dictionary = {
	&"gorilla": {"f": Color8(74, 66, 66), "d": Color8(52, 46, 46), "m": Color8(58, 50, 50), "n": Color8(30, 26, 26)},
	&"gibbon": {"f": Color8(196, 166, 120), "d": Color8(160, 132, 92), "m": Color8(48, 40, 38), "n": Color8(28, 22, 20)},
	&"macaque": {"f": Color8(150, 106, 64), "d": Color8(116, 80, 48), "m": Color8(214, 158, 142), "n": Color8(150, 96, 86)},
	&"orangutan": {"f": Color8(186, 92, 36), "d": Color8(142, 66, 24), "m": Color8(150, 88, 54), "n": Color8(96, 52, 32)},
	&"capuchin": {"f": Color8(78, 56, 42), "d": Color8(56, 40, 30), "m": Color8(236, 214, 180), "n": Color8(150, 120, 92)},
}

## Built once per monkey and kept. The lobby asks for these on every refresh,
## and rebuilding 576 pixels five times a frame is free but pointless.
static var _cache: Dictionary = {}


static func texture(id: StringName) -> ImageTexture:
	if _cache.has(id):
		return _cache[id]
	var made := ImageTexture.create_from_image(image(id))
	_cache[id] = made
	return made


static func image(id: StringName) -> Image:
	var palette := palette_for(id)
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in HALF.size():
		var row: String = HALF[y]
		for x in row.length():
			var color := _color(row[x], palette)
			img.set_pixel(x, y, color)
			img.set_pixel(SIZE - 1 - x, y, color)
	return img


## An unknown monkey still gets a face, tinted from its body colour, rather
## than a magenta square or a crash. A new monkey is then playable the moment
## its .tres exists and only looks generic until someone picks its palette.
static func palette_for(id: StringName) -> Dictionary:
	if PALETTES.has(id):
		return PALETTES[id]
	var base: Color = GameConfig.get_monkey(id).body_color
	return {
		"f": base,
		"d": base.darkened(0.3),
		"m": base.lightened(0.45),
		"n": base.darkened(0.15),
	}


static func _color(symbol: String, palette: Dictionary) -> Color:
	match symbol:
		"o":
			return OUTLINE
		"e":
			return EYE
		"p":
			return PUPIL
		".":
			return Color(0, 0, 0, 0)
	return palette.get(symbol, OUTLINE)
