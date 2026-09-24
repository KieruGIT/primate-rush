extends RefCounted

# ============================================================
# RECT BAKE - turns block-drawn art into one texture.
#
# The low-detail level is painted from code as thousands of flat blocks
# (MockSkin, MockLayers). Drawn live, every one of them is sent to the GPU
# every frame. Baked here once at load, a whole platform, tree or background
# strip becomes a single image: one quad per piece instead of hundreds, which
# is what phones need.
#
# Works because every block is opaque and lands on the 2 px art grid, so the
# image is stored at half size (one texel = 2x2 world px) and drawn back at
# 2x with nearest filtering - pixel-identical to the live drawing.
#
# The painter is any function that takes a canvas and calls
# canvas.draw_rect(Rect2, Color) on it; here the canvas is a recorder.
# ============================================================

const GRID: float = 2.0


## Records the blocks a painter draws, then paints them into an Image.
class Recorder extends RefCounted:
	var rects: Array[Rect2] = []
	var colors: Array[Color] = []

	func draw_rect(rect: Rect2, color: Color, _filled: bool = true, _width: float = -1.0) -> void:
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return
		rects.append(rect)
		colors.append(color)


## Baked textures kept for reuse, by caller-chosen key. The canopy strip and
## the background tree strip are identical in every copy and in every match on
## the same seed, so they are painted once per session instead of once per
## copy per match.
static var _cache: Dictionary = {}   # key -> [ImageTexture, Vector2 origin]


## A Node2D holding the baked art (a nearest-filtered Sprite2D placed at the
## art's own position). Empty node if the painter drew nothing.
static func bake(painter: Callable) -> Node2D:
	var baked := bake_texture(painter)
	var holder := Node2D.new()
	if not baked.is_empty():
		holder.add_child(sprite(baked, Vector2.ZERO))
	return holder


## Same as bake(), but a painter already baked under `key` is not painted
## again: the new node shares the first one's texture.
static func bake_shared(key: String, painter: Callable, shift: Vector2 = Vector2.ZERO) -> Node2D:
	if not _cache.has(key):
		_cache[key] = bake_texture(painter)
	var holder := Node2D.new()
	var baked: Array = _cache[key]
	if not baked.is_empty():
		holder.add_child(sprite(baked, shift))
	return holder


## [texture, origin], or [] if the painter drew nothing.
static func bake_texture(painter: Callable) -> Array:
	var rec := Recorder.new()
	painter.call(rec)
	if rec.rects.is_empty():
		return []
	var bounds: Rect2 = rec.rects[0]
	for r in rec.rects:
		bounds = bounds.merge(r)
	var origin := (bounds.position / GRID).floor() * GRID
	var size := Vector2i(((bounds.end - origin) / GRID).ceil())
	var image := Image.create(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGBA8)
	for i in rec.rects.size():
		var r: Rect2 = rec.rects[i]
		var p0 := ((r.position - origin) / GRID).round()
		var p1 := ((r.end - origin) / GRID).round()
		var cell := Rect2i(Vector2i(p0), Vector2i(p1 - p0))
		if cell.size.x > 0 and cell.size.y > 0:
			image.fill_rect(cell, rec.colors[i])
	return [ImageTexture.create_from_image(image), origin]


static func sprite(baked: Array, shift: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = baked[0]
	s.centered = false
	s.position = (baked[1] as Vector2) + shift
	s.scale = Vector2(GRID, GRID)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return s
