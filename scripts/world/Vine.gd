@tool
class_name Vine
extends Area2D

# ============================================================
# VINE - a grab point, not a rope simulation.
#
# The anchor is a single point and the "rope" is drawn, not simulated. The
# player owns the pendulum maths; this node only says where the pivot is and
# how close you have to be to catch it. Keeping the rope cosmetic is what
# makes swinging cheap enough to run identically on host and client.
# ============================================================

## How far below the pivot the vine hangs, for drawing and for the grab shape.
@export var length: float = 200.0:
	set(value):
		length = maxf(value, 16.0)
		_rebuild()
## Radius around the vine body that counts as grabbable.
@export var grab_radius: float = 44.0:
	set(value):
		grab_radius = maxf(value, 8.0)
		_rebuild()
@export var rope_color: Color = Color8(30, 92, 62)          # JunglePalette.LEAF_DARK

@onready var _shape: CollisionShape2D = $Shape


func _ready() -> void:
	add_to_group(&"vine")
	collision_layer = GameConfig.LAYER_VINE
	collision_mask = 0
	monitoring = false
	monitorable = true
	_rebuild()


## The player grabs the pivot, not the sprite. Returning self keeps the
## pendulum anchored at the top of the vine where it belongs.
func get_anchor() -> Node2D:
	return self


func _rebuild() -> void:
	if not is_inside_tree() or _shape == null:
		return
	var capsule := CapsuleShape2D.new()
	capsule.radius = grab_radius
	capsule.height = length + grab_radius * 2.0
	_shape.shape = capsule
	_shape.position = Vector2(0.0, length * 0.5)
	queue_redraw()


func _draw() -> void:
	draw_vine(self, Vector2.ZERO, Vector2(0.0, length), rope_color)


## Shared with the swing rope a monkey draws, so the vine it holds looks like
## the vine it grabbed. Stem, a leaf pair every so often, a knot at the top.
static func draw_vine(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color) -> void:
	var span := to - from
	var distance := span.length()
	if distance < 1.0:
		return
	var steps := maxi(1, int(ceilf(distance / 2.0)))
	# Rasterize the rope on the same two-pixel grid as terrain and characters.
	for i in range(steps + 1):
		var at := LevelSkin.snap(from.lerp(to, float(i) / float(steps)))
		canvas.draw_rect(Rect2(at - Vector2(4, 2), Vector2(8, 6)), JunglePalette.OUTLINE)
	for i in range(steps + 1):
		var at := LevelSkin.snap(from.lerp(to, float(i) / float(steps)))
		canvas.draw_rect(Rect2(at - Vector2(2, 0), Vector2(4, 2)), JunglePalette.BARK_LIGHT)
		canvas.draw_rect(Rect2(at, Vector2(2, 2)), color)
		if i % 13 == 6:
			var side := -1.0 if (i / 13) % 2 == 0 else 1.0
			canvas.draw_rect(Rect2(at + Vector2(side * 4 - 2, 0), Vector2(6, 4)), JunglePalette.LEAF_DARK)
			canvas.draw_rect(Rect2(at + Vector2(side * 6 - 2, -2), Vector2(4, 2)), JunglePalette.LEAF_LIGHT)
	var anchor := LevelSkin.snap(from)
	canvas.draw_rect(Rect2(anchor - Vector2(8, 6), Vector2(16, 12)), JunglePalette.OUTLINE)
	canvas.draw_rect(Rect2(anchor - Vector2(6, 4), Vector2(12, 8)), JunglePalette.BARK)
	canvas.draw_rect(Rect2(anchor - Vector2(6, 4), Vector2(8, 2)), JunglePalette.LEAF_LIGHT)
