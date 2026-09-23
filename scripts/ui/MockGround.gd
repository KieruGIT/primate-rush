extends Control

# ============================================================
# MOCK GROUND - the strip of jungle floor along the bottom of the mock's
# title and results screens: rolling dark bushes, a grass cap, dirt with
# pebbles, and a few torches with a stepped warm glow. Pure drawing, no
# input, sized to whatever rect it is given.
# ============================================================

const P: float = 4.0
const INK := Color8(26, 15, 10)
const GRASS_TOP := Color8(143, 209, 79)
const GRASS := Color8(90, 163, 63)
const DIRT := Color8(58, 38, 22)
const PEBBLE := Color8(80, 55, 34)
const BUSH := Color8(16, 42, 30)
const BUSH_LIT := Color8(22, 56, 38)

## Height of the grass + dirt strip, in px.
var ground_height: float = 96.0
## Torches, as fractions of the width.
var torches: Array = [0.5]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var top := size.y - ground_height
	# bushes behind the ground line
	var x := -40.0
	var i := 0
	while x < size.x + 40.0:
		var r := 70.0 + float((i * 37) % 50)
		_blob(Vector2(x, top + 20.0), r, BUSH if i % 2 == 0 else BUSH_LIT)
		x += 150.0 + float((i * 53) % 70)
		i += 1
	# torches (behind the grass cap, in front of the bushes)
	var t := Time.get_ticks_msec() / 1000.0
	for k in torches.size():
		_torch(Vector2(snappedf(size.x * float(torches[k]), P), top), t + float(k) * 1.7)
	# ground
	draw_rect(Rect2(0, top - P, size.x, ground_height + P), INK)
	draw_rect(Rect2(0, top, size.x, ground_height), DIRT)
	draw_rect(Rect2(0, top, size.x, P * 2.0), GRASS_TOP)
	draw_rect(Rect2(0, top + P * 2.0, size.x, P * 2.0), GRASS)
	var cx := 12.0
	var n := 0
	while cx < size.x:
		var cy := top + 28.0 + float((n * 29) % int(maxf(ground_height - 40.0, 8.0)))
		draw_rect(Rect2(snappedf(cx, P), snappedf(cy, P), P * 3.0, P * 2.0), PEBBLE)
		cx += 70.0 + float((n * 41) % 90)
		n += 1


func _blob(center: Vector2, radius: float, color: Color) -> void:
	# A stepped half-disc on the 4px grid.
	var rows := int(radius / P)
	for j in rows:
		var dy := float(j) * P
		var half := sqrt(maxf(radius * radius - dy * dy, 0.0))
		draw_rect(Rect2(snappedf(center.x - half, P), center.y - dy - P, snappedf(half * 2.0, P), P), color)
	draw_rect(Rect2(center.x - radius, center.y - P, radius * 2.0, P * 6.0), color)


func _torch(foot: Vector2, t: float) -> void:
	var flick := 0.85 + 0.15 * sin(t * 9.0) * sin(t * 5.3)
	# stepped warm glow rings
	for ring in [[70.0, 0.06], [48.0, 0.08], [28.0, 0.1]]:
		draw_circle(foot + Vector2(2, -64), float(ring[0]) * flick, Color(1.0, 0.6, 0.2, float(ring[1])))
	draw_rect(Rect2(foot.x - P, foot.y - 56.0, P * 2.5, 56.0), INK)
	draw_rect(Rect2(foot.x - P + 2.0, foot.y - 54.0, P * 1.5, 54.0), Color8(92, 58, 28))
	draw_rect(Rect2(foot.x - P * 2.0, foot.y - 72.0, P * 4.5, P * 4.5), INK)
	draw_rect(Rect2(foot.x - P * 1.5, foot.y - 70.0, P * 3.5, P * 3.5), Color8(255, 154, 60))
	draw_rect(Rect2(foot.x - P * 0.5, foot.y - 66.0, P * 1.5, P * 1.5), Color8(255, 216, 74))
