extends Node

# ============================================================
# CLIMB CHECK - dev only. A monkey against an ivy wall, holding only jump,
# must go up it; pushing away and jumping must wall-jump off.
#   godot --headless --fixed-fps 60 res://tools/ClimbCheck.tscn
# ============================================================

const PLAYER := preload("res://scenes/Player.tscn")
const CLIMB := preload("res://scenes/Climbable.tscn")

var _player: Player
var _ticks: int = 0
var _start_y: float = 0.0
var _top_y: float = 0.0


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
	var frame := InputFrame.new()
	if _ticks == 20:
		frame.press(InputFrame.Action.JUMP)
		_start_y = _player.global_position.y
	if _ticks >= 20 and _ticks < 140:
		frame.jump_held = true
	if _ticks == 140:
		_top_y = _player.global_position.y
	if _ticks == 150:
		frame.move = Vector2(-1, 0)
		frame.press(InputFrame.Action.JUMP)
	if _ticks > 150:
		frame.move = Vector2(-1, 0)
	_player.feed_input(frame)
	if _ticks == 175:
		var climbed := _start_y - _top_y
		var left := _player.global_position.x < 20.0
		print("climbed %.0f px holding jump (state then %s); wall jump carried to x=%.0f" % [climbed, Player.State.keys()[_player.state], _player.global_position.x])
		print("CLIMB CHECK %s" % ("OK" if climbed > 200.0 and left else "FAIL"))
		get_tree().quit(0 if climbed > 200.0 and left else 1)
