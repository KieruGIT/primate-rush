class_name Climbable
extends Area2D

# ============================================================
# CLIMBABLE - marks a surface the monkeys can go up.
#
# Separate from the collision body on purpose: a climbable wall is still a
# solid wall, and overloading one shape for both jobs means every climbable
# surface has to be either solid or passable, never both.
# ============================================================

@export var size: Vector2 = Vector2(48.0, 400.0):
	set(value):
		size = value
		_rebuild()
@export var tint: Color = Color(0.45, 0.62, 0.38, 0.55)
@export var draw_debug_face: bool = true

@onready var _shape: CollisionShape2D = $Shape


func _ready() -> void:
	collision_layer = GameConfig.LAYER_CLIMBABLE
	collision_mask = 0
	monitoring = false
	monitorable = true
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree() or _shape == null:
		return
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape.shape = rect
	queue_redraw()


func _draw() -> void:
	if not draw_debug_face:
		return
	# Gray-box readability: you must be able to see what is climbable before
	# there is art, or every playtest note is "I did not know I could climb".
	draw_rect(Rect2(-size * 0.5, size), tint, true)
	for y in range(int(-size.y * 0.5) + 16, int(size.y * 0.5), 32):
		draw_line(Vector2(-size.x * 0.5, y), Vector2(size.x * 0.5, y), tint.lightened(0.4), 3.0)
