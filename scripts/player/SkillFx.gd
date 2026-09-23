extends Node2D

# Loaded with preload() by its users rather than a class_name, so it works
# before the editor has rescanned global classes.
const PATH := "res://scripts/player/SkillFx.gd"

# ============================================================
# SKILL FX - what a skill looks like when it fires.
#
#   burst   a coloured shockwave ring, a few pixel sparks, and the skill's
#           name popping up over the monkey. Spawned on every machine that
#           sees the skill (the one that fired it, and remote copies when
#           the monkey's state turns to DASH).
#   ghost   an afterimage of the sprite in the skill's colour, dropped every
#           few frames while a skill carries the monkey, fading out behind.
#
# Each skill has one colour, used here, on the HUD cooldown card and on the
# touch button, so a colour on screen always means the same skill.
# ============================================================

const INFO: Dictionary = {
	&"grapple_dash": ["GRAPPLE", Color8(255, 200, 58)],
	&"air_launch": ["LAUNCH", Color8(120, 200, 255)],
	&"counter_roll": ["COUNTER ROLL", Color8(110, 220, 130)],
	&"long_arm": ["LONG ARM", Color8(255, 140, 90)],
	&"snatch": ["SNATCH", Color8(255, 110, 200)],
}

const LIFE: float = 0.55

var colour: Color = Color.WHITE
var label: String = ""
var _age: float = 0.0
var _sparks: Array = []


static func colour_of(skill_id: StringName) -> Color:
	return (INFO.get(skill_id, ["", Color.WHITE]) as Array)[1]


static func name_of(skill_id: StringName) -> String:
	var fallback := String(skill_id).replace("_", " ").to_upper()
	return String((INFO.get(skill_id, [fallback, Color.WHITE]) as Array)[0])


static func burst(parent: Node, at: Vector2, skill_id: StringName) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var fx: Node2D = (load(PATH) as Script).new()
	fx.set(&"colour", colour_of(skill_id))
	fx.set(&"label", name_of(skill_id))
	fx.global_position = at
	fx.z_index = 20
	parent.add_child(fx)


static func ghost(parent: Node, sprite: Sprite2D, tint: Color) -> void:
	if parent == null or sprite == null or sprite.texture == null:
		return
	var copy := Sprite2D.new()
	copy.texture = sprite.texture
	copy.hframes = sprite.hframes
	copy.vframes = sprite.vframes
	copy.frame = sprite.frame
	copy.centered = sprite.centered
	copy.offset = sprite.offset
	copy.flip_h = sprite.flip_h
	copy.scale = sprite.global_scale
	copy.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	copy.modulate = Color(tint.r, tint.g, tint.b, 0.55)
	copy.z_index = -1
	parent.add_child(copy)
	copy.global_position = sprite.global_position
	var tween := copy.create_tween()
	tween.tween_property(copy, "modulate:a", 0.0, 0.22)
	tween.tween_callback(copy.queue_free)


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 10:
		var angle := rng.randf_range(0.0, TAU)
		_sparks.append([Vector2.from_angle(angle), rng.randf_range(160.0, 320.0)])


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := _age / LIFE
	var fade := 1.0 - k
	# Shockwave: a thick ring racing out, then a thin one behind it.
	var r := lerpf(18.0, 96.0, 1.0 - pow(1.0 - k, 3.0))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0.08, 0.05, 0.04, 0.6 * fade), 9.0 * fade + 2.0)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(colour, 0.9 * fade), 6.0 * fade + 1.0)
	draw_arc(Vector2.ZERO, r * 0.6, 0.0, TAU, 32, Color(1, 1, 1, 0.7 * fade), 2.0)
	# Square sparks, on the pixel grid.
	for spark in _sparks:
		var at: Vector2 = (spark[0] as Vector2) * float(spark[1]) * k * (1.0 - k * 0.4)
		at = (at / 4.0).round() * 4.0
		var size := 8.0 if k < 0.5 else 4.0
		draw_rect(Rect2(at - Vector2(size, size) * 0.5, Vector2(size, size)), Color(colour.lightened(0.3), fade))
	# The skill's name, rising and fading above the head.
	var font := ThemeDB.fallback_font
	var ui := UiTheme._font(UiTheme.FONT_DISPLAY)
	if ui != null:
		font = ui
	var size_px := 16
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var pos := Vector2(-width * 0.5, -70.0 - k * 34.0)
	var alpha := clampf(fade * 1.6, 0.0, 1.0)
	draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 8, Color(0.08, 0.05, 0.04, alpha))
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(colour.lightened(0.2), alpha))
