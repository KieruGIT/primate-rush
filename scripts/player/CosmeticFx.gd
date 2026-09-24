extends Node2D

# ============================================================
# COSMETIC FX - the four effect slots, on a monkey and on the win screen.
#
# Added as a child of the local player (Main does it). Each frame it looks
# at the player and fires whichever equipped effect fits:
#   TRAIL  a stream of particles behind you while you move fast
#   PUNCH  a burst where the fist lands, every time the hitbox opens
#   CLIMB  puffs while climbing or swinging, and a pop on every grab
# WIN is not tied to a monkey: Results calls play_win() over the podium.
#
# Everything is CPUParticles2D with no texture, so every particle is a flat
# square: the same pixel look as the rest of the game, and cheap on phones.
# ============================================================

var player: Node2D = null
var trail_id: StringName = &""
var punch_id: StringName = &""
var climb_id: StringName = &""

var _trail: CPUParticles2D = null
var _was_hitting: bool = false
var _last_state: int = -1
var _climb_clock: float = 0.0


func setup(target: Node2D, equipped: Dictionary) -> void:
	player = target
	trail_id = StringName(equipped.get(&"trail", &""))
	punch_id = StringName(equipped.get(&"punch", &""))
	climb_id = StringName(equipped.get(&"climb", &""))


func _ready() -> void:
	z_index = -1
	if not trail_id.is_empty():
		_trail = _make_trail(trail_id)
		_trail.emitting = false
		add_child(_trail)


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var velocity: Vector2 = player.get(&"velocity")
	var state: int = int(player.get(&"state"))
	if _trail != null:
		_trail.emitting = velocity.length() > 230.0 and player.visible
		_trail.direction = -velocity.normalized() if velocity.length() > 1.0 else Vector2.UP
	# Punch: the rising edge of the hitbox.
	var hitting := bool(player.get(&"_hitbox_open"))
	if hitting and not _was_hitting and not punch_id.is_empty():
		var hitbox: Node2D = player.get(&"hitbox")
		var at := hitbox.global_position if hitbox != null else player.global_position
		burst(get_parent().get_parent(), punch_id, at)
	_was_hitting = hitting
	# Climb: a pop on each grab, then puffs while holding on.
	var holding := state == 2 or state == 3   # CLIMB, SWING
	if not climb_id.is_empty():
		if holding and _last_state != state:
			burst(get_parent().get_parent(), climb_id, player.global_position + Vector2(0, -20))
			_climb_clock = 0.0
		elif holding:
			_climb_clock += delta
			if _climb_clock > 0.3:
				_climb_clock = 0.0
				burst(get_parent().get_parent(), climb_id, player.global_position + Vector2(randf_range(-10, 10), -10), 0.5)
	_last_state = state


# --- One-shot bursts -------------------------------------------------

## A burst for a PUNCH or CLIMB item at a world position. `scale_amount`
## shrinks the repeated climbing puffs next to the grab pop.
static func burst(parent: Node, id: StringName, at: Vector2, amount_scale: float = 1.0) -> void:
	if parent == null:
		return
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	p.z_index = 20
	p.spread = 180.0
	p.gravity = Vector2(0, 300)
	p.scale_amount_min = 4.0
	p.scale_amount_max = 6.0
	p.lifetime = 0.45
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 200.0
	p.amount = 14
	match id:
		&"punch_sparks":
			p.color_ramp = _ramp([Color(1, 1, 0.8), Color(1, 0.7, 0.2), Color(1, 0.4, 0.1, 0)])
			p.initial_velocity_max = 320.0
			p.scale_amount_min = 2.0
			p.scale_amount_max = 4.0
		&"punch_stars":
			p.color_ramp = _ramp([Color(1, 1, 0.6), Color(1, 0.9, 0.3), Color(1, 0.9, 0.3, 0)])
			p.gravity = Vector2(0, -40)
			p.lifetime = 0.7
			p.amount = 10
			p.scale_amount_min = 6.0
			p.scale_amount_max = 8.0
		&"punch_banana":
			p.color_ramp = _ramp([Color8(255, 226, 90), Color8(230, 180, 40), Color8(230, 180, 40, 0)])
			p.gravity = Vector2(0, 600)
			p.initial_velocity_min = 180.0
			p.initial_velocity_max = 360.0
			p.lifetime = 0.8
			p.scale_amount_min = 6.0
			p.scale_amount_max = 9.0
		&"punch_thunder":
			p.color_ramp = _ramp([Color(1, 1, 1), Color(0.6, 0.85, 1), Color(0.3, 0.5, 1, 0)])
			p.gravity = Vector2.ZERO
			p.initial_velocity_min = 250.0
			p.initial_velocity_max = 480.0
			p.amount = 24
			p.lifetime = 0.3
			p.scale_amount_min = 3.0
			p.scale_amount_max = 5.0
		&"climb_puff":
			p.color_ramp = _ramp([Color8(120, 190, 80), Color8(70, 140, 50), Color8(70, 140, 50, 0)])
			p.gravity = Vector2(0, 120)
			p.initial_velocity_max = 110.0
		&"climb_sparkle":
			p.color_ramp = _ramp([Color(1, 1, 1), Color(0.7, 0.9, 1), Color(0.7, 0.9, 1, 0)])
			p.gravity = Vector2(0, -30)
			p.scale_amount_min = 2.0
			p.scale_amount_max = 4.0
			p.lifetime = 0.6
		&"climb_hearts":
			p.color_ramp = _ramp([Color8(255, 110, 150), Color8(255, 60, 110), Color8(255, 60, 110, 0)])
			p.gravity = Vector2(0, -90)
			p.initial_velocity_max = 90.0
			p.lifetime = 0.8
			p.amount = 8
		&"climb_gold":
			p.color_ramp = _ramp([Color8(255, 240, 150), Color8(255, 196, 52), Color8(200, 130, 20, 0)])
			p.gravity = Vector2(0, 80)
			p.amount = 20
			p.scale_amount_min = 3.0
			p.scale_amount_max = 6.0
		_:
			p.queue_free()
			return
	p.amount = maxi(int(p.amount * amount_scale), 2)
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


# --- Trails ----------------------------------------------------------

static func _make_trail(id: StringName) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.local_coords = false
	p.position = Vector2(0, 20)
	p.amount = 24
	p.lifetime = 0.45
	p.spread = 25.0
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 60.0
	p.scale_amount_min = 6.0
	p.scale_amount_max = 9.0
	p.gravity = Vector2(0, 60)
	match id:
		&"trail_dust":
			p.color_ramp = _ramp([Color8(190, 160, 120, 200), Color8(150, 120, 90, 120), Color8(150, 120, 90, 0)])
		&"trail_leaves":
			p.color_ramp = _ramp([Color8(140, 210, 90), Color8(70, 150, 60), Color8(70, 150, 60, 0)])
			p.lifetime = 0.8
			p.gravity = Vector2(0, 90)
			p.angular_velocity_min = -180.0
			p.angular_velocity_max = 180.0
		&"trail_fire":
			p.color_ramp = _ramp([Color8(255, 240, 150), Color8(255, 140, 40), Color8(200, 40, 20, 0)])
			p.gravity = Vector2(0, -160)
			p.amount = 40
			p.lifetime = 0.5
		&"trail_rainbow":
			p.color_ramp = _ramp([Color8(255, 80, 80), Color8(255, 200, 60), Color8(90, 220, 90), Color8(80, 160, 255), Color8(180, 90, 255, 0)])
			p.gravity = Vector2.ZERO
			p.amount = 48
			p.lifetime = 0.6
			p.scale_amount_min = 5.0
			p.scale_amount_max = 7.0
	return p


# --- Win -------------------------------------------------------------

## Fills `layer` (a full-screen Control or CanvasLayer child) with the WIN
## effect for a few seconds. Called by the results screen when you won.
static func play_win(host: Node, id: StringName, view: Vector2) -> void:
	if host == null or id.is_empty():
		return
	match id:
		&"win_confetti":
			host.add_child(_rain(view, [Color8(255, 90, 90), Color8(255, 210, 60), Color8(90, 200, 255), Color8(120, 230, 110), Color8(220, 120, 255)], 120, 5.0, 260.0))
		&"win_bananas":
			host.add_child(_rain(view, [Color8(255, 226, 90), Color8(240, 190, 50)], 60, 9.0, 380.0))
		&"win_crown":
			host.add_child(_rain(view, [Color8(255, 236, 140), Color8(255, 196, 52), Color8(230, 60, 80)], 90, 7.0, 300.0))
			_fireworks(host, view, 3)
		&"win_fireworks":
			_fireworks(host, view, 6)


static func _rain(view: Vector2, colors: Array, amount: int, size: float, fall: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = Vector2(view.x * 0.5, -20)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(view.x * 0.5, 10)
	p.direction = Vector2.DOWN
	p.spread = 15.0
	p.gravity = Vector2(0, 120)
	p.initial_velocity_min = fall * 0.6
	p.initial_velocity_max = fall
	p.amount = amount
	p.lifetime = view.y / fall + 0.8
	p.scale_amount_min = size * 0.7
	p.scale_amount_max = size
	p.angular_velocity_min = -200.0
	p.angular_velocity_max = 200.0
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0])
	gradient.colors = PackedColorArray([colors[0]])
	for i in range(1, colors.size()):
		gradient.add_point(float(i) / float(colors.size()), colors[i])
	p.color_initial_ramp = gradient
	p.emitting = true
	return p


static func _fireworks(host: Node, view: Vector2, count: int) -> void:
	for i in count:
		var p := CPUParticles2D.new()
		p.one_shot = true
		p.emitting = false
		p.explosiveness = 1.0
		p.position = Vector2(randf_range(view.x * 0.15, view.x * 0.85), randf_range(view.y * 0.12, view.y * 0.45))
		p.amount = 70
		p.lifetime = 1.3
		p.spread = 180.0
		p.gravity = Vector2(0, 140)
		p.initial_velocity_min = 220.0
		p.initial_velocity_max = 360.0
		p.scale_amount_min = 7.0
		p.scale_amount_max = 10.0
		var hue := randf()
		p.color_ramp = _ramp([Color.from_hsv(hue, 0.3, 1.0), Color.from_hsv(hue, 0.8, 1.0), Color.from_hsv(hue, 0.9, 0.8, 0.0)])
		host.add_child(p)
		# Staggered, so they pop one after another instead of all at once.
		# Bound to the particles themselves, so a preview that is closed
		# before its timer fires just drops the call.
		host.get_tree().create_timer(0.35 * i).timeout.connect(p.set_emitting.bind(true))
		p.finished.connect(p.queue_free)


static func _ramp(colors: Array) -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([colors[0], colors[colors.size() - 1]])
	for i in range(1, colors.size() - 1):
		gradient.add_point(float(i) / float(colors.size() - 1), colors[i])
	return gradient
