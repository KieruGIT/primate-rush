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
	# Close to the level's own leaves, just a shade deeper, so the canopy
	# reads as the same trees as the ones you stand on.
	const LEAF_INK := Color8(14, 40, 28)
	const LEAF_DEEP := Color8(26, 66, 40)
	const LEAF_SHADOW := Color8(22, 58, 36)
	const LEAF_MID := Color8(40, 98, 42)
	const LEAF_LIT := Color8(70, 142, 56)
	const LEAF_BRIGHT := Color8(110, 178, 72)
	## Thickness of the leaf band, underside to the lumpy top edge. Above it
	## the night sky shows through.
	const BAND: float = 230.0
	## How far the trunks reach down from the underside: past any ground or
	## water, which the level then draws over.
	const TRUNK_DROP: float = 1500.0
	const BARK := Color8(78, 52, 30)
	const BARK_DARK := Color8(54, 36, 22)
	const BARK_LIT := Color8(102, 68, 38)
	const BARK_FAR := Color8(34, 30, 34)
	const BARK_FAR_LIT := Color8(46, 40, 42)
	var span: float = 1440.0
	## 1.0: the canopy moves with the level, so the things hanging from it
	## stay attached and it reads as right there, not far off.
	var parallax: float = 1.0
	var seed_value: int = 1
	## Where the leaf tiles go, and the world height of their top edge.
	## Set by LevelSkin: a camera-following layer, so the frame stays put
	## in the level. Unset, the tiles ride along at the top of the screen.
	var tile_host: Node2D = null
	var anchor_y: float = 0.0
	var _time: float = 0.0
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
			_clumps.append([x, rng.randf_range(-6.0, 30.0), int(rng.randf_range(9.0, 16.0))])
			x += rng.randf_range(44.0, 90.0)
		for i in 26:
			_flies.append([rng.randf_range(0.0, 1.0), rng.randf_range(0.15, 0.9), rng.randf_range(0.0, TAU)])
		# One bake, three sprites sharing it (it used to be baked three times).
		var key := "canopy5:%d:%d" % [seed_value, int(span)]
		for i in 3:
			var tile := RectBake.bake_shared(key, _draw_tile)
			tile.show_behind_parent = true
			if tile_host != null:
				tile_host.add_child(tile)
			else:
				add_child(tile)
			_tiles.append(tile)
			PerfOverlay.track(tile, &"canopy")
		PerfOverlay.track(self, &"fireflies")
		process_priority = 1000

	func _fx_refresh() -> void:
		queue_redraw()

	func _process(delta: float) -> void:
		_time += delta
		var camera := get_viewport().get_camera_2d()
		var cam_x := camera.get_screen_center_position().x if camera != null else 0.0
		var shift := -fposmod(cam_x * parallax, span)
		if tile_host != null:
			# Screen left edge in world x, so the same shift lands the same.
			var half_w := get_viewport_rect().size.x * 0.5
			tile_host.position = Vector2(roundf(cam_x - half_w), anchor_y)
		for i in _tiles.size():
			_tiles[i].position.x = shift + span * (i - 1)
		if PerfOverlay.fx_on(&"fireflies"):
			queue_redraw()

	## One repeat of the canopy: trunks rising out of the dark into a thick
	## band of leaves, lumpy on top and underneath. Background only: nothing
	## here can be held, and nothing hangs down looking like it could be.
	func _draw_tile(canvas: Variant) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value * 613 + 11
		# A far row first: thin, dark trunks close together, the depth of the
		# forest behind the main trees.
		var fx := rng.randf_range(10.0, 60.0)
		while fx < span:
			var fw := snappedf(rng.randf_range(12.0, 20.0), P)
			var ftx := snappedf(fx, P)
			canvas.draw_rect(Rect2(ftx - fw * 0.5, -BAND * 0.4, fw, TRUNK_DROP + BAND * 0.4), BARK_FAR)
			canvas.draw_rect(Rect2(ftx - fw * 0.5, -BAND * 0.4, P, TRUNK_DROP + BAND * 0.4), BARK_FAR_LIT)
			fx += rng.randf_range(70.0, 150.0)
		# Then the main trunks, so the leaves sit over their tops.
		var x := rng.randf_range(40.0, 160.0)
		while x < span:
			var w := snappedf(rng.randf_range(22.0, 38.0), P)
			var tx := snappedf(x, P)
			canvas.draw_rect(Rect2(tx - w * 0.5 - P, -BAND * 0.5, w + P * 2.0, TRUNK_DROP + BAND * 0.5), BARK_DARK)
			canvas.draw_rect(Rect2(tx - w * 0.5, -BAND * 0.5, w, TRUNK_DROP + BAND * 0.5), BARK)
			canvas.draw_rect(Rect2(tx - w * 0.5 + P, -BAND * 0.5, P, TRUNK_DROP + BAND * 0.5), BARK_LIT)
			# Bark: short dark marks down the trunk.
			var y := 40.0
			while y < TRUNK_DROP:
				canvas.draw_rect(Rect2(tx + snappedf(rng.randf_range(-w * 0.3, w * 0.2), P), y, P, P * 3.0), BARK_DARK)
				y += rng.randf_range(40.0, 90.0)
			# A branch or two climbing into the leaves.
			for b in 2:
				var side := -1.0 if b == 0 else 1.0
				var by := rng.randf_range(10.0, 60.0)
				for k in 10:
					canvas.draw_rect(Rect2(tx + side * (w * 0.4 + k * P * 1.5), by - k * P * 1.2, P * 2.0, P * 2.0), BARK)
			x += rng.randf_range(150.0, 280.0)
		# The leaf mass, mottled so it reads as leaves.
		canvas.draw_rect(Rect2(-P * 20.0, -BAND, span + P * 40.0, BAND), LEAF_DEEP)
		for i in int(span / 14.0):
			var at := Vector2(rng.randf_range(0.0, span), rng.randf_range(-BAND + 10.0, -10.0))
			_disc(canvas, at, int(rng.randf_range(3.0, 7.0)), LEAF_MID if rng.randf() < 0.6 else LEAF_SHADOW)
		# The top edge: big round crowns catching the moonlight.
		x = 0.0
		while x < span:
			var r := int(rng.randf_range(10.0, 18.0))
			var top := Vector2(x, -BAND + rng.randf_range(0.0, 30.0))
			_disc(canvas, top, r + 1, LEAF_INK)
			_disc(canvas, top, r, LEAF_MID)
			_disc(canvas, top + Vector2(-P * 2.0, -P * 2.0), maxi(r - 4, 3), LEAF_LIT)
			_disc(canvas, top + Vector2(-P * 3.0, -P * 4.0), maxi(r / 3, 2), LEAF_BRIGHT)
			x += rng.randf_range(50.0, 100.0)
		# The underside: overlapping clumps, outline first, then body, then a
		# lit top-left and a few bright leaf tips.
		for c in _clumps:
			_disc(canvas, Vector2(float(c[0]), float(c[1])), int(c[2]) + 1, LEAF_INK)
		for c in _clumps:
			var at := Vector2(float(c[0]), float(c[1]))
			var r := int(c[2])
			_disc(canvas, at, r, LEAF_MID)
			_disc(canvas, at + Vector2(-P * 2.0, -P * 2.0), maxi(r - 3, 3), LEAF_LIT)
			_disc(canvas, at + Vector2(-P * 3.0, -P * 3.0), maxi(r / 3, 2), LEAF_BRIGHT)
			for k in 3:
				var tip := at + Vector2(rng.randf_range(-r, r) * P * 0.8, r * P - P)
				canvas.draw_rect(Rect2(snappedf(tip.x, P), snappedf(tip.y, P), P * 2.0, P * 2.0), LEAF_LIT)

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
