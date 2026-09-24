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
	&"grapple_dash": ["GRAPPLE SLAM", Color8(255, 200, 58)],
	&"air_launch": ["SKY LAUNCH", Color8(120, 200, 255)],
	&"counter_roll": ["COUNTER ROLL", Color8(110, 220, 130)],
	&"long_arm": ["LONG ARM", Color8(255, 140, 90)],
	&"snatch": ["SNATCH", Color8(255, 110, 200)],
}

## What each skill does, for the monkey select page. Plain sentences.
const DESCRIPTIONS: Dictionary = {
	&"grapple_dash": "Lunge forward. Catch a monkey, lift it over your head and slam it into the ground. Hold up to grapple onto a ledge instead.",
	&"air_launch": "Blast off the way you aim, even from the ground. Anyone standing next to you gets blown away.",
	&"counter_roll": "Curl into a ball and roll. Bowls over anyone in the way, and a hit taken mid-roll stuns the attacker.",
	&"long_arm": "Wind up, then throw a giant punch across the screen. Miss everyone and the arm grabs the terrain and pulls you there.",
	&"snatch": "Dash straight through a monkey and rob it: bananas if it has some, its speed if not.",
}

## burst: the skill firing. popup: a word over someone. slam: a ground hit.
var kind: StringName = &"burst"
var life: float = LIFE

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


static func description_of(skill_id: StringName) -> String:
	return String(DESCRIPTIONS.get(skill_id, ""))


## A word that pops up over a monkey and floats away: GOTCHA!, POW!...
static func popup(parent: Node, at: Vector2, text: String, tint: Color) -> void:
	_spawn(parent, at, &"popup", text, tint)


## A heavy hit on the ground: a flat shockwave, dust and SLAM!
static func slam(parent: Node, at: Vector2, tint: Color) -> void:
	_spawn(parent, at, &"slam", "SLAM!", tint)


static func _spawn(parent: Node, at: Vector2, what: StringName, text: String, tint: Color) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var fx: Node2D = (load(PATH) as Script).new()
	fx.set(&"kind", what)
	fx.set(&"colour", tint)
	fx.set(&"label", text)
	fx.set(&"life", 0.85)
	fx.global_position = at
	fx.z_index = 21
	parent.add_child(fx)


## A pixel icon for a skill, drawn into any canvas (HUD card, touch button,
## monkey select). `s` is the icon's half size.
static func draw_icon(canvas: CanvasItem, skill_id: StringName, at: Vector2, s: float, tint: Color = Color.WHITE) -> void:
	var ink := Color(0.1, 0.06, 0.04, tint.a)
	var p := maxf(roundf(s / 6.0), 2.0)
	var cells: Array = []
	match skill_id:
		&"grapple_dash":
			# A fist lifting over an arrow slamming down.
			cells = ["..XXXX..", ".XXXXXX.", ".XXXXXX.", "..XXXX..", "...XX...", "X..XX..X", ".X.XX.X.", "..XXXX..", "...XX..."]
		&"air_launch":
			cells = ["...XX...", "..XXXX..", ".XXXXXX.", "XXXXXXXX", "...XX...", ".X.XX.X.", "X..XX..X", "...XX...", "...XX..."]
		&"counter_roll":
			cells = ["..XXXX..", ".XX..XX.", "XX.XX.XX", "X.X..X.X", "X.X..X.X", "XX.XX.XX", ".XX..XX.", "..XXXX.."]
		&"long_arm":
			cells = [".........", "......XXX", "XXXXXXXXX", "XXXXXXXXX", "......XXX", "........."]
		&"snatch":
			cells = ["X.X.X...", "XXXXX...", "XXXXX.XX", ".XXX.XXX", ".XXX.XX.", "....XX..", "...XX...", "..XX...."]
		_:
			cells = ["XXXX", "XXXX", "XXXX", "XXXX"]
	var rows := cells.size()
	var cols := String(cells[0]).length()
	var origin := at - Vector2(cols, rows) * p * 0.5
	for pass_index in 2:
		for y in rows:
			var line := String(cells[y])
			for x in cols:
				if line[x] != "X":
					continue
				var rect := Rect2(origin + Vector2(x, y) * p, Vector2(p, p))
				if pass_index == 0:
					canvas.draw_rect(rect.grow(p * 0.5), ink)
				else:
					canvas.draw_rect(rect, tint)


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
	copy.material = sprite.material
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
	if _age >= life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := _age / life
	var fade := 1.0 - k
	if kind == &"popup":
		_draw_word(label, 18, Vector2(0.0, -k * 40.0), clampf(fade * 2.0, 0.0, 1.0), 1.0 + (0.3 * (1.0 - minf(k * 6.0, 1.0))))
		return
	if kind == &"slam":
		_draw_slam(k, fade)
		return
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
	_draw_word(label, 16, Vector2(0.0, -70.0 - k * 34.0), clampf(fade * 1.6, 0.0, 1.0), 1.0)


## A flat shockwave along the ground, chunks of dirt thrown up, SLAM!
func _draw_slam(k: float, fade: float) -> void:
	var w := lerpf(30.0, 150.0, 1.0 - pow(1.0 - k, 3.0))
	for ring in 2:
		var rx := w * (1.0 - ring * 0.35)
		var ry := rx * 0.22
		var points := PackedVector2Array()
		for i in 33:
			var a := TAU * i / 32.0
			points.append(Vector2(cos(a) * rx, sin(a) * ry))
		draw_polyline(points, Color(0.08, 0.05, 0.04, 0.6 * fade), 10.0 * fade + 2.0)
		draw_polyline(points, Color(colour if ring == 0 else Color.WHITE, 0.9 * fade), 6.0 * fade + 1.0)
	for spark in _sparks:
		var dir: Vector2 = spark[0]
		dir = Vector2(dir.x, -absf(dir.y) - 0.3).normalized()
		var at: Vector2 = dir * float(spark[1]) * 0.6 * k + Vector2(0.0, 300.0 * k * k)
		at = (at / 4.0).round() * 4.0
		draw_rect(Rect2(at - Vector2(5, 5), Vector2(10, 10)), Color(0.45, 0.3, 0.18, fade))
	_draw_word(label, 26, Vector2(0.0, -90.0 - k * 30.0), clampf(fade * 2.0, 0.0, 1.0), 1.0 + 0.4 * (1.0 - minf(k * 5.0, 1.0)))


func _draw_word(text: String, size_px: int, offset: Vector2, alpha: float, grow: float) -> void:
	var font := ThemeDB.fallback_font
	var ui := UiTheme._font(UiTheme.FONT_DISPLAY)
	if ui != null:
		font = ui
	var px := int(round(size_px * grow))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var pos := offset + Vector2(-width * 0.5, 0.0)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 8, Color(0.08, 0.05, 0.04, alpha))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(colour.lightened(0.2), alpha))
