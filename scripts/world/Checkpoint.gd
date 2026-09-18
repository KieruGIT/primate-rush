class_name Checkpoint
extends Area2D

# ============================================================
# CHECKPOINT - where falling sends you back to.
#
# Checkpoints are claimed per player, not globally, so a leader who has
# passed three of them is not dragged back by a straggler's respawn.
# ============================================================

signal claimed(player_id: int)

@export var size: Vector2 = Vector2(56.0, 120.0)
@export var flag_color: Color = Color(0.95, 0.85, 0.30)

var _claimed_by: Array[int] = []

@onready var _shape: CollisionShape2D = $Shape


func _ready() -> void:
	collision_layer = 0
	collision_mask = GameConfig.LAYER_HURTBOX
	area_entered.connect(_on_area_entered)
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape.shape = rect


func _on_area_entered(area: Area2D) -> void:
	if not area.has_meta(&"player"):
		return
	var player := area.get_meta(&"player") as Player
	if player == null or _claimed_by.has(player.player_id):
		return
	_claimed_by.append(player.player_id)
	var arena := get_tree().get_first_node_in_group(&"arena")
	if arena != null and arena.has_method(&"set_checkpoint"):
		arena.call(&"set_checkpoint", player.player_id, global_position)
	claimed.emit(player.player_id)
	queue_redraw()


func _process(_delta: float) -> void:
	# The pennant ripples. Cheap: a triangle and a strip, redrawn.
	queue_redraw()


func _draw() -> void:
	var lit := not _claimed_by.is_empty()
	var outline := Color8(34, 26, 22)
	var wood := Color8(142, 96, 58)
	var cloth: Color = flag_color if lit else Color8(206, 206, 196)
	var top := -size.y * 0.5
	var bottom := size.y * 0.5
	# Pole, outlined, with a knob that goes gold once you have claimed it.
	draw_rect(Rect2(-4.0, top, 8.0, bottom - top), outline)
	draw_rect(Rect2(-2.0, top + 2.0, 4.0, bottom - top - 2.0), wood)
	draw_rect(Rect2(-1.0, top + 2.0, 1.0, bottom - top - 2.0), wood.lightened(0.25))
	draw_circle(Vector2(0.0, top), 6.0, outline)
	draw_circle(Vector2(0.0, top), 4.0, cloth if lit else Color8(150, 150, 150))
	# Pennant: three points, the tip bobbing on a clock so it never looks
	# like a static triangle glued to a stick.
	var t := Time.get_ticks_msec() * 0.004 + global_position.x * 0.01
	var wave := sin(t) * 4.0
	var length := size.x - 6.0
	var p0 := Vector2(3.0, top + 6.0)
	var p1 := Vector2(3.0 + length, top + 20.0 + wave)
	var p2 := Vector2(3.0, top + 36.0)
	var mid := Vector2(3.0 + length * 0.5, top + 21.0 + wave * 0.5)
	draw_colored_polygon(PackedVector2Array([p0 + Vector2(-1, -2), p1 + Vector2(3, 0), p2 + Vector2(-1, 2)]), outline)
	draw_colored_polygon(PackedVector2Array([p0, mid + Vector2(0, -8), p1, mid + Vector2(0, 7), p2]), cloth)
	draw_colored_polygon(PackedVector2Array([p0 + Vector2(0, 16), mid + Vector2(0, 3), p1, mid + Vector2(0, 7), p2]), cloth.darkened(0.2))
