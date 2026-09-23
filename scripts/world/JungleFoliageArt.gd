class_name JungleFoliageArt
extends RefCounted

# ============================================================
# JUNGLE FOLIAGE ART - trees and undergrowth, drawn by hand.
#
# Same idea as JungleTileArt: one character per pixel, every one placed
# rather than rolled. The crowns are built from a leaf clump drawn once and
# stamped in three tiers, each tier a step further down the value ramp than
# the one above it, because a crown is a lit top over a shaded underside and
# not a field of identical bubbles.
#
# The clumps overlap by about a third so they fuse into one silhouette, and
# only the outer edge carries the keyline - outlining the gaps between them
# draws a line round each clump and turns a tree into a pile of shrubs.
#
#   H  leaf sun      L  leaf       D  leaf dark    K  canopy frame
#   o  outline       .  transparent
# ============================================================

static func ink(ch: String) -> Color:
	match ch:
		"H": return JunglePalette.LEAF_SUN
		"L": return JunglePalette.LEAF
		"D": return JunglePalette.LEAF_DARK
		"K": return JunglePalette.CANOPY_FRAME
		"o": return JunglePalette.OUTLINE
		"b": return JunglePalette.BARK_LIGHT
		"k": return JunglePalette.BARK
		"n": return JunglePalette.BARK_DARK
	return Color(0, 0, 0, 0)


const CROWN_BIG: Array[String] = [
	".................oooo....oHHHHoo........................",
	"................oHHHHoo.oHHHHHHLooooo...................",
	"...............oHHHHHHLoHHLLLLLLoHHHHoo.................",
	"..............oHHLLLLLLoLLLLLLLDHHHHHHLo................",
	"..............oLLLLLLLDoLLLLLDDHHLLLLLLoo...............",
	"..........oooooLLLLLDDDHLLDDDDDLLLLLLLDHHoo.............",
	".........oHHHHooLDDDDDLLLKDDKDKLLLLLDDDHHHLo............",
	"........oHHHHHHLKDDLDLLLDKKKHHHHLDDDDDLLLLLo............",
	".......oHHLLLLLLKLLLLLDDDKKHHHHHHDDLDLLLLLDo............",
	".......oLLLLLLLDKKLDDDDDKKHHLLLLLLoLLLLLDDDo............",
	".......oLLLLLDDDKKKDDKDKKKLLLLLLLDooLDDDDDo.............",
	"......oooLDDDDDKKKKKKKKKKKLLLLLDDDo.oDDoDooooooo........",
	".....oLLLLDDKDKKKKKKKKKKKKKLDDDDDo...oo.ooLLLLLLoo......",
	"....oLLLLLLLLDKKKKKKKKKKLLLLDDKDooooooo.oLLLLLLLLDo.....",
	"...oLLLLDDDDDDDLLLLLLKKLLLLLLLLDoLLLLLLoLLLLDDDDDDDo....",
	"..oLLDDDDDDDDDLLLLLLLLLLLLDDDDDDLLLLLLLLLDDDDDDDDDKo....",
	"..oDDDDDDDDDDLLLLDDDDLLDDDDDDDDLLLLDDDDDDDDDDDDDDKKo....",
	"..oDDDDDDDDKLLDDDDDDDDDDDDDDDDLLDDDDDDDDDDDDDDDKKKKo....",
	"...oDDDKKKKKDDDDDDDDDDDDDDDDDKDDDDDDDDDDDDDKKKKKKKDDoo..",
	"..oDDKKDKKKKDDDDDDDDKKDDDKKKKKDDDDDDDDKKKKKKKKKDKKDDDKo.",
	".oDDDDDDDDKKKDDDKKKKKKKKKDKKKKKDDDKKKKKKKDDDDDDDKKKKKKKo",
	"oDDDDKKKKKKDDDKKDKKKDKKDDDDKKDDDKKDKKKDKKDDDDKKKKKKKKKKo",
	"DDKKKKKKKKDDDDDDDDDDDDKKKKKKDDDDDDDDDDDDKKKKKKKKKKKKKKKo",
	"KKKKKKKKKDDDDKKKKDDKKKKKKKKDDDDKKKKDDKKKKKKKKKKKKKKKKKKo",
	"KKKKKKKKDDKKKKKKKKKKKKKKKKDDKKKKKKKKKKKKKKKKKKKDDKKKKKo.",
	"oKKKKDDKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKDDKKoKKo.",
	".oKKoDDKKKKKKKKKKKKKKKKKKKKDDKKKKKKKKKKKKKKKKKooDoo.oo..",
	"..oo.oDooKKKKKKKDDKKKoKKKoKDDKKKKKKKKKDDKKKoKKo.o.......",
	"......o..oKKoKKKDDKoo.ooo.ooDKoKKKoKKoDDooo.oo..........",
	"..........oo.ooooDo.........oo.ooo.oo.oDo...............",
	".................o.....................o................",
	"........................................................",
	"........................................................",
	"........................................................",
	"........................................................",
	"........................................................",
	"........................................................",
	"........................................................",
]

const CROWN_SMALL: Array[String] = [
	"..........oooo...........oooo.........",
	".........oHHHHoo..oooo..oHHHHoo.......",
	"........oHHHHHHLooHHHHooHHHHHHLo......",
	".......oHHLLLLLLoHHHHHHHHLLLLLLo......",
	".......oLLLLLLLDHHLLLLLLLLLLLLDo......",
	".......oLLLLLDDDLLLLLLLLLLLLDDDo......",
	".....ooooLDDDDDKLLLLLDDDLDDDDDo.......",
	"....oLLLLKDDKDKKKLDDDDDLLDDKDooo......",
	"...oLLLLLLDKKLLLLKDDLDLLLLDKLLLLoo....",
	"..oLLDDDDDDKLLLLLLDLLDDDDDDLLLLLLDo...",
	"..oDDDDDDDKLLDDDDDDDDDDDDDLLDDDDDDo...",
	"..oDDDDDKKKDDDDDDDKDDDDDKKDDDDDDDKo...",
	"..ooDKKKKKKDDDDDKKKKDKKKKKDDDDDKKKo...",
	".oDDDKKKKKKKDKKKKKKKKKKKKKKDKKKKKDoo..",
	"oDDDDDDKKKKKKKKKKDDDKKKKKKKKKKDKDDDKo.",
	"DDKKKKKKKDDDDKKDDDDDDKKDDDDKDDKKKKKKo.",
	"KKKKKKKKDDDDDDDDKKKKKKDDDDDDKKKKKKKKo.",
	"KKKKKKKDDKKKKKKKKKKKKDDKKKKKKKKKKKKKo.",
	"oKKKDDKKKKKKKKKKKKKKKKKKKKKKKKKKKKKo..",
	".oKKoDoKKKKKKKKKKKKKKKKKKDDKKoKKoKo...",
	"..oo.o.oKKKKKKDDKKoKooKKKKDKo.oo.o....",
	"........oKKoKooDoo.o..oKKoKo..........",
	".........oo.o..o.......oo.o...........",
	"......................................",
	"......................................",
	"......................................",
]

const SHRUB: Array[String] = [
	"..........................",
	"....ooo..........ooo......",
	"...oHHHo...ooo..oHHHo.....",
	"..oHHLLLo.oHHHooHHLLLo....",
	"..oLLLLDooHHLLLoLLLLDo....",
	"...oLDDo.oLLLLDooLDDo.....",
	"..ooooo...oLDDoooooo......",
	".oLLLLooooooooLLLLooooo...",
	"oLLLLLLDLLLLoLLLLLLLLLLoo.",
	"LLDDDDDLLLLLLLDDDDLLLLLLDo",
	"DDDDDDLLDDDDDDDDDLLDDDDDDo",
	"DDDDDKDDDDDDDDDDDDDDDDDDKo",
	"oDKKKKDDDDDKKDKKKDDDDDKKKo",
	".oKKoKoDKKKKKoKKoKDKKKKKo.",
]

const FERN: Array[String] = [
	"....................HH.......................",
	"...................HHL.......................",
	"..................HHLD.......................",
	"..................HLLD.......................",
	".......HHHH.......HLLD....HHHHHH.............",
	".....HHLLLLHH.....HLLD..HHLLLLLLHH...........",
	"....HLLLLLLLDH....HLLD.HLLLLLLLDDDH..........",
	"...HLLDDDDLLLDH...HLDDHLLLDDDDDDDDDH.........",
	"..HLD....DDLLLDH..HLDHLLDD......DDDD.........",
	"..HD.......DLLLDH.HLHLLDD.........DD.........",
	"..D.........DLLLDHHLLDD......................",
	".............DLLLHHLLD.......................",
	"..HHHHHHHH....DLLLHLLD.....HHHHHHH...........",
	".HLLLLLLLLHH...DLLHLD...HHHLLLLLLLHH.........",
	"HLLDDDDDDLLLHH..DLHLD.HHLLLLDDDDDDLLH........",
	"HDD......DDLLLHH.DHLDHLLLDDD......DDDH.......",
	"D..........DDLLLHHHLLLDDD............D.......",
	".............DDLLLHLLDD......................",
	"...............DLLHLD........................",
	"......HHHHHHHH...DHLD..HHHHHHHH..............",
	"....HHLLLLLLLLHH.DHLDHHLLLLLLLLHH............",
	"...HLLDDDDDDLLLLHHHLLLDDDDDDDDLLLH...........",
	"..HLD......DDDDLLLHLLDD......DDDDLH..........",
	"..DD...........DDDHDDD...........DD..........",
	"..................DLD........................",
	"..................DLD........................",
	".................DDKDD.......................",
	"................DDKKKDD......................",
]

## Prop name -> its pixels.
const BY_NAME: Dictionary = {
	&"crown_big": CROWN_BIG,
	&"crown_small": CROWN_SMALL,
	&"shrub": SHRUB,
	&"fern": FERN,
}

