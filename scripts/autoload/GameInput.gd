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

# Contextual actions (climb, swing) are deliberately not buttons. They
# trigger on contact, which keeps the touch layout down to a stick and two
# buttons on a phone screen that is mostly thumb.
var _frame: InputFrame = InputFrame.new()
var _keyboard_enabled: bool = true


func _ready() -> void:
	# Run before the tree pauses so a paused game can still be unpaused.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _notification(what: int) -> void:
	# Android's back button. It does not arrive as an action, so without
	# this the phone build has no way to reach the pause menu at all.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		pause_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"jump"):
		_frame.press(InputFrame.Button.JUMP)
	elif event.is_action_pressed(&"attack"):
		_frame.press(InputFrame.Button.ATTACK)
	elif event.is_action_pressed(&"skill"):
		_frame.press(InputFrame.Button.SKILL)
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
	out.merge_buttons(_frame)
	_frame.clear_buttons()
	return out


func set_keyboard_enabled(enabled: bool) -> void:
	_keyboard_enabled = enabled


func _resolve_move() -> Vector2:
	var move := touch_move
	if _keyboard_enabled:
		var keys := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		# Whichever device is pushed harder wins, so plugging in a keyboard
		# mid-session never fights a resting virtual stick.
		if keys.length() > move.length():
			move = keys
	return move.limit_length(1.0)


func _resolve_jump_held() -> bool:
	if touch_jump_held:
		return true
	return _keyboard_enabled and Input.is_action_pressed(&"jump")
