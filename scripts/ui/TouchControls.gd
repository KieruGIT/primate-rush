extends CanvasLayer

# ============================================================
# TOUCH CONTROLS - stick on the left, two buttons on the right.
#
# Raw screen touch events rather than Control input, because a phone hand
# holds the stick down while the other thumb taps jump, and Control's
# single-focus input model fights that. Tracking touch indices directly is
# the difference between working multi-touch and a game that eats jumps.
#
# Climb and swing get no buttons on purpose. They are contextual, which
# keeps the layout to three things a thumb can find without looking.
# ============================================================

const STICK_RADIUS: float = 110.0
const STICK_KNOB: float = 46.0
const BUTTON_RADIUS: float = 66.0
const DEAD_ZONE: float = 0.18

var _stick_touch: int = -1
var _stick_origin: Vector2 = Vector2.ZERO
var _stick_vector: Vector2 = Vector2.ZERO
var _jump_touch: int = -1
var _button_touches: Dictionary = {}   # touch index -> action name

var _stick_home: Vector2 = Vector2.ZERO
var _jump_center: Vector2 = Vector2.ZERO
var _attack_center: Vector2 = Vector2.ZERO
var _skill_center: Vector2 = Vector2.ZERO

@onready var _surface: Control = $Surface


func _ready() -> void:
	layer = 10
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	_stick_home = Vector2(STICK_RADIUS + 60.0, view.y - STICK_RADIUS - 50.0)
	_attack_center = Vector2(view.x - BUTTON_RADIUS - 60.0, view.y - BUTTON_RADIUS - 60.0)
	_jump_center = _attack_center + Vector2(-BUTTON_RADIUS * 2.4, -BUTTON_RADIUS * 0.35)
	# Skill sits above attack rather than beside it: the row was already as
	# wide as a thumb can reach without shifting grip.
	_skill_center = _attack_center + Vector2(0.0, -BUTTON_RADIUS * 2.3)
	_stick_origin = _stick_home
	_surface.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _in_button(event.position, _jump_center):
			_button_touches[event.index] = &"jump"
			GameInput.touch_jump_held = true
			GameInput.touch_press(InputFrame.Button.JUMP)
			_jump_touch = event.index
		elif _in_button(event.position, _attack_center):
			_button_touches[event.index] = &"attack"
			GameInput.touch_press(InputFrame.Button.ATTACK)
		elif _in_button(event.position, _skill_center):
			_button_touches[event.index] = &"skill"
			GameInput.touch_press(InputFrame.Button.SKILL)
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


func draw_surface() -> void:
	var idle := Color(1, 1, 1, 0.16)
	var lit := Color(1, 1, 1, 0.34)
	_surface.draw_circle(_stick_origin, STICK_RADIUS, idle)
	_surface.draw_circle(_stick_origin + _stick_vector * STICK_RADIUS, STICK_KNOB, lit)
	_surface.draw_circle(_jump_center, BUTTON_RADIUS, lit if _jump_touch != -1 else idle)
	_surface.draw_circle(_attack_center, BUTTON_RADIUS, idle)
	_surface.draw_circle(_skill_center, BUTTON_RADIUS * 0.85, idle)
	var font := ThemeDB.fallback_font
	_surface.draw_string(font, _jump_center + Vector2(-28.0, 8.0), "JUMP", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.75))
	_surface.draw_string(font, _attack_center + Vector2(-26.0, 8.0), "HIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.75))
	_surface.draw_string(font, _skill_center + Vector2(-32.0, 8.0), "SKILL", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.75))
