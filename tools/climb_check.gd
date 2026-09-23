extends Node

# ============================================================
# CLIMB CHECK - dev only. A monkey jumps beside an ivy wall and keeps jump
# held, which must grab it by the arm. Then it climbs the only way there is:
# haul in on the stick, let go (a pull-up hop), press and hold to grab
# higher. Several rounds of that must gain real height.
#   godot --headless --fixed-fps 60 res://tools/ClimbCheck.tscn
# ============================================================

const PLAYER := preload("res://scenes/Player.tscn")
const CLIMB := preload("res://scenes/Climbable.tscn")

var _player: Player
var _ticks: int = 0
var _start_y: float = 0.0
var _best_y: float = INF
var _grabbed_trunk: bool = false
## Ticks left in the current phase, and which phase: hold (grab and haul
## in) or gap (grip released, waiting to press again).
var _phase_left: int = 0
var _holding: bool = false


func _ready() -> void:
	var floor_body := StaticBody2D.new()
	var floor_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(2000, 40)
	floor_shape.shape = rect
	floor_body.position = Vector2(0, 520)
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	var wall := StaticBody2D.new()
	var wall_shape := CollisionShape2D.new()
	var wall_rect := RectangleShape2D.new()
	wall_rect.size = Vector2(64, 1000)
	wall_shape.shape = wall_rect
	wall.position = Vector2(100, 0)
	wall.add_child(wall_shape)
	add_child(wall)
	var ivy := CLIMB.instantiate()
	ivy.set(&"size", Vector2(112, 1000))
	ivy.position = Vector2(100, 0)
	add_child(ivy)
	_player = PLAYER.instantiate() as Player
	_player.setup(GameConfig.get_monkey(&"macaque"), 1, false)
	_player.position = Vector2(46, 460)
	add_child(_player)


func _physics_process(_delta: float) -> void:
	_ticks += 1
	if _ticks == 20:
		_start_y = _player.global_position.y
	var frame := InputFrame.new()
	if _ticks >= 20:
		_phase_left -= 1
		if _phase_left <= 0:
			_holding = not _holding
			# Hold long enough to grab and haul all the way in; let go for
			# just long enough to hop.
			_phase_left = 50 if _holding else 6
			if _holding:
				frame.press(InputFrame.Action.JUMP)
		frame.jump_held = _holding
		frame.grab_held = _holding
		if _holding:
			frame.move = Vector2(0, -1)
	_player.feed_input(frame)
	if _player.state == Player.State.SWING and _player.swing_on_trunk and not _grabbed_trunk:
		_grabbed_trunk = true
	_best_y = minf(_best_y, _player.global_position.y)
	if _ticks == 420:
		var climbed := _start_y - _best_y
		var ok := _grabbed_trunk and climbed > 250.0
		print("grabbed the wall by the arm: %s; climbed %.0f px by haul-and-hop" % [_grabbed_trunk, climbed])
		print("CLIMB CHECK %s" % ("OK" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
