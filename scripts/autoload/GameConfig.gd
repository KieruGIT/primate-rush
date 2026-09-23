extends Node

# ============================================================
# GAME CONFIG - shared constants and the monkey roster.
#
# Everything that two unrelated systems both need to agree on lives here,
# so a collision layer or a base tuning number is changed in exactly one
# place. Per-monkey variation belongs in MonkeyStats resources instead.
# ============================================================

# --- Collision layers. Mirrors [layer_names] in project.godot. ---
# Written as explicit bit values because a wrong layer is invisible at
# runtime: things just silently stop colliding.
const LAYER_WORLD: int = 1 << 0
const LAYER_PLAYER: int = 1 << 1
const LAYER_HITBOX: int = 1 << 2
const LAYER_HURTBOX: int = 1 << 3
const LAYER_CLIMBABLE: int = 1 << 4
const LAYER_VINE: int = 1 << 5
const LAYER_PICKUP: int = 1 << 6
## Thin ledges. One-way: jump up through them from below, stand on top, and
## hold down to drop back through. Own layer so a drop can switch just these
## off for a moment without letting the monkey fall through the ground.
const LAYER_PLATFORM: int = 1 << 7
## Anything you can stand on. Ground probes (shadows, bot gap checks) use
## this; things that only solid rock should stop (arm reach) use LAYER_WORLD.
const LAYER_SOLID: int = LAYER_WORLD | LAYER_PLATFORM

# --- Base movement tuning. MonkeyStats multiplies these. ---
# A stat of 1.0 means "exactly these numbers", which makes the macaque the
# reference monkey and every other value readable as a percentage of it.
const BASE_RUN_SPEED: float = 420.0
const BASE_CLIMB_SPEED: float = 300.0
const BASE_JUMP_VELOCITY: float = -720.0
const BASE_GRAVITY: float = 1900.0
const BASE_KNOCKBACK: float = 640.0
const BASE_STUN_TIME: float = 0.45

## Match types. Free play is the movement sandbox: no timer, no placement,
## just the level. It is the mode every tuning session actually happens in.
# SLAP is appended, never inserted: the mode travels over the wire as an int.
enum Mode { FREE_PLAY, RACE, HOARD, SLAP }

const MODE_NAMES: Dictionary = {
	Mode.FREE_PLAY: "Free play",
	Mode.RACE: "Race",
	Mode.HOARD: "Banana Hoard",
	Mode.SLAP: "2v2 Slap",
}

## Matchmaking queues. Both look for real players on the network first and
## fill whatever seats are still empty with AI when the search runs out.
##   CLASSIC  your own setup: mode, map, AI count and difficulty
##   RANKED   fixed rules (full field, fierce AI, no free play) and every
##            match moves your rank points up or down
# Appended, never inserted: the queue travels over the wire as an int.
enum Queue { CLASSIC, RANKED }

const QUEUE_NAMES: Dictionary = {
	Queue.CLASSIC: "Classic",
	Queue.RANKED: "Ranked",
}

## Modes a ranked match can be. Free play has no winner to rank.
const RANKED_MODES: Array = [Mode.RACE, Mode.HOARD, Mode.SLAP]

## Seconds spent listening for an open room before opening our own, and then
## seconds our own room waits for players before AI fills it. The listen
## window is jittered per search so two phones that press PLAY in the same
## second do not both give up and both host.
const MATCH_LISTEN_SECONDS: Vector2 = Vector2(2.0, 3.5)
const MATCH_WAIT_SECONDS: float = 10.0

## Rank tiers by rank points. Each tier is split into III, II, I.
const RANK_TIERS: Array = [
	["BRONZE", 0], ["SILVER", 300], ["GOLD", 700], ["JUNGLE", 1200], ["APEX", 1800],
]


func rank_for(rp: int) -> Dictionary:
	var tier := 0
	for index in RANK_TIERS.size():
		if rp >= int(RANK_TIERS[index][1]):
			tier = index
	var low := int(RANK_TIERS[tier][1])
	var last := tier == RANK_TIERS.size() - 1
	if last:
		return {"name": String(RANK_TIERS[tier][0]), "progress": 1.0, "next": -1}
	var high := int(RANK_TIERS[tier + 1][1])
	var step := float(high - low) / 3.0
	var division := clampi(int(float(rp - low) / step), 0, 2)
	var next := low + int(round(step * float(division + 1)))
	var from := low + int(round(step * float(division)))
	return {
		"name": "%s %s" % [RANK_TIERS[tier][0], ["III", "II", "I"][division]],
		"progress": clampf(float(rp - from) / maxf(float(next - from), 1.0), 0.0, 1.0),
		"next": next,
	}


## Rank points for one finished ranked match. First place in a full field is
## +30 and last is -15; 2v2 is a straight win, loss or draw.
func ranked_delta(mode: int, place: int, field: int, row: Dictionary) -> int:
	if mode == Mode.SLAP:
		if bool(row.get("draw", false)):
			return 0
		return 25 if bool(row.get("won", false)) else -12
	if field <= 1 or place <= 0:
		return 0
	var t := float(place - 1) / float(field - 1)
	return int(round(lerpf(30.0, -15.0, t)))


const MAP_PATHS: Dictionary = {
	&"map_a": "res://scenes/maps/MapA.tscn",
	&"map_b": "res://scenes/maps/MapB.tscn",
	&"map_c": "res://scenes/maps/SlapArena.tscn",
}

const MAP_NAMES: Dictionary = {
	&"map_a": "Jungle Run",
	&"map_b": "Canopy Climb",
	&"map_c": "Slap Island",
}

## Which maps a mode can be played on. A race needs a finish line, and a
## slap fight needs an island small enough that the edge is always close.
const MODE_MAPS: Dictionary = {
	Mode.FREE_PLAY: [&"map_a", &"map_b", &"map_c"],
	Mode.RACE: [&"map_a", &"map_b"],
	Mode.HOARD: [&"map_a", &"map_b"],
	Mode.SLAP: [&"map_c"],
}

# --- 2v2 Slap ---
## Seats 0 and 1 are one team, 2 and 3 the other. Solo that is you and an
## AI partner against two AI; in a party the first two people team up.
const TEAM_NAMES: Array[String] = ["Banana", "Coconut"]
const TEAM_COLORS: Array[Color] = [Color(1.0, 0.80, 0.10), Color(0.35, 0.70, 0.95)]
const SLAP_TARGET_KOS: int = 5
const SLAP_ROUND_SECONDS: float = 150.0

## Falling costs time, never a life. Short enough to sting without making
## someone put the phone down.
const RESPAWN_DELAY: float = 0.7

const NET_DEFAULT_PORT: int = 27015
const NET_MAX_PLAYERS: int = 4

# --- Bots ---
## How many AI opponents a fresh lobby asks for. Three, not zero: the first
## thing anyone does is press the big button, and a party game that answers
## that with an empty level has failed at the only moment it had.
const DEFAULT_BOTS: int = NET_MAX_PLAYERS - 1

## Bot difficulty. The value is the skill level handed to BotBrain, which
## scales reaction delay and aim rather than movement speed - an easy bot is
## slow to notice you, not visibly crippled.
enum BotSkill { RELAXED, NORMAL, FIERCE }

const BOT_SKILL_NAMES: Dictionary = {
	BotSkill.RELAXED: "Relaxed",
	BotSkill.NORMAL: "Normal",
	BotSkill.FIERCE: "Fierce",
}

const BOT_SKILL_LEVELS: Dictionary = {
	BotSkill.RELAXED: 0.55,
	BotSkill.NORMAL: 1.0,
	BotSkill.FIERCE: 1.6,
}

## Bots get names because "Gibbon (bot)" three times over is unreadable the
## moment two of them pick the same monkey, and a scoreboard you cannot read
## is a scoreboard nobody looks at.
const BOT_NAMES: Array[String] = [
	"Bongo", "Kiki", "Mango", "Tito", "Nacho", "Pepper", "Zuzu", "Bandit",
]

# Player colors by join order, so four monkeys on one screen stay readable
# before there is any art.
const PLAYER_TINTS: Array[Color] = [
	Color(0.90, 0.55, 0.20),
	Color(0.35, 0.70, 0.95),
	Color(0.55, 0.85, 0.40),
	Color(0.90, 0.45, 0.75),
]

# --- Roster ---
# Paths rather than preloaded resources: preloading a .tres at autoload time
# makes a missing file a hard startup crash instead of a recoverable warning.
const MONKEY_PATHS: Dictionary = {
	&"gorilla": "res://resources/monkeys/gorilla.tres",
	&"gibbon": "res://resources/monkeys/gibbon.tres",
	&"macaque": "res://resources/monkeys/macaque.tres",
	&"orangutan": "res://resources/monkeys/orangutan.tres",
	&"capuchin": "res://resources/monkeys/capuchin.tres",
}

# Locked monkeys are gated behind the RevenueCat entitlement. Keeping the
# gate as data means the purchase unlocks content without touching code.
const PREMIUM_MONKEYS: Array[StringName] = [&"macaque"]

# --- Cosmetics ---
# Recolors and simple shapes first, because they are near free to produce.
# The value here is not the hats, it is that the attachment point, the
# roster field and the network sync all exist before there is any art.
const HATS: Dictionary = {
	&"none": {"name": "Bare head", "style": &"none", "color": Color(1, 1, 1), "premium": false},
	&"cap": {"name": "Cap", "style": &"cap", "color": Color(0.85, 0.30, 0.25), "premium": false},
	&"band": {"name": "Headband", "style": &"band", "color": Color(0.30, 0.65, 0.85), "premium": false},
	&"crown": {"name": "Crown", "style": &"crown", "color": Color(0.95, 0.80, 0.25), "premium": true},
	&"tophat": {"name": "Top hat", "style": &"tophat", "color": Color(0.15, 0.15, 0.20), "premium": true},
}

var _cache: Dictionary = {}


func get_monkey(id: StringName) -> MonkeyStats:
	if _cache.has(id):
		return _cache[id]
	if not MONKEY_PATHS.has(id):
		push_warning("Unknown monkey id: %s" % id)
		return _fallback_stats()
	var res: Resource = load(MONKEY_PATHS[id])
	if res is MonkeyStats:
		_cache[id] = res
		return res
	push_warning("Monkey resource missing or wrong type: %s" % MONKEY_PATHS[id])
	return _fallback_stats()


func roster_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key in MONKEY_PATHS.keys():
		ids.append(key)
	return ids


func is_unlocked(id: StringName) -> bool:
	if not PREMIUM_MONKEYS.has(id):
		return true
	return Purchases.has_premium()


## Bots never take a premium monkey. A locked character playing itself in
## front of someone who has not bought it is a bad advert for buying it.
func random_bot_monkey() -> StringName:
	var pool: Array[StringName] = []
	for id in MONKEY_PATHS.keys():
		if not PREMIUM_MONKEYS.has(id):
			pool.append(id)
	if pool.is_empty():
		return &"gibbon"
	return pool[randi() % pool.size()]


func bot_skill_level(skill: int) -> float:
	return float(BOT_SKILL_LEVELS.get(skill, 1.0))


## Distinct per match rather than random per bot: two monkeys called Mango in
## the same race is exactly the confusion the names exist to prevent.
func bot_names(count: int) -> Array[String]:
	var pool := BOT_NAMES.duplicate()
	pool.shuffle()
	var picked: Array[String] = []
	for index in count:
		picked.append(pool[index % pool.size()])
	return picked


func hat_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key in HATS.keys():
		ids.append(key)
	return ids


func get_hat(id: StringName) -> Dictionary:
	return HATS.get(id, HATS[&"none"])


func is_hat_unlocked(id: StringName) -> bool:
	return not bool(get_hat(id).get("premium", false)) or Purchases.has_premium()


func map_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key in MAP_PATHS.keys():
		ids.append(key)
	return ids


func load_map(id: StringName) -> PackedScene:
	var path: String = MAP_PATHS.get(id, MAP_PATHS[&"map_a"])
	var scene: Resource = load(path)
	return scene as PackedScene


func tint_for_index(index: int) -> Color:
	return PLAYER_TINTS[index % PLAYER_TINTS.size()]


func maps_for_mode(mode: int) -> Array:
	return MODE_MAPS.get(mode, map_ids())


func team_of(slot: int) -> int:
	return clampi(slot / 2, 0, 1)


func _fallback_stats() -> MonkeyStats:
	# A resource that failed to load must not take the game down mid-match,
	# so hand back a playable average monkey and log it instead.
	var stats := MonkeyStats.new()
	stats.id = &"missing"
	stats.display_name = "Missing Monkey"
	return stats
