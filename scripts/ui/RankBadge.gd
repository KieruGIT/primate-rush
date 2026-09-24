extends Control

# ============================================================
# RANK BADGE - the pixel shield for a rank, drawn from code.
#
# One look per tier, so a rank reads at a glance before its name does:
#   BRONZE  copper shield, one leaf
#   SILVER  steel shield, crossed leaves
#   GOLD    gold shield, a banana
#   JUNGLE  green shield with a vine border and a monkey paw
#   APEX    purple shield with a gold rim and a crown
# The chevrons under the emblem are the division: one for III, three for I.
# Drawn on a 4 px grid so it matches the rest of the pixel art at any size.
# ============================================================

## Face, dark edge and light edge per tier.
const TIER_COLORS: Array = [
	[Color8(196, 120, 64), Color8(110, 58, 30), Color8(236, 170, 110)],
	[Color8(176, 186, 204), Color8(88, 96, 118), Color8(232, 238, 248)],
	[Color8(246, 196, 52), Color8(150, 98, 20), Color8(255, 236, 140)],
	[Color8(84, 178, 76), Color8(32, 92, 38), Color8(160, 228, 120)],
	[Color8(156, 86, 222), Color8(72, 30, 120), Color8(214, 170, 255)],
]
const OUTLINE := Color8(26, 15, 10)

var tier: int = 0
## 0 is division III, 2 is division I, -1 for a tier with no divisions.
var division: int = 0
var dim: bool = false


func _init() -> void:
	custom_minimum_size = Vector2(48, 56)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Shows the rank for `rp` rank points.
func set_rp(rp: int) -> void:
	var rank: Dictionary = GameConfig.rank_for(rp)
	set_rank(int(rank["tier"]), int(rank["division"]))


func set_rank(new_tier: int, new_division: int) -> void:
	tier = clampi(new_tier, 0, TIER_COLORS.size() - 1)
	division = new_division
	queue_redraw()


func _draw() -> void:
	# The shield is 12 x 14 cells; a cell is whatever fits the control.
	var cell := floorf(minf(size.x / 12.0, size.y / 14.0))
	cell = maxf(cell, 1.0)
	var origin := ((size - Vector2(12, 14) * cell) * 0.5).floor()
	var tones: Array = TIER_COLORS[tier]
	var face: Color = tones[0]
	var dark: Color = tones[1]
	var light: Color = tones[2]
	if dim:
		face = face.darkened(0.55)
		dark = dark.darkened(0.55)
		light = light.darkened(0.55)
	# Shield rows: [first column, width] for each of the 14 rows.
	var rows := [[1, 10], [0, 12], [0, 12], [0, 12], [0, 12], [0, 12], [0, 12], [0, 12],
		[1, 10], [1, 10], [2, 8], [3, 6], [4, 4], [5, 2]]
	for y in rows.size():
		var x0: int = rows[y][0]
		var w: int = rows[y][1]
		_cells(origin, cell, x0 - 1, y, w + 2, 1, OUTLINE)
	_cells(origin, cell, 1, -1, 10, 1, OUTLINE)
	for y in rows.size():
		var x0: int = rows[y][0]
		var w: int = rows[y][1]
		_cells(origin, cell, x0, y, w, 1, face)
		_cells(origin, cell, x0, y, 1, 1, light)
		_cells(origin, cell, x0 + w - 1, y, 1, 1, dark)
	_cells(origin, cell, 1, 0, 10, 1, light)
	if tier == 4:
		# Apex: a gold rim over the top edge.
		_cells(origin, cell, 1, 0, 10, 1, TIER_COLORS[2][0])
	if tier == 3:
		# Jungle: vine dots down both sides.
		for y in [2, 5, 8]:
			_cells(origin, cell, 1, y, 1, 1, Color8(40, 120, 40))
			_cells(origin, cell, 10, y, 1, 1, Color8(40, 120, 40))
	_emblem(origin, cell, dark, light)
	# Division chevrons.
	if division >= 0:
		for i in division + 1:
			var y := 7 + i * 2
			_cells(origin, cell, 3, y, 2, 1, OUTLINE)
			_cells(origin, cell, 5, y + 1, 2, 1, OUTLINE)
			_cells(origin, cell, 7, y, 2, 1, OUTLINE)


func _emblem(origin: Vector2, cell: float, dark: Color, light: Color) -> void:
	match tier:
		0:
			# One leaf.
			_cells(origin, cell, 5, 2, 2, 1, Color8(60, 130, 50))
			_cells(origin, cell, 4, 3, 4, 2, Color8(80, 160, 60))
			_cells(origin, cell, 5, 5, 2, 1, Color8(60, 130, 50))
		1:
			# Crossed leaves.
			for i in 4:
				_cells(origin, cell, 3 + i, 2 + i, 2, 1, Color8(80, 160, 60))
				_cells(origin, cell, 7 - i, 2 + i, 2, 1, Color8(60, 130, 50))
		2:
			# A banana.
			_cells(origin, cell, 7, 2, 1, 1, Color8(90, 60, 20))
			_cells(origin, cell, 6, 3, 2, 1, Color8(255, 226, 90))
			_cells(origin, cell, 4, 4, 3, 1, Color8(255, 226, 90))
			_cells(origin, cell, 4, 5, 2, 1, Color8(230, 180, 40))
		3:
			# A paw: pad and three toes.
			_cells(origin, cell, 4, 4, 4, 2, OUTLINE)
			for x in [3, 5, 8]:
				_cells(origin, cell, x, 2, 1, 1, OUTLINE)
		4:
			# A crown.
			var gold: Color = TIER_COLORS[2][0]
			_cells(origin, cell, 3, 4, 6, 2, gold)
			for x in [3, 5, 8]:
				_cells(origin, cell, x, 2, 1, 2, gold)
			_cells(origin, cell, 5, 4, 2, 1, Color8(230, 60, 80))
		_:
			_cells(origin, cell, 4, 3, 4, 3, dark)
			_cells(origin, cell, 4, 3, 4, 1, light)


func _cells(origin: Vector2, cell: float, x: int, y: int, w: int, h: int, color: Color) -> void:
	draw_rect(Rect2(origin + Vector2(x, y) * cell, Vector2(w, h) * cell), color)
