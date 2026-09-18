class_name MenuBackdrop
extends Control

# ============================================================
# MENU BACKDROP - the jungle behind every menu screen.
#
# Drawn, not an image: a dusk gradient, sun rays, three rolling ridges and a
# canopy fringe across the top. It scales to any aspect a phone throws at it,
# and the splash, the home screen and the match loader all share it, so
# moving between them never flashes a different world.
# ============================================================

const TOP := Color8(22, 58, 64)
const MIDDLE := Color8(46, 112, 96)
const BOTTOM := Color8(18, 40, 34)
const RIDGES: Array[Color] = [Color8(38, 92, 80), Color8(28, 72, 62), Color8(18, 50, 44)]
const CANOPY := Color8(12, 34, 28)

## Rays turn slowly. Off for the loading screen, where nothing should
## compete with the progress bars.
@export var animate: bool = true

var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	if animate:
		_time += delta
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.55), Vector2(0, h * 0.55)]),
		PackedColorArray([TOP, TOP, MIDDLE, MIDDLE])
	)
	draw_polygon(
		PackedVector2Array([Vector2(0, h * 0.55), Vector2(w, h * 0.55), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([MIDDLE, MIDDLE, BOTTOM, BOTTOM])
	)

	# Light through the canopy, fanning from above the stage.
	var origin := Vector2(w * 0.5, -h * 0.25)
	for i in 9:
		var angle := PI * 0.5 + (float(i) - 4.0) * 0.16 + sin(_time * 0.15 + i) * 0.02
		var spread := 0.035
		var reach := h * 1.6
		var a := origin + Vector2.from_angle(angle - spread) * reach
		var b := origin + Vector2.from_angle(angle + spread) * reach
		draw_colored_polygon(PackedVector2Array([origin, a, b]), Color(1.0, 0.95, 0.7, 0.035))

	for layer in RIDGES.size():
		var base := h * (0.52 + layer * 0.12)
		var amp := h * (0.09 - layer * 0.015)
		var points := PackedVector2Array()
		var steps := 48
		for i in steps + 1:
			var t := float(i) / steps
			var wave := sin(t * TAU * (1.3 + layer * 0.7) + layer * 1.7) * 0.6 + sin(t * TAU * (3.1 + layer)) * 0.4
			points.append(Vector2(t * w, base - amp * wave))
		points.append(Vector2(w, h))
		points.append(Vector2(0, h))
		draw_colored_polygon(points, RIDGES[layer])

	# Leaves drifting down through the light. Their paths are functions of
	# time, so there is nothing to spawn, track or free.
	for n in 14:
		var fall := 30.0 + fmod(n * 13.7, 25.0)
		var y := fmod(_time * fall + n * 97.0, h + 80.0) - 40.0
		var x := fmod(n * 181.0, w) + sin(_time * 0.9 + n) * 26.0
		var spin := _time * 1.4 + n
		var leaf := PackedVector2Array([
			Vector2(x, y) + Vector2.from_angle(spin) * 9.0,
			Vector2(x, y) + Vector2.from_angle(spin + 1.9) * 4.0,
			Vector2(x, y) + Vector2.from_angle(spin + PI) * 9.0,
			Vector2(x, y) + Vector2.from_angle(spin - 1.9) * 4.0,
		])
		draw_colored_polygon(leaf, Color(0.55, 0.85, 0.45, 0.55) if n % 3 else Color(0.95, 0.8, 0.3, 0.5))

	# Leaves hanging into frame from the top edge.
	var x := -20.0
	var i := 0
	while x < w + 40.0:
		var drop := 26.0 + fmod(float(i) * 37.0, 44.0)
		var sway := sin(_time * 0.8 + i) * 3.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, -4.0), Vector2(x + 34.0, -4.0),
			Vector2(x + 22.0 + sway, drop), Vector2(x + 12.0 + sway, drop + 6.0),
		]), CANOPY)
		x += 30.0
		i += 1
