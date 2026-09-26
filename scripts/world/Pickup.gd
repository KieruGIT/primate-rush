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
const BANANA_ART = preload("res://scripts/ui/BananaIcon.gd")
## How far above the floor a pickup rests (its centre), so it sits on top
## of a block instead of half inside it.
const REST_HEIGHT: float = 26.0

var pickup_id: int = 0
var kind: int = Kind.BANANA
var value: int = 1

var _bob: float = 0.0
var _settled: bool = false

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
	if not _settled:
		_settled = true
		_settle()
	_bob += delta * 3.0
	queue_redraw()
	if kind == Kind.BANANA:
		_follow_magnet(delta)


## Out of any block it spawned inside (a knocked-loose banana can land in a
## wall), then onto the surface below it if it is sunk into the floor. Run
## on every machine: every machine gets the same answer from the same map.
func _settle() -> void:
	var space := get_world_2d().direct_space_state
	var probe := PhysicsPointQueryParameters2D.new()
	probe.collision_mask = GameConfig.LAYER_SOLID
	var lifted := 0.0
	probe.position = global_position
	while lifted < 400.0 and not space.intersect_point(probe, 1).is_empty():
		lifted += 8.0
		probe.position = global_position - Vector2(0.0, lifted)
	if lifted > 0.0:
		global_position.y -= lifted
	# Floor just under it: sit on it, not in it.
	var ray := PhysicsRayQueryParameters2D.create(global_position - Vector2(0.0, 4.0), global_position + Vector2(0.0, REST_HEIGHT), GameConfig.LAYER_SOLID)
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		global_position.y = float(hit["position"].y) - REST_HEIGHT


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


## A pixel banana, the same one as the wallet and the banana rain, so a
## banana looks like a banana everywhere. In a night level the bananas are
## the second light source after the torches, so each carries a small halo.
## Worth more: bigger, and redder the more it is worth.
func _draw_banana(at: Vector2, size_scale: float, color: Color) -> void:
	JunglePalette.draw_glow(self, at, 46.0 * size_scale, Color(color, 0.32))
	var cell := floorf(3.0 * size_scale)
	var map: Array = BANANA_ART.MAP
	var art := Vector2(map[0].length(), map.size()) * cell
	var origin := (at - art * 0.5).floor()
	var tint := color
	var shades := {
		"y": tint,
		"l": tint.lightened(0.55),
		"d": tint.darkened(0.2),
	}
	for y in map.size():
		var row: String = map[y]
		for x in row.length():
			var key := row[x]
			var c: Variant = shades.get(key, BANANA_ART.COLORS.get(key))
			if c != null:
				draw_rect(Rect2(origin + Vector2(x, y) * cell, Vector2(cell, cell)), c)
