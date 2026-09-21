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
		var heat := clampf(float(value - 1) / 4.0, 0.0, 1.0)
		var color := JunglePalette.BANANA.lerp(JunglePalette.FLAME, heat)
		_draw_banana(Vector2(0.0, lift), size_scale, color)
		if value > 1:
			draw_string(ThemeDB.fallback_font, Vector2(-6.0, lift + 34.0), str(value), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, JunglePalette.BANANA_LIGHT)
	else:
		var box := Rect2(Vector2(-18.0, -18.0 + lift), Vector2(36.0, 36.0))
		draw_rect(box, JunglePalette.CANOPY_NEAR, true)
		draw_rect(box, JunglePalette.LEAF, false, 3.0)
		draw_string(ThemeDB.fallback_font, Vector2(-6.0, 8.0 + lift), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, JunglePalette.BANANA_LIGHT)


## An actual banana rather than a yellow dot. In a night level the bananas
## are the second light source after the torches, so each one carries its own
## small halo: a plain silhouette this size vanishes against dark ground.
func _draw_banana(at: Vector2, size_scale: float, color: Color) -> void:
	JunglePalette.draw_glow(self, at, 46.0 * size_scale, Color(color, 0.32))

	# The crescent: an arc of segments swept from one tip to the other, each
	# one a quad, fat in the middle and pinched at both ends. Built from the
	# curve rather than from a polygon literal so the value scaling stays a
	# single multiply and the shape never shears.
	var steps := 14
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		var angle := lerpf(PI * 0.82, PI * 0.18, t)
		var centre := Vector2(cos(angle), -sin(angle)) * 17.0 * size_scale
		var thickness := sin(t * PI) * 6.5 * size_scale + 1.5 * size_scale
		var out_dir := centre.normalized()
		outer.append(at + centre + out_dir * thickness)
		inner.append(at + centre - out_dir * thickness)

	var body := PackedVector2Array(outer)
	for i in range(inner.size() - 1, -1, -1):
		body.append(inner[i])
	draw_colored_polygon(body, color)

	# Brown tips top and bottom, and a highlight along the outer edge, which
	# is what makes it read as a banana and not as a crescent moon.
	draw_circle(outer[0].lerp(inner[0], 0.5), 3.0 * size_scale, JunglePalette.BARK)
	draw_circle(outer[steps].lerp(inner[steps], 0.5), 3.0 * size_scale, JunglePalette.BARK)
	for i in steps:
		draw_line(outer[i], outer[i + 1], JunglePalette.BANANA_LIGHT, 2.0 * size_scale)
