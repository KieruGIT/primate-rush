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
signal fell_out_of_world

enum State { GROUND, AIR, CLIMB, SWING, STUN }

const ATTACK_FLAVORS: Array[StringName] = [&"slap", &"punch", &"kick"]

@export_group("Identity")
@export var stats: MonkeyStats
## Peer id when networked, slot index when local. Unique per monkey either way.
@export var player_id: int = 1
## True on the machine whose player this is. Drives camera and prediction.
@export var local_control: bool = true

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
@export var swing_pump: float = 5.5
## Climbing the rope itself, in pixels per second.
@export var swing_rope_speed: float = 180.0
## Release speed multiplier. Above 1.0 so a well-timed release beats running.
@export var swing_release_boost: float = 1.08
@export var swing_regrab_delay: float = 0.35

@export_group("Attack")
## Wind-up before the hitbox opens. Long enough to be readable, short
## enough that whiffing is not a death sentence in a game with no deaths.
@export var attack_windup: float = 0.08
@export var attack_active: float = 0.10
@export var attack_recovery: float = 0.16
@export var attack_cooldown: float = 0.34
## Upward share of knockback. Pure sideways knockback slides people along
## the floor and reads as nothing happening.
@export var knockback_lift: float = 0.55

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

var _climb_lock: float = 0.0
var _swing_lock: float = 0.0
var _swing_anchor: Vector2 = Vector2.ZERO
var _swing_node: Node2D = null
var _swing_length: float = 0.0
var _swing_angle: float = 0.0
var _swing_ang_vel: float = 0.0

var _net_target: Vector2 = Vector2.ZERO
var _has_net_target: bool = false

@onready var body: ColorRect = $Body
@onready var shape: CollisionShape2D = $Collision
@onready var climb_sensor: Area2D = $ClimbSensor
@onready var vine_sensor: Area2D = $VineSensor
@onready var hitbox: Area2D = $Hitbox
@onready var hitbox_shape: CollisionShape2D = $Hitbox/Shape
@onready var hurtbox: Area2D = $Hurtbox
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
func setup(monkey: MonkeyStats, id: int, is_local: bool, tint: Color = Color(0, 0, 0, 0)) -> void:
	stats = monkey
	player_id = id
	local_control = is_local
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

	var rect := shape.shape as RectangleShape2D
	if rect != null:
		# Duplicated because a shape resource shared between instances would
		# resize every monkey in the match at once.
		rect = rect.duplicate()
		rect.size = size
		shape.shape = rect

	if name_label != null:
		name_label.text = stats.display_name
		name_label.position.y = -size.y * 0.5 - 28.0


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
	_input.merge_buttons(frame)


func _apply_input_frame(_delta: float) -> void:
	if absf(_input.move.x) > 0.2:
		facing = 1 if _input.move.x > 0.0 else -1


func _tick_timers(delta: float) -> void:
	_climb_lock = maxf(_climb_lock - delta, 0.0)
	_swing_lock = maxf(_swing_lock - delta, 0.0)
	_attack_cooldown_timer = maxf(_attack_cooldown_timer - delta, 0.0)
	_buffer_timer = maxf(_buffer_timer - delta, 0.0)
	if _input.consume(InputFrame.Button.JUMP):
		_buffer_timer = jump_buffer_time
	if _input.consume(InputFrame.Button.ATTACK):
		_try_attack()


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

	if absf(axis) > 0.1:
		velocity.x = move_toward(velocity.x, axis * stats.run_speed(), accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)


func _try_jump() -> void:
	var can_jump := is_on_floor() or _coyote_timer > 0.0
	if can_jump and _buffer_timer > 0.0:
		velocity.y = stats.jump_velocity()
		_buffer_timer = 0.0
		_coyote_timer = 0.0


func _apply_jump_cut() -> void:
	if velocity.y < 0.0 and not _input.jump_held:
		velocity.y *= jump_cut_multiplier


# --- Climb ---------------------------------------------------------

func _try_enter_climb() -> bool:
	if _climb_lock > 0.0 or not _touching_climbable():
		return false
	# Pressing into the wall or up it. Brushing past a climbable surface
	# mid-jump should not yank you onto it.
	if absf(_input.move.y) < 0.35 and absf(_input.move.x) < 0.5:
		return false
	_set_state(State.CLIMB)
	velocity = Vector2.ZERO
	return true


func _process_climb(delta: float) -> void:
	if not _touching_climbable():
		_set_state(State.AIR)
		return

	if _buffer_timer > 0.0:
		_buffer_timer = 0.0
		_climb_lock = climb_regrab_delay
		velocity = Vector2(-facing * climb_jump_push, stats.jump_velocity() * 0.92)
		_set_state(State.AIR)
		return

	var speed := stats.climb_speed()
	velocity = Vector2(
		_input.move.x * speed * climb_lateral_ratio,
		_input.move.y * speed
	)
	move_and_slide()

	if is_on_floor() and _input.move.y > 0.1:
		_set_state(State.GROUND)


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
	# Pumping: pushing in the direction of travel adds energy, which is the
	# entire skill expression of the swing.
	_swing_ang_vel += _input.move.x * swing_pump * stats.air_control() * delta
	_swing_ang_vel *= stats.swing_retention()

	_swing_length = clampf(
		_swing_length + _input.move.y * swing_rope_speed * delta,
		swing_min_length,
		swing_max_length
	)
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
		velocity.y = minf(velocity.y, stats.jump_velocity() * 0.35)
	_swing_node = null
	_swing_lock = swing_regrab_delay
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
	# The three flavors are cosmetic and must stay mechanically identical.
	# The moment a kick outranges a slap, players fish for an animation they
	# cannot choose, and a variety system becomes a frustration system.
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
	hitbox.monitoring = open
	hitbox_shape.disabled = not open
	if not open:
		return
	hitbox.position.x = absf(hitbox.position.x) * facing
	# Anything already inside the box when it opens never fires area_entered,
	# so sweep once on open.
	if _is_authority():
		for area in hitbox.get_overlapping_areas():
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
	var force := dir * stats.knockback_dealt()
	target.take_hit(player_id, force, GameConfig.BASE_STUN_TIME)
	hit_landed.emit(target.player_id)
	if Net.is_online():
		Net.broadcast_hit(target.player_id, force, GameConfig.BASE_STUN_TIME, player_id)


## Applied by the host, replayed on clients. Never called speculatively by a
## client: knockback that disagrees between machines is the single most
## broken-feeling desync in this game.
func take_hit(attacker_id: int, force: Vector2, base_stun: float) -> void:
	var applied := force.normalized() * stats.knockback_taken(force.length())
	velocity = applied
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
	hit_taken.emit(attacker_id, applied)


func _process_stun(delta: float) -> void:
	stun_timer -= delta
	_apply_gravity(delta)
	# Friction still applies during stun, otherwise a hard hit slides you
	# forever and the stun never visibly ends.
	velocity.x = move_toward(velocity.x, 0.0, air_friction * 0.5 * delta)
	move_and_slide()
	if stun_timer <= 0.0:
		_set_state(State.GROUND if is_on_floor() else State.AIR)


# --- Respawn -------------------------------------------------------

func respawn_at(point: Vector2) -> void:
	global_position = point
	velocity = Vector2.ZERO
	stun_timer = 0.0
	is_attacking = false
	_swing_node = null
	_set_hitbox_open(false)
	_set_state(State.AIR)
	_has_net_target = false


func report_fell() -> void:
	fell_out_of_world.emit()


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


func _update_visual() -> void:
	if body == null:
		return
	# Readability cue while there is no art. State is legible at a glance,
	# which matters more than it sounds when four monkeys share one screen.
	var base: Color = get_meta(&"tint", stats.body_color)
	match state:
		State.STUN:
			body.color = base.lerp(Color(1.0, 0.25, 0.25), 0.65)
		State.CLIMB:
			body.color = base.lerp(Color(0.4, 1.0, 0.5), 0.35)
		State.SWING:
			body.color = base.lerp(Color(0.5, 0.75, 1.0), 0.35)
		State.AIR:
			body.color = base.lightened(0.18)
		_:
			body.color = base
	if is_attacking and _hitbox_open:
		body.color = body.color.lightened(0.45)
