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
		"A": return JunglePalette.ROCK_MID
		"C": return JunglePalette.ROCK_COOL
		"b": return JunglePalette.BARK_LIGHT
		"k": return JunglePalette.BARK
		"n": return JunglePalette.BARK_DARK
	return Color(0, 0, 0, 0)


const GRASS_L: Array[String] = [
	"oGGggGGGGGggGGGGgg",
	"oggGGGgGGggGGGgGGG",
	"ogGggggggGggggggGg",
	"omgdgggmdggggmdggg",
	"ommggdmmddgdmmdggd",
	"ommddgmmrdgdmmrddm",
	"omdErmmrAArrmmErdm",
	"omdAremrAAArmdAerm",
	"ordAeerrAAArrdAerr",
	"oAeeorCCCCCCCrEAAA",
	"oeeerrCCCCCCCrAAAA",
	"oeerrrrCCCCrreeAAA",
	"orrrEEEerrrrrrreee",
	"orrEAAAAeerAAAArrr",
	"orEAAAAAAerAAAAAer",
	"orAAAAAAAerAAAeeer",
	"orAeeeeeerAAeeeerr",
	"orreeeeerrreeeerrr",
]

const GRASS_M: Array[String] = [
	"GGGggGGGGGggGGGGgg",
	"GggGGGgGGggGGGgGGG",
	"ggGggggggGggggggGg",
	"gmgdgggmdggggmdggg",
	"dmmggdmmddgdmmdggd",
	"dmmddgmmrdgdmmrddm",
	"rmdErmmrAArrmmErdm",
	"rmdAremrAAArmdAerm",
	"rrdAeerrAAArrdAerr",
	"AAeeorCCCCCCCrEAAA",
	"AeeerrCCCCCCCrAAAA",
	"eeerrrrCCCCrreeAAA",
	"rrrrEEEerrrrrrreee",
	"rrrEAAAAeerAAAArrr",
	"rrEAAAAAAerAAAAAer",
	"rrAAAAAAAerAAAeeer",
	"rrAeeeeeerAAeeeerr",
	"rrreeeeerrreeeerrr",
]

const GRASS_R: Array[String] = [
	"GGGggGGGGGggGGGGgo",
	"GggGGGgGGggGGGgGGo",
	"ggGggggggGggggggGo",
	"gmgdgggmdggggmdggo",
	"dmmggdmmddgdmmdggo",
	"dmmddgmmrdgdmmrddo",
	"rmdErmmrAArrmmErdo",
	"rmdAremrAAArmdAero",
	"rrdAeerrAAArrdAero",
	"AAeeorCCCCCCCrEAAo",
	"AeeerrCCCCCCCrAAAo",
	"eeerrrrCCCCrreeAAo",
	"rrrrEEEerrrrrrreeo",
	"rrrEAAAAeerAAAArro",
	"rrEAAAAAAerAAAAAeo",
	"rrAAAAAAAerAAAeeeo",
	"rrAeeeeeerAAeeeero",
	"rrreeeeerrreeeerro",
]

const GRASS_SOLO: Array[String] = [
	"oGGggGGGGGggGGGGgo",
	"oggGGGgGGggGGGgGGo",
	"ogGggggggGggggggGo",
	"omgdgggmdggggmdggo",
	"ommggdmmddgdmmdggo",
	"ommddgmmrdgdmmrddo",
	"omdErmmrAArrmmErdo",
	"omdAremrAAArmdAero",
	"ordAeerrAAArrdAero",
	"oAeeorCCCCCCCrEAAo",
	"oeeerrCCCCCCCrAAAo",
	"oeerrrrCCCCrreeAAo",
	"orrrEEEerrrrrrreeo",
	"orrEAAAAeerAAAArro",
	"orEAAAAAAerAAAAAeo",
	"orAAAAAAAerAAAeeeo",
	"orAeeeeeerAAeeeero",
	"orreeeeerrreeeerro",
]

const DIRT_L: Array[String] = [
	"orEEEEEEerrrAAAAAr",
	"oEEAAAAAeorAAAAAAe",
	"oEAAAAAAeorAAAAAAe",
	"oeAAAAAAeorAAAeeee",
	"oeAAeeeeerrAeeeeer",
	"oreeeeeerrrreeeerr",
	"orrrrrrrCCCCrrrrrr",
	"oAArrrrCCCCCCrrEEE",
	"oAAeorCCCCCCCrEEAA",
	"oAeeorCCCCCCCrEAAA",
	"oeeerrCCCCCCCrAAAA",
	"oeerrrrCCCCrreeAAA",
	"orrrEEEerrrrrrreee",
	"orrEAAAAeerAAAArrr",
	"orEAAAAAAerAAAAAer",
	"orAAAAAAAerAAAeeer",
	"orAeeeeeerAAeeeerr",
	"orreeeeerrreeeerrr",
]

const DIRT_M: Array[String] = [
	"rrEEEEEEerrrAAAAAr",
	"rEEAAAAAeorAAAAAAe",
	"rEAAAAAAeorAAAAAAe",
	"reAAAAAAeorAAAeeee",
	"reAAeeeeerrAeeeeer",
	"rreeeeeerrrreeeerr",
	"rrrrrrrrCCCCrrrrrr",
	"AAArrrrCCCCCCrrEEE",
	"AAAeorCCCCCCCrEEAA",
	"AAeeorCCCCCCCrEAAA",
	"AeeerrCCCCCCCrAAAA",
	"eeerrrrCCCCrreeAAA",
	"rrrrEEEerrrrrrreee",
	"rrrEAAAAeerAAAArrr",
	"rrEAAAAAAerAAAAAer",
	"rrAAAAAAAerAAAeeer",
	"rrAeeeeeerAAeeeerr",
	"rrreeeeerrreeeerrr",
]

const DIRT_R: Array[String] = [
	"rrEEEEEEerrrAAAAAo",
	"rEEAAAAAeorAAAAAAo",
	"rEAAAAAAeorAAAAAAo",
	"reAAAAAAeorAAAeeeo",
	"reAAeeeeerrAeeeeeo",
	"rreeeeeerrrreeeero",
	"rrrrrrrrCCCCrrrrro",
	"AAArrrrCCCCCCrrEEo",
	"AAAeorCCCCCCCrEEAo",
	"AAeeorCCCCCCCrEAAo",
	"AeeerrCCCCCCCrAAAo",
	"eeerrrrCCCCrreeAAo",
	"rrrrEEEerrrrrrreeo",
	"rrrEAAAAeerAAAArro",
	"rrEAAAAAAerAAAAAeo",
	"rrAAAAAAAerAAAeeeo",
	"rrAeeeeeerAAeeeero",
	"rrreeeeerrreeeerro",
]

const DIRT_V1: Array[String] = [
	"AAAAeorAAAeeeereAA",
	"eeeeerrAeeeeerreAA",
	"eeeerrrreeeerrrree",
	"rrrrCCCCrrrrrrrrrr",
	"rrrCCCCCCrrEEEAAAr",
	"orCCCCCCCrEEAAAAAe",
	"orCCCCCCCrEAAAAAee",
	"rrCCCCCCCrAAAAAeee",
	"rrrCCCCrreeAAAeeer",
	"EEEerrrrrrreeerrrr",
	"AAAAeerAAAArrrrrrE",
	"AAAAAerAAAAAerrrEA",
	"AAAAAerAAAeeerrrAA",
	"eeeeerAAeeeerrrrAe",
	"eeeerrreeeerrrrrre",
	"EEEEerrrAAAAArrrEE",
	"AAAAeorAAAAAAerEEA",
	"AAAAeorAAAAAAerEAA",
]

const DIRT_V2: Array[String] = [
	"CCCCrrrrrrrrrrrrrr",
	"CCCCCrrEEEAAArrrrC",
	"CCCCCrEEAAAAAeorCC",
	"CCCCCrEAAAAAeeorCC",
	"CCCCCrAAAAAeeerrCC",
	"CCCrreeAAAeeerrrrC",
	"rrrrrrreeerrrrEEEe",
	"eerAAAArrrrrrEAAAA",
	"AerAAAAAerrrEAAAAA",
	"AerAAAeeerrrAAAAAA",
	"erAAeeeerrrrAeeeee",
	"rrreeeerrrrrreeeee",
	"errrAAAAArrrEEEEEE",
	"eorAAAAAAerEEAAAAA",
	"eorAAAAAAerEAAAAAA",
	"eorAAAeeeereAAAAAA",
	"errAeeeeerreAAeeee",
	"rrrreeeerrrreeeeee",
]

const DIRT_V3: Array[String] = [
	"CrEAAAAAeeorCCCCCC",
	"CrAAAAAeeerrCCCCCC",
	"reeAAAeeerrrrCCCCr",
	"rrreeerrrrEEEerrrr",
	"AAArrrrrrEAAAAeerA",
	"AAAAerrrEAAAAAAerA",
	"AAeeerrrAAAAAAAerA",
	"eeeerrrrAeeeeeerAA",
	"eeerrrrrreeeeerrre",
	"AAAAArrrEEEEEEerrr",
	"AAAAAerEEAAAAAeorA",
	"AAAAAerEAAAAAAeorA",
	"AAeeeereAAAAAAeorA",
	"eeeeerreAAeeeeerrA",
	"eeeerrrreeeeeerrrr",
	"rrrrrrrrrrrrrrCCCC",
	"CrrEEEAAArrrrCCCCC",
	"CrEEAAAAAeorCCCCCC",
]

const LEDGE_L: Array[String] = [
	"oGGggGGGGGggGGGGgg",
	"oggGGGgGGggGGGgGGG",
	"ogGggggggGggggggGg",
	"omgdgggmdggggmdggg",
	"ommggdmmddgdmmdggd",
	"ommddgmmrdgdmmrddm",
	"omdErmmrAArrmmErdm",
	"oEAAAAAAeorAAAAAAe",
	"oeAAAAAAeorAAAeeee",
	"oeAAeeeeerrAeeeeer",
	"orrreeerrrreeerrrr",
	"ooorrroooorrrooooo",
	".dmmo...dmmo...dm.",
	".dmm....dmmo...dm.",
	"..dm....dmo....d..",
	"..dm.....m........",
	"...m.....d........",
	".........m........",
]

const LEDGE_M: Array[String] = [
	"GGGggGGGGGggGGGGgg",
	"GggGGGgGGggGGGgGGG",
	"ggGggggggGggggggGg",
	"gmgdgggmdggggmdggg",
	"dmmggdmmddgdmmdggd",
	"dmmddgmmrdgdmmrddm",
	"rmdErmmrAArrmmErdm",
	"rEAAAAAAeorAAAAAAe",
	"reAAAAAAeorAAAeeee",
	"reAAeeeeerrAeeeeer",
	"rrrreeerrrreeerrrr",
	"ooorrroooorrrooooo",
	".dmmo...dmmo...dm.",
	".dmm....dmmo...dm.",
	"..dm....dmo....d..",
	"..dm.....m........",
	"...m.....d........",
	".........m........",
]

const LEDGE_R: Array[String] = [
	"GGGggGGGGGggGGGGgo",
	"GggGGGgGGggGGGgGGo",
	"ggGggggggGggggggGo",
	"gmgdgggmdggggmdggo",
	"dmmggdmmddgdmmdggo",
	"dmmddgmmrdgdmmrddo",
	"rmdErmmrAArrmmErdo",
	"rEAAAAAAeorAAAAAAo",
	"reAAAAAAeorAAAeeeo",
	"reAAeeeeerrAeeeeeo",
	"rrrreeerrrreeerrro",
	"ooorrroooorrrooooo",
	".dmmo...dmmo...dm.",
	".dmm....dmmo...dm.",
	"..dm....dmo....d..",
	"..dm.....m........",
	"...m.....d........",
	".........m........",
]

const LEDGE_SOLO: Array[String] = [
	"oGGggGGGGGggGGGGgo",
	"oggGGGgGGggGGGgGGo",
	"ogGggggggGggggggGo",
	"omgdgggmdggggmdggo",
	"ommggdmmddgdmmdggo",
	"ommddgmmrdgdmmrddo",
	"omdErmmrAArrmmErdo",
	"oEAAAAAAeorAAAAAAo",
	"oeAAAAAAeorAAAeeeo",
	"oeAAeeeeerrAeeeeeo",
	"orrreeerrrreeerrro",
	"ooorrroooorrrooooo",
	".dmmo...dmmo...dm.",
	".dmm....dmmo...dm.",
	"..dm....dmo....d..",
	"..dm.....m........",
	"...m.....d........",
	".........m........",
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
