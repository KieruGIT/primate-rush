extends RefCounted

# ============================================================
# MOCK LAYERS - the parallax dressing from the mock's "Detailed pass":
#
#   Silhouettes  a mid-distance band of dark jungle: round crowns on thin
#                trunks and a few ruin pillars. Scrolls at about a third
#                of the camera, so it slides slower than the level.
#   Canopy       the dark leaf frame across the top of the screen with
#                vines hanging into the play space and drifting fireflies.
#                Screen-space, sliding at 0.9x the camera: the closest
#                layer, so it moves nearly with you.
#
# Pure decoration. No collision, no grab anchors: everything you can hold
# lives in the world layer (LevelSkin / MockSkin).
# ============================================================

const P: float = 4.0
const RectBake = preload("res://scripts/world/RectBake.gd")


class Silhouettes extends Node2D:
	## Width of one repeat, in px; the parallax plane wraps on it.
	var span: float = 1600.0
	var ground_y: float = 0.0
	var seed_value: int = 1

	## One child per repeat, so the copies off screen are skipped.
	## Every copy is the same picture shifted by one span, so it is painted
	## once and the other copies share that texture.
	func _ready() -> void:
		var key := "silhouettes:%d:%d:%d" % [seed_value, int(span), int(ground_y)]
		for copy in range(-1, 3):
			add_child(RectBake.bake_shared(key, _draw_copy.bind(0), Vector2(copy * span, 0.0)))

	func _draw_copy(canvas: Variant, copy: int) -> void:
		var far := Color8(15, 34, 34)
		var near := Color8(19, 45, 38)
		var ruin := Color8(24, 32, 60)
		var ox := copy * span
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value * 131 + 7
		# ruin pillars first, furthest back
		for i in 4:
			var x := ox + rng.randf_range(0.0, span)
			var h := rng.randf_range(90.0, 170.0)
			_rect(canvas, x, ground_y - h, 28.0, h + 400.0, ruin)
			_rect(canvas, x - 6.0, ground_y - h, 40.0, 8.0, ruin.lightened(0.08))
		# two rows of trees
		for row in 2:
			var colour := far if row == 0 else near
			var x := ox + rng.randf_range(0.0, 80.0)
			while x < ox + span:
				var h := rng.randf_range(140.0, 260.0) - row * 50.0
				var r := int(rng.randf_range(10.0, 17.0))
				_rect(canvas, x - 6.0, ground_y - h, 12.0, h + 400.0, colour)
				_disc(canvas, Vector2(x, ground_y - h), r, colour)
				_disc(canvas, Vector2(x - r * P * 0.7, ground_y - h + r * P * 0.4), maxi(r - 4, 5), colour)
				_disc(canvas, Vector2(x + r * P * 0.7, ground_y - h + r * P * 0.3), maxi(r - 5, 5), colour)
				x += rng.randf_range(110.0, 200.0)

	static func _rect(canvas: Variant, x: float, y: float, w: float, h: float, c: Color) -> void:
		canvas.draw_rect(Rect2(snappedf(x, P), snappedf(y, P), snappedf(w, P), snappedf(h, P)), c)

	static func _disc(canvas: Variant, center: Vector2, radius: int, c: Color) -> void:
		for dy in range(-radius, radius + 1):
			var half := int(sqrt(float(radius * radius - dy * dy)))
			_rect(canvas, center.x - half * P, center.y + dy * P, (half * 2 + 1) * P, P, c)


class Canopy extends Node2D:
	var span: float = 1440.0
	var parallax: float = 0.9
	var seed_value: int = 1
	var _time: float = 0.0
	var _vines: Array = []
	var _clumps: Array = []
	var _flies: Array = []
	## The leaves and vines are drawn once into these tiles (one per repeat)
	## and only slid sideways each frame. Redrawing them every frame was a
	## few thousand blocks of work per frame for something that never
	## changes. Only the fireflies below redraw.
	var _tiles: Array[Node2D] = []

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value * 977 + 3
		var x := 0.0
		while x < span:
			_clumps.append([x, rng.randf_range(-20.0, 26.0), int(rng.randf_range(9.0, 16.0))])
			x += rng.randf_range(60.0, 120.0)
		x = rng.randf_range(20.0, 80.0)
		while x < span:
			_vines.append([x, rng.randf_range(90.0, 260.0), rng.randf() < 0.5])
			x += rng.randf_range(90.0, 230.0)
		for i in 26:
			_flies.append([rng.randf_range(0.0, 1.0), rng.randf_range(0.15, 0.9), rng.randf_range(0.0, TAU)])
		# One bake, three sprites sharing it (it used to be baked three times).
		var key := "canopy:%d:%d" % [seed_value, int(span)]
		for i in 3:
			var tile := RectBake.bake_shared(key, _draw_tile)
			tile.show_behind_parent = true
			add_child(tile)
			_tiles.append(tile)
			PerfOverlay.track(tile, &"canopy")
		PerfOverlay.track(self, &"fireflies")

	func _fx_refresh() -> void:
		queue_redraw()

	func _process(delta: float) -> void:
		_time += delta
		var camera := get_viewport().get_camera_2d()
		var cam_x := camera.get_screen_center_position().x if camera != null else 0.0
		var shift := -fposmod(cam_x * parallax, span)
		for i in _tiles.size():
			_tiles[i].position.x = shift + span * i
		if PerfOverlay.fx_on(&"fireflies"):
			queue_redraw()

	## One repeat of the leaf frame: vines hanging from it, then the clumps.
	func _draw_tile(canvas: Variant) -> void:
		var ink := Color8(8, 22, 16)
		var body := Color8(14, 36, 26)
		var lit := Color8(24, 58, 38)
		var vine := Color8(58, 120, 46)
		var leaf := Color8(90, 163, 63)
		for v in _vines:
			var vx := snappedf(float(v[0]), P)
			var length := float(v[1])
			var y := 30.0
			while y < length:
				# A fixed gentle curve instead of a per-frame sway.
				var wobble := snappedf(sin(y * 0.03 + float(v[0])) * 3.0, P)
				canvas.draw_rect(Rect2(vx + wobble, y, P, P * 2.0), vine)
				if int(y / P) % 7 == 0:
					canvas.draw_rect(Rect2(vx + wobble + (P if bool(v[2]) else -P * 2.0), y, P * 2.0, P), leaf)
				y += P * 2.0
		for c in _clumps:
			_disc(canvas, Vector2(float(c[0]), float(c[1])), int(c[2]) + 1, ink)
		for c in _clumps:
			_disc(canvas, Vector2(float(c[0]), float(c[1])), int(c[2]), body)
			_disc(canvas, Vector2(float(c[0]) - P * 3.0, float(c[1]) + P * 2.0), int(c[2]) / 2, lit)

	## Fireflies only: 26 small squares.
	func _draw() -> void:
		if not PerfOverlay.fx_on(&"fireflies"):
			return
		var camera := get_viewport().get_camera_2d()
		var cam_x := camera.get_screen_center_position().x if camera != null else 0.0
		var view := get_viewport_rect().size
		for f in _flies:
			var fx := fposmod(float(f[0]) * view.x - cam_x * 0.4 + sin(_time * 0.5 + float(f[2])) * 30.0, view.x)
			var fy := float(f[1]) * view.y + cos(_time * 0.7 + float(f[2])) * 18.0
			var glow := 0.5 + 0.5 * sin(_time * 3.0 + float(f[2]) * 5.0)
			draw_rect(Rect2(snappedf(fx, P), snappedf(fy, P), P, P), Color(1.0, 0.9, 0.4, 0.35 + glow * 0.6))

	static func _disc(canvas: Variant, center: Vector2, radius: int, c: Color) -> void:
		for dy in range(-radius, radius + 1):
			var half := int(sqrt(float(radius * radius - dy * dy)))
			canvas.draw_rect(Rect2(snappedf(center.x - half * P, P), snappedf(center.y + dy * P, P), (half * 2 + 1) * P, P), c)


## A node that draws once through a painter callback. Godot skips it when it
## is off screen, and never redraws it unless asked.
class _Paint extends Node2D:
	var painter: Callable

	func _draw() -> void:
		painter.call(self)
