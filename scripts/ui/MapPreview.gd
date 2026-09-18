class_name MapPreview
extends Control

# ============================================================
# MAP PREVIEW - a level's layout drawn small, read from the level itself.
#
# The map scene is instanced off-tree, its collision rectangles copied out,
# and the instance thrown away. So a preview can never show a level that
# no longer exists: move a platform and its thumbnail moves with it.
# ============================================================

static var _cache: Dictionary = {}     # map id -> {"solids": Array[Rect2], "finish": Rect2, "vines": Array}

var map_id: StringName = &""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func show_map(id: StringName) -> void:
	map_id = id
	queue_redraw()


static func layout_of(id: StringName) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var out := {"solids": [], "finish": Rect2(), "vines": []}
	var scene := GameConfig.load_map(id)
	if scene != null:
		var map := scene.instantiate()
		for body in map.find_children("*", "StaticBody2D", true, false):
			for child in body.get_children():
				var col := child as CollisionShape2D
				if col != null and col.shape is RectangleShape2D:
					var extent: Vector2 = (col.shape as RectangleShape2D).size
					var at: Vector2 = (body as Node2D).position + col.position
					out["solids"].append(Rect2(at - extent * 0.5, extent))
		for node in map.find_children("*", "Area2D", true, false):
			if node is FinishLine:
				var extent: Vector2 = node.get(&"size")
				out["finish"] = Rect2(_offset_of(node) - extent * 0.5, extent)
			elif node is Vine:
				out["vines"].append([_offset_of(node), float(node.get(&"length"))])
		map.free()
	_cache[id] = out
	return out


static func _offset_of(node: Node) -> Vector2:
	var at := Vector2.ZERO
	var walk := node
	while walk != null and walk is Node2D:
		at += (walk as Node2D).position
		walk = walk.get_parent()
	return at


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	draw_polygon(
		PackedVector2Array([box.position, Vector2(box.end.x, 0), box.end, Vector2(0, box.end.y)]),
		PackedColorArray([Color8(104, 186, 226), Color8(104, 186, 226), Color8(200, 236, 214), Color8(200, 236, 214)])
	)
	if map_id == &"":
		return
	var layout := layout_of(map_id)
	var solids: Array = layout["solids"]
	if solids.is_empty():
		return
	var bounds: Rect2 = solids[0]
	for rect in solids:
		bounds = bounds.merge(rect)
	bounds = bounds.grow(60.0)
	var fit := minf(size.x / bounds.size.x, size.y / bounds.size.y)
	var offset := (size - bounds.size * fit) * 0.5 - bounds.position * fit
	var water := Rect2(0, offset.y + (bounds.end.y - 40.0) * fit, size.x, size.y)
	draw_rect(water, Color8(71, 171, 169))
	for vine in layout["vines"]:
		var top: Vector2 = vine[0] * fit + offset
		draw_line(top, top + Vector2(0, float(vine[1]) * fit), Color8(46, 92, 50), maxf(2.0, fit * 5.0))
	for rect in solids:
		var r := Rect2(rect.position * fit + offset, rect.size * fit)
		draw_rect(r, Color8(96, 128, 136))
		draw_rect(Rect2(r.position, Vector2(r.size.x, maxf(3.0, minf(r.size.y, 10.0 * fit + 2.0)))), Color8(110, 190, 80))
	var finish: Rect2 = layout["finish"]
	if finish.size != Vector2.ZERO:
		var f := Rect2(finish.position * fit + offset, finish.size * fit)
		draw_rect(f, Color(0.96, 0.96, 0.92))
		draw_rect(f, Color8(40, 38, 44), false, 2.0)
	draw_rect(box, Color(0, 0, 0, 0.35), false, 3.0)
