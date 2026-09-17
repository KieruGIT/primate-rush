class_name InputFrame
extends RefCounted

# ============================================================
# INPUT FRAME - one tick of intent, from any source.
#
# The player script never asks "is a key down" or "is the phone being
# touched". It reads one of these. Keyboard, touch, and the network all
# produce the same struct, which is what makes local and networked play
# the same code path instead of two code paths that drift apart.
#
# Axes are continuous state (safe to lose a packet, the next one corrects
# it). Buttons are edges, counted rather than flagged, so two taps inside
# one physics tick still produce two actions.
# ============================================================

enum Action { JUMP, ATTACK, SKILL }

var move: Vector2 = Vector2.ZERO
var jump_held: bool = false

var _pending: Dictionary = {}


func press(button: int) -> void:
	_pending[button] = int(_pending.get(button, 0)) + 1


## Consumes one press. Returns false once the queued presses run out.
func consume(button: int) -> bool:
	var count := int(_pending.get(button, 0))
	if count <= 0:
		return false
	_pending[button] = count - 1
	return true


func clear_buttons() -> void:
	_pending.clear()


## Folds another frame's queued presses into this one, leaving axes alone.
func merge_buttons(other: InputFrame) -> void:
	for button in other._pending.keys():
		_pending[button] = int(_pending.get(button, 0)) + int(other._pending[button])


## Flattens the queue for transport. Buttons travel as counts because the
## receiver may be a physics tick behind and must not silently drop a tap.
func button_counts() -> Dictionary:
	var out: Dictionary = {}
	for button in _pending.keys():
		var count := int(_pending[button])
		if count > 0:
			out[button] = count
	return out


func apply_button_counts(counts: Dictionary) -> void:
	for button in counts.keys():
		var id := int(button)
		if id < 0 or id > InputFrame.Action.SKILL:
			continue
		_pending[id] = int(_pending.get(id, 0)) + clampi(int(counts[button]), 0, 8)
