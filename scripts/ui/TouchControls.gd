extends CanvasLayer

# ============================================================
# TOUCH CONTROLS - stick on the left, three buttons on the right.
#
# Raw screen touch events rather than Control input, because a phone hand
# holds the stick down while the other thumb taps jump, and Control's
# single-focus input model fights that. Tracking touch indices directly is
# the difference between working multi-touch and a game that eats jumps.
#
# Climb and swing get no buttons on purpose. They are contextual, which
# keeps the layout to things a thumb can find without looking.
#
# Drawn from the Kenney round buttons: depth variant at rest, flat variant
# pressed and dropped by the lip, the way the pack is meant to animate.
# ============================================================

const STICK_RADIUS: float = 110.0
const STICK_KNOB: float = 50.0
## Hit and skill. Jump is bigger: it is pressed more than both together.
const BUTTON_RADIUS: float = 64.0
const JUMP_RADIUS: float = 84.0
const PAUSE_RADIUS: float = 30.0
const DEAD_ZONE: float = 0.18

const ROUND := "res://assets/kenney_ui-pack/PNG/%s/Double/button_round_%s.png"
const INK_SHADOW := Color(0.1, 0.08, 0.06, 0.75)

var _stick_touch: int = -1
var _stick_origin: Vector2 = Vector2.ZERO
var _stick_vector: Vector2 = Vector2.ZERO
var _jump_touch: int = -1
var _button_touches: Dictionary = {}   # touch index -> action name

var _stick_home: Vector2 = Vector2.ZERO
var _jump_center: Vector2 = Vector2.ZERO
var _attack_center: Vector2 = Vector2.ZERO
var _skill_center: Vector2 = Vector2.ZERO
var _pause_center: Vector2 = Vector2.ZERO

var _textures: Dictionary = {}
var _font: Font = null

@onready var _surface: Control = $Surface


func _ready() -> void:
	layer = 10
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for colour in ["Yellow", "Red", "Blue", "Grey", "Green"]:
		for kind in ["depth_gloss", "gloss", "depth_flat"]:
			var path: String = ROUND % [colour, kind]
			if ResourceLoader.exists(path):
				_textures["%s_%s" % [colour, kind]] = load(path)
	if ResourceLoader.exists(UiTheme.FONT_DISPLAY):
		_font = load(UiTheme.FONT_DISPLAY)
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
	# Top corner, small, and away from every other control: a pause you can
	# hit by accident mid-swing is worse than no pause button.
	_pause_center = Vector2(view.x - 50.0, 50.0)
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
	_draw_button(_skill_center, BUTTON_RADIUS, "Blue", pressed.has(&"skill"), "SKILL", _draw_skill_icon)
	_draw_cooldown()
	_draw_button(_pause_center, PAUSE_RADIUS, "Grey", pressed.has(&"pause"), "", _draw_pause_icon)


func _draw_stick() -> void:
	var active := _stick_touch != -1
	var alpha := 0.55 if active else 0.34
	_surface.draw_circle(_stick_origin, STICK_RADIUS + 6.0, Color(0.04, 0.06, 0.05, alpha * 0.7))
	_surface.draw_circle(_stick_origin, STICK_RADIUS, Color(0.12, 0.17, 0.15, alpha))
	_surface.draw_arc(_stick_origin, STICK_RADIUS - 2.0, 0.0, TAU, 64, Color(1, 1, 1, alpha * 0.7), 4.0, true)
	# Direction ticks, so it reads as a stick before anyone touches it.
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var dir := Vector2.from_angle(angle)
		var tip := _stick_origin + dir * (STICK_RADIUS - 20.0)
		var side := dir.orthogonal() * 10.0
		_surface.draw_colored_polygon(PackedVector2Array([tip + dir * 9.0, tip - side, tip + side]), Color(1, 1, 1, alpha))
	var knob := _stick_origin + _stick_vector * STICK_RADIUS
	var texture: Texture2D = _textures.get("Grey_depth_flat")
	_surface.draw_circle(knob + Vector2(0.0, 6.0), STICK_KNOB, Color(0, 0, 0, 0.25))
	if texture != null:
		_surface.draw_texture_rect(texture, Rect2(knob - Vector2.ONE * STICK_KNOB, Vector2.ONE * STICK_KNOB * 2.0), false, Color(1, 1, 1, 0.92 if active else 0.75))
	else:
		_surface.draw_circle(knob, STICK_KNOB, Color(1, 1, 1, 0.6))


func _draw_button(center: Vector2, radius: float, colour: String, down: bool, label: String, icon: Callable) -> void:
	var rest: Texture2D = _textures.get("%s_depth_gloss" % colour)
	var flat: Texture2D = _textures.get("%s_gloss" % colour)
	var lip := radius * 0.09
	var face := center + Vector2(0.0, lip if down else 0.0)
	_surface.draw_circle(center + Vector2(0.0, lip + 5.0), radius * 0.98, Color(0, 0, 0, 0.22))
	if rest != null and flat != null:
		var rect := Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
		if down:
			rect.position.y += lip
		_surface.draw_texture_rect(flat if down else rest, rect, false, Color(1, 1, 1, 0.95 if down else 0.85))
	else:
		_surface.draw_circle(face, radius, Color(1, 1, 1, 0.3))
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
