class_name SlapBurst
extends Node2D

# ============================================================
# SLAP BURST - the flash where a hand lands.
#
# Replaces the old hit-arc indicator. Kept small and short: a hard white
# crack of light and a few chips, not a comic caption, so a slap reads as
# a real impact. The starburst is rasterised once into
# a small image at art resolution and drawn NEAREST at the art pixel size,
# so it sits on the same grid as everything else instead of being a smooth
# vector shape pasted over pixel art. Everything about it is time based and
# self-freeing: spawn it and forget it.
# ============================================================

const LIFE := 0.24
const FLASH := 0.04
## Art pixels. The big one is for slaps that will send someone flying.
const SIZE_NORMAL := Vector2i(26, 22)
const SIZE_BIG := Vector2i(38, 30)
const SPIKES := 8
const DEBRIS := 6

static var _textures: Dictionary = {}

var _big: bool = false
var _age: float = 0.0
var _star: Sprite2D
var _flash: Sprite2D
var _debris: Array[Vector2] = []


static func spawn(parent: Node, at: Vector2, big: bool) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var burst := SlapBurst.new()
	burst._big = big
	burst.position = (at / JunglePalette.ART_PIXEL).round() * JunglePalette.ART_PIXEL
	burst.z_index = 30
	parent.add_child(burst)


func _ready() -> void:
	var px := float(JunglePalette.ART_PIXEL)
	_star = Sprite2D.new()
	_star.texture = _texture(_big, false)
	_star.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_star.scale = Vector2(px, px)
	add_child(_star)
	_flash = Sprite2D.new()
	_flash.texture = _texture(_big, true)
	_flash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_flash.scale = Vector2(px, px)
	add_child(_flash)

	# Chips of light flung outward. Fixed angles with a little spread, not
	# random, so every machine in a match sees the same burst.
	for i in DEBRIS:
		var angle := TAU * float(i) / DEBRIS + 0.3 * sin(float(i) * 2.3)
		_debris.append(Vector2.from_angle(angle))


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	_flash.visible = _age < FLASH
	_star.visible = not _flash.visible
	# A hard two-pixel shake for the first frames, then still. Whole pixels
	# only, so the burst never lands between grid lines.
	var px := float(JunglePalette.ART_PIXEL)
	var shake := Vector2.ZERO
	if _age < 0.12:
		var k := int(_age * 60.0)
		shake = Vector2(px if k % 2 == 0 else -px, px if k % 3 == 0 else 0.0)
	_star.position = shake
	_flash.position = shake
	# Stepped fade over the last third: three levels, never a smooth ramp.
	var left := 1.0 - _age / LIFE
	modulate.a = 1.0 if left > 0.33 else (0.66 if left > 0.16 else 0.33)
	queue_redraw()


func _draw() -> void:
	var px := float(JunglePalette.ART_PIXEL)
	var t := _age / LIFE
	var radius := lerpf(8.0, 26.0 if _big else 18.0, sqrt(t)) * px
	for i in _debris.size():
		var at := (_debris[i] * radius / px).round() * px
		# Alternate chips: a three-pixel one with an outline, a bare one.
		if i % 2 == 0:
			draw_rect(Rect2(at - Vector2(px, px), Vector2(px, px) * 3.0), JunglePalette.OUTLINE)
			draw_rect(Rect2(at, Vector2(px, px)), JunglePalette.BANANA_LIGHT)
		else:
			draw_rect(Rect2(at, Vector2(px, px)), JunglePalette.BANANA)


## The flash, built once per size. Thin spikes of alternating length, a
## white-hot core fading through pale yellow; no outline, because light
## does not have one. flash is the brighter first frame.
static func _texture(big: bool, flash: bool) -> ImageTexture:
	var key := "%s_%s" % [big, flash]
	if _textures.has(key):
		return _textures[key]
	var size: Vector2i = SIZE_BIG if big else SIZE_NORMAL
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var center := Vector2(size) * 0.5
	var outer := Vector2(size) * 0.5 - Vector2(1, 1)
	for y in size.y:
		for x in size.x:
			var offset := (Vector2(x, y) + Vector2(0.5, 0.5) - center) / outer
			var reach := _star_radius(offset.angle())
			var r := offset.length()
			if r > reach:
				continue
			var colour: Color
			if flash or r < reach * 0.45:
				colour = JunglePalette.FLAME_CORE
			elif r < reach * 0.75:
				colour = JunglePalette.BANANA_LIGHT
			else:
				colour = Color(JunglePalette.BANANA, 0.8)
			image.set_pixel(x, y, colour)
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


## Radius of the star at an angle, 0..1 of the ellipse. Long and short
## spikes alternate, and the long ones vary so it reads hand-drawn rather
## than like a gear.
static func _star_radius(angle: float) -> float:
	var sector := TAU / SPIKES
	var a := fposmod(angle + sector * 0.5, TAU)
	var index := int(a / sector)
	var along := (a - index * sector) / sector      # 0..1 across one spike
	var tip := 1.0 if index % 2 == 0 else 0.62
	tip -= 0.06 * float((index * 7) % 3)
	var valley := 0.22
	return lerpf(valley, tip, 1.0 - absf(along - 0.5) * 2.0)
