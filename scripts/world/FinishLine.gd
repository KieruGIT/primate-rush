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
@export var banner_color: Color = Color8(255, 210, 51)      # JunglePalette.BANANA

@onready var _shape: CollisionShape2D = $Shape


func _ready() -> void:
	add_to_group(&"finish_line")
	collision_layer = 0
	collision_mask = GameConfig.LAYER_HURTBOX
	area_entered.connect(_on_area_entered)
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape.shape = rect
	_light_the_poles()
	queue_redraw()


## A brazier on each pole. In a night level the finish is the brightest thing
## on screen, which is the point: the player should be able to see where the
## race ends before they can read what it is.
func _light_the_poles() -> void:
	var half := size * 0.5
	for side in [-1.0, 1.0]:
		var torch := Torch.new()
		torch.name = "FinishTorch%s" % ("L" if side < 0.0 else "R")
		torch.position = Vector2(side * (half.x + 22.0), half.y)
		torch.scale_factor = 1.4
		torch.reach = 260.0
		torch.phase = 0.0 if side < 0.0 else 1.9
		add_child(torch)


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
	var outline := JunglePalette.BARK_DARK
	var wood := JunglePalette.BARK_LIGHT
	var origin := -size * 0.5
	# Glow behind the banner, so the finish reads as lit rather than as a
	# bright rectangle pasted onto a dark level.
	JunglePalette.draw_glow(self, Vector2.ZERO, size.length() * 0.85, Color(JunglePalette.BANANA, 0.28))
	var cell := 16.0
	var cols := maxi(1, int(size.x / cell))
	var rows := maxi(1, int(size.y / cell))
	var cell_size := Vector2(size.x / cols, size.y / rows)
	draw_rect(Rect2(origin - Vector2(4, 4), size + Vector2(8, 8)), outline)
	for row in rows:
		for col in cols:
			var light := (row + col) % 2 == 0
			draw_rect(Rect2(origin + Vector2(col, row) * cell_size, cell_size), Color(0.96, 0.96, 0.92) if light else Color8(28, 30, 38))
	draw_rect(Rect2(origin - Vector2(2, 2), size + Vector2(4, 4)), banner_color, false, 3.0)
	for x in [origin.x - 10.0, origin.x + size.x + 2.0]:
		draw_rect(Rect2(x, origin.y - 18.0, 8.0, size.y + 18.0), outline)
		draw_rect(Rect2(x + 2.0, origin.y - 16.0, 4.0, size.y + 16.0), wood)
		draw_circle(Vector2(x + 4.0, origin.y - 18.0), 6.0, outline)
		draw_circle(Vector2(x + 4.0, origin.y - 18.0), 4.0, banner_color)
