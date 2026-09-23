class_name MonkeyPortrait
extends RefCounted

## HUD portraits use the same species-specific heads as the full-body
## three-quarter animation sheets. No shared generic face template.

const SIZE: int = 40

## Fur, fur shade, face and nose per monkey. The outline, the eye white and
## the pupil are shared: five monkeys with five different blacks would read
## as five different lighting conditions rather than five species.
const OUTLINE := JunglePalette.OUTLINE
const EYE := Color8(248, 248, 244)
const PUPIL := Color8(20, 16, 14)

const PALETTES: Dictionary = {
	&"gorilla": {"f": Color8(57, 65, 77), "d": Color8(30, 37, 50), "m": Color8(185, 172, 138), "n": Color8(57, 42, 37)},
	&"gibbon": {"f": Color8(179, 144, 93), "d": Color8(107, 81, 56), "m": Color8(242, 211, 156), "n": Color8(68, 43, 35)},
	&"macaque": {"f": Color8(153, 99, 54), "d": Color8(87, 53, 39), "m": Color8(239, 195, 126), "n": Color8(74, 40, 32)},
	&"orangutan": {"f": Color8(194, 104, 47), "d": Color8(112, 57, 39), "m": Color8(239, 185, 116), "n": Color8(74, 40, 32)},
	&"capuchin": {"f": Color8(97, 66, 49), "d": Color8(51, 37, 36), "m": Color8(249, 219, 162), "n": Color8(74, 40, 32)},
}

## Built once per monkey and kept. The lobby asks for these on every refresh,
## and rebuilding 576 pixels five times a frame is free but pointless.
static var _cache: Dictionary = {}


static func texture(id: StringName) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var made := MonkeySprite.load_art("%s/%s/portrait.png" % [MonkeySprite.ART_DIR, MonkeySprite.asset_id(id)])
	_cache[id] = made
	return made


static func image(id: StringName) -> Image:
	return texture(id).get_image()


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
		"h":
			return (palette["f"] as Color).lerp(Color8(241, 187, 101), 0.30)
		"s":
			return (palette["m"] as Color).lerp(palette["f"], 0.38)
		"o":
			return OUTLINE
		"e":
			return EYE
		"p":
			return PUPIL
		".":
			return Color(0, 0, 0, 0)
	return palette.get(symbol, OUTLINE)
