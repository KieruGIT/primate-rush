extends Control

# ============================================================
# BANANA ICON - a pixel-art banana, the game's currency symbol.
#
# Drawn from a small pixel map so it matches the chunky art everywhere it
# appears: the wallet, the shop packs, rewards and stakes. `count` draws a
# bunch: 1 is one banana, 3 a fanned bunch, 6 a heap.
# ============================================================

const MAP: Array[String] = [
	"...........gg.",
	"..........obbo",
	".........oylyo",
	"........oylyyo",
	".......oylyydo",
	".....ooylyydo.",
	"...ooyllyyddo.",
	".ooyyyyyyddo..",
	"oyyyyyyyddoo..",
	"oddyyyyddoo...",
	".ooddddoo.....",
	"...oooo.......",
]
const COLORS: Dictionary = {
	"o": Color8(74, 44, 18),
	"y": Color8(255, 214, 58),
	"l": Color8(255, 244, 170),
	"d": Color8(226, 160, 30),
	"b": Color8(120, 78, 36),
	"g": Color8(96, 150, 60),
}

@export var count: int = 1


func _init() -> void:
	custom_minimum_size = Vector2(28, 24)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	draw_bunch(self, Rect2(Vector2.ZERO, size), count)


## Draws `count` bananas fitted inside `area` on any canvas.
static func draw_bunch(canvas: CanvasItem, area: Rect2, bananas: int = 1) -> void:
	var offsets: Array = [Vector2.ZERO]
	match bananas:
		2:
			offsets = [Vector2(-0.12, 0.08), Vector2(0.12, -0.04)]
		3:
			offsets = [Vector2(-0.18, 0.1), Vector2(0.0, -0.04), Vector2(0.18, 0.1)]
		_:
			if bananas >= 4:
				offsets = [Vector2(-0.24, 0.16), Vector2(0.0, 0.2), Vector2(0.24, 0.16),
					Vector2(-0.12, -0.06), Vector2(0.12, -0.06), Vector2(0.0, -0.24)]
	var spread := 1.0 + (0.5 if bananas > 1 else 0.0)
	var w := MAP[0].length()
	var h := MAP.size()
	var cell := floorf(minf(area.size.x / (w * spread), area.size.y / (h * spread)))
	cell = maxf(cell, 1.0)
	var art := Vector2(w, h) * cell
	for offset in offsets:
		var origin := (area.position + (area.size - art) * 0.5 + (offset as Vector2) * area.size).floor()
		draw_one(canvas, origin, cell)


static func draw_one(canvas: CanvasItem, origin: Vector2, cell: float) -> void:
	for y in MAP.size():
		var row: String = MAP[y]
		for x in row.length():
			var key := row[x]
			if COLORS.has(key):
				canvas.draw_rect(Rect2(origin + Vector2(x, y) * cell, Vector2(cell, cell)), COLORS[key])
