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
## Knocked this far from the centre sideways and you are out, as if you
## fell. Zero means no side limit, which is right for every race map.
@export var blast_half_width: float = 0.0
## Camera zoom for this map. Below 1 shows more: an arena wants the whole
## island and both edges on screen, a race wants the monkey big.
@export var camera_zoom: float = 1.0
## Direction of progress. (1,0) for a left-to-right run, (0,-1) for an ascent.
@export var progress_axis: Vector2 = Vector2.RIGHT
## Tiny Swords terrain colour, 1 to 5. See LevelSkin.
@export_range(1, 5) var skin_palette: int = 3
## Off shows the raw gray box, for checking collision against the art.
@export var dressed: bool = true


## The racing line, as world points, from an optional "Route" child whose
## Marker2D children are in order. Bots follow it; people never see it.
var _route: PackedVector2Array = PackedVector2Array()
var _route_read: bool = false


func _ready() -> void:
	add_to_group(&"map")
	if dressed:
		var skin := LevelSkin.new()
		skin.name = "LevelSkin"
		skin.palette = skin_palette
		add_child(skin)
		move_child(skin, 0)


func progress_of(point: Vector2) -> float:
	return point.dot(progress_axis.normalized())


func route_points() -> PackedVector2Array:
	if not _route_read:
		_route_read = true
		var holder := get_node_or_null(^"Route")
		if holder != null:
			for child in holder.get_children():
				if child is Node2D:
					_route.append((child as Node2D).global_position)
	return _route


func finish_line() -> Node2D:
	for child in get_children():
		if child is FinishLine:
			return child
		if child is Node2D:
			for grandchild in child.get_children():
				if grandchild is FinishLine:
					return grandchild
	return null
