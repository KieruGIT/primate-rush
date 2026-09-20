class_name Player
extends CharacterBody2D

# ============================================================
# MONKEY
#
# One script, five states: ground, air, climb, swing, stun. Movement feel
# (coyote time, jump buffering, variable jump height, asymmetric gravity)
# is the foundation everything else sits on, so it stays here rather than
# being split across a state machine of tiny files that each hide a third
# of the tuning.
#
# Nothing in here reads the keyboard. It consumes an InputFrame, which is
# what lets keyboard, touch, and the network drive the same monkey.
#
# Authority: the host simulates everyone. A client simulates only its own
# monkey, as prediction, and snaps when the host disagrees by enough to
# matter. Hits and knockback are resolved on the host only, because a
# desynced knockback is the one thing in this game that reads as broken.
# ============================================================

signal state_changed(new_state: int)
signal attacked(flavor: StringName)
signal hit_landed(target_id: int)
signal hit_taken(attacker_id: int, knockback: Vector2)
signal skill_used(skill_id: StringName)
signal bananas_changed(count: int)
signal ability_changed(ability_id: StringName)

# DASH is appended rather than inserted: the state enum travels over the
# wire as an int, and renumbering it would desync mid-update.
enum State { GROUND, AIR, CLIMB, SWING, STUN, DASH }

const ATTACK_FLAVORS: Array[StringName] = [&"slap", &"punch", &"kick"]

@export_group("Identity")
@export var stats: MonkeyStats
## Peer id when networked, slot index when local. Unique per monkey either way.
@export var player_id: int = 1
## True on the machine whose player this is. Drives camera and prediction.
@export var local_control: bool = true
## Cosmetic only. Never touches stats, and never will.
@export var hat_id: StringName = &"none"
## Driven by a BotBrain instead of a device. Changes nothing about how the
## monkey moves, only who is sending the input.
@export var is_bot: bool = false
## What a bot is called on the name tag and the scoreboard. Empty for people,
## who are named after the monkey they picked.
@export var bot_name: String = ""

@export_group("Ground and air")
@export var ground_accel: float = 2800.0
@export var ground_friction: float = 3200.0
@export var air_accel: float = 1900.0
@export var air_friction: float = 600.0
## Heavier gravity on the way down is worth more to game feel than any other
## number here. Tune this before tuning anything else.
@export var fall_gravity_mult: float = 1.7
@export var max_fall_speed: float = 1400.0

@export_group("Jump")
## Jump shortly after walking off a ledge still counts.
@export var coyote_time: float = 0.12
## Jump pressed shortly before landing still counts.
@export var jump_buffer_time: float = 0.12
## Releasing jump early cuts the rise, giving short and tall hops.
@export var jump_cut_multiplier: float = 0.45

@export_group("Climb")
## Horizontal drift while on a wall, as a fraction of climb speed.
@export var climb_lateral_ratio: float = 0.45
## Sideways shove when jumping off a wall, so wall jumps make progress.
@export var climb_jump_push: float = 320.0
## Blocks instantly regrabbing the wall you just jumped off.
@export var climb_regrab_delay: float = 0.18

@export_group("Swing")
@export var swing_min_length: float = 48.0
@export var swing_max_length: float = 260.0
## Pumping the stick adds angular velocity, which is the whole skill.
@export var swing_pump: float = 8.2
## Climbing the rope itself, in pixels per second.
@export var swing_rope_speed: float = 180.0
## Release speed multiplier. Above 1.0 so a well-timed release beats running.
@export var swing_release_boost: float = 1.18
## Prevents a shortened rope from becoming an accidental physics cannon.
@export var swing_max_speed: float = 1320.0
@export var swing_regrab_delay: float = 0.35

@export_group("Attack")
## Wind-up before the hitbox opens. Long enough to be readable, short
## enough that whiffing is not a death sentence in a game with no deaths.
@export var attack_windup: float = 0.08
@export var attack_active: float = 0.10
@export var attack_recovery: float = 0.16
@export var attack_cooldown: float = 0.34
## Small forward commitment makes a slap close distance instead of feeling
## like the fist is detached from the monkey.
@export var attack_lunge: float = 115.0
## Upward share of knockback. Pure sideways knockback slides people along
## the floor and reads as nothing happening.
@export var knockback_lift: float = 0.55

@export_group("Skills")
## Gorilla. Short forward grapple: terrain pulls you to it, a player gets
## yanked to you instead.
@export var grapple_range: float = 420.0
@export var grapple_pull_speed: float = 1500.0
@export var grapple_yank_speed: float = 900.0
## Gibbon. One launch per landing, in the aimed direction.
@export var air_launch_speed: float = 1150.0
## Macaque. Short roll that ignores knockback and punishes whoever swung.
@export var roll_speed: float = 900.0
@export var roll_time: float = 0.26
## Orangutan. Twice the gorilla's reach, paid for with a visible windup.
@export var long_arm_range_multiplier: float = 2.0
@export var long_arm_windup: float = 0.32
## Capuchin. Dash that steals from whoever it passes through.
@export var snatch_speed: float = 1150.0
@export var snatch_time: float = 0.3
@export var snatch_radius: float = 46.0
## Share of the victim's bananas a snatch takes.
@export_range(0.0, 1.0, 0.05) var snatch_fraction: float = 0.3
## Momentum theft in modes with no bananas: they slow, you speed up.
@export var snatch_slow_seconds: float = 1.6
## Safety valve so a grapple that never arrives cannot strand you in DASH.
@export var dash_timeout: float = 0.7
## Whiffing still costs something, or the grapple is a free scan every frame.
@export var skill_whiff_cooldown: float = 0.6

@export_group("Sprint and dash")
## Held sprint multiplies run speed, on the ground and in the air, so a
## sprinting jump carries further. Every monkey has it; the stats still
## decide how fast "fast" is.
@export var sprint_multiplier: float = 1.45
## Dash: a short burst in the aimed direction, any of eight. One in the air
## per jump, reset by landing, climbing or grabbing a vine.
@export var dash_speed: float = 1050.0
@export var dash_time: float = 0.15
@export var dash_cooldown: float = 0.55
## Share of dash speed kept when it ends, so a dash flows into the run.
@export var dash_carry: float = 0.55

@export_group("Hoard")
## Banana Magnet reach.
@export var magnet_radius: float = 260.0
## Super Hit. Massive knockback and a doubled banana drop, once.
@export var super_hit_multiplier: float = 2.5
@export var speed_boost_multiplier: float = 1.5
## Share of a target's bananas knocked loose by a normal hit. Load bearing:
## without a drop, players farm separate corners and the mode has no tension.
@export_range(0.0, 1.0, 0.05) var drop_fraction: float = 0.4

@export_group("Feel")
## Camera kick when this monkey gets hit. Local camera only: shaking a
## screen for something that happened to someone else is just noise.
@export var shake_on_hit: float = 14.0
@export var shake_on_land: float = 5.0
## Impact speed a landing needs before it registers as heavy.
@export var heavy_land_speed: float = 900.0
@export var squash_recovery: float = 6.0

@export_group("Networking")
## Position error past which a predicting client stops arguing and snaps.
@export var reconcile_snap_distance: float = 64.0
@export var reconcile_blend: float = 0.28

var state: int = State.AIR
var facing: int = 1
var stun_timer: float = 0.0
var is_attacking: bool = false

var _input: InputFrame = InputFrame.new()
var _coyote_timer: float = 0.0
var _buffer_timer: float = 0.0
var _attack_timer: float = 0.0
var _attack_cooldown_timer: float = 0.0
var _hitbox_open: bool = false
var _already_hit: Array[int] = []

var skill_timer: float = 0.0
var invuln_timer: float = 0.0
var _dash_time: float = 0.0
var _windup_timer: float = 0.0
var _windup_skill: StringName = &""
var _snatch_hit: Array[int] = []
var _dash_kind: StringName = &""
var _dash_target: Vector2 = Vector2.ZERO
var _air_launch_ready: bool = true
var _air_dash_ready: bool = true
var _dash_cooldown_timer: float = 0.0
var _dash_dir: Vector2 = Vector2.RIGHT
var _trail_timer: float = 0.0
## A spring launch waiting for the next gravity step. Set by bounce(), used
## by _apply_gravity, because a monkey standing on a pad is on the floor and
## the floor would otherwise zero the launch before it ever moved anyone.
var _pending_bounce: float = 0.0
## True from a pressed jump until it peaks or is cut. See _apply_jump_cut.
var _jump_rising: bool = false

## 2v2 Slap. Team is -1 outside that mode. Damage is a percentage that only
## goes up while you stay on the island, and every point of it makes the
## next slap throw you further - the reason a long survivor finally flies.
var team: int = -1
var slap_damage: float = 0.0
## Share of extra knockback per percent of damage.
const SLAP_SCALING: float = 0.022
## Knockback at 0%, as a share of the normal amount. Low, so the first
## slaps shove rather than launch and a fight has a middle, not just an end.
const SLAP_BASE: float = 0.4
## Invulnerable after coming back, so nobody is slapped off the moment
## they land. Shown as a blink.
const SPAWN_SHIELD: float = 1.5
var _spawn_shield: float = 0.0
## Damage a slap adds, before the attacker's Power.
const SLAP_DAMAGE_PER_HIT: float = 11.0

var bananas: int = 0
var ability: StringName = &""
var ability_timer: float = 0.0

var _climb_lock: float = 0.0
var _swing_lock: float = 0.0
var _swing_anchor: Vector2 = Vector2.ZERO
var _swing_node: Node2D = null
var _swing_length: float = 0.0
var _swing_angle: float = 0.0
var _swing_ang_vel: float = 0.0
var _sprint_blend: float = 0.0
var _sprint_latched: bool = false

var _shake_time: float = 0.0
var _shake_power: float = 0.0
var _squash: float = 0.0
var _was_on_floor: bool = true
var _fall_speed: float = 0.0

var _net_target: Vector2 = Vector2.ZERO
var _has_net_target: bool = false

## Gray-box body, kept hidden: it still sizes itself to the collision box,
## which makes it the quickest way to check the art against the hitbox.
@onready var body: ColorRect = $Body
var sprite: MonkeySprite = null
var _sprite_shadow: Sprite2D = null
var _sprite_rim: Sprite2D = null
var _slap_fist: SlapFist = null
var _attack_was_visible: bool = false
var _ground_shadow_y: float = 34.0
var _ground_shadow_alpha: float = 0.0
var _last_position: Vector2 = Vector2.ZERO
var _moved_speed: float = 0.0
@onready var shape: CollisionShape2D = $Collision
@onready var climb_sensor: Area2D = $ClimbSensor
@onready var vine_sensor: Area2D = $VineSensor
@onready var hitbox: Area2D = $Hitbox
@onready var hitbox_shape: CollisionShape2D = $Hitbox/Shape
@onready var hurtbox: Area2D = $Hurtbox
@onready var head_anchor: Marker2D = $HeadAnchor
@onready var headwear: Headwear = $HeadAnchor/Headwear
@onready var camera: Camera2D = $Camera2D
@onready var name_label: Label = $NameLabel


func _ready() -> void:
	if stats == null:
		stats = GameConfig.get_monkey(&"macaque")
	hurtbox.set_meta(&"player", self)
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	_apply_appearance()
	_set_camera_active(local_control)


## Call right after instancing, before the monkey is added to the tree.
func setup(monkey: MonkeyStats, id: int, is_local: bool, tint: Color = Color(0, 0, 0, 0), hat: StringName = &"none") -> void:
	stats = monkey
	player_id = id
	local_control = is_local
	hat_id = hat
	if tint.a > 0.0:
		set_meta(&"tint", tint)
	if is_node_ready():
		_apply_appearance()
		_set_camera_active(is_local)


func _apply_appearance() -> void:
	var size: Vector2 = stats.body_size
	body.size = size
	body.position = -size * 0.5
	body.color = get_meta(&"tint", stats.body_color)
	body.visible = false

	if sprite == null:
		sprite = MonkeySprite.new()
		sprite.name = "Sprite"
		add_child(sprite)
		move_child(sprite, 0)
	sprite.setup(stats.id)
	if _sprite_shadow == null:
		_sprite_shadow = Sprite2D.new()
		_sprite_shadow.name = "CharacterDepthShadow"
		_sprite_shadow.z_index = -1
		_sprite_shadow.modulate = Color(0.06, 0.035, 0.07, 0.34)
		add_child(_sprite_shadow)
		move_child(_sprite_shadow, 0)
	if _sprite_rim == null:
		_sprite_rim = Sprite2D.new()
		_sprite_rim.name = "CharacterLightRim"
		_sprite_rim.z_index = -1
		_sprite_rim.modulate = Color(1.0, 0.78, 0.32, 0.48)
		add_child(_sprite_rim)
		move_child(_sprite_rim, 1)
	if _slap_fist == null:
		_slap_fist = SlapFist.new()
		_slap_fist.name = "SlapFist"
		_slap_fist.z_index = 8
		add_child(_slap_fist)
		_slap_fist.visible = false
	# Feet on the bottom of the collision box, whatever size the monkey is.
	sprite.position = Vector2(0.0, size.y * 0.5)
	var head_top := size.y * 0.5 - MonkeySprite.head_height(stats.id)

	var rect := shape.shape as RectangleShape2D
	if rect != null:
		# Duplicated because a shape resource shared between instances would
		# resize every monkey in the match at once.
		rect = rect.duplicate()
		rect.size = size
		shape.shape = rect

	if name_label != null:
		name_label.text = display_label()
		name_label.position.y = head_top - 30.0
		# The slot colour lives on the name now that the body wears the
		# monkey's own fur. Four orange rectangles told players apart; four
		# brown monkeys need their names to.
		name_label.add_theme_color_override(&"font_color", get_meta(&"tint", Color.WHITE))
		name_label.add_theme_color_override(&"font_outline_color", Color(0.08, 0.06, 0.05))
		name_label.add_theme_constant_override(&"outline_size", 6)
		_refresh_name_label()

	# The anchor moves with the body rather than the hat carrying a per-monkey
	# offset, so one hat sits correctly on a capuchin and on a gorilla.
	if head_anchor != null:
		head_anchor.position = Vector2(0.0, head_top + 4.0)
	if headwear != null:
		var hat: Dictionary = GameConfig.get_hat(hat_id)
		headwear.apply(hat["style"], hat["color"], 24.0)


var _damage_label: Label = null


func _refresh_name_label() -> void:
	if name_label == null:
		return
	name_label.text = display_label()
	if team < 0:
		return
	# Team colour on the name in 2v2, so allies read at a glance.
	name_label.add_theme_color_override(&"font_color", GameConfig.TEAM_COLORS[team])
	# Damage as its own big number over the head, white going to red as it
	# climbs: the one number that says how close this monkey is to flying.
	if _damage_label == null:
		_damage_label = Label.new()
		_damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_damage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_damage_label.add_theme_font_size_override(&"font_size", 22)
		_damage_label.add_theme_color_override(&"font_outline_color", Color(0.08, 0.06, 0.05))
		_damage_label.add_theme_constant_override(&"outline_size", 8)
		add_child(_damage_label)
	_damage_label.size = Vector2(120, 30)
	_damage_label.position = name_label.position + Vector2(-60.0 + name_label.size.x * 0.5, -26.0)
	_damage_label.text = str(int(slap_damage))
	var heat := clampf(slap_damage / 120.0, 0.0, 1.0)
	var colour := Color.WHITE.lerp(Color(1.0, 0.85, 0.2), minf(heat * 2.0, 1.0)).lerp(Color(1.0, 0.25, 0.2), maxf(heat * 2.0 - 1.0, 0.0))
	_damage_label.add_theme_color_override(&"font_color", colour)


## Bots read as a name, people read as a monkey. Four rows of "Gibbon" on a
## scoreboard tells you nothing; "Mango" tells you who just took your lead.
func display_label() -> String:
	if not is_bot:
		return stats.display_name
	return bot_name if not bot_name.is_empty() else "%s (bot)" % stats.display_name


func _set_camera_active(active: bool) -> void:
	if camera == null:
		return
	camera.enabled = active
	if active:
		camera.make_current()


# --- Simulation ----------------------------------------------------

func _physics_process(delta: float) -> void:
	if _simulates():
		_apply_input_frame(delta)
		_tick_timers(delta)
		match state:
			State.STUN:
				_process_stun(delta)
			State.DASH:
				_process_dash(delta)
			State.CLIMB:
				_process_climb(delta)
			State.SWING:
				_process_swing(delta)
			_:
				_process_grounded_or_air(delta)
		_tick_attack(delta)
		if _has_net_target and local_control and not _is_authority():
			_reconcile()
	else:
		_follow_net_target(delta)
	_update_visual()


## The host simulates every monkey. A client simulates only its own, as
## prediction. Everyone else on a client is replay of host state.
func _simulates() -> bool:
	if not Net.is_online():
		return true
	if Net.is_host():
		return true
	return local_control


func _is_authority() -> bool:
	return not Net.is_online() or Net.is_host()


func feed_input(frame: InputFrame) -> void:
	_input.move = frame.move
	_input.jump_held = frame.jump_held
	_input.sprint_held = frame.sprint_held
	_input.merge_buttons(frame)


func _apply_input_frame(_delta: float) -> void:
	if absf(_input.move.x) > 0.2:
		facing = 1 if _input.move.x > 0.0 else -1


func _tick_timers(delta: float) -> void:
	_climb_lock = maxf(_climb_lock - delta, 0.0)
	_swing_lock = maxf(_swing_lock - delta, 0.0)
	_attack_cooldown_timer = maxf(_attack_cooldown_timer - delta, 0.0)
	_buffer_timer = maxf(_buffer_timer - delta, 0.0)
	skill_timer = maxf(skill_timer - delta, 0.0)
	invuln_timer = maxf(invuln_timer - delta, 0.0)
	if ability_timer > 0.0:
		ability_timer -= delta
		if ability_timer <= 0.0:
			set_ability(&"", 0.0)
	_tick_windup(delta)
	_dash_cooldown_timer = maxf(_dash_cooldown_timer - delta, 0.0)
	_spawn_shield = maxf(_spawn_shield - delta, 0.0)
	if is_on_floor() or state == State.CLIMB or state == State.SWING:
		_air_dash_ready = true
	if is_on_floor():
		_air_launch_ready = true
	if _input.consume(InputFrame.Action.DASH):
		_try_dash()
	if _input.consume(InputFrame.Action.JUMP):
		_buffer_timer = jump_buffer_time
	if _input.consume(InputFrame.Action.ATTACK):
		_try_attack()
	if _input.consume(InputFrame.Action.SKILL):
		_try_skill()


# --- Ground and air ------------------------------------------------

func _process_grounded_or_air(delta: float) -> void:
	if _try_enter_swing():
		return
	if _try_enter_climb():
		return

	_apply_gravity(delta)
	_apply_horizontal(delta)
	_try_jump()
	_apply_jump_cut()

	move_and_slide()

	if is_on_floor():
		_coyote_timer = coyote_time
		_set_state(State.GROUND)
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)
		_set_state(State.AIR)


func _apply_gravity(delta: float) -> void:
	if _pending_bounce > 0.0:
		velocity.y = -_pending_bounce
		_pending_bounce = 0.0
		return
	if is_on_floor():
		# A small downward bias instead of zero keeps floor contact across
		# slopes and moving edges, which is what is_on_floor() actually tests.
		velocity.y = 40.0
		return
	var g := GameConfig.BASE_GRAVITY
	if velocity.y > 0.0:
		g *= fall_gravity_mult
	velocity.y = minf(velocity.y + g * delta, max_fall_speed)


func _apply_horizontal(delta: float) -> void:
	var axis := _input.move.x
	var grounded := is_on_floor()
	var accel := ground_accel if grounded else air_accel * stats.air_control()
	var friction := ground_friction if grounded else air_friction
	var wants_sprint := _input.sprint_held and absf(axis) > 0.1
	var sprint_rate := 7.5 if wants_sprint else 4.5
	_sprint_blend = move_toward(_sprint_blend, 1.0 if wants_sprint else 0.0, sprint_rate * delta)
	if wants_sprint and grounded and not _sprint_latched:
		# A small launch on the first stride makes sprint a verb rather than a
		# barely visible maximum-speed setting.
		velocity.x += axis * 72.0
	_sprint_latched = wants_sprint

	if absf(axis) > 0.1:
		var top := stats.run_speed() * _speed_multiplier() * lerpf(1.0, sprint_multiplier, _sprint_blend)
		if grounded:
			accel *= lerpf(1.0, 1.72, _sprint_blend)
			if signf(velocity.x) != signf(axis):
				accel *= 1.28
		velocity.x = move_toward(velocity.x, axis * top, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)


func _speed_multiplier() -> float:
	match ability:
		&"speed_boost":
			return speed_boost_multiplier
		&"slowed":
			return 0.55
	return 1.0


# --- Bananas and lucky box abilities -------------------------------

## Set by the hoard director's scores broadcast. Never set locally, so the
## number on screen is always the number the host is scoring.
func set_bananas(count: int) -> void:
	bananas = maxi(count, 0)
	bananas_changed.emit(bananas)


## Ghost cannot be hit and cannot hit. Both halves matter: an untouchable
## monkey that could still knock people around would be the only pickup
## anyone ever wants.
func set_ability(ability_id: StringName, duration: float) -> void:
	ability = ability_id
	ability_timer = duration
	modulate.a = 0.45 if ability_id == &"ghost" else 1.0
	ability_changed.emit(ability_id)


func is_ghost() -> bool:
	return ability == &"ghost"


func _try_jump() -> void:
	var can_jump := is_on_floor() or _coyote_timer > 0.0
	if can_jump and _buffer_timer > 0.0:
		velocity.y = stats.jump_velocity()
		_jump_rising = true
		_buffer_timer = 0.0
		_coyote_timer = 0.0
		Sfx.play(&"jump", _voice_pitch())


## Only a jump the player pressed can be cut short. A spring, a dash or a
## skill launch that rises is not a jump, and cutting it would throw away
## the height the level was built around.
func _apply_jump_cut() -> void:
	if not _jump_rising:
		return
	if velocity.y >= 0.0:
		_jump_rising = false
		return
	if not _input.jump_held:
		velocity.y *= jump_cut_multiplier
		_jump_rising = false


# --- Climb ---------------------------------------------------------

func _try_enter_climb() -> bool:
	if _climb_lock > 0.0 or not _touching_climbable():
		return false
	# Pressing into the wall or up it - or holding jump against it, since
	# jump climbs too. Brushing past a wall mid-jump with nothing held
	# should not yank you onto it.
	var holding_jump := _input.jump_held and not is_on_floor()
	if absf(_input.move.y) < 0.35 and absf(_input.move.x) < 0.5 and not holding_jump:
		return false
	_set_state(State.CLIMB)
	velocity = Vector2.ZERO
	_air_launch_ready = true
	return true


func _process_climb(delta: float) -> void:
	if not _touching_climbable():
		_set_state(State.AIR)
		return

	# Jump on a wall is a climb. It becomes a wall jump only when you are
	# also pushing away from the wall - the one case where leaving is meant.
	if _buffer_timer > 0.0:
		_buffer_timer = 0.0
		var wall_side := _wall_side()
		if wall_side != 0.0 and _input.move.x * wall_side < -0.3:
			_climb_lock = climb_regrab_delay
			velocity = Vector2(-wall_side * climb_jump_push, stats.jump_velocity() * 0.92)
			facing = -int(wall_side)
			_jump_rising = true
			Sfx.play(&"jump", _voice_pitch())
			_set_state(State.AIR)
			return

	var speed := stats.climb_speed()
	var vertical := _input.move.y
	if _input.jump_held and vertical > -0.35 and vertical < 0.35:
		vertical = -1.0
	velocity = Vector2(
		_input.move.x * speed * climb_lateral_ratio,
		vertical * speed
	)
	move_and_slide()

	if is_on_floor() and _input.move.y > 0.1:
		_set_state(State.GROUND)


## Which side the wall being climbed is on: -1 left, 1 right, 0 unknown.
func _wall_side() -> float:
	for area in climb_sensor.get_overlapping_areas():
		var offset := (area as Node2D).global_position.x - global_position.x
		if absf(offset) > 1.0:
			return signf(offset)
	return float(facing)


func _touching_climbable() -> bool:
	return climb_sensor.has_overlapping_areas() or climb_sensor.has_overlapping_bodies()


# --- Swing ---------------------------------------------------------
#
# Manual pendulum integration rather than PinJoint2D. Joints are a physics
# server black box that is hard to sync and harder to tune; an angle and an
# angular velocity are two floats the host can ship over the wire.

func _try_enter_swing() -> bool:
	if _swing_lock > 0.0 or is_on_floor():
		return false
	var anchor_node := _nearest_vine()
	if anchor_node == null:
		return false

	_swing_node = anchor_node
	_swing_anchor = anchor_node.global_position
	var offset := global_position - _swing_anchor
	if offset.length() < 1.0:
		return false

	_swing_length = clampf(offset.length(), swing_min_length, swing_max_length)
	_swing_angle = offset.angle()
	# Only the tangential part of current velocity survives the grab. The
	# radial part is what the rope yanks away, and keeping it would let you
	# rocket straight outward off a vine.
	var tangent := Vector2(-sin(_swing_angle), cos(_swing_angle))
	_swing_ang_vel = velocity.dot(tangent) / _swing_length
	_air_launch_ready = true
	Sfx.play(&"grab", _voice_pitch())
	_set_state(State.SWING)
	return true


func _process_swing(delta: float) -> void:
	if _swing_node == null or not is_instance_valid(_swing_node):
		_release_swing(false)
		return
	_swing_anchor = _swing_node.global_position

	if _buffer_timer > 0.0:
		_buffer_timer = 0.0
		_release_swing(true)
		return

	# Angle is measured from +X with +Y down, so straight below the anchor
	# is PI/2 and gravity's tangential component is cos(angle).
	var ang_accel := (GameConfig.BASE_GRAVITY / _swing_length) * cos(_swing_angle)
	_swing_ang_vel += ang_accel * delta
	# Horizontal input is projected onto the rope's tangent.  Raw world-X
	# input was previously added straight to angular velocity, which made the
	# correct pump direction reverse at surprising points in the arc.
	var tangent := Vector2(-sin(_swing_angle), cos(_swing_angle))
	var pump := _input.move.x * tangent.x
	var helping := absf(_swing_ang_vel) < 0.05 or signf(pump) == signf(_swing_ang_vel)
	_swing_ang_vel += pump * swing_pump * stats.air_control() * (1.0 if helping else 0.42) * delta
	# Stats used to damp once per physics tick.  Making that time based keeps
	# feel stable at other tick rates, while the gentler exponent preserves a
	# satisfying arc instead of bleeding all momentum before release.
	_swing_ang_vel *= pow(stats.swing_retention(), delta * 20.0)

	var old_length := _swing_length
	_swing_length = clampf(
		_swing_length + _input.move.y * swing_rope_speed * delta,
		swing_min_length,
		swing_max_length
	)
	# Pulling inward conserves tangential speed, the intuitive reward for
	# actively working the rope.  The speed cap keeps the result competitive.
	if _swing_length < old_length:
		_swing_ang_vel *= old_length / maxf(_swing_length, 1.0)
	var tangential_speed := clampf(_swing_ang_vel * _swing_length, -swing_max_speed, swing_max_speed)
	_swing_ang_vel = tangential_speed / _swing_length
	_swing_angle += _swing_ang_vel * delta

	var target := _swing_anchor + Vector2(cos(_swing_angle), sin(_swing_angle)) * _swing_length
	# Driving through move_and_slide instead of teleporting keeps level
	# collision honest: you scrape along a wall instead of clipping into it.
	velocity = (target - global_position) / delta
	move_and_slide()

	if get_slide_collision_count() > 0:
		_swing_ang_vel *= 0.6


func _release_swing(boosted: bool) -> void:
	var tangent := Vector2(-sin(_swing_angle), cos(_swing_angle))
	velocity = tangent * _swing_ang_vel * _swing_length
	if boosted:
		velocity *= swing_release_boost
		var release_lift := lerpf(0.32, 0.52, clampf(velocity.length() / swing_max_speed, 0.0, 1.0))
		velocity.y = minf(velocity.y, stats.jump_velocity() * release_lift)
	_swing_node = null
	_swing_lock = swing_regrab_delay
	if boosted:
		Sfx.play(&"swing", _voice_pitch())
	_set_state(State.AIR)


func _nearest_vine() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for area in vine_sensor.get_overlapping_areas():
		if not area.is_in_group(&"vine"):
			continue
		var anchor := area as Node2D
		if area.has_method(&"get_anchor"):
			anchor = area.call(&"get_anchor")
		if anchor == null:
			continue
		var dist := global_position.distance_squared_to(anchor.global_position)
		if dist < best_dist:
			best_dist = dist
			best = anchor
	return best


# --- Attack, knockback, stun ---------------------------------------

func _try_attack() -> void:
	if is_attacking or _attack_cooldown_timer > 0.0 or state == State.STUN:
		return
	is_attacking = true
	_attack_timer = 0.0
	_already_hit.clear()
	var lunge := attack_lunge if is_on_floor() else attack_lunge * 0.45
	velocity.x += float(facing) * lunge
	# The three flavors are cosmetic and must stay mechanically identical.
	# The moment a kick outranges a slap, players fish for an animation they
	# cannot choose, and a variety system becomes a frustration system.
	Sfx.play(&"attack", _voice_pitch())
	if _slap_fist != null:
		_slap_fist.play(facing, stats.body_color)
		_attack_was_visible = true
	attacked.emit(ATTACK_FLAVORS[randi() % ATTACK_FLAVORS.size()])


func _tick_attack(delta: float) -> void:
	if not is_attacking:
		return
	_attack_timer += delta
	var should_be_open := _attack_timer >= attack_windup and _attack_timer < attack_windup + attack_active
	if should_be_open != _hitbox_open:
		_set_hitbox_open(should_be_open)
	if _attack_timer >= attack_windup + attack_active + attack_recovery:
		is_attacking = false
		_attack_cooldown_timer = attack_cooldown


func _set_hitbox_open(open: bool) -> void:
	_hitbox_open = open
	# Deferred because this is reached from area_entered, and the physics
	# server refuses a monitoring change while it is flushing queries.
	hitbox.set_deferred(&"monitoring", open)
	hitbox_shape.set_deferred(&"disabled", not open)
	if not open:
		return
	hitbox.position.x = absf(hitbox.position.x) * facing
	# Anything already inside the box when it opens never fires area_entered,
	# so sweep once on open. A direct shape query rather than
	# get_overlapping_areas(), because monitoring was only just enabled and
	# deferred, so the area itself does not know what it overlaps yet.
	if _is_authority():
		_sweep_hitbox()


func _sweep_hitbox() -> void:
	var shape_2d := hitbox_shape.shape
	if shape_2d == null:
		return
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape_2d
	query.transform = hitbox.global_transform
	query.collision_mask = GameConfig.LAYER_HURTBOX
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for hit in get_world_2d().direct_space_state.intersect_shape(query, GameConfig.NET_MAX_PLAYERS):
		var area := hit.get("collider") as Area2D
		if area != null:
			_resolve_hit(area)


func _on_hitbox_area_entered(area: Area2D) -> void:
	if _hitbox_open and _is_authority():
		_resolve_hit(area)


func _resolve_hit(area: Area2D) -> void:
	if not area.has_meta(&"player"):
		return
	var target := area.get_meta(&"player") as Player
	if target == null or target == self or _already_hit.has(target.player_id):
		return
	# No friendly fire: slapping your partner off the island is funny once.
	if team >= 0 and target.team == team:
		return
	if is_ghost() or target.is_ghost():
		return
	_already_hit.append(target.player_id)

	var dir := Vector2(float(facing), 0.0)
	var to_target := (target.global_position - global_position)
	if absf(to_target.x) > 1.0:
		dir.x = signf(to_target.x)
	dir.y = -knockback_lift
	dir = dir.normalized()

	# Magnitude is the attacker's Power against the target's Weight, resolved
	# on the target so one monkey's stat block is the only thing that decides
	# how far it flies.
	var super_hit := ability == &"super_hit"
	var force := dir * stats.knockback_dealt() * (super_hit_multiplier if super_hit else 1.0)
	if target.team >= 0:
		force *= SLAP_BASE * (1.0 + target.slap_damage * SLAP_SCALING)
	if super_hit:
		# One shot, spent on contact rather than on the swing, so a whiffed
		# Super Hit is not the whole pickup wasted.
		set_ability(&"", 0.0)
	target.take_hit(player_id, force, GameConfig.BASE_STUN_TIME, super_hit)
	if _slap_fist != null:
		_slap_fist.impact()
	if local_control:
		kick_camera(4.5 if not super_hit else 8.0, 0.10)
	hit_landed.emit(target.player_id)
	if Net.is_online():
		Net.broadcast_hit(target.player_id, force, GameConfig.BASE_STUN_TIME, player_id)


## Applied by the host, replayed on clients. Never called speculatively by a
## client: knockback that disagrees between machines is the single most
## broken-feeling desync in this game.
func take_hit(attacker_id: int, force: Vector2, base_stun: float, double_drop: bool = false) -> void:
	if _spawn_shield > 0.0:
		return
	if invuln_timer > 0.0:
		_counter_attacker(attacker_id)
		return
	if is_ghost():
		return
	if _is_authority() and bananas > 0:
		_knock_bananas_loose(double_drop)
	var applied := force.normalized() * stats.knockback_taken(force.length())
	velocity = applied
	if team >= 0:
		# Every machine applies the same hits in the same order, so every
		# machine arrives at the same percentage without shipping it.
		slap_damage += SLAP_DAMAGE_PER_HIT
		_refresh_name_label()
	stun_timer = base_stun / maxf(stats.weight, 0.2)
	is_attacking = false
	_set_hitbox_open(false)

	# Being hit is the universal interrupt: it drops you off a vine and
	# peels you off a wall. That is what makes interference worth doing.
	if state == State.SWING:
		_swing_node = null
		_swing_lock = swing_regrab_delay
	if state == State.CLIMB:
		_climb_lock = climb_regrab_delay
	_set_state(State.STUN)
	# Pitched by the weight of whoever got hit, so a gorilla taking one reads
	# differently from a capuchin without any extra audio.
	# A slap that will send you far gets the heavy sound.
	Sfx.play(&"slap" if applied.length() > 900.0 else &"hit", _voice_pitch())
	if local_control:
		kick_camera(shake_on_hit, 0.28)
	_squash = 0.5
	hit_taken.emit(attacker_id, applied)


## Hitting someone knocks bananas loose for anyone to grab. The director
## owns the number and this only asks: the score it broadcasts is the single
## source of truth, and a monkey deducting its own bananas would be undone
## by the next scores packet.
func _knock_bananas_loose(double_drop: bool) -> void:
	var director: Node = get_tree().get_first_node_in_group(&"hoard_director")
	if director != null and director.has_method(&"knock_bananas_loose"):
		director.call(&"knock_bananas_loose", player_id, global_position, double_drop, drop_fraction)


func _process_stun(delta: float) -> void:
	stun_timer -= delta
	_apply_gravity(delta)
	# Friction still applies during stun, otherwise a hard hit slides you
	# forever and the stun never visibly ends.
	velocity.x = move_toward(velocity.x, 0.0, air_friction * 0.5 * delta)
	move_and_slide()
	if stun_timer <= 0.0:
		_set_state(State.GROUND if is_on_floor() else State.AIR)


# --- Skills --------------------------------------------------------
#
# One skill per monkey, dispatched by the stat resource rather than by a
# subclass per monkey. A monkey is data plus a skill id, so adding the
# capuchin later is a .tres and one branch, not a new script.

func _try_skill() -> void:
	if skill_timer > 0.0 or state == State.STUN or stats.skill_id == &"":
		return
	var fired := false
	match stats.skill_id:
		&"grapple_dash":
			fired = _skill_grapple_dash(1.0)
		&"air_launch":
			fired = _skill_air_launch()
		&"counter_roll":
			fired = _skill_counter_roll()
		&"long_arm":
			fired = _skill_long_arm()
		&"snatch":
			fired = _skill_snatch()
	skill_timer = stats.skill_cooldown if fired else skill_whiff_cooldown
	if fired:
		skill_used.emit(stats.skill_id)


func _aim_direction() -> Vector2:
	if _input.move.length() > 0.35:
		return _input.move.normalized()
	return Vector2(float(facing), -0.2).normalized()


func _skill_grapple_dash(range_multiplier: float) -> bool:
	var aim := Vector2(float(facing), 0.0)
	if absf(_input.move.y) > 0.3:
		aim = Vector2(float(facing), _input.move.y).normalized()

	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + aim * grapple_range * range_multiplier,
		GameConfig.LAYER_WORLD | GameConfig.LAYER_PLAYER,
		[get_rid()]
	)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false

	var collider: Object = hit.get("collider")
	var target := collider as Player
	if target != null:
		# Yanking another monkey is a hit, so it resolves where every other
		# hit resolves. A client pulling someone on its own screen only would
		# be the most visible desync in the game.
		if not _is_authority():
			return true
		var pull := (global_position - target.global_position).normalized() * grapple_yank_speed
		target.take_hit(player_id, pull, GameConfig.BASE_STUN_TIME * 0.6)
		if Net.is_online():
			Net.broadcast_hit(target.player_id, pull, GameConfig.BASE_STUN_TIME * 0.6, player_id)
		return true

	_dash_kind = &"grapple"
	_dash_target = hit.get("position", global_position)
	_dash_time = dash_timeout
	_swing_node = null
	_set_state(State.DASH)
	return true


func _skill_air_launch() -> bool:
	if is_on_floor() or not _air_launch_ready:
		return false
	velocity = _aim_direction() * air_launch_speed
	_air_launch_ready = false
	# Clearing the regrab lock is what lets a launch chain straight into a
	# vine, which is the gibbon's whole identity.
	_swing_lock = 0.0
	_swing_node = null
	_set_state(State.AIR)
	return true


func _skill_counter_roll() -> bool:
	_dash_kind = &"roll"
	_dash_time = roll_time
	invuln_timer = roll_time
	_swing_node = null
	_set_state(State.DASH)
	return true


## Long Arm is the gorilla's grapple with reach and a windup instead of
## instant commitment. The windup is the balance lever: a slow telegraph is
## what stops twice the range from being strictly better.
func _skill_long_arm() -> bool:
	if _windup_timer > 0.0:
		return false
	_windup_skill = &"long_arm"
	_windup_timer = long_arm_windup
	return true


func _tick_windup(delta: float) -> void:
	if _windup_timer <= 0.0:
		return
	_windup_timer -= delta
	if _windup_timer > 0.0:
		return
	var skill := _windup_skill
	_windup_skill = &""
	if skill == &"long_arm":
		_skill_grapple_dash(long_arm_range_multiplier)


func _skill_snatch() -> bool:
	_dash_kind = &"snatch"
	_dash_time = snatch_time
	_snatch_hit.clear()
	_swing_node = null
	_set_state(State.DASH)
	return true


## Passing through someone steals from them: bananas where there are
## bananas, momentum where there are not. Host only, like every other
## interaction that moves a number on somebody else's screen.
func _resolve_snatch() -> void:
	if not _is_authority():
		return
	var arena: Node = get_tree().get_first_node_in_group(&"arena")
	if arena == null:
		return
	var table: Variant = arena.get(&"players")
	if not (table is Dictionary):
		return
	for id in table.keys():
		var victim := table[id] as Player
		if victim == null or victim == self or _snatch_hit.has(victim.player_id):
			continue
		if victim.is_ghost() or global_position.distance_to(victim.global_position) > snatch_radius + snatch_speed * get_physics_process_delta_time():
			continue
		_snatch_hit.append(victim.player_id)

		var director: Node = get_tree().get_first_node_in_group(&"hoard_director")
		if director != null and director.has_method(&"steal_bananas") and victim.bananas > 0:
			director.call(&"steal_bananas", victim.player_id, player_id, snatch_fraction)
			continue
		# No bananas to take, so take the tempo instead.
		victim.set_ability(&"slowed", snatch_slow_seconds)
		set_ability(&"speed_boost", snatch_slow_seconds)
		if Net.is_online():
			Net.broadcast_ability(victim.player_id, &"slowed", snatch_slow_seconds)
			Net.broadcast_ability(player_id, &"speed_boost", snatch_slow_seconds)


func _process_dash(delta: float) -> void:
	_dash_time -= delta
	if _dash_kind == &"grapple":
		var to_target := _dash_target - global_position
		if _dash_time <= 0.0 or to_target.length() < 28.0:
			# Arriving keeps some speed rather than stopping dead, so a
			# grapple into a ledge flows into a jump instead of parking you.
			velocity = to_target.normalized() * grapple_pull_speed * 0.25
			_end_dash()
			return
		velocity = to_target.normalized() * grapple_pull_speed
	elif _dash_kind == &"dash":
		velocity = _dash_dir * dash_speed
		if _dash_time <= 0.0:
			velocity = _dash_dir * dash_speed * dash_carry
			_end_dash()
			return
	elif _dash_kind == &"snatch":
		velocity = Vector2(float(facing) * snatch_speed, 0.0)
		_resolve_snatch()
		if _dash_time <= 0.0:
			_end_dash()
			return
	else:
		velocity.x = float(facing) * roll_speed
		_apply_gravity(delta)
		if _dash_time <= 0.0:
			_end_dash()
			return

	move_and_slide()
	if _dash_kind == &"grapple" and get_slide_collision_count() > 0:
		_end_dash()


## Everyone's dash. Separate from the species skill on purpose: movement is
## the game, and a move only some monkeys have is a move nobody learns.
func _try_dash() -> void:
	if _dash_cooldown_timer > 0.0 or state == State.STUN or state == State.DASH:
		return
	var grounded := is_on_floor()
	if not grounded and not _air_dash_ready:
		return
	var aim := _input.move
	if aim.length() < 0.3:
		aim = Vector2(float(facing), 0.0)
	# Eight directions, snapped, so a dash goes where the thumb meant and not
	# two degrees off it.
	var angle := snappedf(aim.angle(), PI / 4.0)
	_dash_dir = Vector2.from_angle(angle)
	if grounded and _dash_dir.y > 0.1:
		_dash_dir = Vector2(signf(_dash_dir.x) if absf(_dash_dir.x) > 0.1 else float(facing), 0.0)
	if not grounded:
		_air_dash_ready = false
	if state == State.SWING:
		_swing_node = null
		_swing_lock = swing_regrab_delay
	_dash_kind = &"dash"
	_dash_time = dash_time
	_dash_cooldown_timer = dash_cooldown
	if absf(_dash_dir.x) > 0.1:
		facing = 1 if _dash_dir.x > 0.0 else -1
	Sfx.play(&"dash", _voice_pitch())
	_set_state(State.DASH)


## Bounce pads. Replaces vertical speed rather than adding to it, so a pad
## launches the same height whether you walked on or fell on - which is what
## lets a level designer put a ledge exactly at the top of the arc.
func bounce(strength: float) -> void:
	if not _simulates():
		return
	if state == State.SWING:
		_swing_node = null
		_swing_lock = swing_regrab_delay
	if state == State.DASH:
		_dash_kind = &""
	velocity.y = -strength
	_pending_bounce = strength
	_jump_rising = false
	_coyote_timer = 0.0
	_air_dash_ready = true
	_squash = 0.35
	_set_state(State.AIR)
	Sfx.play(&"bounce", _voice_pitch())


func _end_dash() -> void:
	_dash_kind = &""
	_dash_time = 0.0
	_set_state(State.GROUND if is_on_floor() else State.AIR)


## The macaque's counter. Rolling through an attack stuns the attacker
## instead, which is what makes careless swinging cost something.
func _counter_attacker(attacker_id: int) -> void:
	if not _is_authority():
		return
	var arena: Node = get_tree().get_first_node_in_group(&"arena")
	if arena == null:
		return
	var table: Variant = arena.get(&"players")
	if not (table is Dictionary):
		return
	var attacker := table.get(attacker_id) as Player
	if attacker == null:
		return
	var push := (attacker.global_position - global_position).normalized() * stats.knockback_dealt() * 0.7
	attacker.take_hit(player_id, push, GameConfig.BASE_STUN_TIME)
	if Net.is_online():
		Net.broadcast_hit(attacker_id, push, GameConfig.BASE_STUN_TIME, player_id)


# --- Respawn -------------------------------------------------------

func respawn_at(point: Vector2) -> void:
	global_position = point
	velocity = Vector2.ZERO
	slap_damage = 0.0
	_spawn_shield = SPAWN_SHIELD if team >= 0 else 0.0
	_refresh_name_label()
	stun_timer = 0.0
	invuln_timer = 0.0
	_dash_kind = &""
	_windup_timer = 0.0
	_windup_skill = &""
	_air_launch_ready = true
	# Bananas survive a fall. Falling already costs time, and losing a
	# hoard to a missed jump punishes the mode's whole risk curve twice.
	is_attacking = false
	_swing_node = null
	_set_hitbox_open(false)
	_set_state(State.AIR)
	_has_net_target = false


# --- Networking ----------------------------------------------------

func get_net_state() -> Dictionary:
	return {
		"p": global_position,
		"v": velocity,
		"s": state,
		"f": facing,
		"a": is_attacking,
	}


func apply_net_state(data: Dictionary) -> void:
	_net_target = data.get("p", global_position)
	_has_net_target = true
	velocity = data.get("v", velocity)
	facing = int(data.get("f", facing))
	is_attacking = bool(data.get("a", is_attacking))
	var incoming := int(data.get("s", state))
	if incoming != state:
		_set_state(incoming)


func _follow_net_target(delta: float) -> void:
	if not _has_net_target:
		return
	# Remote monkeys are smoothed toward host truth rather than snapped.
	# Drift of a few pixels is invisible in a party game; teleporting is not.
	global_position = global_position.lerp(_net_target, clampf(delta * 18.0, 0.0, 1.0))


func _reconcile() -> void:
	var error := global_position.distance_to(_net_target)
	if error > reconcile_snap_distance:
		global_position = _net_target
	elif error > 2.0:
		global_position = global_position.lerp(_net_target, reconcile_blend)
	_has_net_target = false


# --- State and visuals ---------------------------------------------

func _set_state(next: int) -> void:
	if next == state:
		return
	state = next
	state_changed.emit(next)


## Screen shake and squash run on _process, not _physics_process: they are
## presentation, and tying them to the physics tick makes them stutter on a
## machine whose render rate and tick rate disagree.
var _step_clock: float = 0.0


func _process(delta: float) -> void:
	_tick_steps(delta)
	_tick_landing()
	_tick_shake(delta)
	_tick_squash(delta)
	_update_ground_shadow()
	# Remote attacks arrive as one boolean in snapshots.  Detect the rising
	# edge here so they get the same full animation as the local attacker.
	if is_attacking and not _attack_was_visible and _slap_fist != null:
		_slap_fist.play(facing, stats.body_color)
	_attack_was_visible = is_attacking
	if is_attacking or state == State.SWING or _dash_kind == &"grapple":
		queue_redraw()
	elif _sprint_blend > 0.01 or _ground_shadow_alpha > 0.01:
		queue_redraw()


## The rope, the swing arc and the grapple line are the only way to read
## what a monkey is doing while everything is still coloured rectangles.
## None of it is decoration: a vine you cannot see is a vine you cannot aim
## at, and an attack with no telegraph is an attack nobody can respect.
func _draw() -> void:
	_draw_ground_shadow()
	_draw_speed_lines()
	if state == State.SWING and _swing_node != null and is_instance_valid(_swing_node):
		Vine.draw_vine(self, to_local(_swing_anchor), Vector2(0.0, -12.0), Color(0.35, 0.55, 0.28))

	if _dash_kind == &"grapple":
		var target := to_local(_dash_target)
		draw_line(Vector2.ZERO, target, Color(0.85, 0.75, 0.45), 3.0)
		draw_circle(target, 7.0, Color(0.95, 0.85, 0.5))

	if is_attacking:
		_draw_attack_arc()


func _draw_attack_arc() -> void:
	var radius: float = absf(hitbox.position.x) + 8.0
	if hitbox_shape.shape is RectangleShape2D:
		radius = absf(hitbox.position.x) + (hitbox_shape.shape as RectangleShape2D).size.x * 0.5
	var facing_angle: float = 0.0 if facing > 0 else PI
	var windup_done: bool = _attack_timer >= attack_windup
	var spread: float = 0.75 if windup_done else 0.35
	var color := Color(1.0, 0.95, 0.6, 0.9) if windup_done else Color(1.0, 1.0, 1.0, 0.35)
	var width: float = 7.0 if windup_done else 3.0
	draw_arc(Vector2(0.0, -4.0), radius, facing_angle - spread, facing_angle + spread, 16, color, width)


func _update_ground_shadow() -> void:
	if not is_inside_tree():
		return
	var query := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, 8), global_position + Vector2(0, 330), GameConfig.LAYER_WORLD, [get_rid()])
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_ground_shadow_alpha = move_toward(_ground_shadow_alpha, 0.0, 0.16)
		return
	_ground_shadow_y = to_local(hit.get("position", global_position + Vector2(0, 34))).y - 2.0
	var distance := maxf(_ground_shadow_y, 0.0)
	_ground_shadow_alpha = clampf(0.34 - distance / 900.0, 0.08, 0.34)


func _draw_ground_shadow() -> void:
	if _ground_shadow_alpha <= 0.01:
		return
	var distance_scale := clampf(1.0 - maxf(_ground_shadow_y - 35.0, 0.0) / 520.0, 0.45, 1.0)
	var center := Vector2(5.0, _ground_shadow_y)
	for ring in 3:
		var rx := (24.0 + ring * 7.0) * distance_scale
		var ry := (5.0 + ring * 2.0) * distance_scale
		var points := PackedVector2Array()
		for i in 20:
			var a := TAU * float(i) / 20.0
			points.append(center + Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(points, Color(0.025, 0.02, 0.05, _ground_shadow_alpha * (1.0 - ring * 0.23)))


func _draw_speed_lines() -> void:
	if _sprint_blend < 0.22 or state != State.GROUND or absf(velocity.x) < 220.0:
		return
	var back := -float(facing)
	var pulse := fmod(float(Time.get_ticks_msec()) * 0.09, 16.0)
	for i in 3:
		var y := 3.0 + i * 9.0
		var start := Vector2(back * (23.0 + pulse + i * 8.0), y)
		var finish := start + Vector2(back * (18.0 + _sprint_blend * 24.0), 0.0)
		draw_line(start, finish, Color(1.0, 0.94, 0.68, 0.22 + _sprint_blend * 0.28), 2.0 + i)


## Heavier monkeys sound lower. One number, and the roster reads by ear.
func _voice_pitch() -> float:
	return clampf(1.25 - stats.weight * 0.28, 0.55, 1.6)


func kick_camera(power: float, duration: float) -> void:
	# Strongest kick wins rather than accumulating, so two hits in quick
	# succession do not turn the screen into a blender.
	_shake_power = maxf(_shake_power, power)
	_shake_time = maxf(_shake_time, duration)


## Footsteps on grass while running, paced by speed. Quiet: they are there
## to make running feel like running, not to be listened to.
func _tick_steps(delta: float) -> void:
	if state != State.GROUND or absf(velocity.x) < 120.0:
		_step_clock = 0.0
		return
	_step_clock -= delta * absf(velocity.x) / 420.0
	if _step_clock <= 0.0:
		_step_clock = 0.3
		Sfx.play(&"step", _voice_pitch())


func _tick_landing() -> void:
	var grounded := is_on_floor()
	if grounded and not _was_on_floor and _fall_speed > heavy_land_speed:
		Sfx.play(&"land", _voice_pitch())
		if local_control:
			kick_camera(shake_on_land, 0.12)
		_squash = clampf(_fall_speed / max_fall_speed, 0.2, 0.6)
	_was_on_floor = grounded
	_fall_speed = velocity.y


func _tick_shake(delta: float) -> void:
	if camera == null:
		return
	if _shake_time <= 0.0:
		camera.offset = Vector2.ZERO
		return
	_shake_time -= delta
	var falloff := clampf(_shake_time * 4.0, 0.0, 1.0)
	camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_power * falloff
	if _shake_time <= 0.0:
		_shake_power = 0.0
		camera.offset = Vector2.ZERO


func _tick_squash(delta: float) -> void:
	if body == null:
		return
	_squash = maxf(_squash - delta * squash_recovery, 0.0)
	# Wider and shorter on impact. Cheap, readable, and the only animation
	# in the game until there is art.
	var squash := Vector2(1.0 + _squash * 0.35, 1.0 - _squash * 0.35)
	body.scale = squash
	if sprite != null:
		sprite.scale = squash * MonkeySprite.PIXEL


func _update_visual() -> void:
	if sprite == null:
		return
	# Measured from position, not velocity: a remote monkey on a client is
	# replayed from snapshots and its velocity is whatever the last one said.
	var step := global_position - _last_position
	_last_position = global_position
	var tick := get_physics_process_delta_time()
	_moved_speed = lerpf(_moved_speed, step.length() / maxf(tick, 0.001), 0.35)

	sprite.flip_h = facing < 0
	sprite.rotation = 0.0
	sprite.paused = false
	sprite.speed_scale = 1.0
	var tint := Color.WHITE
	match state:
		State.STUN:
			sprite.play(&"stun")
			# Flicker, so a stunned monkey reads as hit rather than as posing.
			tint = Color(1.0, 0.55, 0.55) if int(Time.get_ticks_msec() / 80) % 2 == 0 else Color.WHITE
		State.CLIMB:
			sprite.play(&"climb")
			sprite.paused = _moved_speed < 20.0
		State.SWING:
			sprite.play(&"swing")
			if _swing_node != null and is_instance_valid(_swing_node):
				# Hang from the vine: the sprite's up points at the pivot.
				var to_anchor := _swing_anchor - global_position
				sprite.rotation = to_anchor.angle() + PI * 0.5
		State.DASH:
			sprite.play(&"dash")
			tint = Color(1.0, 0.97, 0.8)
		State.AIR:
			sprite.play(&"jump" if step.y < 0.0 else &"fall")
		_:
			if absf(step.x) / maxf(tick, 0.001) > 40.0:
				sprite.play(&"run")
				sprite.speed_scale = clampf(_moved_speed / 320.0, 0.6, 1.8)
			else:
				sprite.play(&"idle")
	if is_attacking and state != State.STUN:
		sprite.play(&"punch")
		sprite.rotation = float(facing) * -0.075
		sprite.scale *= Vector2(1.08, 0.94)
		if _hitbox_open:
			tint = Color(1.25, 1.2, 1.05)
	if _spawn_shield > 0.0 and int(Time.get_ticks_msec() / 90) % 2 == 0:
		tint.a = 0.35
	sprite.self_modulate = tint
	if state == State.GROUND and _sprint_blend > 0.05 and absf(step.x) > 0.05:
		sprite.rotation = float(facing) * 0.055 * _sprint_blend
		sprite.speed_scale *= lerpf(1.0, 1.26, _sprint_blend)
	if _sprite_shadow != null:
		_sync_sprite_layer(_sprite_shadow, Vector2(5.0, 6.0), 1.015)
	if _sprite_rim != null:
		_sync_sprite_layer(_sprite_rim, Vector2(-2.0, -2.0), 1.0)


func _sync_sprite_layer(layer: Sprite2D, offset_position: Vector2, size_scale: float) -> void:
	layer.texture = sprite.texture
	layer.hframes = sprite.hframes
	layer.vframes = sprite.vframes
	layer.frame = sprite.frame
	layer.centered = sprite.centered
	layer.offset = sprite.offset
	layer.flip_h = sprite.flip_h
	layer.position = sprite.position + offset_position
	layer.rotation = sprite.rotation
	layer.scale = sprite.scale * size_scale
	layer.visible = sprite.visible
