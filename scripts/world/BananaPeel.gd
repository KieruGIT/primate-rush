extends Area2D

# ============================================================
# BANANA PEEL - the chimp's trap, left behind after its snack.
#
# Dropped (or tossed) to a spot on the ground, then it sits there. The first
# monkey other than the thrower (and its teammate in 2v2) to step on it
# slips: feet out, a skid and a short stun. The host decides the slip and
# broadcasts it as a hit; every machine removes the peel on contact.
# ============================================================

const PATH := "res://scripts/world/BananaPeel.gd"
const SkillFx = preload("res://scripts/player/SkillFx.gd")
const LIFETIME: float = 9.0
const FLIGHT: float = 0.3
const PX: float = 2.0
## A splayed peel, 12 x 7 art pixels.
const ART: Array[String] = [
	"....yy......",
	"...yyly.....",
	"y..yyly..yy.",
	"yy.yyyy.yly.",
	".yyyyyyyyy..",
	"..ddyyyydd..",
	"...dddddd...",
]
const COLORS: Dictionary = {
	"y": Color8(255, 214, 58),
	"l": Color8(255, 244, 170),
	"d": Color8(200, 140, 30),
}

var owner_id: int = 0
var owner_team: int = -1
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _t: float = 0.0
var _age: float = 0.0
var _landed: bool = false


## Every thrower keeps at most six peels down; the oldest goes first.
static func throw(parent: Node, thrower: Node2D, from: Vector2, to: Vector2) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var mine: Array = []
	for node in parent.get_children():
		if node.get_script() != null and node.get_script().resource_path == PATH and int(node.get(&"owner_id")) == int(thrower.get(&"player_id")):
			mine.append(node)
	while mine.size() >= 6:
		(mine.pop_front() as Node).queue_free()
	var peel: Area2D = (load(PATH) as Script).new()
	peel.set(&"owner_id", int(thrower.get(&"player_id")))
	peel.set(&"owner_team", int(thrower.get(&"team")))
	peel.set(&"_from", from)
	peel.set(&"_to", to)
	peel.global_position = from
	parent.add_child(peel)


func _ready() -> void:
	z_index = 4
	collision_layer = 0
	collision_mask = GameConfig.LAYER_PLAYER
	monitoring = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(34.0, 16.0)
	shape.shape = rect
	shape.position = Vector2(0.0, -6.0)
	add_child(shape)
	body_entered.connect(_on_body)


func _process(delta: float) -> void:
	_age += delta
	if not _landed:
		_t = minf(_t + delta / FLIGHT, 1.0)
		# A lob: straight line plus a hump.
		# Dropped straight down there is no hump; tossed sideways, a lob.
		var hump := clampf(absf(_to.x - _from.x) * 0.4, 0.0, 120.0)
		global_position = _from.lerp(_to, _t) + Vector2(0.0, -hump * 4.0 * _t * (1.0 - _t))
		if _t >= 1.0:
			_landed = true
	if _age >= LIFETIME:
		queue_free()
		return
	if _landed:
		# Checked every frame rather than on enter only: a peel that lands
		# right under someone's feet still gets them.
		for body in get_overlapping_bodies():
			_on_body(body)
			if is_queued_for_deletion():
				return
	queue_redraw()


func _on_body(body: Node) -> void:
	if not _landed or not (body is Player):
		return
	if is_queued_for_deletion():
		return
	var victim := body as Player
	if victim.player_id == owner_id or (owner_team >= 0 and victim.team == owner_team):
		return
	if victim.is_ghost() or victim.is_unstoppable():
		return
	if victim._is_authority():
		# Feet out from under it, the way it was going.
		var dir := signf(victim.velocity.x)
		if dir == 0.0:
			dir = float(victim.facing)
		# Feet out and a long skid along the ground, the full cartoon slip.
		var force := Vector2(dir * 820.0, -120.0)
		victim.take_hit(owner_id, force, 0.85)
		victim.slide_after_slip()
		# Off balance for a moment afterwards: hits land harder.
		victim.set_ability(&"slipped", 1.6)
		if Net.is_online() and not victim.sandbox:
			Net.broadcast_ability(victim.player_id, &"slipped", 1.6)
		if Net.is_online() and not victim.sandbox:
			Net.broadcast_hit(victim.player_id, force, 0.85, owner_id)
		SkillFx.popup(get_parent(), victim.global_position + Vector2(0.0, -64.0), "SLIP!", SkillFx.colour_of(&"snatch"))
	queue_free()


func _draw() -> void:
	# Fades in its last second so it does not just blink out.
	var alpha := clampf(LIFETIME - _age, 0.0, 1.0)
	var spin := 0.0 if _landed else _t * TAU * 1.5
	draw_set_transform(Vector2.ZERO, spin, Vector2.ONE)
	var w := ART[0].length()
	var h := ART.size()
	var origin := Vector2(-w * PX * 0.5, -h * PX)
	for y in h:
		var row: String = ART[y]
		for x in w:
			var key := row[x]
			if COLORS.has(key):
				var c: Color = COLORS[key]
				c.a = alpha
				draw_rect(Rect2(origin + Vector2(x, y) * PX, Vector2(PX, PX)), c)
