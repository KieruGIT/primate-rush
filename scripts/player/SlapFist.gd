class_name SlapFist
extends Node2D

# ============================================================
# SLAP - the monkey's own arm, swung flat-handed.
#
# Life-sized and on the art grid: the arm is laid down pixel by pixel from
# the shoulder, and the hand is a drawn grid (HAND) turned to the arm's
# angle by nearest-neighbour sampling, so it stays crisp at every angle
# instead of being a smooth vector shape pasted over pixel art.
#
# The motion is what sells it as a real slap rather than a punch: a
# wind-up back over the shoulder, a fast accelerating whip through, a
# follow-through past the target, and a drop back to the side. On contact
# the arm holds for a few frames (hitstop), which gives the hit its weight.
# ============================================================

# Timed against Player's attack: the hitbox opens at 0.08s, which is the
# instant the hand reaches contact.
const TOTAL_TIME := 0.30
const WINDUP_END := 0.04
const STRIKE_END := 0.08
const FOLLOW_END := 0.17
const HITSTOP := 0.055

## Arm angles in facing space: 0 is straight ahead, positive is downward.
const REST_ANGLE := deg_to_rad(85.0)
## Drawn back behind the body and a little up, where a real slap loads.
const WOUND_ANGLE := deg_to_rad(-160.0)
const CONTACT_ANGLE := deg_to_rad(6.0)
const FOLLOW_ANGLE := deg_to_rad(32.0)

## At the side of the body, just under the head, relative to the monkey's
## centre. Inside the face it read as a monkey scratching its head.
const SHOULDER := Vector2(13.0, 2.0)

# Open hand seen from the side, fingers pointing along +x from the wrist at
# (0, 4). o outline, L lit skin, m skin, s crease/shade.
const HAND := [
	"..oo.........",
	".oLmo........",
	".oLmo.ooooo..",
	"oLLmooLLLLLoo",
	"oLmmmmmmmmmmo",
	"oLmmsssssssso",
	"oLmmmmmmmmmo.",
	".osmmssssso..",
	"..oooooooo...",
]
const HAND_WRIST := Vector2(1.0, 4.0)
## Length of the hand along the arm, world pixels.
const HAND_LENGTH := 26.0

## Set by Player before play(): which monkey's arm art to use and where its
## shoulder sits (Player-local). With art present the punch is the authored
## arm shot straight out horizontally on the facing side, fist on the end.
## Punch fist drawn bigger than the grab hand so a hit reads from afar.
const PUNCH_FIST_SCALE: float = 2.0  # 4 screen px per art px, stays on a whole-pixel grid
var species: StringName = &""
var shoulder_local: Vector2 = Vector2.ZERO
var _time: float = TOTAL_TIME
var _direction: float = 1.0
var _fur := Color(0.53, 0.31, 0.18)
var _arm: float = 1.0
var _hold: float = 0.0


func play(direction: int, fur: Color, arm_length: float = 1.0) -> void:
	_direction = 1.0 if direction >= 0 else -1.0
	_fur = fur
	_arm = arm_length
	_time = 0.0
	_hold = 0.0
	visible = true
	queue_redraw()


## The hand met a face: freeze on it for a moment. A hit can resolve a tick
## before the drawn hand gets there, so jump to the contact pose first -
## freezing a raised arm would show the hit landing on nothing.
func impact() -> void:
	_time = maxf(_time, STRIKE_END)
	_hold = HITSTOP
	queue_redraw()


# Physics, not _process: the hitbox opens and closes on physics ticks, and a
# hand animated on render frames drifts off it on any machine whose frame
# rate is not exactly the tick rate.
func _physics_process(delta: float) -> void:
	if _time >= TOTAL_TIME:
		visible = false
		return
	# Behind the body while the arm is drawn back, in front from the moment
	# it starts forward: the depth cue that makes the swing read as a swing.
	z_index = -2 if _time < WINDUP_END else 8
	if _hold > 0.0:
		_hold -= delta
	else:
		_time += delta
	queue_redraw()


func _draw() -> void:
	if _time >= TOTAL_TIME:
		return
	if species != &"" and MonkeyArm.texture_for(species, true) != null:
		_draw_textured()
		return
	var skin := _fur.lightened(0.45)
	# Afterimages through the fast part of the swing only, stepped fades.
	if _time > WINDUP_END and _time < FOLLOW_END:
		var trail := [[0.012, 0.45], [0.024, 0.28], [0.036, 0.14]]
		for sample in trail:
			var then := maxf(_time - float(sample[0]), WINDUP_END)
			var ghost := Color(1.0, 0.97, 0.88, float(sample[1]))
			_draw_arm(_angle_at(then), _reach_at(then), ghost, ghost, ghost, true)
	_draw_arm(_angle_at(_time), _reach_at(_time), JunglePalette.OUTLINE, _fur, skin, false)


## Where the arm points at time t: eased back, whipped through, followed.
func _angle_at(t: float) -> float:
	if t < WINDUP_END:
		return lerpf(REST_ANGLE, WOUND_ANGLE, _ease_out(t / WINDUP_END))
	if t < STRIKE_END:
		# Accelerating into contact: the speed is at the end, where it hits.
		var k := (t - WINDUP_END) / (STRIKE_END - WINDUP_END)
		return lerpf(WOUND_ANGLE, CONTACT_ANGLE, k * k)
	if t < FOLLOW_END:
		var k := (t - STRIKE_END) / (FOLLOW_END - STRIKE_END)
		return lerpf(CONTACT_ANGLE, FOLLOW_ANGLE, _ease_out(k))
	var k := (t - FOLLOW_END) / (TOTAL_TIME - FOLLOW_END)
	return lerpf(FOLLOW_ANGLE, REST_ANGLE, k)


## The arm is bent on the wind-up and straight at contact, where the tips
## of the fingers land exactly on the far edge of the slap hitbox.
func _reach_at(t: float) -> float:
	var full := Player.SLAP_REACH * _arm - SHOULDER.x - HAND_LENGTH
	if t < WINDUP_END:
		return full * 0.7
	if t < STRIKE_END:
		return lerpf(full * 0.7, full, (t - WINDUP_END) / (STRIKE_END - WINDUP_END))
	if t < FOLLOW_END:
		return full
	return lerpf(full, full * 0.6, (t - FOLLOW_END) / (TOTAL_TIME - FOLLOW_END))


func _draw_arm(angle: float, reach: float, outline: Color, fur: Color, skin: Color, ghost: bool) -> void:
	var px := MonkeySprite.PIXEL
	var dir := Vector2.from_angle(angle)
	dir.x *= _direction
	var shoulder := Vector2(SHOULDER.x * _direction, SHOULDER.y)
	var wrist := shoulder + dir * reach
	var steps := maxi(int(reach / px), 1)
	# Arm: an outline pass one pixel fatter, then fur. Two art pixels thick.
	for pass_index in 2:
		if ghost and pass_index == 0:
			continue
		var half := (2.0 if pass_index == 0 else 1.0) * px
		var colour := outline if pass_index == 0 else fur
		for i in steps + 1:
			var cell := (shoulder.lerp(wrist, float(i) / steps) / px).floor() * px
			draw_rect(Rect2(cell - Vector2(half, half), Vector2(half, half) * 2.0), colour)
	# Hand, turned to the arm by sampling the grid backwards from each
	# screen pixel. Nearest neighbour, so no pixel is ever half a pixel.
	var rows := HAND.size()
	var cols := String(HAND[0]).length()
	var radius := int(ceil(Vector2(cols, rows).length())) + 1
	var base := (wrist / px).floor()
	var cos_a := dir.x
	var sin_a := dir.y
	for gy in range(-radius, radius + 1):
		for gx in range(-radius, radius + 1):
			# Inverse rotation into hand space. The hand is drawn facing +x,
			# so a left-facing slap mirrors it vertically as well, keeping the
			# thumb on top.
			var hx := gx * cos_a + gy * sin_a
			var hy := -gx * sin_a + gy * cos_a
			if _direction < 0.0:
				hy = -hy
			var col := int(floor(hx + HAND_WRIST.x))
			var row := int(floor(hy + HAND_WRIST.y))
			if row < 0 or row >= rows or col < 0 or col >= cols:
				continue
			var key := String(HAND[row])[col]
			if key == ".":
				continue
			var colour: Color
			if ghost:
				colour = outline
			else:
				match key:
					"o": colour = outline
					"L": colour = skin.lightened(0.18)
					"s": colour = skin.darkened(0.22)
					_: colour = skin
			draw_rect(Rect2((base + Vector2(gx, gy)) * px, Vector2(px, px)), colour)


## Horizontal punch: pulled in on the wind-up, fist tip exactly at the far
## edge of the hitbox at contact (SLAP_REACH * arm), then drawn back.
func _draw_textured() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tip := Player.SLAP_REACH * _arm
	var base := absf(shoulder_local.x) + 6.0
	var out := _extension_at(_time)
	# No afterimages on the textured arm: overlapping translucent copies
	# read as blur on pixel art. The speed comes from the 2-frame strike.
	var reach := lerpf(base, tip, out)
	MonkeyArm.draw_arm(self, species, shoulder_local, Vector2(reach * _direction, shoulder_local.y), true, int(_direction), Color.WHITE, PUNCH_FIST_SCALE)


func _extension_at(t: float) -> float:
	if t < WINDUP_END:
		return 0.15
	if t < STRIKE_END:
		var k := (t - WINDUP_END) / (STRIKE_END - WINDUP_END)
		return lerpf(0.15, 1.0, k * k)
	if t < FOLLOW_END:
		return 1.0
	return lerpf(1.0, 0.1, (t - FOLLOW_END) / (TOTAL_TIME - FOLLOW_END))


func _ease_out(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)
