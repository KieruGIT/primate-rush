class_name MapData
extends Node2D

# ============================================================
# MAP DATA - everything the arena needs to know about a level.
#
# Maps are swapped into the arena rather than being arenas themselves, so
# adding a level is adding one scene file and one entry in GameConfig, not
# duplicating the spawn, respawn, and netcode wiring per map.
#
# progress_axis is what makes one race director serve both a horizontal run
# and a vertical ascent: progress is a dot product, not a hardcoded x.
# ============================================================

@export var display_name: String = "Unnamed Map"
@export var spawn_point: Vector2 = Vector2.ZERO
## Offset between player spawns so four monkeys do not start inside each other.
@export var spawn_stride: Vector2 = Vector2(72.0, 0.0)
## Fall past this and you respawn. Measured on the axis that can kill you.
@export var kill_depth: float = 1400.0
## Direction of progress. (1,0) for a left-to-right run, (0,-1) for an ascent.
@export var progress_axis: Vector2 = Vector2.RIGHT


func _ready() -> void:
	add_to_group(&"map")


func progress_of(point: Vector2) -> float:
	return point.dot(progress_axis.normalized())


func finish_line() -> Node2D:
	for child in get_children():
		if child is FinishLine:
			return child
		if child is Node2D:
			for grandchild in child.get_children():
				if grandchild is FinishLine:
					return grandchild
	return null
