extends SubViewportContainer

# ============================================================
# ABILITY PREVIEW - a live, looping demo of a monkey's skill.
#
# Not a video and not a drawing: a tiny arena of its own (a SubViewport with
# its own physics world) where the real Player script does the real skill on
# a practice dummy, over and over. So what the preview shows is exactly what
# the button does in a match, and a change to a skill changes its preview.
#
# Each loop: stand, walk in, press SKILL, watch it land, reset.
# ============================================================

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const LOOP_SECONDS: float = 3.2
const FLOOR_Y: float = 0.0

## Per skill: where the dummy stands, when the skill is pressed, and any
## stick direction held while it plays.
const SCRIPTS: Dictionary = {
	&"grapple_dash": {"dummy_x": 150.0, "press_at": 0.45, "hold": Vector2.ZERO, "walk": 0.0},
	&"air_launch": {"dummy_x": 130.0, "press_at": 0.45, "hold": Vector2(1, 0), "walk": 0.0},
	&"counter_roll": {"dummy_x": 170.0, "press_at": 0.45, "hold": Vector2.ZERO, "walk": 0.0},
	&"long_arm": {"dummy_x": 300.0, "press_at": 0.35, "hold": Vector2.ZERO, "walk": 0.0},
	&"snatch": {"dummy_x": 150.0, "press_at": 0.45, "hold": Vector2(0, -1), "walk": 0.0},
}

var monkey_id: StringName = &""
var skin_id: StringName = &"natural"

var _viewport: SubViewport
var _world_root: Node2D
var _hero: Player = null
var _dummy: Player = null
var _clock: float = 0.0
var _pressed: bool = false
var _plan: Dictionary = {}


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)
	_world_root = Node2D.new()
	_viewport.add_child(_world_root)
	_build_floor()
	var camera := Camera2D.new()
	camera.position = Vector2(60.0, -90.0)
	_world_root.add_child(camera)
	camera.make_current()
	visibility_changed.connect(_on_visibility)
	if monkey_id != &"":
		_rebuild()


func show_monkey(id: StringName, skin: StringName = &"natural") -> void:
	if id == monkey_id and skin == skin_id and _hero != null:
		return
	monkey_id = id
	skin_id = skin
	if is_node_ready():
		_rebuild()


func _on_visibility() -> void:
	# Hidden pages do not simulate: no work, and every visit starts fresh.
	var on := is_visible_in_tree()
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if on:
		_reset_loop()


func _build_floor() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = GameConfig.LAYER_WORLD
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(4000.0, 60.0)
	shape.shape = rect
	shape.position = Vector2(0.0, FLOOR_Y + 30.0)
	body.add_child(shape)
	_world_root.add_child(body)
	var ground := _Ground.new()
	_world_root.add_child(ground)


func _rebuild() -> void:
	for node in [_hero, _dummy]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	var stats := GameConfig.get_monkey(monkey_id)
	_plan = SCRIPTS.get(stats.skill_id, SCRIPTS[&"counter_roll"])
	_hero = _make(monkey_id, 1, skin_id)
	# The dummy is a plain gibbon in grey, so the hero is what you look at.
	_dummy = _make(&"gibbon" if monkey_id != &"gibbon" else &"macaque", 2, &"snow")
	_reset_loop()


func _make(id: StringName, pid: int, skin: StringName) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.setup(GameConfig.get_monkey(id), pid, false, Color(0, 0, 0, 0), &"none", skin)
	player.muted = true
	player.sandbox = true
	player.is_bot = pid != 1
	_world_root.add_child(player)
	player.name_label.visible = false
	return player


func _reset_loop() -> void:
	_clock = 0.0
	_pressed = false
	if _hero == null or not is_instance_valid(_hero):
		return
	_hero.respawn_at(Vector2(-150.0, FLOOR_Y - _hero.stats.body_size.y * 0.5 - 2.0))
	_hero.facing = 1
	_hero.skill_timer = 0.0
	_hero.set_ability(&"", 0.0)
	var dummy_x: float = float(_plan.get("dummy_x", 150.0)) - 150.0
	_dummy.respawn_at(Vector2(dummy_x, FLOOR_Y - _dummy.stats.body_size.y * 0.5 - 2.0))
	_dummy.facing = -1
	_dummy.set_ability(&"", 0.0)


func _physics_process(delta: float) -> void:
	if _hero == null or not is_instance_valid(_hero):
		return
	_clock += delta
	if _clock >= LOOP_SECONDS:
		_reset_loop()
		return
	var frame := InputFrame.new()
	var press_at: float = float(_plan.get("press_at", 0.4))
	if _clock >= press_at:
		frame.move = _plan.get("hold", Vector2.ZERO)
		if not _pressed:
			_pressed = true
			frame.press(InputFrame.Action.SKILL)
	elif _clock < press_at:
		# Face the dummy before the skill: a tap toward it, then still.
		frame.move = Vector2(1, 0) if _clock < 0.05 else Vector2.ZERO
	_hero.feed_input(frame)
	_dummy.feed_input(InputFrame.new())
	# Anyone thrown off the little stage is caught before they fall forever.
	for player in [_hero, _dummy]:
		if player.global_position.y > 600.0 or absf(player.global_position.x) > 1400.0:
			player.velocity = Vector2.ZERO
			player.global_position.y = -600.0


## A strip of grass and dirt under the demo, in the level's colours.
class _Ground extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(-900.0, 0.0, 1800.0, 12.0), Color8(79, 154, 58))
		draw_rect(Rect2(-900.0, 0.0, 1800.0, 4.0), Color8(126, 217, 87))
		draw_rect(Rect2(-900.0, 12.0, 1800.0, 60.0), Color8(92, 58, 34))
		for i in 30:
			draw_rect(Rect2(-880.0 + i * 60.0, 24.0 + (i % 3) * 10.0, 8.0, 6.0), Color8(70, 44, 26))
