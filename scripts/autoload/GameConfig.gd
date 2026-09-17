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
enum Mode { FREE_PLAY, RACE, HOARD }

const MODE_NAMES: Dictionary = {
	Mode.FREE_PLAY: "Free play",
	Mode.RACE: "Race",
	Mode.HOARD: "Banana Hoard",
}

const MAP_PATHS: Dictionary = {
	&"map_a": "res://scenes/maps/MapA.tscn",
	&"map_b": "res://scenes/maps/MapB.tscn",
}

const MAP_NAMES: Dictionary = {
	&"map_a": "Horizontal Run",
	&"map_b": "Vertical Ascent",
}

## Falling costs time, never a life. Short enough to sting without making
## someone put the phone down.
const RESPAWN_DELAY: float = 0.7

const NET_DEFAULT_PORT: int = 27015
const NET_MAX_PLAYERS: int = 4

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
}

# Locked monkeys are gated behind the RevenueCat entitlement. Keeping the
# gate as data means the purchase unlocks content without touching code.
const PREMIUM_MONKEYS: Array[StringName] = [&"macaque"]

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


func _fallback_stats() -> MonkeyStats:
	# A resource that failed to load must not take the game down mid-match,
	# so hand back a playable average monkey and log it instead.
	var stats := MonkeyStats.new()
	stats.id = &"missing"
	stats.display_name = "Missing Monkey"
	return stats
