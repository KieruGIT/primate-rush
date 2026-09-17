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
@export var rope_color: Color = Color(0.35, 0.55, 0.28)

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
	draw_line(Vector2.ZERO, Vector2(0.0, length), rope_color, 5.0)
	draw_circle(Vector2.ZERO, 8.0, rope_color.darkened(0.25))
	draw_circle(Vector2(0.0, length), 10.0, rope_color.lightened(0.15))
