class_name Torch
extends Node2D

# ============================================================
# TORCH - a warm light in a cold jungle.
#
# The key art puts torches wherever it wants the eye: flanking the start
# banner, up the temple steps, either side of the podium. They are the only
# warm thing in frame, so they are what the player looks at. Here they do the
# same job on the levels: one every few hundred pixels along a ground, and a
# pair on the finish line.
#
# Drawn, not lit. A real PointLight2D would need a CanvasModulate dark enough
# to make the unlit rest of the level unreadable, and every prop in the game
# would then need a light mask and a normal map to look like anything. A
# painted pool of light costs one draw call, reads the same at this pixel
# size, and can never turn the arena black on a renderer we did not test.
#
# The flicker is two sine waves at unrelated speeds, so it never visibly
# repeats, plus a per-torch phase so a row of them does not pulse in unison.
# ============================================================

## World radius of the light pool on the ground.
@export var reach: float = 170.0
## Scales the whole fixture. 1.0 is a wall torch, 1.4 a finish-line brazier.
@export var scale_factor: float = 1.0
## Staggers this torch against its neighbours.
@export var phase: float = 0.0

var _t: float = 0.0
var _flicker: float = 1.0


func _ready() -> void:
	z_index = 3
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_t = phase


func _process(delta: float) -> void:
	_t += delta
	# 0.78..1.0, never dark, never a strobe.
	_flicker = 0.89 + sin(_t * 9.3) * 0.07 + sin(_t * 3.7) * 0.04
	queue_redraw()


func _draw() -> void:
	var s := scale_factor
	var flame_at := Vector2(0.0, -34.0 * s)
	_draw_pool(flame_at)
	_draw_post(s)
	_draw_flame(flame_at, s)


## The light on the world: one wide soft pool and a tighter warmer one
## inside it. Both are the shared glow ramp - flat circles at this size read
## as painted rings, which is exactly what a torch must not look like.
func _draw_pool(at: Vector2) -> void:
	var r := reach * _flicker
	JunglePalette.draw_glow(self, at, r, JunglePalette.torchlight(0.42))
	JunglePalette.draw_glow(self, at, r * 0.45, Color(JunglePalette.FLAME, 0.30 * _flicker))


func _draw_post(s: float) -> void:
	var dark := JunglePalette.BARK
	var light := JunglePalette.BARK_LIGHT
	# Square pixels: the post is 6 art pixels wide at 2x, like everything else.
	draw_rect(Rect2(-4.0 * s, -30.0 * s, 8.0 * s, 30.0 * s), dark)
	draw_rect(Rect2(-4.0 * s, -30.0 * s, 4.0 * s, 30.0 * s), light)
	# Binding under the bowl, and the bowl itself.
	draw_rect(Rect2(-8.0 * s, -34.0 * s, 16.0 * s, 6.0 * s), dark)
	draw_rect(Rect2(-8.0 * s, -34.0 * s, 16.0 * s, 2.0 * s), JunglePalette.EMBER)


func _draw_flame(at: Vector2, s: float) -> void:
	var f := _flicker
	# Halo, body, core - biggest and softest first, so the core stays crisp.
	JunglePalette.draw_glow(self, at + Vector2(0.0, -7.0 * s * f), 26.0 * s * f, Color(JunglePalette.FLAME_CORE, 0.55))
	draw_circle(at + Vector2(0.0, -7.0 * s * f), 8.0 * s * f, JunglePalette.FLAME)
	draw_circle(at + Vector2(0.0, -9.0 * s * f), 4.0 * s * f, JunglePalette.FLAME_CORE)
	# A tongue of flame leaning with the flicker, so it is not a bead.
	var lean := sin(_t * 5.1) * 4.0 * s
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(-5.0 * s, -6.0 * s),
		at + Vector2(lean, -22.0 * s * f),
		at + Vector2(5.0 * s, -6.0 * s),
	]), Color(JunglePalette.FLAME, 0.9))
