
extends RefCounted

# ============================================================
# MOCK SKIN - the low-detail level look from the Primate Rush mock.
#
# Flat colour blocks on one chunky pixel grid (P world px per art px): grass
# topped dirt ground, mossy stone-brick ledges, rope-less wood planks, round
# leaf-clump trees, bushes. One highlight and one shadow per material and a
# hard ink outline, matching the chibi monkeys. Everything is drawn from the
# map's real collision rects, so what you see is exactly what you stand on.
# ============================================================

const P: float = 4.0

const INK := Color8(26, 15, 10)
const GRASS_TOP := Color8(143, 209, 79)
const GRASS := Color8(90, 163, 63)
const GRASS_DARK := Color8(47, 107, 36)
const DIRT := Color8(58, 38, 22)
const DIRT_DEEP := Color8(44, 29, 17)
const PEBBLE := Color8(92, 63, 40)
const STONE := Color8(90, 96, 122)
const STONE_ALT := Color8(78, 84, 112)
const STONE_LIT := Color8(102, 108, 136)
const MORTAR := Color8(38, 42, 60)
const WOOD := Color8(138, 90, 46)
const WOOD_LIT := Color8(168, 116, 62)
const WOOD_LINE := Color8(116, 74, 36)
const WOOD_EDGE := Color8(92, 58, 28)
const BARK := Color8(107, 68, 36)
const BARK_DARK := Color8(76, 48, 26)
const BARK_LIT := Color8(138, 90, 46)
const LEAF_INK := Color8(15, 42, 31)
const LEAF_DARK := Color8(31, 74, 44)
const LEAF := Color8(47, 107, 36)
const LEAF_LIT := Color8(79, 154, 58)
const GOLD := Color8(255, 216, 74)
const GOLD_DARK := Color8(212, 138, 18)


static func _hash(a: int, b: int) -> int:
	return posmod((a * 73856093) ^ (b * 19349663), 1000003)


static func _block(canvas: Variant, x: float, y: float, w: float, h: float, color: Color) -> void:
	canvas.draw_rect(Rect2(x, y, w, h), color)


## Grass-topped dirt with pebbles, like the mock's ground strip.
static func ground(canvas: Variant, rect: Rect2) -> void:
	var x0 := rect.position.x
	var y0 := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	_block(canvas, x0 - P, y0 - P, w + P * 2.0, h + P * 2.0, INK)
	_block(canvas, x0, y0, w, h, DIRT)
	if h > P * 14.0:
		_block(canvas, x0, y0 + P * 12.0, w, h - P * 12.0, DIRT_DEEP)
	# pebbles on the art grid
	var cols := int(w / P)
	var rows := int(h / P)
	for cx in range(1, cols - 2, 3):
		for cy in range(6, rows - 1, 4):
			if _hash(cx + int(x0), cy) % 7 == 0:
				_block(canvas, x0 + cx * P, y0 + cy * P, P * 2.0, P, PEBBLE)
	# grass cap: light top, body, dark underline
	_block(canvas, x0, y0, w, P, GRASS_TOP)
	_block(canvas, x0, y0 + P, w, P * 2.0, GRASS)
	_block(canvas, x0, y0 + P * 3.0, w, P, GRASS_DARK)
	# tufts standing up off the cap, and a few drips of grass over the edge
	for cx in range(1, cols - 1):
		var k := _hash(cx + int(x0), int(y0))
		if k % 6 == 0:
			_block(canvas, x0 + cx * P, y0 - P, P, P, GRASS_TOP)
		elif k % 11 == 0:
			_block(canvas, x0 + cx * P, y0 + P * 4.0, P, P * float(1 + k % 2), GRASS_DARK)


## Mossy stone-brick ledge, or a wood plank on every other ledge.
static func ledge(canvas: Variant, rect: Rect2, index: int) -> void:
	if index % 3 == 2:
		plank(canvas, rect)
		return
	var x0 := rect.position.x
	var y0 := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	_block(canvas, x0 - P, y0 - P, w + P * 2.0, h + P * 2.0, INK)
	_block(canvas, x0, y0, w, h, STONE)
	# brick courses, 3 art px tall, staggered joints
	var course := 0
	var y := y0 + P * 2.0
	while y < y0 + h:
		var ch := minf(P * 3.0, y0 + h - y)
		_block(canvas, x0, y, w, P, MORTAR)
		var x := x0 + (P * 3.0 if course % 2 == 1 else 0.0)
		var brick := 0
		while x < x0 + w:
			var bw := minf(P * 6.0, x0 + w - x)
			var tone := STONE_ALT if _hash(brick + int(x0), course + int(y0)) % 3 == 0 else STONE
			_block(canvas, x, y + P, maxf(bw - P, 0.0), ch - P, tone)
			_block(canvas, x, y + P, maxf(bw - P, 0.0), minf(P, ch - P), STONE_LIT)
			if x > x0:
				_block(canvas, x - P, y + P, P, ch - P, MORTAR)
			x += P * 6.0
			brick += 1
		y += P * 3.0
		course += 1
	# moss cap with drips
	_block(canvas, x0, y0, w, P, GRASS_TOP)
	_block(canvas, x0, y0 + P, w, P, GRASS)
	var cols := int(w / P)
	for cx in range(0, cols):
		var k := _hash(cx + int(x0) * 3, int(y0))
		if k % 5 == 0:
			_block(canvas, x0 + cx * P, y0 + P * 2.0, P, P * float(1 + k % 3), GRASS)


## Where plank ropes end at the top: the canopy's underside (set by
## LevelSkin), so a plank hangs from the trees rather than from nothing.
static var rope_top_y: float = INF


static func plank(canvas: Variant, rect: Rect2) -> void:
	var x0 := rect.position.x
	var y0 := rect.position.y
	var w := rect.size.x
	var h := minf(rect.size.y, P * 6.0)
	# rope-hung, as in the mock: two ropes rising from the plank ends
	var top := y0 - 180.0
	if rope_top_y < y0 - 20.0:
		top = rope_top_y
	for rx in [x0 + P * 3.0, x0 + w - P * 4.0]:
		var ry := y0 - P
		while ry > top:
			_block(canvas, rx, ry - P * 2.0, P, P * 2.0, Color8(201, 184, 154) if int((y0 - ry) / (P * 2.0)) % 2 == 0 else Color8(160, 142, 112))
			ry -= P * 2.0
	_block(canvas, x0 - P, y0 - P, w + P * 2.0, h + P * 2.0, INK)
	_block(canvas, x0, y0, w, h, WOOD)
	_block(canvas, x0, y0, w, P, WOOD_LIT)
	_block(canvas, x0, y0 + h - P, w, P, WOOD_EDGE)
	var x := x0 + P * 8.0
	while x < x0 + w - P:
		_block(canvas, x, y0 + P, P, h - P * 2.0, WOOD_LINE)
		_block(canvas, x - P * 2.0, y0 + P * 2.0, P, P, WOOD_EDGE)
		x += P * 8.0


## A climb wall: bark column with vertical grain.
static func column(canvas: Variant, rect: Rect2, bottom: float) -> void:
	var r := Rect2(rect.position, Vector2(rect.size.x, bottom - rect.position.y))
	trunk(canvas, r)


static func trunk(canvas: Variant, r: Rect2) -> void:
	_block(canvas, r.position.x - P, r.position.y, r.size.x + P * 2.0, r.size.y, INK)
	_block(canvas, r.position.x, r.position.y, r.size.x, r.size.y, BARK)
	_block(canvas, r.position.x, r.position.y, P, r.size.y, BARK_LIT)
	var x := r.position.x + P * 2.0
	while x < r.end.x - P:
		var y := r.position.y + float(_hash(int(x), int(r.position.y)) % 5) * P
		while y < r.end.y - P * 2.0:
			_block(canvas, x, y, P, P * 3.0, BARK_DARK)
			y += P * 7.0
		x += P * 3.0


## A round clump of leaves on the art grid: ink rim, dark body, lit top-left.
static func clump(canvas: Variant, center: Vector2, radius: int) -> void:
	for layer in 3:
		var r := radius + 1 - layer
		var color: Color = [LEAF_INK, LEAF_DARK, LEAF][layer]
		for dy in range(-r, r + 1):
			var half := int(floor(sqrt(float(r * r - dy * dy)) + 0.35))
			_block(canvas, center.x - half * P, center.y + dy * P, (half * 2 + 1) * P, P, color)
	# lit crescent, top-left
	var lr := maxi(radius - 2, 1)
	for dy in range(-lr, 0):
		var half := int(floor(sqrt(float(lr * lr - dy * dy))))
		_block(canvas, center.x - half * P - P, center.y + dy * P - P, maxf(half * P, P), P, LEAF_LIT)


## A grab tree: trunk, a leaf crown of clumps, and a branch with gold grip
## rings on the real anchor side.
static func tree(canvas: Variant, foot: Vector2, height: float, side: float, branch_length: float, branch_y: float) -> void:
	var width := P * 6.0
	trunk(canvas, Rect2(foot.x - width * 0.5, foot.y - height, width, height))
	# roots
	_block(canvas, foot.x - width * 0.5 - P * 2.0, foot.y - P * 2.0, P * 2.0, P * 2.0, BARK_DARK)
	_block(canvas, foot.x + width * 0.5, foot.y - P * 2.0, P * 2.0, P * 2.0, BARK_DARK)
	if side != 0.0:
		branch(canvas, foot, side, branch_length, branch_y)
	var top := foot - Vector2(0.0, height)
	var shape := int(foot.x)
	clump(canvas, top + Vector2(-P * 7.0, P * 2.0), 6 + shape % 2)
	clump(canvas, top + Vector2(P * 7.0, P * 1.0), 6)
	clump(canvas, top + Vector2(0.0, -P * 5.0), 8)


static func branch(canvas: Variant, foot: Vector2, side: float, length: float, y: float) -> void:
	var x0 := foot.x if side > 0.0 else foot.x - length
	var body := Rect2(x0, y - P * 1.5, length, P * 3.0)
	_block(canvas, body.position.x - P, body.position.y - P, body.size.x + P * 2.0, body.size.y + P * 2.0, INK)
	_block(canvas, body.position.x, body.position.y, body.size.x, body.size.y, BARK)
	_block(canvas, body.position.x, body.position.y, body.size.x, P, BARK_LIT)
	# gold grip rings: the "you can grab this" signal, only on real anchors
	for k in [0.45, 0.9]:
		var cx: float = foot.x + side * length * float(k)
		var ring := Rect2(cx - P, body.position.y - P, P * 2.0, body.size.y + P * 2.0)
		_block(canvas, ring.position.x - P, ring.position.y, ring.size.x + P * 2.0, ring.size.y, INK)
		_block(canvas, ring.position.x, ring.position.y, ring.size.x, ring.size.y, GOLD_DARK)
		_block(canvas, ring.position.x, ring.position.y, P, ring.size.y, GOLD)
	clump(canvas, Vector2(foot.x + side * length, y - P), 3)


static func bush(canvas: Variant, foot: Vector2, big: bool) -> void:
	var r := 4 if big else 3
	clump(canvas, foot + Vector2(-P * 3.0, -P * float(r - 1)), r)
	clump(canvas, foot + Vector2(P * 3.0, -P * float(r - 1)), r - 1)
