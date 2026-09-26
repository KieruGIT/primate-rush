extends Node

# ============================================================
# GAME INPUT - the one place that knows what a control device is.
#
# Keyboard stays alive on Android builds on purpose: iterating on a phone
# is slow, and losing desktop testing to gain touch would cost more time
# than it saves. Touch state is pushed in here by the on-screen controls
# rather than polled, so the HUD owns its own layout and this stays a
# dumb aggregator.
# ============================================================

signal pause_requested

var touch_move: Vector2 = Vector2.ZERO
var touch_jump_held: bool = false
var touch_grab_held: bool = false
## Stick past this and the monkey sprints. See InputFrame.sprint_held.
const TOUCH_SPRINT_AT: float = 0.92

# Grabbing has its own button, separate from jump: L, Ctrl or the right
# mouse button on a keyboard, SWING on a phone. Hold it to hang on.
var _frame: InputFrame = InputFrame.new()


func _ready() -> void:
	# Run before the tree pauses so a paused game can still be unpaused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_grab_action()


## Added in code rather than in project.godot, so an editor that is open
## while this lands cannot save over it.
func _register_grab_action() -> void:
	if InputMap.has_action(&"grab"):
		return
	InputMap.add_action(&"grab", 0.2)
	# Right click is grab. L stays for keyboard-only play (J punch, K skill,
	# L grab); Shift and Ctrl were duplicates and are gone. The skill is E.
	for code in [KEY_L]:
		var key := InputEventKey.new()
		key.physical_keycode = code
		InputMap.action_add_event(&"grab", key)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event(&"grab", mouse)


func _notification(what: int) -> void:
	# Android's back button. It does not arrive as an action, so without
	# this the phone build has no way to reach the pause menu at all.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		pause_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	# A left click slaps, but only from a real mouse. Phones turn every tap
	# into an emulated click, and a slap on every touch would be chaos.
	if event is InputEventMouseButton and (OS.has_feature("mobile") or event.device == InputEvent.DEVICE_ID_EMULATION):
		return
	if event.is_action_pressed(&"jump"):
		_frame.press(InputFrame.Action.JUMP)
	elif event.is_action_pressed(&"attack"):
		_frame.press(InputFrame.Action.ATTACK)
	elif event.is_action_pressed(&"skill"):
		_frame.press(InputFrame.Action.SKILL)
	elif event.is_action_pressed(&"grab"):
		_frame.press(InputFrame.Action.GRAB)
	elif event.is_action_pressed(&"ui_cancel"):
		pause_requested.emit()


## Called by the touch controls when a virtual button goes down.
func touch_press(button: int) -> void:
	_frame.press(button)


## Builds this tick's intent and hands ownership of the buttons to the caller.
## Calling this twice in one tick means the second call sees no buttons, which
## is correct: exactly one consumer should drive a monkey.
func take_local_frame() -> InputFrame:
	var out := InputFrame.new()
	out.move = _resolve_move()
	out.jump_held = _resolve_jump_held()
	out.grab_held = touch_grab_held or Input.is_action_pressed(&"grab")
	out.sprint_held = Input.is_action_pressed(&"sprint") or touch_move.length() >= TOUCH_SPRINT_AT
	out.merge_buttons(_frame)
	_frame.clear_buttons()
	return out


func _resolve_move() -> Vector2:
	var move := touch_move
	var keys := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	# Whichever device is pushed harder wins, so plugging in a keyboard
	# mid-session never fights a resting virtual stick.
	if keys.length() > move.length():
		move = keys
	return move.limit_length(1.0)


func _resolve_jump_held() -> bool:
	return touch_jump_held or Input.is_action_pressed(&"jump")
