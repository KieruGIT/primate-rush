class_name Pickup
extends Area2D

# ============================================================
# PICKUP - a banana or a lucky box lying in the world.
#
# Pickups are dumb. They report a touch and draw themselves; the hoard
# director decides whether the touch counts. That split is what keeps
# collection host authoritative: a client can make its own banana vanish
# on screen, but it cannot award itself a point.
# ============================================================

signal touched(pickup_id: int, player_id: int)

enum Kind { BANANA, LUCKY_BOX }

const MAGNET_PULL_SPEED: float = 620.0

var pickup_id: int = 0
var kind: int = Kind.BANANA
var value: int = 1

var _bob: float = 0.0

@onready var _shape: CollisionShape2D = $Shape


func _ready() -> void:
	add_to_group(&"pickup")
	collision_layer = GameConfig.LAYER_PICKUP
	collision_mask = GameConfig.LAYER_HURTBOX
	area_entered.connect(_on_area_entered)
	var circle := CircleShape2D.new()
	circle.radius = 22.0 if kind == Kind.BANANA else 30.0
	_shape.shape = circle
	_bob = randf() * TAU


func setup(id: int, pickup_kind: int, point: Vector2, points: int) -> void:
	pickup_id = id
	kind = pickup_kind
	value = points
	position = point


func _physics_process(delta: float) -> void:
	_bob += delta * 3.0
	queue_redraw()
	if kind == Kind.BANANA:
		_follow_magnet(delta)


## Banana Magnet. Run on every machine rather than replicated, because the
## pull is cosmetic: the host still decides who actually collects.
func _follow_magnet(delta: float) -> void:
	var puller := _nearest_magnet()
	if puller == null:
		return
	var to_player := puller.global_position - global_position
	global_position += to_player.normalized() * MAGNET_PULL_SPEED * delta


func _nearest_magnet() -> Player:
	var arena: Node = get_tree().get_first_node_in_group(&"arena")
	if arena == null:
		return null
	var table: Variant = arena.get(&"players")
	if not (table is Dictionary):
		return null
	var best: Player = null
	var best_dist := INF
	for id in table.keys():
		var player := table[id] as Player
		if player == null or player.ability != &"magnet":
			continue
		var dist := global_position.distance_squared_to(player.global_position)
		if dist < best_dist and dist < player.magnet_radius * player.magnet_radius:
			best_dist = dist
			best = player
	return best


func _on_area_entered(area: Area2D) -> void:
	if not area.has_meta(&"player"):
		return
	var player := area.get_meta(&"player") as Player
	if player != null:
		touched.emit(pickup_id, player.player_id)


func _draw() -> void:
	var lift := sin(_bob) * 4.0
	if kind == Kind.BANANA:
		# Worth more means bigger and brighter, so a player can read the
		# value of a spawn from across the map instead of memorizing it.
		var size_scale := 1.0 + float(value - 1) * 0.18
		var color := Color(0.95, 0.82, 0.25).lerp(Color(1.0, 0.55, 0.15), clampf(float(value - 1) / 4.0, 0.0, 1.0))
		draw_circle(Vector2(0.0, lift), 12.0 * size_scale, color)
		draw_arc(Vector2(0.0, lift), 17.0 * size_scale, 0.0, TAU, 20, color.darkened(0.3), 3.0)
		if value > 1:
			draw_string(ThemeDB.fallback_font, Vector2(-6.0, lift + 34.0), str(value), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, color)
	else:
		var box := Rect2(Vector2(-18.0, -18.0 + lift), Vector2(36.0, 36.0))
		draw_rect(box, Color(0.45, 0.75, 0.95), true)
		draw_rect(box, Color(0.15, 0.3, 0.45), false, 3.0)
		draw_string(ThemeDB.fallback_font, Vector2(-6.0, 8.0 + lift), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.1, 0.2, 0.3))
