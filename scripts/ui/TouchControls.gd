extends CanvasLayer

# ============================================================
# TOUCH CONTROLS - stick on the left, three buttons on the right.
#
# Raw screen touch events rather than Control input, because a phone hand
# holds the stick down while the other thumb taps jump, and Control's
# single-focus input model fights that. Tracking touch indices directly is
# the difference between working multi-touch and a game that eats jumps.
#
# JUMP only jumps (tap again in the air to double jump). GRAB, just up and
# left of it, grabs whatever is in reach while held and lets go on release.
#
# Low-detail look (Primate Rush mock): flat pixel buttons - one face colour,
# a darker lip underneath, a 3px ink outline and a light top edge. Pressed
# drops the face onto the lip. No gloss, no textures.
# ============================================================

const STICK_RADIUS: float = 110.0
const STICK_KNOB: float = 50.0
## Hit and skill. Jump is bigger: it is pressed more than both together.
const BUTTON_RADIUS: float = 64.0
const JUMP_RADIUS: float = 84.0
const PAUSE_RADIUS: float = 30.0
const DEAD_ZONE: float = 0.18

const INK_SHADOW := Color(0.1, 0.08, 0.06, 0.75)
const OUTLINE := Color8(26, 15, 10)
## Face and lip per button colour, from the mock's style sheet.
const FLAT := {
	"Green": [Color8(79, 154, 58), Color8(47, 107, 36)],
	"Red": [Color8(224, 80, 74), Color8(158, 46, 42)],
	"Blue": [Color8(58, 123, 213), Color8(36, 85, 158)],
	"Grey": [Color8(42, 51, 88), Color8(28, 36, 68)],
	"Yellow": [Color8(236, 178, 44), Color8(168, 118, 20)],
}
const SkillFx = preload("res://scripts/player/SkillFx.gd")

var _stick_touch: int = -1
var _stick_origin: Vector2 = Vector2.ZERO
var _stick_vector: Vector2 = Vector2.ZERO
var _jump_touch: int = -1
var _button_touches: Dictionary = {}   # touch index -> action name

var _stick_home: Vector2 = Vector2.ZERO
var _jump_center: Vector2 = Vector2.ZERO
var _attack_center: Vector2 = Vector2.ZERO
var _skill_center: Vector2 = Vector2.ZERO
var _grab_center: Vector2 = Vector2.ZERO
var _pause_center: Vector2 = Vector2.ZERO

var _font: Font = null

@onready var _surface: Control = $Surface


func _ready() -> void:
	layer = 10
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiTheme._font(UiTheme.FONT_DISPLAY)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	_stick_home = Vector2(STICK_RADIUS + 60.0, view.y - STICK_RADIUS - 50.0)
	# Jump in the corner, where a resting right thumb already is. Hit and
	# skill fan out around it, each one a short thumb-roll away.
	_jump_center = Vector2(view.x - JUMP_RADIUS - 48.0, view.y - JUMP_RADIUS - 44.0)
	_attack_center = _jump_center + Vector2(-JUMP_RADIUS - BUTTON_RADIUS - 26.0, 16.0)
	_skill_center = _jump_center + Vector2(-30.0, -JUMP_RADIUS - BUTTON_RADIUS - 22.0)
	# SWING between PUNCH and SKILL, up and to the left: a thumb rolls onto
	# it from jump without lifting off the screen.
	_grab_center = _jump_center + Vector2(-JUMP_RADIUS - BUTTON_RADIUS - 70.0, -JUMP_RADIUS - BUTTON_RADIUS - 6.0)
	# Top corner, small, and away from every other control: a pause you can
	# hit by accident mid-swing is worse than no pause button.
	# Mock layout: a small square under the top-left banana panel.
	_pause_center = Vector2(52.0, 152.0)
	_stick_origin = _stick_home
	_surface.queue_redraw()


func _process(_delta: float) -> void:
	# The cooldown wedge moves every frame; everything else only on touch.
	var player := _local_player()
	if player != null and player.skill_timer > 0.0:
		_surface.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if event.position.distance_to(_jump_center) <= JUMP_RADIUS * 1.15:
			_button_touches[event.index] = &"jump"
			GameInput.touch_jump_held = true
			GameInput.touch_press(InputFrame.Action.JUMP)
			_jump_touch = event.index
		elif _in_button(event.position, _attack_center):
			_button_touches[event.index] = &"attack"
			GameInput.touch_press(InputFrame.Action.ATTACK)
		elif _in_button(event.position, _skill_center):
			_button_touches[event.index] = &"skill"
			GameInput.touch_press(InputFrame.Action.SKILL)
		elif _in_button(event.position, _grab_center):
			_button_touches[event.index] = &"grab"
			GameInput.touch_grab_held = true
			GameInput.touch_press(InputFrame.Action.GRAB)
		elif event.position.distance_to(_pause_center) <= PAUSE_RADIUS * 1.3:
			_button_touches[event.index] = &"pause"
			GameInput.pause_requested.emit()
		elif _stick_touch == -1 and event.position.x < get_viewport().get_visible_rect().size.x * 0.5:
			# The stick re-homes to wherever the thumb landed. A fixed stick
			# position means every missed grab is a missed input.
			_stick_touch = event.index
			_stick_origin = event.position
			_stick_vector = Vector2.ZERO
	else:
		if event.index == _stick_touch:
			_stick_touch = -1
			_stick_vector = Vector2.ZERO
			_stick_origin = _stick_home
			GameInput.touch_move = Vector2.ZERO
		if _button_touches.has(event.index):
			if _button_touches[event.index] == &"jump":
				GameInput.touch_jump_held = false
				_jump_touch = -1
			elif _button_touches[event.index] == &"grab":
				GameInput.touch_grab_held = false
			_button_touches.erase(event.index)
	_surface.queue_redraw()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index != _stick_touch:
		return
	var offset := (event.position - _stick_origin) / STICK_RADIUS
	_stick_vector = offset.limit_length(1.0)
	if _stick_vector.length() < DEAD_ZONE:
		_stick_vector = Vector2.ZERO
	GameInput.touch_move = _stick_vector
	_surface.queue_redraw()


func _in_button(position: Vector2, center: Vector2) -> bool:
	return position.distance_to(center) <= BUTTON_RADIUS * 1.15


# --- Drawing -------------------------------------------------------

func draw_surface() -> void:
	_draw_stick()
	var pressed: Array = _button_touches.values()
	_draw_button(_jump_center, JUMP_RADIUS, "Green", pressed.has(&"jump"), "JUMP", _draw_jump_icon)
	_draw_button(_attack_center, BUTTON_RADIUS, "Red", pressed.has(&"attack"), "PUNCH", _draw_hit_icon)
	_draw_button(_skill_center, BUTTON_RADIUS, "Blue", pressed.has(&"skill"), "SKILL", _draw_own_skill_icon)
	_draw_button(_grab_center, BUTTON_RADIUS, "Yellow", pressed.has(&"grab"), "GRAB", _draw_grab_icon)
	_draw_cooldown()
	_draw_button(_pause_center, PAUSE_RADIUS, "Grey", pressed.has(&"pause"), "", _draw_pause_icon)


func _draw_stick() -> void:
	var active := _stick_touch != -1
	var alpha := 0.8 if active else 0.55
	# Mock stick: a thin light ring over a faint dark disc, and a pale knob.
	_surface.draw_circle(_stick_origin, STICK_RADIUS, Color(0.02, 0.03, 0.08, alpha * 0.35))
	_surface.draw_arc(_stick_origin, STICK_RADIUS, 0.0, TAU, 64, Color(OUTLINE, alpha), 7.0)
	_surface.draw_arc(_stick_origin, STICK_RADIUS, 0.0, TAU, 64, Color(0.83, 0.85, 0.9, alpha), 4.0)
	var knob := _stick_origin + _stick_vector * STICK_RADIUS
	_surface.draw_circle(knob, STICK_KNOB + 3.0, Color(OUTLINE, alpha))
	_surface.draw_circle(knob, STICK_KNOB, Color(0.8, 0.8, 0.78, 0.95 if active else 0.8))
	_surface.draw_arc(knob, STICK_KNOB - 6.0, PI * 1.1, PI * 1.9, 16, Color(1, 1, 1, 0.6), 4.0)


## One flat mock button: ink outline, darker lip below, face, light top edge.
func _flat_disc(center: Vector2, radius: float, face: Color, lip: Color, down: bool, alpha: float = 0.92) -> void:
	var depth := maxf(4.0, radius * 0.09)
	var top := center + Vector2(0.0, depth if down else 0.0)
	_surface.draw_circle(center + Vector2(0.0, depth + 6.0), radius, Color(0, 0, 0, 0.25 * alpha))
	_surface.draw_circle(center + Vector2(0.0, depth), radius + 3.0, Color(OUTLINE, alpha))
	_surface.draw_circle(center + Vector2(0.0, depth), radius, Color(lip, alpha))
	_surface.draw_circle(top, radius + 3.0 if down else radius, Color(OUTLINE, alpha) if down else Color(lip, alpha))
	_surface.draw_circle(top, radius, Color(face, alpha))
	_surface.draw_arc(top, radius + 1.5, 0.0, TAU, 48, Color(OUTLINE, alpha), 3.0)
	if not down:
		_surface.draw_arc(top, radius - 6.0, PI * 1.15, PI * 1.85, 16, Color(face.lightened(0.35), alpha), 4.0)


func _draw_button(center: Vector2, radius: float, colour: String, down: bool, label: String, icon: Callable) -> void:
	var tones: Array = FLAT.get(colour, FLAT["Grey"])
	var lip := maxf(4.0, radius * 0.09)
	var face := center + Vector2(0.0, lip if down else 0.0)
	if label == "":
		# Pause: a small square block, like the mock's panel buttons.
		var box := Rect2(face - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
		_surface.draw_rect(box.grow(3.0), OUTLINE)
		_surface.draw_rect(box, tones[0])
		_surface.draw_rect(Rect2(box.position + Vector2(0, box.size.y - 5.0), Vector2(box.size.x, 5.0)), tones[1])
		icon.call(face + Vector2(0.0, -2.0), radius * 0.34)
		return
	_flat_disc(center, radius, tones[0], tones[1], down)
	var lift := radius * 0.14 if label != "" else 0.0
	icon.call(face + Vector2(0.0, -lip * 0.5 - lift), radius * 0.34)
	if label != "" and _font != null:
		var size := int(radius * 0.25)
		var width := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var at := face + Vector2(-width * 0.5, radius * 0.52)
		_surface.draw_string_outline(_font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, INK_SHADOW)
		_surface.draw_string(_font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)


func _draw_jump_icon(at: Vector2, s: float) -> void:
	_outlined(PackedVector2Array([
		at + Vector2(0, -s), at + Vector2(s, 0), at + Vector2(s * 0.42, 0),
		at + Vector2(s * 0.42, s * 0.8), at + Vector2(-s * 0.42, s * 0.8),
		at + Vector2(-s * 0.42, 0), at + Vector2(-s, 0),
	]))


## A starburst - the impact, not a fist, because it reads at thumb size.
func _draw_hit_icon(at: Vector2, s: float) -> void:
	var points := PackedVector2Array()
	for i in 16:
		var r := s * (1.05 if i % 2 == 0 else 0.5)
		points.append(at + Vector2.from_angle(TAU * i / 16.0 - PI * 0.5) * r)
	_outlined(points)


func _draw_skill_icon(at: Vector2, s: float) -> void:
	_outlined(PackedVector2Array([
		at + Vector2(s * 0.25, -s * 1.05), at + Vector2(-s * 0.6, s * 0.15), at + Vector2(-s * 0.02, s * 0.15),
		at + Vector2(-s * 0.25, s * 1.05), at + Vector2(s * 0.6, -s * 0.2), at + Vector2(s * 0.04, -s * 0.2),
	]))


## A hand hooked over a bar: what the button does, at thumb size.
func _draw_grab_icon(at: Vector2, s: float) -> void:
	_surface.draw_rect(Rect2(at + Vector2(-s * 1.1, -s * 0.95), Vector2(s * 2.2, s * 0.36)), INK_SHADOW)
	_surface.draw_rect(Rect2(at + Vector2(-s * 1.0, -s * 0.9), Vector2(s * 2.0, s * 0.26)), Color.WHITE)
	_outlined(PackedVector2Array([
		at + Vector2(-s * 0.55, -s * 0.62), at + Vector2(s * 0.55, -s * 0.62), at + Vector2(s * 0.6, s * 0.35),
		at + Vector2(s * 0.2, s * 0.95), at + Vector2(-s * 0.2, s * 0.95), at + Vector2(-s * 0.6, s * 0.35),
	]))


## The local monkey's own skill icon on the SKILL button.
func _draw_own_skill_icon(at: Vector2, s: float) -> void:
	var player := _local_player()
	if player == null or player.stats == null:
		_draw_skill_icon(at, s)
		return
	SkillFx.draw_icon(_surface, player.stats.skill_id, at, s * 1.1, Color.WHITE)


func _draw_pause_icon(at: Vector2, s: float) -> void:
	_surface.draw_rect(Rect2(at + Vector2(-s * 0.95, -s), Vector2(s * 0.7, s * 2.0)), Color.WHITE)
	_surface.draw_rect(Rect2(at + Vector2(s * 0.25, -s), Vector2(s * 0.7, s * 2.0)), Color.WHITE)


func _outlined(points: PackedVector2Array) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	_surface.draw_polyline(closed, INK_SHADOW, 6.0, true)
	_surface.draw_colored_polygon(points, Color.WHITE)


## Skill cooldown as a dark wedge that unwinds, plus the seconds left. A
## button that looks pressable while it is not is a button people stop
## trusting.
func _draw_cooldown() -> void:
	var player := _local_player()
	if player == null or player.stats == null or player.skill_timer <= 0.0:
		return
	var total := maxf(player.stats.skill_cooldown, player.skill_timer)
	var left := player.skill_timer / total
	var points := PackedVector2Array([_skill_center])
	var steps := 32
	for i in steps + 1:
		var angle := -PI * 0.5 + TAU * left * float(i) / steps
		points.append(_skill_center + Vector2.from_angle(angle) * BUTTON_RADIUS * 0.96)
	_surface.draw_colored_polygon(points, Color(0.04, 0.06, 0.1, 0.6))
	# A ring in the skill's colour fills clockwise as it recharges.
	var colour := SkillFx.colour_of(player.stats.skill_id)
	_surface.draw_arc(_skill_center, BUTTON_RADIUS + 8.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - left), 48, colour, 6.0)
	if _font == null:
		return
	var text := "%.1f" % player.skill_timer
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	var at := _skill_center + Vector2(-width * 0.5, 10.0)
	_surface.draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, INK_SHADOW)
	_surface.draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)


func _local_player() -> Player:
	var arena: Node = get_tree().get_first_node_in_group(&"arena")
	if arena == null:
		return null
	var table: Variant = arena.get(&"players")
	if not (table is Dictionary):
		return null
	return (table as Dictionary).get(Net.local_id()) as Player
