class_name JungleTileArt
extends RefCounted

# ============================================================
# JUNGLE TILE ART - the terrain tiles, drawn by hand.
#
# One character per pixel, exactly like MonkeySprite's HEAD. This is not
# generated: every rock, root, grass tooth and bark knot below sits where it
# was put. That is the whole difference between this and the procedural
# version it replaced, which scattered shapes from a seed and produced
# texture that read as static rather than as ground.
#
# 18x18 to match the tile grid, drawn at 2x like everything else.
#
#   .  transparent      o  outline
#   G  grass sun        g  grass        d  grass dark     m  moss
#   E  dirt light       e  dirt         r  dirt dark
#   b  bark light       k  bark         n  bark dark
#
# Keep every row 18 characters. `JungleTiles.atlas()` asserts it.
# ============================================================

const SIZE: int = 18

## Character to colour. Every colour comes from JunglePalette; nothing here
## invents one. `.` is a hole, not a colour.
static func ink(ch: String) -> Color:
	match ch:
		"o": return JunglePalette.OUTLINE
		"G": return JunglePalette.GRASS_SUN
		"g": return JunglePalette.GRASS
		"d": return JunglePalette.GRASS_DARK
		"m": return JunglePalette.MOSS
		"E": return JunglePalette.DIRT_LIGHT
		"e": return JunglePalette.DIRT
		"r": return JunglePalette.DIRT_DARK
		"b": return JunglePalette.BARK_LIGHT
		"k": return JunglePalette.BARK
		"n": return JunglePalette.BARK_DARK
	return Color(0, 0, 0, 0)


const GRASS_L: Array[String] = [
	"oooooooooooooooooo",
	"oGGGGGGGGGGGGGGGGG",
	"oGgGGGGgGGGGGgGGgG",
	"oggggdgggdgggggdgg",
	"oggggggggggggggggg",
	"oddddddddddddddddd",
	"oeeddeeedeeddeeede",
	"oeedEeeeeeedeeeeee",
	"oeeeeeeeeeeEeeeeee",
	"oeeeeeeeEeerreeeee",
	"oeEEeeeeeeeeeeeeee",
	"oeerreeeeeeeeeeeee",
	"oeeeeeeeeeeeeeerre",
	"oeeeeeeeeeeeeerrEe",
	"oeeeeeEEEeeeerreee",
	"oeeeeeerrreeeeeeee",
	"oeeeeeeeeeeeeeeEee",
	"oeeeeeeeeeeeeeeeee",
]

const GRASS_M: Array[String] = [
	"oooooooooooooooooo",
	"GGGGGGGGGGGGGGGGGG",
	"GGgGGGGgGGGGGgGGgG",
	"gggggdgggdgggggdgg",
	"gggggggggggggggggg",
	"dddddddddddddddddd",
	"deeddeeedeeddeeede",
	"eeedEeeeeeedeeeeee",
	"eeeeeeeeeeeEeeeeee",
	"eeeeeeeeEeerreeeee",
	"eeEEeeeeeeeeeeeeee",
	"eeerreeeeeeeeeeeee",
	"eeeeeeeeeeeeeeerre",
	"eeeeeeeeeeeeeerrEe",
	"eeeeeeEEEeeeerreee",
	"eeeeeeerrreeeeeeee",
	"eeeeeeeeeeeeeeeEee",
	"eeeeeeeeeeeeeeeeee",
]

const GRASS_R: Array[String] = [
	"oooooooooooooooooo",
	"GGGGGGGGGGGGGGGGGo",
	"GGgGGGGgGGGGGgGGgo",
	"gggggdgggdgggggdgo",
	"gggggggggggggggggo",
	"dddddddddddddddddo",
	"deeddeeedeeddeeedo",
	"eeedEeeeeeedeeeero",
	"eeeeeeeeeeeEeeeero",
	"eeeeeeeeEeerreeero",
	"eeEEeeeeeeeeeeeero",
	"eeerreeeeeeeeeeero",
	"eeeeeeeeeeeeeeerro",
	"eeeeeeeeeeeeeerrro",
	"eeeeeeEEEeeeerrero",
	"eeeeeeerrreeeeeero",
	"eeeeeeeeeeeeeeeEro",
	"eeeeeeeeeeeeeeeero",
]

const GRASS_SOLO: Array[String] = [
	"oooooooooooooooooo",
	"oGGGGGGGGGGGGGGGGo",
	"oGgGGGGgGGGGGgGGgo",
	"oggggdgggdgggggdgo",
	"oggggggggggggggggo",
	"oddddddddddddddddo",
	"oeeddeeedeeddeeedo",
	"oeedEeeeeeedeeeero",
	"oeeeeeeeeeeEeeeero",
	"oeeeeeeeEeerreeero",
	"oeEEeeeeeeeeeeeero",
	"oeerreeeeeeeeeeero",
	"oeeeeeeeeeeeeeerro",
	"oeeeeeeeeeeeeerrro",
	"oeeeeeEEEeeeerrero",
	"oeeeeeerrreeeeeero",
	"oeeeeeeeeeeeeeeEro",
	"oeeeeeeeeeeeeeeero",
]

const DIRT_L: Array[String] = [
	"oeeeeeeerreeeeeeee",
	"oeeeeeeeerreeeeeee",
	"oeEEeeeeeerreeeeEe",
	"oeerreeeeeeeeeeeee",
	"oeeeeeeeeeeeEeeeee",
	"oeeeeeeeeeeerreeee",
	"oeeeeeeeeEeeeeeeee",
	"oeeeeeeeeeeeeeeeee",
	"oeeeeeeeeeeeeeeeee",
	"oeeeeeEEEeeeeeeeee",
	"oeeeeeerrreeeeeeee",
	"oeeeeeeeeeeEeeeeee",
	"oeeeeeeeeeeeeeeeee",
	"oeeeeeeeeeeeeeEEee",
	"oeeeeeeeeeeeeeerre",
	"oeeeeeeeeeeeeeeeee",
	"oeeeeEeeeeeeeeeeee",
	"oeeeeeeeeeeeeeeeee",
]

const DIRT_M: Array[String] = [
	"eeeeeeeerreeeeeeee",
	"eeeeeeeeerreeeeeee",
	"eeEEeeeeeerreeeeEe",
	"eeerreeeeeeeeeeeee",
	"eeeeeeeeeeeeEeeeee",
	"eeeeeeeeeeeerreeee",
	"eeeeeeeeeEeeeeeeee",
	"eeeeeeeeeeeeeeeeee",
	"Eeeeeeeeeeeeeeeeee",
	"eeeeeeEEEeeeeeeeee",
	"eeeeeeerrreeeeeeee",
	"eeeeeeeeeeeEeeeeee",
	"eeeeeeeeeeeeeeeeee",
	"eeeeeeeeeeeeeeEEee",
	"eeeeeeeeeeeeeeerre",
	"eeeeeeeeeeeeeeeeee",
	"eeeeeEeeeeeeeeeeee",
	"eeeeeeeeeeeeeeeeee",
]

const DIRT_R: Array[String] = [
	"eeeeeeeerreeeeeero",
	"eeeeeeeeerreeeeero",
	"eeEEeeeeeerreeeero",
	"eeerreeeeeeeeeeero",
	"eeeeeeeeeeeeEeeero",
	"eeeeeeeeeeeerreero",
	"eeeeeeeeeEeeeeeero",
	"eeeeeeeeeeeeeeeero",
	"Eeeeeeeeeeeeeeeero",
	"eeeeeeEEEeeeeeeero",
	"eeeeeeerrreeeeeero",
	"eeeeeeeeeeeEeeeero",
	"eeeeeeeeeeeeeeeero",
	"eeeeeeeeeeeeeeEEro",
	"eeeeeeeeeeeeeeerro",
	"eeeeeeeeeeeeeeeero",
	"eeeeeEeeeeeeeeeero",
	"eeeeeeeeeeeeeeeero",
]

const DIRT_V1: Array[String] = [
	"eeeeeeeeeeeeeeeeee",
	"eeeeeeeeeEeeeeeeee",
	"eeeeeeeeerreeeeeee",
	"eEeeeeeeeeeeeeeeee",
	"eeeeeeeeeeeeeeeeee",
	"eeeEEEeeeeeeeeEeee",
	"eeeerrreeeeeeeeeee",
	"eeeeeeeeeeeEeeeeee",
	"eeeeeeeeeeeeeeeeee",
	"eeEeeeeeeeeeeEEeee",
	"eeeeeeeeeeeeeerrEe",
	"eeeeeeeeeeeeeeeeee",
	"eeeeeeeeeeeeeeeeee",
	"eeeeeEeeeeeeeeeeee",
	"eeeeerreeeeeeeeeee",
	"eeeeeeeeEeeeeeeeee",
	"eeeeeeeeeeeeeeeeee",
	"eeeeeeeeeeeeeeeeee",
]

const DIRT_V2: Array[String] = [
	"eeeeeeeeeeeeeeeeee",
	"eeeeEeeeeeeeeeeeee",
	"eeeeeeeeeeeeEeeeee",
	"eeeeeeEeeeeeeeeeee",
	"eeeeeerreeeeeeeeee",
	"eeeeeeeeeeeeeeeeee",
	"eeeeeeeeeeeeeeeeee",
	"eeeeeeeeeeeeeeEEEe",
	"eeeeeeeeEeeeeeerrr",
	"eeeeeeeeeeeeeeeeee",
	"eeeeeeeeeeeeeeeeee",
	"eEEeeeeeeeeeeeeeee",
	"eerreeeeeeerreeeee",
	"eeeeeeeeeerreeeeee",
	"eeeeeeeeerreeeeeEe",
	"eeEeeeeeeeeeeeeeee",
	"eeeeeeeeeeEeeeeeee",
	"eeeeeeeeeeeeeeeeee",
]

const DIRT_V3: Array[String] = [
	"eeeeeeeeeeeeeeeeee",
	"eeeeeeeeeeeeeeeeee",
	"eeeeeeeeeeeEEEeeee",
	"eeeeeeeeeeeerrreee",
	"eeeeeeeEeeeeeeeeee",
	"Eeeeeeeeeeeeeeeeee",
	"eeeeeeeeeeeeeEeeee",
	"eeeeeeeeeeeeeeeeee",
	"eeeeEEeeeeeeeeeeee",
	"eeeeerreeeeeeeeeeE",
	"eeeeeeeeeEeeeeeeee",
	"eeeeeeeeeeeeeeeeee",
	"eeeEeeeeeeeeeeeEee",
	"eeeeeeeeeeeeeeerre",
	"eeeeeeeeeeeeeeeeee",
	"eeeeeeeEeeeeeeeeee",
	"eeeeeeerreeeeeeeee",
	"eeeeeeeeeeeeeeeeee",
]

const LEDGE_L: Array[String] = [
	"oooooooooooooooooo",
	"oGGGGGGGGGGGGGGGGG",
	"oGGgGGGGgGGGGGgGGG",
	"odggggdggggdggggdg",
	"oddddddddddddddddd",
	"oeeeEeeeeeeeEeeeee",
	"oeeerreeeeeeeeeeee",
	"orrrrrrrrrrrrrrrrr",
	"oooooooooooooooooo",
	"omm...mm..m..mm.m.",
	"omm...m...m..mm...",
	"om....m......m....",
	"o.....m...........",
	"o.................",
	"o.................",
	"o.................",
	"o.................",
	"o.................",
]

const LEDGE_M: Array[String] = [
	"oooooooooooooooooo",
	"GGGGGGGGGGGGGGGGGG",
	"GGGgGGGGgGGGGGgGGG",
	"gdggggdggggdggggdg",
	"dddddddddddddddddd",
	"eeeeEeeeeeeeEeeeee",
	"eeeerreeeeeeeeeeee",
	"rrrrrrrrrrrrrrrrrr",
	"oooooooooooooooooo",
	".mm...mm..m..mm.m.",
	".mm...m...m..mm...",
	".m....m......m....",
	"......m...........",
	"..................",
	"..................",
	"..................",
	"..................",
	"..................",
]

const LEDGE_R: Array[String] = [
	"oooooooooooooooooo",
	"GGGGGGGGGGGGGGGGGo",
	"GGGgGGGGgGGGGGgGGo",
	"gdggggdggggdggggdo",
	"dddddddddddddddddo",
	"eeeeEeeeeeeeEeeero",
	"eeeerreeeeeeeeeero",
	"rrrrrrrrrrrrrrrrro",
	"oooooooooooooooooo",
	".mm...mm..m..mm.mo",
	".mm...m...m..mm..o",
	".m....m......m...o",
	"......m..........o",
	".................o",
	".................o",
	".................o",
	".................o",
	".................o",
]

const LEDGE_SOLO: Array[String] = [
	"oooooooooooooooooo",
	"oGGGGGGGGGGGGGGGGo",
	"oGGgGGGGgGGGGGgGGo",
	"odggggdggggdggggdo",
	"oddddddddddddddddo",
	"oeeeEeeeeeeeEeeero",
	"oeeerreeeeeeeeeero",
	"orrrrrrrrrrrrrrrro",
	"oooooooooooooooooo",
	"omm...mm..m..mm.mo",
	"omm...m...m..mm..o",
	"om....m......m...o",
	"o.....m..........o",
	"o................o",
	"o................o",
	"o................o",
	"o................o",
	"o................o",
]

const TRUNK_L: Array[String] = [
	"obkkknkkknkbkkkknn",
	"obkkknkkknkbkknknn",
	"obkkkkkkknkkkknknn",
	"obkkbnnnnnkkkknknn",
	"obkkknnknnkbkknknn",
	"obkkknnnnkkkkknknn",
	"obkkbnkkknkkkknknn",
	"obkkbnkkknkkkkkknn",
	"obkkknkkknkbkknknn",
	"obkkkkkkknkkkknknn",
	"obkkbnkkknkkkknknn",
	"obkkknkkknkbkknknn",
	"obkkknkkkkkbnnnknn",
	"obkkknkkknkknnnknn",
	"obkkbnkkknkkkkkknn",
	"obkkknkkknkbkknknn",
	"obkkkkkkknkkkknknn",
	"obkkbnkkknkkkknknn",
]

const TRUNK_M: Array[String] = [
	"bbkkknkkknkbkkkknn",
	"bbkkknkkknkbkknknn",
	"bbkkkkkkknkkkknknn",
	"bbkkbnnnnnkkkknknn",
	"bbkkknnknnkbkknknn",
	"bbkkknnnnkkkkknknn",
	"bbkkbnkkknkkkknknn",
	"bbkkbnkkknkkkkkknn",
	"bbkkknkkknkbkknknn",
	"bbkkkkkkknkkkknknn",
	"bbkkbnkkknkkkknknn",
	"bbkkknkkknkbkknknn",
	"bbkkknkkkkkbnnnknn",
	"bbkkknkkknkknnnknn",
	"bbkkbnkkknkkkkkknn",
	"bbkkknkkknkbkknknn",
	"bbkkkkkkknkkkknknn",
	"bbkkbnkkknkkkknknn",
]

const TRUNK_R: Array[String] = [
	"bbkkknkkknkbkkkkno",
	"bbkkknkkknkbkknkno",
	"bbkkkkkkknkkkknkno",
	"bbkkbnnnnnkkkknkno",
	"bbkkknnknnkbkknkno",
	"bbkkknnnnkkkkknkno",
	"bbkkbnkkknkkkknkno",
	"bbkkbnkkknkkkkkkno",
	"bbkkknkkknkbkknkno",
	"bbkkkkkkknkkkknkno",
	"bbkkbnkkknkkkknkno",
	"bbkkknkkknkbkknkno",
	"bbkkknkkkkkbnnnkno",
	"bbkkknkkknkknnnkno",
	"bbkkbnkkknkkkkkkno",
	"bbkkknkkknkbkknkno",
	"bbkkkkkkknkkkknkno",
	"bbkkbnkkknkkkknkno",
]

## Tile index in the atlas -> its pixels.
const BY_INDEX: Dictionary = {
	0: GRASS_L,
	1: GRASS_M,
	2: GRASS_R,
	3: GRASS_SOLO,
	8: DIRT_L,
	9: DIRT_M,
	10: DIRT_R,
	11: DIRT_V1,
	12: DIRT_V2,
	13: DIRT_V3,
	16: LEDGE_L,
	17: LEDGE_M,
	18: LEDGE_R,
	19: LEDGE_SOLO,
	20: TRUNK_L,
	21: TRUNK_M,
	22: TRUNK_R,
}


## The soil tiles, in the order a ground cycles through them.
const DIRT_VARIANTS: Array[int] = [9, 11, 12, 13]
