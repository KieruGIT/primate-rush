class_name FinishLine
extends Area2D

# ============================================================
# FINISH LINE - the end of a race.
#
# Reports to the race director rather than deciding anything itself. A map
# should be able to place a finish line without knowing whether a race is
# even being played on it.
# ============================================================

signal crossed(player_id: int)

@export var size: Vector2 = Vector2(80.0, 320.0)
@export var banner_color: Color = Color(0.95, 0.9, 0.35)

@onready var _shape: CollisionShape2D = $Shape


func _ready() -> void:
	add_to_group(&"finish_line")
	collision_layer = 0
	collision_mask = GameConfig.LAYER_HURTBOX
	area_entered.connect(_on_area_entered)
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape.shape = rect
	queue_redraw()


func _on_area_entered(area: Area2D) -> void:
	if not area.has_meta(&"player"):
		return
	var player := area.get_meta(&"player") as Player
	if player != null:
		crossed.emit(player.player_id)


func _draw() -> void:
	# Checkerboard, because a solid rectangle in a gray-box level reads as
	# more level geometry rather than as the thing you are running at.
	var cell := 20.0
	var origin := -size * 0.5
	var rows := int(size.y / cell)
	var cols := int(size.x / cell)
	for row in rows:
		for col in cols:
			if (row + col) % 2 != 0:
				continue
			draw_rect(Rect2(origin + Vector2(col * cell, row * cell), Vector2(cell, cell)), banner_color, true)
	draw_rect(Rect2(origin, size), banner_color.darkened(0.3), false, 3.0)
