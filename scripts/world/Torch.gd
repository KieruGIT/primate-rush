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
## Only a torch the camera can see animates. A level has fifteen of them and
## each redraws a few dozen shapes, which was being paid for every frame.
var _on_screen: bool = false


func _ready() -> void:
	z_index = 3
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_t = phase
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(-reach * scale_factor, -reach * scale_factor, reach * 2.0 * scale_factor, reach * 2.0 * scale_factor)
	notifier.screen_entered.connect(func() -> void: _on_screen = true)
	notifier.screen_exited.connect(func() -> void: _on_screen = false)
	add_child(notifier)
	PerfOverlay.track(self, &"torch_glow")


func _fx_refresh() -> void:
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	# 0.78..1.0, never dark, never a strobe.
	# Quantised to whole art pixels. A flame whose radius is 13.4 pixels one
	# frame and 13.9 the next is a flame whose edge never lands on the grid.
	if not _on_screen:
		return
	var raw := 0.89 + sin(_t * 9.3) * 0.07 + sin(_t * 3.7) * 0.04
	var next := roundf(raw * 8.0) / 8.0
	# The flicker is quantised to eighths, so most frames it has not moved:
	# redraw only when it actually changes.
	if next != _flicker:
		_flicker = next
		queue_redraw()


func _draw() -> void:
	var s := scale_factor
	var flame_at := Vector2(0.0, -34.0 * s)
	# _draw_flame works in torch-local space, so `at` is only the glow anchor.
	_draw_pool(flame_at)
	_draw_post(s)
	_draw_flame(flame_at, s)


## The light on the world: one wide soft pool and a tighter warmer one
## inside it. Both are the shared glow ramp - flat circles at this size read
## as painted rings, which is exactly what a torch must not look like.
func _draw_pool(at: Vector2) -> void:
	if not PerfOverlay.fx_on(&"torch_glow"):
		return
	var r := reach * _flicker
	JunglePalette.draw_glow(self, at, r, JunglePalette.torchlight(0.42))
	JunglePalette.draw_glow(self, at, r * 0.45, Color(JunglePalette.FLAME, 0.30 * _flicker))


func _draw_post(s: float) -> void:
	var dark := JunglePalette.BARK
	var light := JunglePalette.BARK_LIGHT
	# Every edge a whole number of art pixels from the torch's own position,
	# which the skin already snapped to the grid.
	_block(-4.0 * s, -30.0 * s, 8.0 * s, 30.0 * s, dark)
	_block(-4.0 * s, -30.0 * s, 4.0 * s, 30.0 * s, light)
	_block(-8.0 * s, -34.0 * s, 16.0 * s, 6.0 * s, dark)
	_block(-8.0 * s, -34.0 * s, 16.0 * s, 2.0 * s, JunglePalette.EMBER)


## A rectangle rounded onto the art grid.
func _block(x: float, y: float, w: float, h: float, color: Color) -> void:
	var g := float(JunglePalette.ART_PIXEL)
	var a := (Vector2(x, y) / g).round() * g
	var b := (Vector2(x + w, y + h) / g).round() * g
	draw_rect(Rect2(a, b - a), color)


## `at` is the bowl; the rows are drawn relative to it through _block, so
## they inherit the same grid rounding as the post.
func _draw_flame(at: Vector2, s: float) -> void:
	var f := _flicker
	JunglePalette.draw_glow(self, at + Vector2(0.0, -7.0 * s * f), 26.0 * s * f, Color(JunglePalette.FLAME_CORE, 0.55))
	# The flame is a stack of rows, widest in the middle and pinched at the
	# tip, rather than two circles and a triangle. Circles and polygons are
	# vector calls: their edges land wherever the maths puts them, which on
	# pixel art reads as a smudge of light rather than a flame.
	var rows := 7
	var lean := roundf(sin(_t * 5.1) * 1.5)
	for i in rows:
		var t := float(i) / float(rows - 1)
		var half := roundf((1.0 - t) * 3.0 + sin(t * PI) * 1.5) + 1.0
		var tone := JunglePalette.FLAME if t < 0.55 else JunglePalette.FLAME_CORE
		_block(
			(-half + lean * t) * 2.0 * s, (-6.0 - 16.0 * t * f) * s,
			half * 4.0 * s, 3.0 * s, tone)
