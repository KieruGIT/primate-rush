class_name Atmosphere
extends Node

# ============================================================
# ATMOSPHERE - the three things that sit between the level and the player.
#
# Every panel of the key art does the same two tricks, and neither of them is
# the level itself:
#   motes      - pollen and insects drifting in the light, so the frame moves
#                even when the monkeys do not
#   vignette   - corners falling into shade, which is what keeps the eye on
#                the middle of the screen
#
# The near foliage that frames the key art is *not* here: it is baked into
# JungleBackdrop's near layer, as pixels, with the rest of the jungle. Drawn
# here it would be smooth polygons over pixel art, which is the one thing
# this style cannot survive.
#
# They live on CanvasLayers between the world and the HUD (1-3; the HUD is 5,
# the touch pad 10) so they follow the camera for free and never cover a
# button. Nothing here takes input: every node is MOUSE_FILTER_IGNORE or not
# a Control at all.
# ============================================================

const MOTE_LAYER: int = 1
const VIGNETTE_LAYER: int = 3


## Builds the whole stack under `host`. Called once, by LevelSkin.
static func install(host: Node, seed_value: int, motes: bool = true) -> void:
	if motes:
		_layer(host, MOTE_LAYER).add_child(Motes.new(seed_value))
	var vignette := _vignette()
	_layer(host, VIGNETTE_LAYER).add_child(vignette)
	PerfOverlay.track(vignette, &"vignette")


static func _layer(host: Node, index: int) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = index
	host.add_child(layer)
	return layer


static func _vignette() -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.50)
	gradient.set_color(0, Color(JunglePalette.VIGNETTE, 0.0))
	gradient.add_point(0.72, Color(JunglePalette.VIGNETTE, 0.14))
	gradient.add_point(0.88, Color(JunglePalette.VIGNETTE, 0.28))
	gradient.set_offset(gradient.get_point_count() - 1, 1.0)
	gradient.set_color(gradient.get_point_count() - 1, Color(JunglePalette.VIGNETTE, 0.40))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	# Fine enough that its steps are a couple of art pixels, coarse enough
	# that it is not a smooth gradient. At 32 the steps were forty screen
	# pixels wide and the vignette read as a giant arch drawn over the sky.
	texture.width = 256
	texture.height = 256

	var rect := TextureRect.new()
	rect.texture = texture
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect


## Pollen in the light shafts, on slow loops. Screen space, so a long level
## does not need more of them and they never fall behind the camera.
## Drawn as square pixels at the art scale, never as circles.
class Motes extends Node2D:
	const COUNT: int = 22

	var _motes: Array = []      # [origin, radius, speed, phase, size]
	var _t: float = 0.0

	func _init(p_seed: int) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = p_seed * 17 + 3
		for i in COUNT:
			_motes.append([
				Vector2(rng.randf_range(-40.0, 1320.0), rng.randf_range(40.0, 700.0)),
				Vector2(rng.randf_range(18.0, 70.0), rng.randf_range(12.0, 44.0)),
				rng.randf_range(0.22, 0.62),
				rng.randf_range(0.0, TAU),
				rng.randf_range(1.5, 3.0),
			])

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		for mote in _motes:
			var origin: Vector2 = mote[0]
			var radius: Vector2 = mote[1]
			var speed: float = mote[2]
			var phase: float = mote[3]
			var size: float = mote[4]
			var at := origin + Vector2(
				cos(_t * speed + phase) * radius.x,
				sin(_t * speed * 1.37 + phase) * radius.y
			)
			# Each one breathes on its own clock, and a few are dark at any
			# moment, which is what makes them read as insects.
			var pulse := 0.55 + 0.45 * sin(_t * (1.4 + speed) + phase * 2.0)
			# Snapped to the art grid and drawn as a square: a mote is one
			# pixel of pollen catching the light, not a little sphere.
			var px := (at / 2.0).floor() * 2.0
			var side := ceilf(size * 0.5) * 2.0
			draw_rect(Rect2(px, Vector2(side, side)), Color(JunglePalette.MOTE, 0.75 * pulse))
