class_name Player
extends CharacterBody2D

# ============================================================
# MONKEY
#
# One script: ground, slide, air, swing, stun. Movement feel
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

# New states are appended rather than inserted: the state enum travels over
# the wire as an int, and renumbering it would desync mid-update. DASH is
# now only the skill movers (grapple, roll, snatch); there is no dash button.
enum State { GROUND, AIR, CLIMB, SWING, STUN, DASH, SLIDE }

const SkillFx = preload("res://scripts/player/SkillFx.gd")
const ATTACK_FLAVORS: Array[StringName] = [&"slap", &"punch", &"kick"]
## How far forward of the monkey's centre a slap connects, before arm length
## stretches it. Matched to where the drawn hand actually lands, so nobody
## is hit by a hand that visibly never reached them.
const SLAP_REACH: float = 120.0
## Height of the punch box. Taller than the body so the bigger fist lands on
## a monkey a step above or below, the way the drawn arm looks like it does.
const SLAP_HEIGHT: float = 84.0

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
## Air braking with the stick let go. Firm enough that a monkey you stop
## steering stops drifting within a few steps.
@export var air_stop_friction: float = 1500.0
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
## Forward shove on a jump from the ground, in the direction held. It is
## allowed past run speed, so every jump is a small burst of momentum.
@export var jump_push: float = 70.0
## Second jump in the air, as a share of the first. One per airtime, given
## back by landing or grabbing something.
@export var double_jump_ratio: float = 0.86
## Unused since grabbing moved to its own button; kept so saved scenes that
## set it still load.
@export var grab_hold_time: float = 0.1
## How long a drop through a platform ignores platforms. Long enough to fall
## clear of a 32 px ledge, short enough not to skip the next one down.
@export var platform_drop_time: float = 0.24

@export_group("Momentum")
## Speed past run speed comes only from jumps, swing releases and hops.
## This is the ceiling that keeps a chain of bunny hops finite.
@export var max_momentum_speed: float = 780.0
## How fast speed above run speed bleeds in the air while you keep holding
## the way you are going. Low, so a swing release carries across a gap.
@export var momentum_air_drag: float = 180.0
## Speed above run speed survives this long after landing. Jump inside it
## and the speed carries into the next hop - that is the bunny hop.
@export var bhop_window: float = 0.12
## Each chained hop keeps its speed times this, capped by max_momentum_speed.
@export var bhop_gain: float = 1.04
## Holding down while landing or running fast slides instead of braking.
@export var slide_friction: float = 380.0
## A slide needs at least this share of run speed to start, and ends below
## half of it.
@export var slide_min_ratio: float = 0.85

@export_group("Arm grab")
## How far the arm stretches to take hold of a trunk or a cliff face. The
## monkey reaches up and grabs the nearest point of it inside this range,
## then swings from that point like a vine.
@export var grab_reach: float = 150.0
## Letting go of a trunk while hanging nearly still is a pull-up: a hop up
## and a little away, so a cliff is climbed grab, pull in, let go, grab.
@export var trunk_hop_lift: float = 0.85
@export var trunk_hop_push: float = 120.0
## Below this speed a trunk release counts as "hanging still" and hops.
@export var trunk_hop_below_speed: float = 260.0

@export_group("Swing")
@export var swing_min_length: float = 48.0
@export var swing_max_length: float = 260.0
## Pumping the stick adds angular velocity, which is the whole skill.
@export var swing_pump: float = 8.2
## Pulling in on the rope or the stretched arm, in pixels per second,
## scaled by the Climb stat.
@export var swing_rope_speed: float = 280.0
## Release speed multiplier. Above 1.0 so a well-timed release beats running.
@export var swing_release_boost: float = 1.22
## Flat speed added along the release direction on a swing let-go.
@export var swing_release_kick: float = 70.0
## Prevents a shortened rope from becoming an accidental physics cannon.
@export var swing_max_speed: float = 1100.0
@export var swing_regrab_delay: float = 0.2
## Share of your speed kept as swing speed when you grab mid-flight.
@export_range(0.0, 1.0, 0.05) var swing_grab_keep: float = 0.85
## Moving faster than this, grab points behind you are ignored, so a grab
## never yanks you back against the way you were going.
@export var grab_behind_speed: float = 220.0

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
@export var snatch_time: float = 0.22
@export var snatch_radius: float = 46.0
## Share of the victim's bananas a snatch takes.
@export_range(0.0, 1.0, 0.05) var snatch_fraction: float = 0.3
## Momentum theft in modes with no bananas: they slow, you speed up.
@export var snatch_slow_seconds: float = 1.6
## Safety valve so a grapple that never arrives cannot strand you in DASH.
@export var dash_timeout: float = 0.7
## Whiffing still costs something, or the grapple is a free scan every frame.
@export var skill_whiff_cooldown: float = 0.6

@export_group("Sprint")
## Held sprint multiplies run speed, on the ground and in the air, so a
## sprinting jump carries further. Every monkey has it; the stats still
## decide how fast "fast" is.
@export var sprint_multiplier: float = 1.3
## Always sprint while moving. The sprint key is no longer needed.
@export var auto_sprint: bool = true
## Every jump adds this to your speed in the direction you are moving.
@export var jump_momentum: float = 55.0
## Punches hit this much harder than the stat block alone.
@export var punch_power: float = 1.4

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
var _double_jump_ready: bool = true
## Letting go of a swing gives back the full jump as well as the double
## jump, the same two jumps you have standing on the ground.
var _swing_jump_ready: bool = false
## Counts down from bhop_window on landing. While it runs, speed above run
## speed is not braked away.
var _momentum_grace: float = 0.0
## How long jump has been held without letting go. Drives the grab.
var _jump_held_time: float = 0.0
## Counts down while this monkey's sprite jolts from a slap it just took.
## Presentation only.
var _jolt_time: float = 0.0
## Counts down through the double jump's tucked roll. The roll is drawn
## frames in the sprite sheet; the sprite itself never rotates.
var _roll_time: float = 0.0
const ROLL_SECONDS: float = 0.4
var _trail_timer: float = 0.0
## A spring launch waiting for the next gravity step. Set by bounce(), used
## by _apply_gravity, because a monkey standing on a pad is on the floor and
## the floor would otherwise zero the launch before it ever moved anyone.
var _pending_bounce: float = 0.0
## True from a pressed jump until it peaks or is cut. See _apply_jump_cut.
var _jump_rising: bool = false
## Counting down while this monkey is dropping through a platform.
var _drop_timer: float = 0.0
## Standing on a one-way platform (so down means drop, not slide).
var _on_platform: bool = false
## Where a grab would land right now, for the reach marker. Local player only.
var _grab_preview: Vector2 = Vector2.INF
var _grab_preview_clock: float = 0.0
## Skill presentation: afterimage clock, and a short trail after a launch.
var _ghost_clock: float = 0.0
var _launch_trail: float = 0.0
var _skill_ready_flash: float = 0.0
var _trunk_miss_wait: int = 0
var _shadow_wait: int = 0
## Silences this monkey (the menu's ability preview loops without noise).
var muted: bool = false
## A monkey outside any match (the menu's ability preview): simulates on
## its own and never talks to the network.
var sandbox: bool = false
## Skin id, applied to the sprite (see MonkeySkins).
var skin_id: StringName = &"natural"

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

var _swing_lock: float = 0.0
var _swing_anchor: Vector2 = Vector2.ZERO
var _swing_node: Node2D = null
## Grab point relative to _swing_node. Zero for a vine (its pivot is the
## node); the spot the hand closed on for a trunk.
var _swing_offset: Vector2 = Vector2.ZERO
## True when hanging from a trunk by the stretched arm rather than a vine.
var swing_on_trunk: bool = false
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
	# Ground and one-way platforms both. A drop clears the platform bit for
	# a moment (see _drop_through).
	collision_mask = GameConfig.LAYER_SOLID
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	_apply_appearance()
	_set_camera_active(local_control)


## Call right after instancing, before the monkey is added to the tree.
func setup(monkey: MonkeyStats, id: int, is_local: bool, tint: Color = Color(0, 0, 0, 0), hat: StringName = &"none", skin: StringName = &"natural") -> void:
	stats = monkey
	player_id = id
	local_control = is_local
	hat_id = hat
	skin_id = skin
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
	sprite.setup(stats.id, false, skin_id)
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

	# The slap box runs from the monkey's centre to where its hand lands.
	# Long arms land further away.
	var hit_rect := hitbox_shape.shape as RectangleShape2D
	if hit_rect != null:
		hit_rect = hit_rect.duplicate()
		hit_rect.size.x = SLAP_REACH * stats.slap_reach_scale()
		hit_rect.size.y = SLAP_HEIGHT
		hitbox_shape.shape = hit_rect
		hitbox.position.x = hit_rect.size.x * 0.5 * float(facing)

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
	if sandbox or not Net.is_online():
		return true
	if Net.is_host():
		return true
	return local_control


func _is_authority() -> bool:
	return sandbox or not Net.is_online() or Net.is_host()


## True when this monkey's hits should go over the network. Never for a
## sandbox monkey (the menu preview), whatever the party is doing.
func _net_live() -> bool:
	return Net.is_online() and not sandbox


func feed_input(frame: InputFrame) -> void:
	_input.move = frame.move
	_input.jump_held = frame.jump_held
	_input.sprint_held = frame.sprint_held
	_input.grab_held = frame.grab_held
	_input.merge_buttons(frame)


func _apply_input_frame(_delta: float) -> void:
	if absf(_input.move.x) > 0.2:
		facing = 1 if _input.move.x > 0.0 else -1


func _tick_timers(delta: float) -> void:
	_swing_lock = maxf(_swing_lock - delta, 0.0)
	_attack_cooldown_timer = maxf(_attack_cooldown_timer - delta, 0.0)
	_buffer_timer = maxf(_buffer_timer - delta, 0.0)
	var cooling := skill_timer > 0.0
	skill_timer = maxf(skill_timer - delta, 0.0)
	if cooling and skill_timer <= 0.0:
		# Ready again: a quick flash on the monkey so you notice without
		# looking at the corner of the screen.
		_skill_ready_flash = 0.35
	invuln_timer = maxf(invuln_timer - delta, 0.0)
	if ability_timer > 0.0:
		ability_timer -= delta
		if ability_timer <= 0.0:
			set_ability(&"", 0.0)
	_tick_windup(delta)
	_tick_long_arm(delta)
	_momentum_grace = maxf(_momentum_grace - delta, 0.0)
	_jump_held_time = _jump_held_time + delta if _input.jump_held else 0.0
	_spawn_shield = maxf(_spawn_shield - delta, 0.0)
	if is_on_floor() or state == State.SWING:
		_double_jump_ready = true
	if is_on_floor():
		_swing_jump_ready = false
	if is_on_floor():
		_air_launch_ready = true
	# There is no dash button any more. A press left over from an older
	# client, or a stale touch layout, is dropped rather than queued forever.
	while _input.consume(InputFrame.Action.DASH):
		pass
	# Grab is read as held (see _grab_held); the press edge only exists so a
	# tap that starts and ends inside one tick still reaches the host.
	while _input.consume(InputFrame.Action.GRAB):
		pass
	if _drop_timer > 0.0:
		_drop_timer -= delta
		if _drop_timer <= 0.0:
			collision_mask |= GameConfig.LAYER_PLATFORM
	_launch_trail = maxf(_launch_trail - delta, 0.0)
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

	if _wants_drop():
		_drop_through()
	_apply_gravity(delta)
	_apply_horizontal(delta)
	_try_jump()
	_apply_jump_cut()

	var was_airborne := not is_on_floor()
	move_and_slide()
	_on_platform = _standing_on_platform()

	if is_on_floor():
		if was_airborne and absf(velocity.x) > _top_speed():
			# Landing fast opens the bunny hop window. Until it closes the
			# ground does not brake the extra speed away.
			_momentum_grace = bhop_window
		_coyote_timer = coyote_time
		_set_state(State.SLIDE if _wants_slide() else State.GROUND)
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
	var wants_sprint := (auto_sprint or _input.sprint_held) and absf(axis) > 0.1
	var sprint_rate := 7.5 if wants_sprint else 4.5
	_sprint_blend = move_toward(_sprint_blend, 1.0 if wants_sprint else 0.0, sprint_rate * delta)
	var sliding := grounded and state == State.SLIDE
	if wants_sprint and grounded and not _sprint_latched and not sliding:
		# A small launch on the first stride makes sprint a verb rather than a
		# barely visible maximum-speed setting.
		velocity.x += axis * 72.0
	_sprint_latched = wants_sprint

	# A slide ignores the stick: it is the carried speed running out slowly.
	if sliding:
		velocity.x = move_toward(velocity.x, 0.0, slide_friction * delta)
		return

	# Let go of the stick and the monkey stops: hard on the ground, and
	# quickly in the air too, so nothing keeps drifting once you stop
	# pressing. Carried momentum only survives while you hold the way you
	# are going (and for a moment after a launch, so a release still flies).
	# Down held at speed is a slide starting, not a stop.
	# Down held in the air with no stick is a slide on its way down: keep the
	# speed for the landing instead of braking it away before touchdown.
	if not grounded and absf(axis) <= 0.1 and _input.move.y > 0.5:
		velocity.x = move_toward(velocity.x, 0.0, momentum_air_drag * delta)
		return
	# Same on the ground: the frame that down goes in at speed is the slide
	# starting, so it loses only slide friction, not a full ground brake.
	if grounded and absf(axis) <= 0.1 and _wants_slide():
		velocity.x = move_toward(velocity.x, 0.0, slide_friction * delta)
		return
	if absf(axis) <= 0.1 and _input.move.y <= 0.5:
		var stop := ground_friction * 1.6 if grounded else (air_friction if _launch_trail > 0.0 else air_stop_friction)
		velocity.x = move_toward(velocity.x, 0.0, stop * delta)
		return

	var top := _top_speed()
	# Momentum: speed above run speed that a jump, a hop or a swing earned.
	# Holding the way you are going (or nothing) lets it bleed slowly instead
	# of being clamped straight back to run speed. Pushing against it brakes
	# at the normal rate below.
	var same_way := absf(axis) <= 0.1 or signf(axis) == signf(velocity.x)
	if absf(velocity.x) > top and same_way:
		var bleed: float
		if grounded:
			bleed = 0.0 if _momentum_grace > 0.0 else ground_friction
		else:
			bleed = momentum_air_drag if absf(axis) > 0.1 else air_friction
		velocity.x = move_toward(velocity.x, signf(velocity.x) * top, bleed * delta)
		return

	if absf(axis) > 0.1:
		if grounded:
			accel *= lerpf(1.0, 1.72, _sprint_blend)
			if signf(velocity.x) != signf(axis):
				accel *= 1.28
		velocity.x = move_toward(velocity.x, axis * top, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)


## Run speed right now: stats, pickups and how far into a sprint you are.
func _top_speed() -> float:
	return stats.run_speed() * _speed_multiplier() * lerpf(1.0, sprint_multiplier, _sprint_blend)


## Down held with speed to spend. Starting needs most of run speed; an
## ongoing slide keeps going down to half of it, so it does not flicker off
## the moment friction takes the first bite.
func _wants_slide() -> bool:
	if _input.move.y < 0.5 or _on_platform:
		return false
	var needed := slide_min_ratio if state != State.SLIDE else 0.5
	return absf(velocity.x) >= stats.run_speed() * needed


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
	if _buffer_timer <= 0.0:
		return
	if is_on_floor() or _coyote_timer > 0.0:
		_ground_jump()
	elif _swing_jump_ready:
		_swing_jump_ready = false
		_ground_jump()
	elif _double_jump_ready and not _landing_soon():
		_double_jump()
	# With the double jump spent, the press stays buffered and fires as a
	# normal jump if the ground arrives inside the buffer window.


## Falling with the floor only a few frames away. A press now is someone
## timing a hop off the landing, and spending the double jump on it instead
## would throw the hop away, so the press waits in the buffer for the ground.
func _landing_soon() -> bool:
	if velocity.y <= 0.0:
		return false
	var reach := maxf(velocity.y * jump_buffer_time * 0.6, 10.0)
	return test_move(global_transform, Vector2(0.0, reach))


func _ground_jump() -> void:
	# Jumping out of a slide or inside the landing window is the bunny hop:
	# the carried speed survives, slightly amplified.
	if _momentum_grace > 0.0 or state == State.SLIDE:
		velocity.x *= bhop_gain
	var axis := _input.move.x
	if absf(axis) > 0.2:
		velocity.x += axis * jump_push
		# Momentum: every jump pushes a little past run speed.
		velocity.x += signf(axis) * jump_momentum
	velocity.x = clampf(velocity.x, -max_momentum_speed, max_momentum_speed)
	velocity.y = stats.jump_velocity()
	_momentum_grace = 0.0
	_jump_rising = true
	_buffer_timer = 0.0
	_coyote_timer = 0.0
	_sfx(&"jump", _voice_pitch())


func _double_jump() -> void:
	_double_jump_ready = false
	var axis := _input.move.x
	# Reversing in the air is the reason to double jump as often as height
	# is, so a stick pushed against the drift turns you round at run speed.
	if absf(axis) > 0.2 and signf(axis) != signf(velocity.x):
		velocity.x = axis * stats.run_speed() * 0.8
	elif absf(axis) > 0.2:
		velocity.x = clampf(velocity.x + signf(axis) * jump_momentum * 0.6, -max_momentum_speed, max_momentum_speed)
	velocity.y = stats.jump_velocity() * double_jump_ratio
	_jump_rising = true
	_buffer_timer = 0.0
	_roll_time = ROLL_SECONDS
	_sfx(&"jump", _voice_pitch() * 1.18)


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


# --- Grab ----------------------------------------------------------

## Tap jump to jump; keep holding it in the air and the arm takes hold of
## whatever is in reach. The grab key (L / right click) grabs straight away,
## on the ground too.
## Grabbing is its own button now. Jump used to grab too when held in the
## air, which snagged bushes, torches and ledges on every high jump.
func _grab_held() -> bool:
	return _input.grab_held


## The grip while hanging: hold GRAB to hang on, let go to let go.
func _grip_held() -> bool:
	return _input.grab_held


# --- One-way platforms ---------------------------------------------

## Down on the stick or the arrow keys while standing on a platform.
func _wants_drop() -> bool:
	return _on_platform and is_on_floor() and _drop_timer <= 0.0 and _input.move.y > 0.6


func _drop_through() -> void:
	collision_mask &= ~GameConfig.LAYER_PLATFORM
	_drop_timer = platform_drop_time
	_on_platform = false
	position.y += 2.0
	velocity.y = maxf(velocity.y, 140.0)
	_coyote_timer = 0.0
	_set_state(State.AIR)


func _standing_on_platform() -> bool:
	if not is_on_floor():
		return false
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		if hit.get_normal().y > -0.7:
			continue
		var body := hit.get_collider() as Node
		if body != null and body.is_in_group(&"platforms"):
			return true
	return false


# --- Swing ---------------------------------------------------------
#
# Manual pendulum integration rather than PinJoint2D. Joints are a physics
# server black box that is hard to sync and harder to tune; an angle and an
# angular velocity are two floats the host can ship over the wire.

func _try_enter_swing() -> bool:
	# Nothing is grabbed by bumping into it: GRAB has to be held.
	if _swing_lock > 0.0 or not _grab_held():
		return false
	# A vine in reach wins over a trunk: it is the thing placed to be swung on.
	var anchor_node := _nearest_vine()
	var on_trunk := false
	var grab_point := Vector2.ZERO
	if anchor_node == null:
		# The trunk search is a physics query plus a ray per candidate. When
		# it just found nothing, wait two ticks before asking again: nothing
		# new comes into arm's reach in 1/30 s.
		if _trunk_miss_wait > 0:
			_trunk_miss_wait -= 1
			return false
		var trunk := _nearest_trunk_point()
		if trunk.is_empty():
			_trunk_miss_wait = 2
			return false
		anchor_node = trunk["node"]
		grab_point = trunk["point"]
		on_trunk = true
	else:
		grab_point = anchor_node.global_position

	_swing_node = anchor_node
	_swing_offset = grab_point - anchor_node.global_position
	swing_on_trunk = on_trunk
	_swing_anchor = grab_point
	var offset := global_position - _swing_anchor
	if offset.length() < 1.0:
		return false

	_swing_length = clampf(offset.length(), swing_min_length, _swing_max())
	_swing_angle = offset.angle()
	# Only the tangential part of current velocity survives the grab. The
	# radial part is what the rope yanks away, and keeping it would let you
	# rocket straight outward off a vine.
	var tangent := Vector2(-sin(_swing_angle), cos(_swing_angle))
	var along := velocity.dot(tangent)
	# Keep most of the speed you arrived with. Only the part along the swing
	# used to survive, so jumping up into a branch above you (all of your
	# speed pointing at the grab point) stopped you dead. Now that speed is
	# turned into swing in the direction you were already travelling.
	var keep := velocity.length() * swing_grab_keep
	if absf(along) < keep:
		var travel := velocity.x if absf(velocity.x) > 20.0 else float(facing) * 100.0
		var dir := signf(along) if absf(along) > 40.0 else signf(travel * tangent.x)
		if dir == 0.0:
			dir = 1.0
		along = dir * keep
	_swing_ang_vel = along / _swing_length
	_air_launch_ready = true
	_buffer_timer = 0.0
	_sfx(&"grab", _voice_pitch())
	_set_state(State.SWING)
	return true


## The point on a trunk or cliff face the arm closes on: the highest part
## of it the arm can reach. Reaching up is the whole point of the arm -
## grabbing a wall level with your own head and hauling in just drags you
## sideways into it. Empty when nothing is within grab_reach.
func _nearest_trunk_point() -> Dictionary:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	var reach := grab_reach * stats.arm_length
	circle.radius = reach
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = GameConfig.LAYER_CLIMBABLE
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var best: Dictionary = {}
	var best_y := INF
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var area := hit.get("collider") as Climbable
		if area == null:
			continue
		var rect := Rect2(area.global_position - area.size * 0.5, area.size)
		var x := clampf(global_position.x, rect.position.x, rect.end.x)
		var dx := absf(x - global_position.x)
		if dx > reach:
			continue
		# As high as the arm stretches at that sideways distance, kept on
		# the trunk.
		var rise := sqrt(reach * reach - dx * dx)
		var y := clampf(global_position.y - rise, rect.position.y, rect.end.y)
		var point := Vector2(x, y)
		if point.distance_to(global_position) > reach + 0.5:
			continue
		# Hands go up, never down: hanging from a treetop you are flying
		# over would yank you back down onto it.
		if point.y > global_position.y - 24.0:
			continue
		if _is_behind(point):
			continue
		if not _arm_can_reach(point):
			continue
		if y < best_y:
			best_y = y
			best = {"node": area, "point": point}
	return best


## A grab point behind a monkey that is moving fast sideways. Grabbing it
## would reverse the run, which is the awkward stop this rules out.
func _is_behind(point: Vector2) -> bool:
	if absf(velocity.x) < grab_behind_speed:
		return false
	var dx := point.x - global_position.x
	return absf(dx) > 28.0 and signf(dx) != signf(velocity.x)


## The arm cannot pass through solid ground. A grab point on a wall sits
## inside the wall, so the ray is allowed to stop just short of it; stopping
## well short means a ledge or a slab is in the way.
func _arm_can_reach(point: Vector2) -> bool:
	var ray := PhysicsRayQueryParameters2D.create(global_position, point, GameConfig.LAYER_WORLD, [get_rid()])
	var hit := get_world_2d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return true
	return (hit["position"] as Vector2).distance_to(point) < 36.0


func _process_swing(delta: float) -> void:
	if _swing_node == null or not is_instance_valid(_swing_node):
		_release_swing(false)
		return
	_swing_anchor = _swing_node.global_position + _swing_offset

	# The button is the grip. Let go of it and you let go.
	if not _grip_held():
		_release_swing(true)
		return
	# Hanging by the grab key, a jump press leaps off with a jump's lift.
	if _buffer_timer > 0.0 and _input.grab_held:
		_jump_off_swing()
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

	# Climbed all the way up a vine and still pushing up: hop off the top.
	# Before, a monkey at the top of a vine just hung there.
	if not swing_on_trunk and _input.move.y < -0.5 and _swing_length <= swing_min_length + 2.0:
		_jump_off_swing()
		return

	var old_length := _swing_length
	_swing_length = clampf(
		_swing_length + _input.move.y * swing_rope_speed * stats.climb * delta,
		swing_min_length,
		_swing_max()
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


## Long arms hang from further down: the orangutan's reach is its swing.
func _swing_max() -> float:
	return swing_max_length * maxf(stats.arm_length * 0.8, 1.0)


func _release_swing(boosted: bool) -> void:
	var tangent := Vector2(-sin(_swing_angle), cos(_swing_angle))
	velocity = tangent * _swing_ang_vel * _swing_length
	if boosted and swing_on_trunk and velocity.length() < trunk_hop_below_speed and _swing_node != null:
		# Let go while hanging still from a trunk: pull up and hop off it,
		# up and a little away, which is how a cliff gets climbed.
		var away := signf(global_position.x - _swing_node.global_position.x)
		if away == 0.0:
			away = -float(facing)
		velocity = Vector2(away * trunk_hop_push + _input.move.x * trunk_hop_push, stats.jump_velocity() * trunk_hop_lift)
		_jump_rising = false
	elif boosted:
		velocity *= swing_release_boost
		if velocity.length() > 1.0:
			velocity += velocity.normalized() * swing_release_kick
		velocity = velocity.limit_length(max_momentum_speed)
		var release_lift := lerpf(0.32, 0.52, clampf(velocity.length() / swing_max_speed, 0.0, 1.0))
		velocity.y = minf(velocity.y, stats.jump_velocity() * release_lift)
	_swing_node = null
	swing_on_trunk = false
	_swing_lock = swing_regrab_delay
	_double_jump_ready = true
	_swing_jump_ready = true
	# A release is momentum on purpose: let it carry a moment even with the
	# stick let go.
	_launch_trail = maxf(_launch_trail, 0.3)
	if boosted:
		_sfx(&"swing", _voice_pitch())
	_set_state(State.AIR)


func _jump_off_swing() -> void:
	_release_swing(true)
	# The leap off counts as the first of the two jumps.
	_swing_jump_ready = false
	velocity.y = minf(velocity.y, stats.jump_velocity() * 0.9)
	_jump_rising = true
	_buffer_timer = 0.0
	# Longer than a plain release, so still holding grab does not snatch the
	# same branch straight back.
	_swing_lock = 0.35
	_sfx(&"jump", _voice_pitch())


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
		if _is_behind(anchor.global_position):
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
	_sfx(&"attack", _voice_pitch())
	if _slap_fist != null:
		_play_fist()
		_attack_was_visible = true
	attacked.emit(ATTACK_FLAVORS[randi() % ATTACK_FLAVORS.size()])


func _tick_attack(delta: float) -> void:
	if not is_attacking:
		return
	_attack_timer += delta
	# Smaller monkeys swing faster: wind-up, recovery and cooldown all scale
	# with attack_speed. The hit window itself stays the same length.
	var pace := maxf(stats.attack_speed, 0.3)
	var windup := attack_windup / pace
	var should_be_open := _attack_timer >= windup and _attack_timer < windup + attack_active
	if should_be_open != _hitbox_open:
		_set_hitbox_open(should_be_open)
	if _attack_timer >= windup + attack_active + attack_recovery / pace:
		is_attacking = false
		_attack_cooldown_timer = attack_cooldown / pace


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
	var force := dir * stats.knockback_dealt() * punch_power * (super_hit_multiplier if super_hit else 1.0)
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
		kick_camera(6.5 if not super_hit else 10.0, 0.13)
	hit_landed.emit(target.player_id)
	if _net_live():
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
	_held_by = null
	if is_carrying():
		# Hit while carrying: drop them.
		_end_dash()
	if is_ghost():
		return
	if _is_authority() and bananas > 0:
		_knock_bananas_loose(double_drop)
	var applied := force.normalized() * stats.knockback_taken(force.length())
	velocity = applied
	# Runs on every machine that applies the hit, so everyone sees the burst.
	# It sits on the side the slap came from, where the hand met the face.
	SlapBurst.spawn(get_parent(), global_position + Vector2(-signf(force.x) * 14.0, -14.0), force.length() > 900.0)
	_jolt_time = 0.12
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
	_set_state(State.STUN)
	# Pitched by the weight of whoever got hit, so a gorilla taking one reads
	# differently from a capuchin without any extra audio.
	# A slap that will send you far gets the heavy sound.
	_sfx(&"slap" if applied.length() > 900.0 else &"hit", _voice_pitch())
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
	if _held_by != null:
		if is_instance_valid(_held_by) and _held_by.is_carrying():
			# Carried overhead by a gorilla: ride its grip, no gravity.
			global_position = _held_by.held_point()
			velocity = Vector2.ZERO
			return
		_held_by = null
	_apply_gravity(delta)
	# Friction still applies during stun, otherwise a hard hit slides you
	# forever and the stun never visibly ends.
	velocity.x = move_toward(velocity.x, 0.0, air_friction * 0.5 * delta)
	move_and_slide()
	if stun_timer <= 0.0:
		_set_state(State.GROUND if is_on_floor() else State.AIR)


# --- Skills --------------------------------------------------------
#
# One skill per monkey, dispatched by the stat resource. Each one is a short
# animated move with a real effect, readable from across the screen:
#   Gorilla     GRAPPLE SLAM  lunge forward; catch a monkey, lift it over
#                             your head and slam it down. Stick up: the old
#                             grapple, pulling you to the terrain above.
#   Gibbon      SKY LAUNCH    launch the way you aim (from the ground too),
#                             blasting anyone next to you away
#   Macaque     COUNTER ROLL  roll as a ball: bowls monkeys over, and a hit
#                             taken mid-roll stuns the attacker instead
#   Orangutan   LONG ARM      wind up, then a huge punch across the screen;
#                             hit terrain instead and it pulls you there
#   Chimpanzee  SNATCH        dash through: steal bananas, or their speed

@export_group("Skill moves")
@export var lunge_speed: float = 1050.0
@export var lunge_time: float = 0.28
@export var lunge_catch_radius: float = 58.0
@export var slam_lift_time: float = 0.32
@export var slam_drop_time: float = 0.1
@export var slam_power: float = 1.5
@export var launch_shove_radius: float = 110.0
@export var roll_bowl_power: float = 0.95
@export var long_arm_reach: float = 420.0
@export var long_arm_power: float = 2.0

const LONG_ARM_OUT: float = 0.1
const LONG_ARM_HOLD: float = 0.14
const LONG_ARM_BACK: float = 0.16

## On the monkey being carried: who has it.
var _held_by: Player = null
## On the gorilla: who it is carrying, and that monkey's id for replicas.
var _held_target: Player = null
var _held_target_id: int = 0
## Time into the orangutan's long punch; -1 while not punching.
var _long_arm_t: float = -1.0
var _long_arm_len: float = 0.0
var _long_arm_hit: bool = false


func _try_skill() -> void:
	if skill_timer > 0.0 or state == State.STUN or stats.skill_id == &"" or _long_arm_t >= 0.0:
		return
	var fired := false
	match stats.skill_id:
		&"grapple_dash":
			fired = _skill_grapple_slam()
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
		SkillFx.burst(get_parent(), global_position, stats.skill_id)
		_sfx(&"attack", _voice_pitch() * 0.8)


func _aim_direction() -> Vector2:
	if _input.move.length() > 0.35:
		return _input.move.normalized()
	return Vector2(float(facing), -0.2).normalized()


## Is this gorilla mid lift or slam (so the monkey it holds rides along)?
func is_carrying() -> bool:
	return _dash_kind == &"lift" or _dash_kind == &"slam"


## Where a carried monkey sits: overhead during the lift, then swung down
## in front of the gorilla for the slam.
func held_point() -> Vector2:
	var other_half := 30.0
	if _held_target != null and is_instance_valid(_held_target):
		other_half = _held_target.stats.body_size.y * 0.5
	var overhead := global_position + Vector2(float(facing) * 6.0, -(stats.body_size.y * 0.5 + other_half + 18.0))
	if _dash_kind != &"slam":
		return overhead
	var front := global_position + Vector2(float(facing) * (stats.body_size.x * 0.5 + 34.0), stats.body_size.y * 0.5 - other_half)
	var k := clampf(1.0 - _dash_time / maxf(slam_drop_time, 0.01), 0.0, 1.0)
	# Over the top and down: an arc, not a straight line.
	var mid := (overhead + front) * 0.5 + Vector2(float(facing) * 30.0, -30.0)
	return overhead.lerp(mid, k).lerp(mid.lerp(front, k), k)


func _skill_grapple_slam() -> bool:
	# Stick pushed up: the old grapple, a pull to the terrain above.
	if _input.move.y < -0.5:
		return _skill_grapple_dash(1.0)
	_dash_kind = &"lunge"
	_dash_time = lunge_time
	_swing_node = null
	velocity = Vector2(float(facing) * lunge_speed, minf(velocity.y, -160.0))
	_set_state(State.DASH)
	return true


func _skill_grapple_dash(range_multiplier: float) -> bool:
	var aim := Vector2(float(facing), 0.0)
	if absf(_input.move.y) > 0.3:
		aim = Vector2(float(facing), _input.move.y).normalized()
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + aim * grapple_range * range_multiplier,
		GameConfig.LAYER_SOLID,
		[get_rid()]
	)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false
	_dash_kind = &"grapple"
	_dash_target = hit.get("position", global_position)
	_dash_time = dash_timeout
	_swing_node = null
	_set_state(State.DASH)
	return true


func _begin_lift(target: Player) -> void:
	_held_target = target
	_held_target_id = target.player_id
	_dash_kind = &"lift"
	_dash_time = slam_lift_time
	velocity.x = 0.0
	var hold := slam_lift_time + slam_drop_time + 0.15
	target.grabbed_by(self, hold)
	if _net_live():
		Net.broadcast_grab(target.player_id, player_id, hold)
	SkillFx.popup(get_parent(), global_position + Vector2(0.0, -110.0), "GOTCHA!", SkillFx.colour_of(stats.skill_id))
	_sfx(&"grab", _voice_pitch())
	if local_control:
		kick_camera(4.0, 0.1)


func _finish_slam() -> void:
	var target := _held_target
	var drop_at := held_point()
	_held_target = null
	_held_target_id = 0
	var ground := global_position + Vector2(float(facing) * (stats.body_size.x * 0.5 + 34.0), stats.body_size.y * 0.5)
	SkillFx.slam(get_parent(), ground, SkillFx.colour_of(stats.skill_id))
	_sfx(&"slap", _voice_pitch() * 0.8)
	if local_control:
		kick_camera(13.0, 0.26)
	if _is_authority():
		if target != null and is_instance_valid(target):
			target._held_by = null
			target.global_position = drop_at
			var force := Vector2(float(facing), -0.55).normalized() * stats.knockback_dealt() * slam_power
			_deal_hit(target, force, GameConfig.BASE_STUN_TIME * 1.6)
		# Anyone standing where it lands is shoved away too.
		for other in _opponents_near(ground, 90.0):
			if other == target:
				continue
			var away := Vector2(signf(other.global_position.x - ground.x), -0.7).normalized()
			_deal_hit(other, away * stats.knockback_dealt() * 0.6, GameConfig.BASE_STUN_TIME)
	_end_dash()


## Lands as a hit on another monkey, the same way a slap does: host only,
## broadcast to everyone, and scaled by damage in 2v2.
func _deal_hit(target: Player, force: Vector2, stun: float) -> void:
	if target.team >= 0:
		force *= SLAP_BASE * (1.0 + target.slap_damage * SLAP_SCALING) * 1.5
	target.take_hit(player_id, force, stun)
	hit_landed.emit(target.player_id)
	if _net_live():
		Net.broadcast_hit(target.player_id, force, stun, player_id)


## Monkeys this one may hit, near a point. A physics query on hurtboxes, so
## it works in the arena and in the menu's ability preview alike.
func _opponents_near(center: Vector2, radius: float) -> Array[Player]:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.transform = Transform2D(0.0, center)
	return _opponents_in(query)


func _opponents_in(query: PhysicsShapeQueryParameters2D) -> Array[Player]:
	query.collision_mask = GameConfig.LAYER_HURTBOX
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var out: Array[Player] = []
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 8):
		var area := hit.get("collider") as Area2D
		if area == null or not area.has_meta(&"player"):
			continue
		var other := area.get_meta(&"player") as Player
		if other == null or other == self or out.has(other):
			continue
		if team >= 0 and other.team == team:
			continue
		if other.is_ghost() or other._spawn_shield > 0.0:
			continue
		out.append(other)
	return out


## Grabbed: a rolling macaque slips out (and counters), a ghost cannot be
## held, and nobody is lifted twice.
func can_be_grabbed() -> bool:
	return invuln_timer <= 0.0 and not is_ghost() and _spawn_shield <= 0.0 and _held_by == null and not is_carrying()


func grabbed_by(attacker: Player, seconds: float) -> void:
	_held_by = attacker
	stun_timer = seconds
	is_attacking = false
	_set_hitbox_open(false)
	if state == State.SWING:
		_swing_node = null
		_swing_lock = swing_regrab_delay
	velocity = Vector2.ZERO
	_jolt_time = 0.12
	_set_state(State.STUN)


func _skill_air_launch() -> bool:
	if not _air_launch_ready:
		return false
	var aim := _aim_direction()
	if is_on_floor() and aim.y > -0.3:
		# From the ground a launch always goes up: that is the point of it.
		aim = Vector2(float(facing) * 0.55, -0.85).normalized()
	# Take-off blasts anyone standing next to you away.
	if _is_authority():
		for other in _opponents_near(global_position, launch_shove_radius):
			var away := (other.global_position - global_position).normalized()
			away.y = minf(away.y, -0.45)
			_deal_hit(other, away.normalized() * stats.knockback_dealt() * 1.3, GameConfig.BASE_STUN_TIME)
	velocity = aim * air_launch_speed
	_air_launch_ready = false
	_double_jump_ready = true
	_jump_rising = false
	# Clearing the regrab lock is what lets a launch chain straight into a
	# vine, which is the gibbon's whole identity.
	_swing_lock = 0.0
	_swing_node = null
	_roll_time = ROLL_SECONDS
	_launch_trail = 0.45
	_set_state(State.AIR)
	return true


func _skill_counter_roll() -> bool:
	_dash_kind = &"roll"
	_dash_time = roll_time
	invuln_timer = roll_time + 0.05
	_snatch_hit.clear()
	_swing_node = null
	_set_state(State.DASH)
	return true


## Long Arm: a slow telegraph (the charging ring), then a punch that crosses
## the screen. The windup is the balance lever against the reach.
func _skill_long_arm() -> bool:
	if _windup_timer > 0.0 or _long_arm_t >= 0.0:
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
		_long_arm_t = 0.0
		_long_arm_hit = false
		_long_arm_len = long_arm_reach
		_sfx(&"attack", _voice_pitch() * 0.7)


func _tick_long_arm(delta: float) -> void:
	if _long_arm_t < 0.0:
		return
	var before := _long_arm_t
	_long_arm_t += delta
	if before < LONG_ARM_OUT and _long_arm_t >= LONG_ARM_OUT and _simulates():
		_resolve_long_arm()
	if _long_arm_t >= LONG_ARM_OUT + LONG_ARM_HOLD + LONG_ARM_BACK:
		_long_arm_t = -1.0


## The fist reaches its full length: hit the first monkey along the arm, or,
## with nobody there, grab the terrain it touched and pull yourself to it.
func _resolve_long_arm() -> void:
	var rect := RectangleShape2D.new()
	rect.size = Vector2(long_arm_reach, 76.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = rect
	query.transform = Transform2D(0.0, global_position + Vector2(float(facing) * long_arm_reach * 0.5, -6.0))
	var victims := _opponents_in(query)
	victims.sort_custom(func(a: Player, b: Player) -> bool:
		return absf(a.global_position.x - global_position.x) < absf(b.global_position.x - global_position.x))
	if not victims.is_empty():
		var victim: Player = victims[0]
		_long_arm_len = clampf(absf(victim.global_position.x - global_position.x), 60.0, long_arm_reach)
		_long_arm_hit = true
		if _is_authority():
			_deal_hit(victim, Vector2(float(facing), -0.45).normalized() * stats.knockback_dealt() * long_arm_power, GameConfig.BASE_STUN_TIME * 1.5)
		SkillFx.popup(get_parent(), victim.global_position + Vector2(0.0, -60.0), "POW!", SkillFx.colour_of(stats.skill_id))
		if local_control:
			kick_camera(9.0, 0.18)
		return
	var ray := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(float(facing) * long_arm_reach, 0.0), GameConfig.LAYER_SOLID, [get_rid()])
	var hit := get_world_2d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		var point: Vector2 = hit["position"]
		_long_arm_len = absf(point.x - global_position.x)
		_dash_kind = &"grapple"
		_dash_target = point
		_dash_time = dash_timeout
		_swing_node = null
		_set_state(State.DASH)


## How far out the long arm is right now, for drawing.
func _long_arm_extent() -> float:
	if _long_arm_t < 0.0:
		return 0.0
	if _long_arm_t < LONG_ARM_OUT:
		var k := _long_arm_t / LONG_ARM_OUT
		return _long_arm_len * k * k
	if _long_arm_t < LONG_ARM_OUT + LONG_ARM_HOLD:
		return _long_arm_len
	var back := (_long_arm_t - LONG_ARM_OUT - LONG_ARM_HOLD) / LONG_ARM_BACK
	return _long_arm_len * (1.0 - clampf(back, 0.0, 1.0))


func _skill_snatch() -> bool:
	_dash_kind = &"snatch"
	_dash_time = snatch_time
	_snatch_hit.clear()
	_swing_node = null
	_set_state(State.DASH)
	return true


## Passing through someone steals from them: bananas where there are
## bananas, their speed where there are not, and a stumble either way.
## Host only, like every other interaction that moves a number on somebody
## else's screen.
func _resolve_snatch() -> void:
	if not _is_authority():
		return
	for victim in _opponents_near(global_position, snatch_radius + snatch_speed * get_physics_process_delta_time()):
		if _snatch_hit.has(victim.player_id):
			continue
		_snatch_hit.append(victim.player_id)
		_deal_hit(victim, Vector2(float(facing) * 0.25, -0.6).normalized() * stats.knockback_dealt() * 0.6, 0.3)
		var colour := SkillFx.colour_of(stats.skill_id)
		var director: Node = get_tree().get_first_node_in_group(&"hoard_director")
		if director != null and director.has_method(&"steal_bananas") and victim.bananas > 0:
			director.call(&"steal_bananas", victim.player_id, player_id, snatch_fraction)
			SkillFx.popup(get_parent(), victim.global_position + Vector2(0.0, -64.0), "STOLEN!", colour)
			continue
		# No bananas to take, so take the tempo instead.
		victim.set_ability(&"slowed", snatch_slow_seconds)
		set_ability(&"speed_boost", snatch_slow_seconds)
		SkillFx.popup(get_parent(), victim.global_position + Vector2(0.0, -64.0), "SLOWED!", colour)
		if _net_live():
			Net.broadcast_ability(victim.player_id, &"slowed", snatch_slow_seconds)
			Net.broadcast_ability(player_id, &"speed_boost", snatch_slow_seconds)


## A rolling macaque bowls over whoever it rolls into.
func _resolve_roll() -> void:
	if not _is_authority():
		return
	for other in _opponents_near(global_position, 42.0):
		if _snatch_hit.has(other.player_id):
			continue
		_snatch_hit.append(other.player_id)
		_deal_hit(other, Vector2(float(facing), -1.15).normalized() * stats.knockback_dealt() * roll_bowl_power, GameConfig.BASE_STUN_TIME * 1.3)
		SkillFx.popup(get_parent(), other.global_position + Vector2(0.0, -64.0), "BOWLED!", SkillFx.colour_of(stats.skill_id))


func _process_dash(delta: float) -> void:
	_dash_time -= delta
	match _dash_kind:
		&"grapple":
			var to_target := _dash_target - global_position
			if _dash_time <= 0.0 or to_target.length() < 28.0:
				# Arriving keeps some speed rather than stopping dead, so a
				# grapple into a ledge flows into a jump instead of parking you.
				velocity = to_target.normalized() * grapple_pull_speed * 0.25
				_end_dash()
				return
			velocity = to_target.normalized() * grapple_pull_speed
			move_and_slide()
			if get_slide_collision_count() > 0:
				_end_dash()
		&"lunge":
			velocity.x = float(facing) * lunge_speed
			_apply_gravity(delta)
			move_and_slide()
			if _is_authority():
				var reach := global_position + Vector2(float(facing) * (stats.body_size.x * 0.5 + 10.0), 0.0)
				for other in _opponents_near(reach, lunge_catch_radius):
					if other.can_be_grabbed():
						_begin_lift(other)
						return
					if other.invuln_timer > 0.0:
						# Lunged into a rolling macaque: the counter wins.
						other._counter_attacker(player_id)
						_end_dash()
						return
			if _dash_time <= 0.0 or is_on_wall():
				velocity.x *= 0.3
				_end_dash()
		&"lift", &"slam":
			velocity.x = 0.0
			_apply_gravity(delta)
			move_and_slide()
			if _dash_time > 0.0:
				return
			if _dash_kind == &"lift":
				_dash_kind = &"slam"
				_dash_time = slam_drop_time
			else:
				_finish_slam()
		&"snatch":
			velocity = Vector2(float(facing) * snatch_speed, 0.0)
			move_and_slide()
			_resolve_snatch()
			if _dash_time <= 0.0:
				_end_dash()
		_:
			velocity.x = float(facing) * roll_speed
			_apply_gravity(delta)
			move_and_slide()
			_resolve_roll()
			if _dash_time <= 0.0:
				_end_dash()


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
	_double_jump_ready = true
	_squash = 0.35
	_set_state(State.AIR)
	_sfx(&"bounce", _voice_pitch())


func _end_dash() -> void:
	if is_carrying() and _held_target != null and is_instance_valid(_held_target):
		_held_target._held_by = null
	_held_target = null
	_held_target_id = 0
	_dash_kind = &""
	_dash_time = 0.0
	_set_state(State.GROUND if is_on_floor() else State.AIR)


## The macaque's counter. Rolling through an attack stuns the attacker
## instead, which is what makes careless swinging cost something.
func _counter_attacker(attacker_id: int) -> void:
	if not _is_authority():
		return
	var attacker: Player = null
	var arena: Node = get_tree().get_first_node_in_group(&"arena")
	if arena != null and arena.get(&"players") is Dictionary:
		attacker = (arena.get(&"players") as Dictionary).get(attacker_id) as Player
	if attacker == null:
		for other in _opponents_near(global_position, 200.0):
			if other.player_id == attacker_id:
				attacker = other
	if attacker == null:
		return
	var push := (attacker.global_position - global_position).normalized() * stats.knockback_dealt() * 0.9
	push.y = minf(push.y, -200.0)
	attacker.take_hit(player_id, push, GameConfig.BASE_STUN_TIME * 1.4)
	SkillFx.popup(get_parent(), attacker.global_position + Vector2(0.0, -64.0), "COUNTER!", SkillFx.colour_of(stats.skill_id))
	if _net_live():
		Net.broadcast_hit(attacker_id, push, GameConfig.BASE_STUN_TIME * 1.4, player_id)


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
	_long_arm_t = -1.0
	_held_by = null
	_held_target = null
	_held_target_id = 0
	_air_launch_ready = true
	_drop_timer = 0.0
	collision_mask = GameConfig.LAYER_SOLID
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
		# Skill presentation, so replicas draw the same move.
		"k": String(_dash_kind),
		"ht": _held_target_id,
		"la": _long_arm_t >= 0.0,
		"wu": _windup_timer > 0.0,
	}


func apply_net_state(data: Dictionary) -> void:
	_net_target = data.get("p", global_position)
	_has_net_target = true
	velocity = data.get("v", velocity)
	facing = int(data.get("f", facing))
	is_attacking = bool(data.get("a", is_attacking))
	if not _simulates():
		# Replicas only: the monkey this machine predicts keeps its own.
		_dash_kind = StringName(String(data.get("k", String(_dash_kind))))
		_held_target_id = int(data.get("ht", 0))
		if bool(data.get("la", false)) and _long_arm_t < 0.0:
			_long_arm_t = 0.0
			_long_arm_len = long_arm_reach
		if bool(data.get("wu", false)) and _windup_timer <= 0.0:
			_windup_timer = long_arm_windup
	var incoming := int(data.get("s", state))
	if incoming != state:
		if incoming == State.DASH:
			# A remote monkey's skill arrives as a state change. Burst here so
			# everyone sees it, not just the machine that pressed the button.
			SkillFx.burst(get_parent(), global_position, stats.skill_id)
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
	if not _simulates():
		# Replicas animate the long arm and its windup from the snapshot flags.
		if _windup_timer > 0.0:
			_windup_timer = maxf(_windup_timer - delta, 0.0)
		_tick_long_arm(delta)
	_tick_skill_fx(delta)
	_tick_grab_preview(delta)
	_tick_steps(delta)
	_tick_landing()
	_tick_shake(delta)
	_tick_squash(delta)
	_update_ground_shadow()
	# Remote attacks arrive as one boolean in snapshots.  Detect the rising
	# edge here so they get the same full animation as the local attacker.
	if is_attacking and not _attack_was_visible and _slap_fist != null:
		_play_fist()
	_attack_was_visible = is_attacking
	if is_attacking or state == State.SWING or _dash_kind != &"" or _windup_timer > 0.0 or _long_arm_t >= 0.0 \
			or _grab_preview != Vector2.INF or _skill_ready_flash > 0.0:
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
	_draw_skill_windup()
	_draw_grab_preview()
	_draw_ready_flash()
	if state == State.SWING and _swing_node != null and is_instance_valid(_swing_node):
		if swing_on_trunk:
			_draw_stretch_arm(to_local(_swing_anchor))
		else:
			Vine.draw_vine(self, to_local(_swing_anchor), Vector2(0.0, -12.0), Color(0.35, 0.55, 0.28))

	if _dash_kind == &"grapple":
		# The arm itself shoots out to the grip point.
		_draw_stretch_arm(to_local(_dash_target))
	if is_carrying():
		_draw_carry_arms()
	if _long_arm_t >= 0.0:
		_draw_long_arm()


# --- Skill and grab presentation -----------------------------------

## Both arms up to the monkey being lifted and slammed.
func _draw_carry_arms() -> void:
	var target_pos := Vector2.INF
	if _held_target != null and is_instance_valid(_held_target):
		target_pos = _held_target.global_position
	else:
		var arena: Node = get_tree().get_first_node_in_group(&"arena")
		if arena != null and arena.get(&"players") is Dictionary:
			var other := (arena.get(&"players") as Dictionary).get(_held_target_id) as Player
			if other != null:
				target_pos = other.global_position
	if target_pos == Vector2.INF or sprite == null:
		return
	var local := to_local(target_pos)
	var shoulder := sprite.position + sprite.shoulder_position()
	var other_shoulder := Vector2(-shoulder.x, shoulder.y)
	MonkeyArm.draw_arm(self, stats.id, other_shoulder, local + Vector2(-12.0, 16.0), true, facing, Color(0.8, 0.8, 0.8), 1.2, 1.2)
	MonkeyArm.draw_arm(self, stats.id, shoulder, local + Vector2(12.0, 16.0), true, facing, Color.WHITE, 1.2, 1.2)


## The orangutan's long punch: the arm shot straight out across the screen,
## a huge fist on the end and a puff where it lands.
func _draw_long_arm() -> void:
	if sprite == null:
		return
	var shoulder := sprite.position + sprite.shoulder_position()
	var reach := maxf(_long_arm_extent(), absf(shoulder.x) + 8.0)
	var hand := Vector2(reach * float(facing), shoulder.y)
	MonkeyArm.draw_arm(self, stats.id, shoulder, hand, true, facing, Color.WHITE, 2.2, 1.8)
	if _long_arm_t >= LONG_ARM_OUT and _long_arm_t < LONG_ARM_OUT + LONG_ARM_HOLD:
		var k := (_long_arm_t - LONG_ARM_OUT) / LONG_ARM_HOLD
		var colour := Color(1, 1, 1, 1.0 - k)
		for i in 6:
			var angle := TAU * i / 6.0 + k
			var at := hand + Vector2(float(facing) * 18.0, 0.0) + Vector2.from_angle(angle) * (14.0 + k * 22.0)
			draw_rect(Rect2(((at / 4.0).floor() * 4.0) - Vector2(6, 6), Vector2(12, 12)), colour)


## Every sound this monkey makes goes through here, so a muted monkey (the
## menu preview) is silent without touching the audio system.
func _sfx(id: StringName, pitch: float = 1.0) -> void:
	if muted:
		return
	Sfx.play(id, pitch)


## Afterimages while a skill moves the monkey (roll, snatch, grapple, and
## the first moments of a launch), in the skill's colour.
func _tick_skill_fx(delta: float) -> void:
	_skill_ready_flash = maxf(_skill_ready_flash - delta, 0.0)
	if sprite == null or not is_inside_tree():
		return
	if state != State.DASH and _launch_trail <= 0.0:
		_ghost_clock = 0.0
		return
	_ghost_clock -= delta
	if _ghost_clock <= 0.0:
		_ghost_clock = 0.035
		SkillFx.ghost(get_parent(), sprite, SkillFx.colour_of(stats.skill_id))


## Local player only: where a grab would take hold right now, marked with a
## small pulsing ring, so what can be grabbed is never a guess.
func _tick_grab_preview(delta: float) -> void:
	if not local_control or state == State.SWING or state == State.STUN or not is_inside_tree():
		_grab_preview = Vector2.INF
		return
	_grab_preview_clock -= delta
	if _grab_preview_clock > 0.0:
		return
	_grab_preview_clock = 0.08
	var vine := _nearest_vine()
	if vine != null:
		_grab_preview = vine.global_position
		return
	var trunk := _nearest_trunk_point()
	_grab_preview = trunk["point"] if not trunk.is_empty() else Vector2.INF


func _draw_grab_preview() -> void:
	if _grab_preview == Vector2.INF:
		return
	var at := to_local(_grab_preview)
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
	var colour := Color(1.0, 0.85, 0.25, 0.75 + pulse * 0.25)
	var radius := 14.0 + pulse * 4.0
	draw_arc(at, radius, 0.0, TAU, 24, Color(0.1, 0.06, 0.04, 0.85), 8.0)
	draw_arc(at, radius, 0.0, TAU, 24, colour, 4.0)
	# Four ticks pointing in, like a target: "the hand goes here".
	for i in 4:
		var d := Vector2.from_angle(TAU * i / 4.0 + PI * 0.25)
		draw_line(at + d * (radius + 8.0), at + d * (radius + 2.0), colour, 3.0)
	draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), colour)


## The orangutan's long arm charging: a ring closing in on the monkey.
func _draw_skill_windup() -> void:
	if _windup_timer <= 0.0:
		return
	var k := 1.0 - clampf(_windup_timer / maxf(long_arm_windup, 0.01), 0.0, 1.0)
	var colour := SkillFx.colour_of(stats.skill_id)
	draw_arc(Vector2.ZERO, lerpf(70.0, 30.0, k), 0.0, TAU, 32, Color(colour, 0.35 + k * 0.5), 4.0 + k * 3.0)
	draw_arc(Vector2.ZERO, lerpf(70.0, 30.0, k), -PI * 0.5, -PI * 0.5 + TAU * k, 32, Color(1, 1, 1, 0.9), 3.0)


func _draw_ready_flash() -> void:
	if _skill_ready_flash <= 0.0 or not local_control:
		return
	var k := _skill_ready_flash / 0.35
	var colour := SkillFx.colour_of(stats.skill_id)
	draw_arc(Vector2(0, 4), lerpf(52.0, 26.0, k), 0.0, TAU, 28, Color(colour, k), 4.0)


## The punch uses the same authored arm as the grab: the monkey's own
## species arm texture, shot straight out on the side it faces.
func _play_fist() -> void:
	_slap_fist.species = stats.id
	_slap_fist.shoulder_local = sprite.position + sprite.shoulder_position() if sprite != null else Vector2.ZERO
	_slap_fist.play(facing, stats.body_color, stats.slap_reach_scale())


## The rubber arm, from the shoulder to the hand clamped on the grab point.
## Uses the species' crisp arm texture (MonkeyArm) on the sprite's 2x grid;
## the old pixel-by-pixel arm stays as the fallback if the art is missing.
func _draw_stretch_arm(hand: Vector2) -> void:
	if sprite != null and MonkeyArm.texture_for(stats.id, true) != null:
		MonkeyArm.draw_arm(self, stats.id, sprite.position + sprite.shoulder_position(), hand, true, facing)
		return
	var dir := hand.normalized()
	var shoulder := dir * 14.0
	var fur := stats.body_color if stats != null else Color(0.6, 0.4, 0.25)
	var px := MonkeySprite.PIXEL
	var length := shoulder.distance_to(hand)
	var steps := maxi(int(length / px), 1)
	for pass_index in 2:
		# Outline pass first, one art pixel fatter, then the fur on top.
		var half := 2.0 * px if pass_index == 0 else 1.0 * px
		var colour := JunglePalette.OUTLINE if pass_index == 0 else fur
		for i in steps + 1:
			var at := shoulder.lerp(hand, float(i) / steps)
			var cell := (at / px).floor() * px
			draw_rect(Rect2(cell - Vector2(half, half), Vector2(half, half) * 2.0), colour)
	# The hand, a lighter fist closed round the trunk.
	var fist := (hand / px).floor() * px
	draw_rect(Rect2(fist - Vector2(3, 3) * px, Vector2(6, 6) * px), JunglePalette.OUTLINE)
	draw_rect(Rect2(fist - Vector2(2, 2) * px, Vector2(4, 4) * px), fur.lightened(0.18))


func _update_ground_shadow() -> void:
	if not is_inside_tree():
		return
	# The floor under a monkey barely changes frame to frame: re-cast the
	# shadow ray every third frame instead of every frame.
	_shadow_wait -= 1
	if _shadow_wait > 0:
		return
	_shadow_wait = 3
	var query := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, 8), global_position + Vector2(0, 330), GameConfig.LAYER_SOLID, [get_rid()])
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
	var sliding := state == State.SLIDE
	if (_sprint_blend < 0.22 and not sliding) or not (state == State.GROUND or sliding) or absf(velocity.x) < 220.0:
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
		_sfx(&"step", _voice_pitch())


func _tick_landing() -> void:
	var grounded := is_on_floor()
	if grounded and not _was_on_floor and _fall_speed > heavy_land_speed:
		_sfx(&"land", _voice_pitch())
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
		# The rig supplies the poses; fractional scaling breaks the art grid.
		sprite.scale = Vector2.ONE * MonkeySprite.pixel_for(stats.id)


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
		State.SWING:
			sprite.play(&"swing")
		State.DASH:
			match _dash_kind:
				&"roll":
					# A ball, spinning: the roll frames on a loop.
					sprite.show_progress(&"roll", fmod(float(Time.get_ticks_msec()) * 0.0045, 1.0))
				&"lift":
					sprite.play(&"cheer")
				&"slam":
					sprite.play(&"punch")
				_:
					sprite.play(&"dash")
			tint = Color(1.0, 0.97, 0.8)
		State.SLIDE:
			# The dash pose leans hard into the motion, which is what a slide
			# on the backside reads as at this size.
			sprite.play(&"dash")
		State.AIR:
			if _roll_time > 0.0:
				_roll_time = maxf(_roll_time - tick, 0.0)
				sprite.show_progress(&"roll", 1.0 - _roll_time / ROLL_SECONDS)
			else:
				sprite.play(&"jump" if step.y < 0.0 else &"fall")
		_:
			if absf(step.x) / maxf(tick, 0.001) > 40.0:
				sprite.play(&"run")
				sprite.speed_scale = clampf(_moved_speed / 320.0, 0.6, 1.8)
			else:
				sprite.play(&"idle")
	if (is_attacking or _long_arm_t >= 0.0) and state != State.STUN:
		sprite.play(&"punch")
		if _hitbox_open:
			tint = Color(1.25, 1.2, 1.05)
	if state != State.AIR:
		_roll_time = 0.0
	# A slap lands as a jolt: the struck monkey's sprite snaps a pixel or
	# two away from the hand and back for a few frames, before the
	# knockback carries it off. Whole pixels, so it stays on the grid.
	var feet := Vector2(0.0, stats.body_size.y * 0.5)
	if _jolt_time > 0.0:
		_jolt_time = maxf(_jolt_time - tick, 0.0)
		var k := int(_jolt_time * 60.0)
		sprite.position = feet + Vector2(MonkeySprite.PIXEL * (2.0 if k % 2 == 0 else -1.0), 0.0)
	else:
		sprite.position = feet
	if _spawn_shield > 0.0 and int(Time.get_ticks_msec() / 90) % 2 == 0:
		tint.a = 0.35
	sprite.self_modulate = tint
	if state == State.GROUND and _sprint_blend > 0.05 and absf(step.x) > 0.05:
		sprite.speed_scale *= lerpf(1.0, 1.26, _sprint_blend)
	# Snap only the artwork, never the physics body or network position.
	sprite.position = LevelSkin.snap(global_position + Vector2(0, stats.body_size.y * 0.5)) - global_position
	if _sprite_shadow != null:
		_sync_sprite_layer(_sprite_shadow, Vector2(4.0, 6.0), 1.0)
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
