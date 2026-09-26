class_name MonkeyStats
extends Resource

# ============================================================
# MONKEY STATS - the five axes from the design doc, as data.
#
# Every axis is a multiplier against the base values in GameConfig, where
# 1.0 is the reference monkey. Balancing is then editing a .tres in the
# inspector, not editing code, which is the whole point of the resource.
# ============================================================

@export var id: StringName = &"macaque"
@export var display_name: String = "Macaque"
@export_multiline var blurb: String = ""
@export var body_color: Color = Color(0.90, 0.55, 0.20)

# Body size matters for feel as much as the stats do: the gorilla reading
# as physically bigger is what sells "hard to move" before you even hit it.
@export var body_size: Vector2 = Vector2(32.0, 64.0)

@export_group("Axes")
## Ground movement rate.
@export_range(0.4, 1.8, 0.05) var speed: float = 1.0
## Resistance to incoming knockback and stun. Higher is harder to move.
@export_range(0.4, 2.2, 0.05) var weight: float = 1.0
## Knockback dealt by normal attacks.
@export_range(0.3, 2.2, 0.05) var power: float = 1.0
## Vertical climbing speed.
@export_range(0.4, 2.0, 0.05) var climb: float = 1.0
## Swing momentum retention and air control.
@export_range(0.4, 2.0, 0.05) var swing: float = 1.0
## Arm length. Stretches the slap's reach and the grab reach together, so a
## long-armed monkey is long-armed at everything it does with its arms.
@export_range(0.8, 2.0, 0.05) var arm_length: float = 1.0

## Attack pace. Above 1 winds up, recovers and cools down faster.
@export_range(0.5, 2.0, 0.05) var attack_speed: float = 1.0

@export_group("Skill")
## Identifier consumed by the skill system. Empty means no skill yet.
@export var skill_id: StringName = &""
@export var skill_cooldown: float = 3.0
## Uses stored up. Above 1 the skill can be fired again straight away until
## the stack is empty; spent charges refill one per cooldown.
@export_range(1, 3) var skill_charges: int = 1


# --- Derived values -------------------------------------------------
# Kept as functions rather than exported numbers so a stat edit can never
# fall out of sync with the value it is supposed to drive.

func run_speed() -> float:
	return GameConfig.BASE_RUN_SPEED * speed


func climb_speed() -> float:
	return GameConfig.BASE_CLIMB_SPEED * climb


func jump_velocity() -> float:
	# Heavier monkeys jump slightly lower, but only slightly. Tying jump
	# height directly to weight would make the gorilla unable to clear the
	# level geometry that the gibbon plays on.
	var jump := GameConfig.BASE_JUMP_VELOCITY * lerpf(1.0, 0.88, clampf((weight - 1.0) / 1.2, 0.0, 1.0))
	# Small monkeys spring a little higher.
	if body_size.x < 30.0:
		jump *= 1.05
	return jump


func knockback_dealt() -> float:
	return GameConfig.BASE_KNOCKBACK * power


## Knockback actually received, after this monkey's weight resists it.
func knockback_taken(incoming: float) -> float:
	return incoming / maxf(weight, 0.2)


## 0.0 means a swing bleeds speed fast, 1.0 means it keeps almost everything.
func swing_retention() -> float:
	return clampf(0.985 + (swing - 1.0) * 0.012, 0.95, 0.999)


## How far the normal slap reaches, as a share of the base reach. Arm length
## as before, but a small body no longer reaches as far as a gorilla's.
func slap_reach_scale() -> float:
	return arm_length * clampf(body_size.x / 32.0, 0.88, 1.0)


func air_control() -> float:
	return clampf(swing, 0.4, 2.0)
