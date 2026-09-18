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
	# A chequered banner between two poles. Black and white rather than the
	# banner colour, which goes on the frame: a finish line should read as a
	# finish line before it reads as this game's palette.
	var outline := Color8(30, 26, 24)
	var wood := Color8(142, 96, 58)
	var origin := -size * 0.5
	var cell := 16.0
	var cols := maxi(1, int(size.x / cell))
	var rows := maxi(1, int(size.y / cell))
	var cell_size := Vector2(size.x / cols, size.y / rows)
	draw_rect(Rect2(origin - Vector2(4, 4), size + Vector2(8, 8)), outline)
	for row in rows:
		for col in cols:
			var light := (row + col) % 2 == 0
			draw_rect(Rect2(origin + Vector2(col, row) * cell_size, cell_size), Color(0.96, 0.96, 0.92) if light else Color8(40, 38, 44))
	draw_rect(Rect2(origin - Vector2(2, 2), size + Vector2(4, 4)), banner_color, false, 3.0)
	for x in [origin.x - 10.0, origin.x + size.x + 2.0]:
		draw_rect(Rect2(x, origin.y - 18.0, 8.0, size.y + 18.0), outline)
		draw_rect(Rect2(x + 2.0, origin.y - 16.0, 4.0, size.y + 16.0), wood)
		draw_circle(Vector2(x + 4.0, origin.y - 18.0), 6.0, outline)
		draw_circle(Vector2(x + 4.0, origin.y - 18.0), 4.0, banner_color)
