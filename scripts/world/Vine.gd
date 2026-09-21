@tool
class_name Vine
extends Area2D

# ============================================================
# VINE - a grab point, not a rope simulation.
#
# The anchor is a single point and the "rope" is drawn, not simulated. The
# player owns the pendulum maths; this node only says where the pivot is and
# how close you have to be to catch it. Keeping the rope cosmetic is what
# makes swinging cheap enough to run identically on host and client.
# ============================================================

## How far below the pivot the vine hangs, for drawing and for the grab shape.
@export var length: float = 200.0:
	set(value):
		length = maxf(value, 16.0)
		_rebuild()
## Radius around the vine body that counts as grabbable.
@export var grab_radius: float = 44.0:
	set(value):
		grab_radius = maxf(value, 8.0)
		_rebuild()
@export var rope_color: Color = Color8(30, 92, 62)          # JunglePalette.LEAF_DARK

@onready var _shape: CollisionShape2D = $Shape


func _ready() -> void:
	add_to_group(&"vine")
	collision_layer = GameConfig.LAYER_VINE
	collision_mask = 0
	monitoring = false
	monitorable = true
	_rebuild()


## The player grabs the pivot, not the sprite. Returning self keeps the
## pendulum anchored at the top of the vine where it belongs.
func get_anchor() -> Node2D:
	return self


func _rebuild() -> void:
	if not is_inside_tree() or _shape == null:
		return
	var capsule := CapsuleShape2D.new()
	capsule.radius = grab_radius
	capsule.height = length + grab_radius * 2.0
	_shape.shape = capsule
	_shape.position = Vector2(0.0, length * 0.5)
	queue_redraw()


func _draw() -> void:
	draw_vine(self, Vector2.ZERO, Vector2(0.0, length), rope_color)


## Shared with the swing rope a monkey draws, so the vine it holds looks like
## the vine it grabbed. Stem, a leaf pair every so often, a knot at the top.
static func draw_vine(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color) -> void:
	var outline := JunglePalette.BARK_DARK
	var leaf := color.lightened(0.35)
	var leaf_dark := color.darkened(0.15)
	var span := to - from
	var length := span.length()
	if length < 1.0:
		return
	var dir := span / length
	var side := Vector2(-dir.y, dir.x)
	canvas.draw_line(from, to, outline, 6.0)
	canvas.draw_line(from, to, color, 3.0)
	var steps := int(length / 16.0)
	for i in range(1, steps):
		var at := from + dir * (i * 16.0)
		var flip := 1.0 if i % 2 == 0 else -1.0
		var tip := at + side * flip * 9.0 + dir * 4.0
		canvas.draw_colored_polygon(PackedVector2Array([at, tip + side * flip * -2.0 - dir * 3.0, tip, tip + dir * 4.0]), outline)
		canvas.draw_colored_polygon(PackedVector2Array([at + dir, tip - dir * 2.0, tip - side * flip * 1.0 + dir * 2.0]), leaf if i % 3 else leaf_dark)
	canvas.draw_circle(from, 9.0, outline)
	canvas.draw_circle(from, 7.0, leaf_dark)
	canvas.draw_circle(from + Vector2(-3.0, -2.0), 3.0, leaf)
	canvas.draw_circle(to, 6.0, outline)
	canvas.draw_circle(to, 4.0, leaf)
