class_name Headwear
extends Node2D

# ============================================================
# HEADWEAR - the cosmetic attachment point.
#
# This exists now, with drawn placeholder shapes, for the reason the design
# doc gives: retrofitting an attachment point onto a finished sprite rig is
# genuinely painful, and the hook costs almost nothing today. When there is
# art, `_draw` is replaced by a Sprite2D and everything upstream of it - the
# roster field, the lobby row, the network sync - already works.
#
# It scales to the monkey's body width, so the same hat sits correctly on a
# capuchin and on a gorilla without a per-monkey offset table.
# ============================================================

var style: StringName = &"none"
var color: Color = Color.WHITE
var body_width: float = 32.0


func apply(hat_style: StringName, hat_color: Color, width: float) -> void:
	style = hat_style
	color = hat_color
	body_width = maxf(width, 8.0)
	visible = style != &"none"
	queue_redraw()


func _draw() -> void:
	if style == &"none":
		return
	var half := body_width * 0.5
	match style:
		&"cap":
			draw_rect(Rect2(Vector2(-half, -12.0), Vector2(body_width, 12.0)), color, true)
			draw_rect(Rect2(Vector2(-half, -3.0), Vector2(body_width * 1.5, 5.0)), color.darkened(0.2), true)
		&"band":
			draw_rect(Rect2(Vector2(-half, -8.0), Vector2(body_width, 8.0)), color, true)
			draw_circle(Vector2(half - 2.0, -4.0), 5.0, color.lightened(0.35))
		&"crown":
			var points := PackedVector2Array([
				Vector2(-half, 0.0),
				Vector2(-half, -14.0),
				Vector2(-half * 0.5, -6.0),
				Vector2(0.0, -18.0),
				Vector2(half * 0.5, -6.0),
				Vector2(half, -14.0),
				Vector2(half, 0.0),
			])
			draw_colored_polygon(points, color)
		&"shades":
			# Across the eyes, which sit a little under the head's top.
			var y := 10.0
			draw_rect(Rect2(Vector2(-half * 0.95, y - 1.0), Vector2(body_width * 0.95, 3.0)), color)
			draw_rect(Rect2(Vector2(-half * 0.9, y), Vector2(half * 0.8, 7.0)), color)
			draw_rect(Rect2(Vector2(half * 0.1, y), Vector2(half * 0.8, 7.0)), color)
			draw_rect(Rect2(Vector2(-half * 0.8, y + 1.0), Vector2(3.0, 2.0)), Color(1, 1, 1, 0.8))
			draw_rect(Rect2(Vector2(half * 0.2, y + 1.0), Vector2(3.0, 2.0)), Color(1, 1, 1, 0.8))
		&"flower":
			var at := Vector2(half * 0.55, -2.0)
			for i in 5:
				draw_circle(at + Vector2.from_angle(TAU * i / 5.0) * 5.0, 4.0, color)
			draw_circle(at, 3.5, Color(1.0, 0.85, 0.2))
		&"headphones":
			var arc := PackedVector2Array()
			for i in 13:
				var a := lerpf(PI, TAU, i / 12.0)
				arc.append(Vector2(cos(a) * (half + 3.0), sin(a) * 12.0 + 6.0))
			draw_polyline(arc, Color(0.12, 0.12, 0.14), 4.0)
			for side in [-1.0, 1.0]:
				draw_rect(Rect2(Vector2(side * (half + 3.0) - 5.0, 2.0), Vector2(10.0, 13.0)), color)
				draw_rect(Rect2(Vector2(side * (half + 3.0) - 5.0, 2.0), Vector2(10.0, 3.0)), color.lightened(0.4))
		&"party":
			var cone := PackedVector2Array([Vector2(-half * 0.55, 0.0), Vector2(0.0, -26.0), Vector2(half * 0.55, 0.0)])
			draw_colored_polygon(cone, color)
			draw_line(Vector2(-half * 0.35, -6.0), Vector2(half * 0.2, -14.0), Color(1, 1, 1, 0.8), 3.0)
			draw_circle(Vector2(0.0, -26.0), 4.0, Color(1.0, 0.85, 0.2))
		&"halo":
			var ring := PackedVector2Array()
			for i in 25:
				var a := TAU * i / 24.0
				ring.append(Vector2(cos(a) * half * 0.8, sin(a) * 4.0 - 14.0))
			draw_polyline(ring, Color(color, 0.5), 7.0)
			draw_polyline(ring, color, 3.0)
		&"tophat":
			draw_rect(Rect2(Vector2(-half * 1.4, -4.0), Vector2(body_width * 1.4, 5.0)), color.darkened(0.25), true)
			draw_rect(Rect2(Vector2(-half * 0.8, -30.0), Vector2(body_width * 0.8, 27.0)), color, true)
			draw_rect(Rect2(Vector2(-half * 0.8, -12.0), Vector2(body_width * 0.8, 6.0)), color.lightened(0.5), true)
