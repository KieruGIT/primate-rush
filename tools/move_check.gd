extends Node

# ============================================================
# MOVE CHECK - dev only. Drives one monkey through the jump and momentum
# rules and prints a line per rule, so a tuning change that breaks one is a
# FAIL in the terminal rather than a feeling three playtests later.
#   godot --headless --fixed-fps 60 res://tools/MoveCheck.tscn
# ============================================================

const PLAYER := preload("res://scenes/Player.tscn")
const VINE := preload("res://scenes/Vine.tscn")

const FLOOR_TOP := 500.0
const VINE_X := 1400.0

var _player: Player
var _failures: int = 0


func _ready() -> void:
	var floor_body := StaticBody2D.new()
	var floor_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(6000, 40)
	floor_shape.shape = rect
	floor_body.position = Vector2(0, FLOOR_TOP + 20.0)
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	var vine := VINE.instantiate()
	vine.position = Vector2(VINE_X, 0)
	vine.set(&"length", 240.0)
	add_child(vine)
	_player = PLAYER.instantiate() as Player
	_player.setup(GameConfig.get_monkey(&"macaque"), 1, false)
	add_child(_player)
	_run.call_deferred()


func _run() -> void:
	var run := _player.stats.run_speed()

	# Single jump height, then a double jump pressed near the top.
	await _reset(Vector2(0, FLOOR_TOP - 40))
	var single := await _jump_height(-1)
	await _reset(Vector2(0, FLOOR_TOP - 40))
	var double := await _jump_height(18)
	_check("double jump goes higher", double > single + 60.0, "single %.0f px, double %.0f px" % [single, double])

	# A jump from a run carries past run speed.
	await _reset(Vector2(0, FLOOR_TOP - 40))
	for i in 40:
		await _tick(Vector2(1, 0))
	await _tick(Vector2(1, 0), true, true)
	await _tick(Vector2(1, 0), true)
	_check("jump adds momentum", _player.velocity.x > run + 50.0, "vx %.0f after jump, run %.0f" % [_player.velocity.x, run])

	# Arriving fast (as off a swing) and hopping on the landing keeps it.
	var hopped := await _land_fast(true)
	_check("bunny hop keeps speed", hopped > run + 200.0, "vx %.0f after hop" % hopped)
	var braked := await _land_fast(false)
	# Auto-sprint (Player.auto_sprint) makes top speed the running ceiling.
	var top: float = _player.call(&"_top_speed")
	_check("no hop brakes to top speed", braked <= top + 10.0, "vx %.0f after landing, top %.0f" % [braked, top])

	# Pressing jump just before touching down must hop, not double jump.
	# A hop leaves the double jump unspent; a double jump would have spent it.
	var early := await _land_fast(true, 3)
	var kept := bool(_player.get(&"_double_jump_ready"))
	_check("early press waits for the ground", early > run + 200.0 and kept, "vx %.0f, double jump still ready: %s" % [early, kept])

	# Holding down at speed slides instead of stopping.
	await _reset(Vector2(0, FLOOR_TOP - 40))
	_player.velocity.x = 640.0
	for i in 12:
		await _tick(Vector2(0, 1))
	_check("down at speed slides", _player.state == Player.State.SLIDE and _player.velocity.x > 450.0,
		"state %s, vx %.0f" % [Player.State.keys()[_player.state], _player.velocity.x])

	# A tap near a vine does not grab it; holding does.
	await _reset(Vector2(VINE_X, 120))
	var tapped := false
	for i in 14:
		await _tick(Vector2.ZERO, i < 3)
		tapped = tapped or _player.state == Player.State.SWING
	_check("tap does not grab", not tapped, "")
	await _reset(Vector2(VINE_X, 120))
	var held := false
	for i in 14:
		await _tick(Vector2.ZERO, true)
		held = held or _player.state == Player.State.SWING
	_check("hold grabs a vine", held, "")
	# The button is the grip: letting go of jump lets go of the vine.
	for i in 20:
		await _tick(Vector2(1, 0), true)
	await _tick(Vector2(1, 0), false)
	await _tick(Vector2(1, 0), false)
	_check("letting go of jump lets go", _player.state != Player.State.SWING,
		"state %s" % Player.State.keys()[_player.state])

	print("MOVE CHECK %s" % ("OK" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


## Jumps from standing and returns the peak height. second_at >= 0 presses
## again that many ticks after the first.
func _jump_height(second_at: int) -> float:
	var start := _player.global_position.y
	var peak := start
	for i in 70:
		await _tick(Vector2.ZERO, true, i == 0 or i == second_at)
		peak = minf(peak, _player.global_position.y)
	return start - peak


## Drops the monkey onto the floor at 800 px/s, holding right. hop presses
## jump on the landing, or press_early ticks before it. Returns vx a few
## ticks after touching down.
func _land_fast(hop: bool, press_early: int = 0) -> float:
	await _reset(Vector2(0, FLOOR_TOP - 150))
	_player.velocity = Vector2(800, 0)
	var pressed := false
	for i in 90:
		var near := _player.global_position.y > FLOOR_TOP - 32.0 - 6.0 * press_early
		var press := hop and not pressed and ((press_early > 0 and near and _player.velocity.y > 0.0) or (press_early == 0 and _player.is_on_floor()))
		pressed = pressed or press
		await _tick(Vector2(1, 0), press, press)
		if _player.is_on_floor() and not hop and i > 0:
			for j in 20:
				await _tick(Vector2(1, 0))
			return _player.velocity.x
		if pressed and _player.velocity.y < 0.0:
			await _tick(Vector2(1, 0), true)
			return _player.velocity.x
	return _player.velocity.x


func _reset(at: Vector2) -> void:
	_player.respawn_at(at)
	_player.set(&"_swing_lock", 0.0)
	_player.set(&"_sprint_blend", 0.0)
	await _tick(Vector2.ZERO)
	if at.y > FLOOR_TOP - 60.0:
		for i in 20:
			await _tick(Vector2.ZERO)


func _tick(move: Vector2, held: bool = false, press: bool = false) -> void:
	await get_tree().physics_frame
	var frame := InputFrame.new()
	frame.move = move
	frame.jump_held = held
	if press:
		frame.press(InputFrame.Action.JUMP)
	_player.feed_input(frame)


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		_failures += 1
	print("%s  %s  %s" % ["ok  " if ok else "FAIL", label, detail])
