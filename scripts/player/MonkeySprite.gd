class_name MonkeySprite
extends Sprite2D

# ============================================================
# MONKEY SPRITE - a full-body pixel monkey, rigged and drawn at runtime.
#
# Same idea as MonkeyPortrait, one step further. A face can be an ASCII
# template; a body with fourteen poses cannot, not without fourteen hand
# drawings that drift apart the first time someone tweaks an arm. So each
# pose is a handful of joint angles, the limbs are rasterised as fat pixel
# lines, and every part gets its own one-pixel outline before it is laid
# over the parts behind it. That last step is what makes it read as pixel
# art rather than as a stick figure: a front arm is outlined against the
# body it crosses.
#
# Proportions are per species, so the roster reads by silhouette - broad
# gorilla, long-armed gibbon, tailed capuchin - at one pixel size (2x) for
# everyone. No fractional scaling, no uneven pixels.
#
# Facing right in the sheet. The player flips it.
# ============================================================

const CANVAS: int = 48
## World pixels per art pixel.
const PIXEL: float = 2.0

enum { EMPTY, OUTLINE, FUR, SHADE, FACE, EYE, PUPIL, NOSE, BELLY }

## Side-on head, facing right, fill only - the outline is computed.
## f fur  d shade  m face  e eye  p pupil  n nose/mouth
const HEAD: Array[String] = [
	"....fffff....",
	"..fffffffff..",
	".fffffffffff.",
	"fffffffffmmm.",
	"fmmffffmmmmm.",
	"fmdfffmmepmmm",
	".ffffffmmmmmn",
	".dfffffmmmmn.",
	"..ddffffmnm..",
	"....ffffff...",
]
## Where the neck joins, in HEAD coordinates.
const HEAD_NECK := Vector2(5.5, 9.0)

## torso: length and half-width. arm, leg: segment lengths (upper, lower).
## limb: limb radius. tail: length in pixels, 0 for apes, who have none.
const BUILDS: Dictionary = {
	&"capuchin": {"torso": 8.0, "girth": 3.5, "arm": Vector2(5, 5), "leg": Vector2(4, 4), "limb": 1.2, "tail": 16},
	&"gibbon": {"torso": 8.0, "girth": 3.5, "arm": Vector2(8, 8), "leg": Vector2(5, 5), "limb": 1.2, "tail": 0},
	&"macaque": {"torso": 10.0, "girth": 4.5, "arm": Vector2(6, 6), "leg": Vector2(6, 5), "limb": 1.5, "tail": 8},
	&"orangutan": {"torso": 12.0, "girth": 6.0, "arm": Vector2(9, 9), "leg": Vector2(5, 5), "limb": 1.8, "tail": 0},
	&"gorilla": {"torso": 14.0, "girth": 7.0, "arm": Vector2(8, 8), "leg": Vector2(6, 6), "limb": 2.2, "tail": 0},
}
const DEFAULT_BUILD := {"torso": 10.0, "girth": 4.5, "arm": Vector2(6, 6), "leg": Vector2(6, 5), "limb": 1.5, "tail": 8}

## Joint angles in degrees. 0 points down, +90 forward, 180 up, -90 back.
## Each limb is [upper, lower]. lean tips the torso forward, bob drops the
## upper body a pixel, eyes is open / shut / dizzy.
const POSES: Dictionary = {
	&"idle_0": {"fa": [24, 36], "ba": [-16, -4], "fl": [6, 0], "bl": [-8, 0], "lean": 4, "bob": 0, "tail": 0.0},
	&"idle_1": {"fa": [22, 32], "ba": [-14, -2], "fl": [6, 0], "bl": [-8, 0], "lean": 4, "bob": 1, "tail": 0.25},
	&"blink": {"fa": [24, 36], "ba": [-16, -4], "fl": [6, 0], "bl": [-8, 0], "lean": 4, "bob": 0, "tail": 0.0, "eyes": "shut"},
	&"run_0": {"fa": [-40, -10], "ba": [45, 95], "fl": [40, 10], "bl": [-35, -80], "lean": 14, "bob": 0, "tail": 0.6},
	&"run_1": {"fa": [-10, 30], "ba": [15, 70], "fl": [15, -40], "bl": [-5, -10], "lean": 14, "bob": -1, "tail": 0.3},
	&"run_2": {"fa": [45, 95], "ba": [-40, -10], "fl": [-35, -80], "bl": [40, 10], "lean": 14, "bob": 0, "tail": 0.6},
	&"run_3": {"fa": [15, 70], "ba": [-10, 30], "fl": [-5, -10], "bl": [15, -40], "lean": 14, "bob": -1, "tail": 0.3},
	&"jump": {"fa": [150, 170], "ba": [125, 155], "fl": [75, -20], "bl": [25, -50], "lean": 6, "bob": -1, "tail": -0.4},
	&"fall": {"fa": [140, 100], "ba": [-140, -100], "fl": [25, 5], "bl": [-15, 10], "lean": 0, "bob": 0, "tail": 0.8},
	&"climb_0": {"fa": [165, 175], "ba": [105, 150], "fl": [65, -25], "bl": [25, -35], "lean": 8, "bob": 0, "tail": 0.2},
	&"climb_1": {"fa": [105, 150], "ba": [165, 175], "fl": [25, -35], "bl": [65, -25], "lean": 8, "bob": 0, "tail": 0.5},
	&"swing": {"fa": [176, 180], "ba": [168, 176], "fl": [25, 15], "bl": [5, 0], "lean": 0, "bob": 0, "tail": 0.9},
	&"stun": {"fa": [110, 70], "ba": [-110, -70], "fl": [20, 0], "bl": [-18, 0], "lean": -14, "bob": 1, "tail": 1.0, "eyes": "dizzy"},
	&"punch": {"fa": [88, 90], "ba": [-35, 30], "fl": [32, 0], "bl": [-28, 0], "lean": 16, "bob": 0, "tail": 0.5},
	&"dash": {"fa": [-65, -85], "ba": [-80, -100], "fl": [60, 20], "bl": [-45, -85], "lean": 32, "bob": 0, "tail": 1.0},
}

## Frames per animation, and how fast each plays.
const ANIMS: Dictionary = {
	&"idle": {"frames": [&"idle_0", &"idle_1"], "fps": 2.0},
	&"run": {"frames": [&"run_0", &"run_1", &"run_2", &"run_3"], "fps": 10.0},
	&"jump": {"frames": [&"jump"], "fps": 1.0},
	&"fall": {"frames": [&"fall"], "fps": 1.0},
	&"climb": {"frames": [&"climb_0", &"climb_1"], "fps": 6.0},
	&"swing": {"frames": [&"swing"], "fps": 1.0},
	&"stun": {"frames": [&"stun"], "fps": 1.0},
	&"punch": {"frames": [&"punch"], "fps": 1.0},
	&"dash": {"frames": [&"dash"], "fps": 1.0},
}

static var _sheets: Dictionary = {}     # species -> {"texture", "index", "top"}
static var _front_sheets: Dictionary = {}

# --- Facing the camera -------------------------------------------------
# The menus show a monkey looking at you, not walking past you. Same rig,
# same builds, seen from the front: the pixel portrait is the head, the
# body is two legs, two arms and a belly, mirrored, and the idle breathes,
# blinks, sways its tail and now and then waves.

## Arms are [upper, lower], degrees out from straight down, mirrored for the
## left arm. bob drops the upper body a pixel; eyes as in POSES.
const FRONT_POSES: Dictionary = {
	&"f_idle_0": {"right": [14, 6], "left": [14, 6], "bob": 0, "tail": 0.0},
	&"f_idle_1": {"right": [18, 10], "left": [18, 10], "bob": 1, "tail": 0.5},
	&"f_blink": {"right": [14, 6], "left": [14, 6], "bob": 0, "tail": 0.0, "eyes": "shut"},
	&"f_wave_0": {"right": [128, 170], "left": [14, 6], "bob": 0, "tail": 0.3},
	&"f_wave_1": {"right": [112, 200], "left": [14, 6], "bob": 0, "tail": 0.6},
	&"f_cheer": {"right": [150, 172], "left": [150, 172], "bob": -1, "tail": 1.0},
}
const FRONT_ANIMS: Dictionary = {
	&"idle": {"frames": [&"f_idle_0", &"f_idle_1"], "fps": 1.6},
	&"wave": {"frames": [&"f_wave_0", &"f_wave_1"], "fps": 6.0},
	&"cheer": {"frames": [&"f_cheer"], "fps": 1.0},
}

var species: StringName = &"macaque"
var anim: StringName = &"idle"
## Multiplies the animation's own rate. Running scales it with speed.
var speed_scale: float = 1.0
## Climbing only animates while the monkey is actually moving.
var paused: bool = false

var _clock: float = 0.0
var _blink_in: float = 2.5
var _blinking: float = 0.0
var _index: Dictionary = {}
## Seen from the front, for menus. See FRONT_POSES.
var front: bool = false
var _wave_in: float = 3.0
var _anim_left: float = 0.0


func setup(id: StringName, facing_camera: bool = false) -> void:
	species = id
	front = facing_camera
	var sheet := front_sheet_for(id) if front else sheet_for(id)
	texture = sheet["texture"]
	_index = sheet["index"]
	hframes = (FRONT_POSES if front else POSES).size()
	centered = false
	offset = Vector2(-CANVAS * 0.5, -CANVAS)
	scale = Vector2(PIXEL, PIXEL)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_show(&"f_idle_0" if front else &"idle_0")
	_wave_in = randf_range(2.0, 5.0)


## Plays a one-shot animation for a while, then back to idle. Front only.
func play_for(next: StringName, seconds: float) -> void:
	play(next)
	_anim_left = seconds


## Height from the feet to the top of the head, in world pixels. The hat
## anchor goes here, not at the collision box top.
static func head_height(id: StringName) -> float:
	return float(sheet_for(id)["top"]) * PIXEL


func play(next: StringName) -> void:
	if next == anim:
		return
	anim = next
	_clock = 0.0


func _process(delta: float) -> void:
	if front:
		_process_front(delta)
		return
	var spec: Dictionary = ANIMS.get(anim, ANIMS[&"idle"])
	var frames: Array = spec["frames"]
	if not paused:
		_clock += delta * float(spec["fps"]) * speed_scale
	var pose: StringName = frames[int(_clock) % frames.size()]
	if anim == &"idle":
		# Blink now and then. Idle monkeys that never blink look stuffed.
		_blink_in -= delta
		if _blink_in <= 0.0:
			_blinking = 0.14
			_blink_in = randf_range(2.0, 4.5)
		if _blinking > 0.0:
			_blinking -= delta
			pose = &"blink"
	_show(pose)


func _process_front(delta: float) -> void:
	if _anim_left > 0.0:
		_anim_left -= delta
		if _anim_left <= 0.0:
			play(&"idle")
	elif anim == &"idle":
		# Every few seconds a wave, so a menu left open still feels alive.
		_wave_in -= delta
		if _wave_in <= 0.0:
			_wave_in = randf_range(4.0, 8.0)
			play_for(&"wave", 1.3)
	var spec: Dictionary = FRONT_ANIMS.get(anim, FRONT_ANIMS[&"idle"])
	var frames: Array = spec["frames"]
	_clock += delta * float(spec["fps"])
	var pose: StringName = frames[int(_clock) % frames.size()]
	if anim == &"idle":
		_blink_in -= delta
		if _blink_in <= 0.0:
			_blinking = 0.14
			_blink_in = randf_range(2.0, 4.5)
		if _blinking > 0.0:
			_blinking -= delta
			pose = &"f_blink"
	_show(pose)


func _show(pose: StringName) -> void:
	frame = int(_index.get(pose, 0))


static func front_sheet_for(id: StringName) -> Dictionary:
	if _front_sheets.has(id):
		return _front_sheets[id]
	var build: Dictionary = BUILDS.get(id, DEFAULT_BUILD)
	var palette := _palette(id)
	var names: Array = FRONT_POSES.keys()
	var image := Image.create_empty(CANVAS * names.size(), CANVAS, false, Image.FORMAT_RGBA8)
	var index: Dictionary = {}
	for i in names.size():
		var codes := _render_front(FRONT_POSES[names[i]], build, id)
		index[names[i]] = i
		for y in CANVAS:
			for x in CANVAS:
				var code: int = codes[y * CANVAS + x]
				if code != EMPTY:
					image.set_pixel(i * CANVAS + x, y, palette[code])
	var made := {"texture": ImageTexture.create_from_image(image), "index": index}
	_front_sheets[id] = made
	return made


static func _render_front(pose: Dictionary, build: Dictionary, id: StringName) -> PackedByteArray:
	var arm: Vector2 = build["arm"]
	var leg: Vector2 = build["leg"]
	var limb: float = build["limb"]
	var girth: float = build["girth"] + 1.0
	var torso_len: float = build["torso"]
	var bob := float(pose.get("bob", 0))
	var cx := CANVAS * 0.5 - 0.5
	var hip := Vector2(cx, CANVAS - 1.5 - leg.x - leg.y - limb)
	var shoulder := hip + Vector2(0.0, -(torso_len - bob))

	var layers: Array[PackedByteArray] = []
	if int(build["tail"]) > 0:
		# From the front the tail curls out from behind one hip.
		layers.append(_tail(hip + Vector2(girth * 0.6, -1.0), int(build["tail"]), float(pose.get("tail", 0.0)) * 0.6 - 0.5))

	var legs := _blank()
	for side in [-1.0, 1.0]:
		var top := hip + Vector2(side * girth * 0.45, 0.0)
		var foot := top + Vector2(side * 0.8, leg.x + leg.y)
		_capsule(legs, top, foot, limb + 0.4, FUR)
		_capsule(legs, foot + Vector2(side * 0.8, 0.0), foot + Vector2(side * 0.8, 0.0), limb + 0.6, FACE)
	layers.append(legs)

	var body := _blank()
	_capsule(body, hip, shoulder, girth, FUR)
	_capsule(body, hip + Vector2(0.0, -1.0), shoulder + Vector2(0.0, 2.0), girth * 0.6, BELLY)
	layers.append(body)

	for side in [-1.0, 1.0]:
		var angles: Array = pose["right"] if side > 0.0 else pose["left"]
		layers.append(_front_arm(shoulder + Vector2(side * (girth - 0.5), 1.0), angles, arm, limb, side))

	layers.append(_front_head(shoulder + Vector2(0.0, 2.0), String(pose.get("eyes", "open"))))

	var out := _blank()
	for i in layers.size():
		var layer: PackedByteArray = layers[i]
		# The head is the portrait, which already carries its outline.
		if i < layers.size() - 1:
			_outline(layer)
		for j in layer.size():
			if layer[j] != EMPTY:
				out[j] = layer[j]
	return out


static func _front_arm(root: Vector2, angles: Array, lengths: Vector2, radius: float, side: float) -> PackedByteArray:
	var layer := _blank()
	var a := deg_to_rad(float(angles[0]))
	var b := deg_to_rad(float(angles[1]))
	var elbow := root + Vector2(sin(a) * side, cos(a)) * lengths.x
	var hand := elbow + Vector2(sin(b) * side, cos(b)) * lengths.y
	_capsule(layer, root, elbow, radius, FUR)
	_capsule(layer, elbow, hand, radius, FUR)
	_capsule(layer, hand, hand, radius + 0.5, FACE)
	return layer


## The portrait's head rows (not its bust), centred on the neck.
static func _front_head(neck: Vector2, eyes: String) -> PackedByteArray:
	var layer := _blank()
	var rows := 19
	var origin := Vector2(roundf(neck.x - MonkeyPortrait.SIZE * 0.5 + 0.5), roundf(neck.y - rows + 3.0))
	for y in rows:
		var row: String = MonkeyPortrait.HALF[y]
		for x in row.length():
			var code := _portrait_code(row[x], eyes)
			if code == EMPTY:
				continue
			_put(layer, int(origin.x) + x, int(origin.y) + y, code)
			_put(layer, int(origin.x) + MonkeyPortrait.SIZE - 1 - x, int(origin.y) + y, code)
	return layer


static func _portrait_code(symbol: String, eyes: String) -> int:
	match symbol:
		"o":
			return OUTLINE
		"f":
			return FUR
		"d":
			return SHADE
		"m":
			return FACE
		"n":
			return NOSE
		"e":
			return FACE if eyes == "shut" else EYE
		"p":
			return NOSE if eyes == "shut" else PUPIL
	return EMPTY


# --- Building the sheet --------------------------------------------

static func sheet_for(id: StringName) -> Dictionary:
	if _sheets.has(id):
		return _sheets[id]
	var build: Dictionary = BUILDS.get(id, DEFAULT_BUILD)
	var palette := _palette(id)
	var names: Array = POSES.keys()
	var image := Image.create_empty(CANVAS * names.size(), CANVAS, false, Image.FORMAT_RGBA8)
	var index: Dictionary = {}
	var top := CANVAS
	for i in names.size():
		var codes := _render(POSES[names[i]], build)
		index[names[i]] = i
		for y in CANVAS:
			for x in CANVAS:
				var code: int = codes[y * CANVAS + x]
				if code == EMPTY:
					continue
				image.set_pixel(i * CANVAS + x, y, palette[code])
				if names[i] == &"idle_0":
					top = mini(top, y)
	var made := {"texture": ImageTexture.create_from_image(image), "index": index, "top": CANVAS - top}
	_sheets[id] = made
	return made


static func _render(pose: Dictionary, build: Dictionary) -> PackedByteArray:
	var arm: Vector2 = build["arm"]
	var leg: Vector2 = build["leg"]
	var limb: float = build["limb"]
	var girth: float = build["girth"]
	var torso_len: float = build["torso"]
	var bob: float = float(pose.get("bob", 0))

	# Hip height comes from straight legs, so every pose stands on the same
	# floor and a bent knee lifts the foot instead of sinking the body.
	var hip := Vector2(CANVAS * 0.5 - 0.5, CANVAS - 1.5 - leg.x - leg.y - limb)
	var lean := deg_to_rad(float(pose.get("lean", 0)))
	var up := Vector2(sin(lean), -cos(lean))
	var shoulder := hip + up * (torso_len - bob)
	var arm_root := shoulder - up * 1.0

	var layers: Array[PackedByteArray] = []

	# Back limbs first, in shade, so they sit behind the body.
	layers.append(_limb(arm_root, pose["ba"], arm, limb, SHADE, SHADE))
	layers.append(_limb(hip, pose["bl"], leg, limb + 0.3, SHADE, SHADE))
	if int(build["tail"]) > 0:
		layers.append(_tail(hip - up * 1.0 - Vector2(girth * 0.8, 0.0), int(build["tail"]), float(pose.get("tail", 0.0))))

	var body := _blank()
	_capsule(body, hip, shoulder, girth, FUR)
	# Belly: a smaller capsule nudged forward, lighter than the fur.
	_capsule(body, hip + Vector2(girth * 0.35, -1.0), shoulder + up * -2.0 + Vector2(girth * 0.35, 0.0), girth * 0.55, BELLY)
	layers.append(body)

	layers.append(_limb(hip, pose["fl"], leg, limb + 0.3, FUR, FACE))
	layers.append(_head(shoulder + up * 1.5, String(pose.get("eyes", "open"))))
	layers.append(_limb(arm_root, pose["fa"], arm, limb, FUR, FACE))

	var out := _blank()
	for layer in layers:
		_outline(layer)
		for i in layer.size():
			if layer[i] != EMPTY:
				out[i] = layer[i]
	return out


static func _limb(root: Vector2, angles: Array, lengths: Vector2, radius: float, fill: int, end_fill: int) -> PackedByteArray:
	var layer := _blank()
	var a := deg_to_rad(float(angles[0]))
	var b := deg_to_rad(float(angles[1]))
	var joint := root + Vector2(sin(a), cos(a)) * lengths.x
	var tip := joint + Vector2(sin(b), cos(b)) * lengths.y
	_capsule(layer, root, joint, radius, fill)
	_capsule(layer, joint, tip, radius, fill)
	# Hands and feet in the face colour: pale palms on a dark monkey, dark
	# on a pale one, and either way the end of a limb is findable.
	_capsule(layer, tip, tip, radius + 0.4, end_fill)
	return layer


## A curl: starts pointing back and down, sweeps up, and the tip hooks
## forward. `sway` bends the whole thing, which is all the tail animation.
static func _tail(root: Vector2, length: int, sway: float) -> PackedByteArray:
	var layer := _blank()
	var point := root
	var angle := -60.0 - sway * 15.0
	for i in length:
		var t := float(i) / length
		angle -= 9.0 + t * 10.0 - sway * 2.0
		var r := deg_to_rad(angle)
		var next := point + Vector2(sin(r), cos(r))
		_capsule(layer, point, next, 0.9, FUR if t < 0.8 else SHADE)
		point = next
	return layer


static func _head(neck: Vector2, eyes: String) -> PackedByteArray:
	var layer := _blank()
	var origin := (neck - HEAD_NECK).round()
	for y in HEAD.size():
		var row: String = HEAD[y]
		for x in row.length():
			var code := _code(row[x])
			if code == EMPTY:
				continue
			if eyes == "shut" and (code == EYE or code == PUPIL):
				code = SHADE
			_put(layer, int(origin.x) + x, int(origin.y) + y, code)
	if eyes == "dizzy":
		# An X where the eye was. Stunned should be legible from across the
		# screen, and a spiral at this size is just a smudge.
		var eye_at := origin + Vector2(8.0, 4.0)
		for d in [Vector2(0, 0), Vector2(2, 0), Vector2(1, 1), Vector2(0, 2), Vector2(2, 2)]:
			_put(layer, int(eye_at.x + d.x), int(eye_at.y + d.y), PUPIL)
		_put(layer, int(eye_at.x + 1), int(eye_at.y), FACE)
		_put(layer, int(eye_at.x), int(eye_at.y + 1), FACE)
		_put(layer, int(eye_at.x + 2), int(eye_at.y + 1), FACE)
		_put(layer, int(eye_at.x + 1), int(eye_at.y + 2), FACE)
	return layer


static func _code(symbol: String) -> int:
	match symbol:
		"f":
			return FUR
		"d":
			return SHADE
		"m":
			return FACE
		"e":
			return EYE
		"p":
			return PUPIL
		"n":
			return NOSE
	return EMPTY


# --- Raster helpers ------------------------------------------------

static func _blank() -> PackedByteArray:
	var layer := PackedByteArray()
	layer.resize(CANVAS * CANVAS)
	return layer


static func _put(layer: PackedByteArray, x: int, y: int, code: int) -> void:
	if x < 0 or y < 0 or x >= CANVAS or y >= CANVAS:
		return
	layer[y * CANVAS + x] = code


## Every pixel whose centre is within `radius` of the segment. A zero-length
## segment is a disc, which is how hands and feet are drawn.
static func _capsule(layer: PackedByteArray, a: Vector2, b: Vector2, radius: float, code: int) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (radius + 1.0)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (radius + 1.0)
	for y in range(int(floorf(lo.y)), int(ceilf(hi.y)) + 1):
		for x in range(int(floorf(lo.x)), int(ceilf(hi.x)) + 1):
			var centre := Vector2(x + 0.5, y + 0.5)
			var closest := Geometry2D.get_closest_point_to_segment(centre, a, b)
			if centre.distance_to(closest) <= radius:
				_put(layer, x, y, code)


## One-pixel outline around whatever the layer holds, four-connected. Done
## per layer so an arm in front of the body gets a line between them.
static func _outline(layer: PackedByteArray) -> void:
	var edge: Array[int] = []
	for y in CANVAS:
		for x in CANVAS:
			if layer[y * CANVAS + x] != EMPTY:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= CANVAS or ny >= CANVAS:
					continue
				var n: int = layer[ny * CANVAS + nx]
				if n != EMPTY and n != OUTLINE:
					edge.append(y * CANVAS + x)
					break
	for i in edge:
		layer[i] = OUTLINE


static func _palette(id: StringName) -> Array[Color]:
	var colors := MonkeyPortrait.palette_for(id)
	var fur: Color = colors["f"]
	var face: Color = colors["m"]
	var out: Array[Color] = []
	out.resize(BELLY + 1)
	out[EMPTY] = Color(0, 0, 0, 0)
	out[OUTLINE] = MonkeyPortrait.OUTLINE
	out[FUR] = fur
	out[SHADE] = colors["d"]
	out[FACE] = face
	out[EYE] = MonkeyPortrait.EYE
	out[PUPIL] = MonkeyPortrait.PUPIL
	out[NOSE] = colors["n"]
	out[BELLY] = fur.lerp(face, 0.35).lightened(0.08)
	return out
