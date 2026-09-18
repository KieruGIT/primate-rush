class_name BouncePad
extends Area2D

# ============================================================
# BOUNCE PAD - a spring that throws whoever lands on it straight up.
#
# The level's fastest way up, and a reason to route through a spot instead
# of around it. Strength is launch speed; the height it buys is
# strength^2 / (2 * gravity), about 480 px at the default.
#
# Every machine detects its own overlaps, and Player.bounce only acts on a
# monkey this machine simulates, so a client's own monkey springs with no
# round trip while everyone else's follows from host snapshots.
# ============================================================

const PACK := "res://assets/kenney_pixel-platformer/tilemap_packed.png"
const REST_TILE: int = 107
const SPRUNG_TILE: int = 108

@export var strength: float = 1350.0
@export var width: float = 64.0

var _sprung: float = 0.0
var _tiles: Texture2D

@onready var _shape: CollisionShape2D = $Shape


func _ready() -> void:
	add_to_group(&"bounce_pad")
	collision_layer = 0
	collision_mask = GameConfig.LAYER_HURTBOX
	area_entered.connect(_on_area_entered)
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, 20.0)
	_shape.shape = rect
	_shape.position = Vector2(0.0, -10.0)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(PACK):
		_tiles = load(PACK)


func _on_area_entered(area: Area2D) -> void:
	if not area.has_meta(&"player"):
		return
	var player := area.get_meta(&"player") as Player
	# Only on the way down or level: a monkey rising through a pad from
	# below should not get a second launch for free.
	if player == null or player.velocity.y < -50.0:
		return
	player.bounce(strength)
	_sprung = 0.25
	queue_redraw()


func _process(delta: float) -> void:
	if _sprung > 0.0:
		_sprung -= delta
		if _sprung <= 0.0:
			queue_redraw()


func _draw() -> void:
	var tile := SPRUNG_TILE if _sprung > 0.0 else REST_TILE
	if _tiles == null:
		draw_rect(Rect2(-width * 0.5, -16.0, width, 16.0), Color(0.9, 0.3, 0.25))
		return
	var src := Rect2((tile % 20) * 18, (tile / 20) * 18, 18, 18)
	# 3x, feet-down: the spring's base sits on the surface it stands on.
	var size := Vector2(54.0, 54.0)
	draw_texture_rect_region(_tiles, Rect2(Vector2(-size.x * 0.5, -size.y), size), src)
