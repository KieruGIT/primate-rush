extends Node

# ============================================================
# FX SHEET - dev only. Stages a macaque slapping a monkey, an orangutan
# slapping one from further off, and a double jump, then writes a sheet of
# frames: the slap swing, the impact flash and the long arm, all visible
# without playing a match.
#   godot --fixed-fps 60 --path . res://tools/FxSheet.tscn -- --out=/tmp/shots/
# ============================================================

const PLAYER := preload("res://scenes/Player.tscn")
const VIEW := Vector2i(640, 300)
## Physics ticks at which a frame is kept. The slap presses at tick 20 and
## the double jump second-presses at tick 36.
const SHOTS := [22, 24, 25, 26, 27, 28, 30, 34]

var _viewport: SubViewport
var _world: Node2D
var _slappers: Array[Player] = []
var _jumper: Player
var _frames: Array[Image] = []
var _tick: int = 0
var _taken: Dictionary = {}


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = VIEW
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_world = Node2D.new()
	_viewport.add_child(_world)
	var bg := ColorRect.new()
	bg.color = JunglePalette.CANOPY_MID
	bg.size = Vector2(VIEW)
	bg.position = Vector2(-60, -200)
	_world.add_child(bg)
	var camera := Camera2D.new()
	camera.position = Vector2(260, -40)
	_world.add_child(camera)
	camera.make_current()

	var floor_body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(2000, 40)
	shape.shape = rect
	floor_body.add_child(shape)
	floor_body.position = Vector2(300, 60)
	_world.add_child(floor_body)
	var ground := ColorRect.new()
	ground.color = JunglePalette.DIRT
	ground.position = Vector2(-700, 40)
	ground.size = Vector2(2000, 40)
	_world.add_child(ground)

	_slappers.append(_add(&"macaque", Vector2(0, 0), 1))
	_add(&"gibbon", Vector2(84, 0), 2)
	_slappers.append(_add(&"orangutan", Vector2(250, 0), 3))
	_add(&"gorilla", Vector2(372, 0), 4)
	_jumper = _add(&"capuchin", Vector2(520, 0), 5)


func _add(id: StringName, at: Vector2, slot: int) -> Player:
	var monkey := PLAYER.instantiate() as Player
	monkey.setup(GameConfig.get_monkey(id), slot, false)
	monkey.position = at
	_world.add_child(monkey)
	return monkey


func _physics_process(_delta: float) -> void:
	_tick += 1
	for slapper in _slappers:
		var frame := InputFrame.new()
		if _tick == 20:
			frame.press(InputFrame.Action.ATTACK)
		slapper.feed_input(frame)
	var jump := InputFrame.new()
	jump.jump_held = _tick >= 24 and _tick < 70
	if _tick == 24 or _tick == 36:
		jump.press(InputFrame.Action.JUMP)
	_jumper.feed_input(jump)



# Run with --fixed-fps 60 so each drawn frame is exactly one physics tick;
# the image read here is the frame just drawn for this tick.
func _process(_delta: float) -> void:
	if SHOTS.has(_tick) and _frames.size() < SHOTS.size() and not _taken.has(_tick):
		_taken[_tick] = true
		_frames.append(_viewport.get_texture().get_image())
		if _frames.size() == SHOTS.size():
			_write()


func _write() -> void:
	var out := "user://"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
	var cols := 2
	var rows := int(ceil(_frames.size() / float(cols)))
	var sheet := Image.create(VIEW.x * cols, VIEW.y * rows, false, Image.FORMAT_RGBA8)
	for i in _frames.size():
		var image := _frames[i]
		image.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, VIEW), Vector2i((i % cols) * VIEW.x, (i / cols) * VIEW.y))
	var path := out.path_join("fx_sheet.png")
	sheet.save_png(path)
	print("fx sheet -> %s" % path)
	get_tree().quit()
