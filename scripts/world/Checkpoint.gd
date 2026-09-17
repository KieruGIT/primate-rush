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


func _draw() -> void:
	var lit := not _claimed_by.is_empty()
	var color: Color = flag_color if lit else flag_color.darkened(0.55)
	draw_line(Vector2(0.0, -size.y * 0.5), Vector2(0.0, size.y * 0.5), color, 5.0)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(0.0, -size.y * 0.5),
			Vector2(size.x, -size.y * 0.5 + 18.0),
			Vector2(0.0, -size.y * 0.5 + 36.0),
		]),
		color
	)
