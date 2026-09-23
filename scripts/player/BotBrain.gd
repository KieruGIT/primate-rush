class_name BotBrain
extends RefCounted

# ============================================================
# BOT BRAIN - an opponent that plays the game the way a player does.
#
# A bot produces an InputFrame and nothing else. It has no special access:
# no teleporting, no ignoring gravity, no reading another monkey's state
# through a back door. That falls straight out of the input abstraction, and
# it means anything a bot can do, a human can do, and every movement fix
# helps both.
#
# Bots run on the host only. Clients see them as ordinary monkeys arriving
# in snapshots, because to the netcode that is exactly what they are.
# ============================================================

## How far ahead to look for a wall worth jumping.
const WALL_PROBE: float = 40.0
## How far ahead to look for a floor that is not there.
const GAP_PROBE: float = 64.0
const GAP_DEPTH: float = 140.0
## Beyond this, a bot ignores a player and goes back to the objective.
const AGGRO_RANGE: float = 320.0
const ATTACK_RANGE: float = 115.0

## Lower is sloppier. Scales reaction delays rather than movement speed, so
## an easy bot is slow to react, not visibly crippled. A bot that ran slower
## would just look broken; one that notices you late looks beatable.
var skill_level: float = 1.0

## Where the bot currently believes it is going, refreshed on its own clock
## rather than every tick. This is the whole difficulty knob: a relaxed bot
## steers toward where the banana was a third of a second ago, and overshoots
## it exactly the way a distracted person does.
var _target: Vector2 = Vector2.ZERO
var _has_target: bool = false
var _think_timer: float = 0.0

var _jump_hold: float = 0.0
var _attack_cooldown: float = 0.0
var _skill_cooldown: float = 0.0
var _stuck_time: float = 0.0
var _unstick_dir: float = 0.0
var _unstick_time: float = 0.0
var _last_position: Vector2 = Vector2.ZERO
## Index into the map's route, or -1 before the bot has placed itself on it.
var _route_index: int = -1
## True while chasing a route point that is not the last: run flat out at
## it instead of easing in, because easing in is how a bot arrives at a gap
## edge at walking pace and drops short.
var _passing_through: bool = false
## How long the current swing has lasted. A bot that has not let go after a
## few seconds lets go anyway: hanging forever is the one failure a swing
## must never have.
var _swing_time: float = 0.0
## The vine just let go of, and how long to leave it alone. Without it a
## bot dropping to a target below re-takes the same vine, forever. Only
## that vine: the next one in a chain is fair game at once.
var _left_vine: Node2D = null
var _no_grab_time: float = 0.0
## 2v2: one recovery double jump per trip off the island.
var _recovery_jumped: bool = false


func think(player: Player, arena: Node, delta: float) -> InputFrame:
	_tick_cooldowns(delta)
	_swing_time = _swing_time + delta if player.state == Player.State.SWING else 0.0
	_update_stuck(player, delta)

	if Net.mode == GameConfig.Mode.SLAP:
		var recovery := _recover(player)
		if recovery != null:
			return recovery

	var to_target := _aim(player, arena, delta) - player.global_position

	var frame := InputFrame.new()
	frame.move = _steer(player, to_target)
	frame.jump_held = _jump_hold > 0.0
	# Racing bots sprint whenever they are going somewhere, like people do.
	# Racing bots sprint on the long stretches, like people do, and ease off
	# for hops onto something small or lower, where sprinting overshoots.
	frame.sprint_held = Net.mode == GameConfig.Mode.RACE and absf(frame.move.x) > 0.5 		and absf(to_target.x) > 280.0 and to_target.y < 40.0

	if _should_jump(player, to_target):
		frame.press(InputFrame.Action.JUMP)
		# Held for a moment afterwards, because the jump cut in Player means
		# a tapped jump is a short hop and bots need the full arc to clear
		# the gaps the level designer built for a full arc.
		_jump_hold = 0.24
		frame.jump_held = true
	elif player.state == Player.State.SWING:
		# The grab button is the grip: keep holding until it is time to let go.
		frame.grab_held = not _should_release(player, to_target)
		if not frame.grab_held and not player.swing_on_trunk:
			_left_vine = player.get(&"_swing_node") as Node2D
			_no_grab_time = 0.6
	elif not player.is_on_floor() and _wants_grab(player, to_target):
		frame.grab_held = true

	var victim := _nearest_opponent(player, arena)
	if victim != null and _attack_cooldown <= 0.0:
		var offset := victim.global_position - player.global_position
		if offset.length() < ATTACK_RANGE and signf(offset.x) == signf(float(player.facing)):
			# In a race the route comes first: a bot that stops to trade
			# slaps at every ledge never finishes, and neither does anyone
			# it is trading with. Everywhere else, slapping is the point.
			if Net.mode != GameConfig.Mode.RACE or randf() < 0.3:
				frame.press(InputFrame.Action.ATTACK)
			_attack_cooldown = 0.55 / maxf(skill_level, 0.3)

	if _should_use_skill(player, victim):
		frame.press(InputFrame.Action.SKILL)
		_skill_cooldown = 2.5 / maxf(skill_level, 0.3)

	return frame


## Refreshed on a timer scaled by skill, and held in between. Re-picking
## every tick is what makes a bot feel like a homing missile instead of an
## opponent.
func _aim(player: Player, arena: Node, delta: float) -> Vector2:
	var map := arena.get(&"map") as MapData
	if map != null and player.global_position.y > map.kill_depth:
		# Parked below the world waiting to respawn. Deciding anything from
		# down here re-places the bot at the start of the route.
		return _target
	if Net.mode == GameConfig.Mode.RACE:
		# The route is a plan, not a reaction: re-read it every frame, or a
		# bot launched off a spring still steers for the spring.
		_target = _pick_target(player, arena)
		_has_target = true
		return _target
	_think_timer -= delta
	if _think_timer <= 0.0 or not _has_target:
		_target = _pick_target(player, arena)
		_has_target = true
		_think_timer = clampf(0.18 / maxf(skill_level, 0.25), 0.04, 0.9)
	return _target


func _tick_cooldowns(delta: float) -> void:
	_jump_hold = maxf(_jump_hold - delta, 0.0)
	_no_grab_time = maxf(_no_grab_time - delta, 0.0)
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_skill_cooldown = maxf(_skill_cooldown - delta, 0.0)


func _update_stuck(player: Player, delta: float) -> void:
	# Distance, not x: a bot climbing straight up a trunk is not stuck.
	var moved := player.global_position.distance_to(_last_position) >= 1.0
	_last_position = player.global_position
	if _unstick_time > 0.0:
		_unstick_time -= delta
		if _unstick_time <= 0.0:
			# The detour is over; go back to the plan and judge afresh.
			_unstick_dir = 0.0
			_stuck_time = 0.0
		return
	if moved or player.state == Player.State.SWING:
		_stuck_time = 0.0
		return
	_stuck_time += delta
	if _stuck_time > 0.9:
		# Commit to one direction for a while instead of re-deciding every
		# frame, which is how a bot ends up vibrating against a wall - but
		# only for a while, or the detour becomes the new wall.
		_unstick_dir = -signf(float(player.facing))
		_unstick_time = 0.7


# --- Targets -------------------------------------------------------

func _pick_target(player: Player, arena: Node) -> Vector2:
	match Net.mode:
		GameConfig.Mode.HOARD:
			return _hoard_target(player, arena)
		GameConfig.Mode.RACE:
			return _race_target(player, arena)
		GameConfig.Mode.SLAP:
			var enemy := _nearest_opponent(player, arena, INF)
			return enemy.global_position if enemy != null else Vector2(0.0, player.global_position.y)
	return _free_play_target(player, arena)


var _pads: Array = []


func _race_target(player: Player, arena: Node) -> Vector2:
	if _pads.is_empty():
		_pads = player.get_tree().get_nodes_in_group(&"bounce_pad")
	var map := arena.get(&"map") as MapData
	if map == null:
		return player.global_position + Vector2(400.0, 0.0)
	var route := map.route_points()
	_passing_through = false
	if not route.is_empty():
		_follow_route(player.global_position, route, player.is_on_floor())
		if _route_index < route.size():
			_passing_through = _route_index < route.size() - 1
			return route[_route_index]
	var finish := map.finish_line()
	if finish != null:
		return finish.global_position + Vector2(0.0, 40.0)
	return player.global_position + map.progress_axis.normalized() * 600.0


## Walks the route forward past every point already reached. A bot that is
## far from where it thought it was - just spawned, just respawned, knocked
## off a ledge - re-places itself on the nearest point instead.
func _follow_route(here: Vector2, route: PackedVector2Array, grounded: bool) -> void:
	var lost := _route_index < 0
	if not lost and _route_index < route.size():
		var target := route[_route_index]
		# Far away, or standing well below a point a jump cannot reach:
		# knocked off, respawned, or never got there. Find a real foothold.
		lost = here.distance_to(target) > 600.0 or (grounded and here.y - target.y > 130.0) 			or (grounded and target.y - here.y > 220.0)
	if lost:
		_route_index = _nearest_reachable(here, route)
	while _route_index < route.size() and (_reached(here, route[_route_index]) or _launched_past(here, route[_route_index])):
		_route_index += 1


## The furthest-along route point that is close and not above jump height,
## so a bot knocked to the floor restarts at the first ledge it can reach,
## and one standing on a ledge never walks back to the point below it.
func _nearest_reachable(here: Vector2, route: PackedVector2Array) -> int:
	var best := -1
	for i in route.size():
		if route[i].y < here.y - 110.0:
			continue
		if here.distance_to(route[i]) < 700.0:
			best = i
	if best >= 0:
		return best
	# Nothing close: the nearest point that is not out of reach overhead,
	# and only if there is none of those, the nearest point at all.
	var best_dist := INF
	for pass_index in 2:
		for i in route.size():
			if pass_index == 0 and route[i].y < here.y - 110.0:
				continue
			var dist := here.distance_squared_to(route[i])
			if dist < best_dist:
				best_dist = dist
				best = i
		if best >= 0:
			return best
	return 0


## A route point on a spring is passed the moment the spring throws you:
## by the time you are back near it you are coming down on it again.
func _launched_past(here: Vector2, point: Vector2) -> bool:
	if here.y > point.y - 60.0 or absf(here.x - point.x) > 140.0:
		return false
	for node in _pads:
		if (node as Node2D).global_position.distance_to(point + Vector2(0.0, 36.0)) < 40.0:
			return true
	return false


func _reached(here: Vector2, point: Vector2) -> bool:
	return absf(here.x - point.x) < 48.0 and absf(here.y - point.y) < 72.0


func _hoard_target(player: Player, arena: Node) -> Vector2:
	var best: Vector2 = player.global_position
	var best_dist := INF
	for node in player.get_tree().get_nodes_in_group(&"pickup"):
		var pickup := node as Node2D
		if pickup == null:
			continue
		var dist := player.global_position.distance_squared_to(pickup.global_position)
		if dist < best_dist:
			best_dist = dist
			best = pickup.global_position
	if best_dist < INF:
		return best
	# Nothing on the map: go bully whoever is carrying the most.
	var richest := _richest_opponent(player, arena)
	return richest.global_position if richest != null else player.global_position


func _free_play_target(player: Player, arena: Node) -> Vector2:
	var victim := _nearest_opponent(player, arena)
	return victim.global_position if victim != null else player.global_position


# --- Steering ------------------------------------------------------

func _steer(player: Player, to_target: Vector2) -> Vector2:
	var move := Vector2.ZERO
	move.x = clampf(to_target.x / 90.0, -1.0, 1.0)
	if _passing_through and absf(to_target.x) > 6.0:
		move.x = signf(to_target.x)
	if _unstick_dir != 0.0:
		move.x = _unstick_dir

	if player.state == Player.State.SWING and player.swing_on_trunk:
		# Hanging off a trunk by the arm: haul in, then lean toward the
		# target for the hop that letting go turns into.
		move.y = -1.0 if to_target.y < -30.0 else 0.0
		move.x = 0.0
		if _pulled_in(player):
			# Still well below the target: lean into the trunk, which turns
			# the release hop straight up. Nearly level: lean at the target.
			var trunk := player.get(&"_swing_node") as Node2D
			var toward_trunk := signf(trunk.global_position.x - player.global_position.x) if trunk != null else 0.0
			move.x = toward_trunk if to_target.y < -60.0 else signf(to_target.x)
	elif player.state == Player.State.SWING:
		move.y = 0.0
		move.x = _pump(player, to_target)
	if Net.mode == GameConfig.Mode.SLAP and player.is_on_floor() and absf(move.x) > 0.1:
		# On an island the edge is the enemy's best friend. Stop at it.
		var edge := player.global_position + Vector2(signf(move.x) * GAP_PROBE, 0.0)
		if not _ray(player, edge, edge + Vector2(0.0, GAP_DEPTH)):
			move.x = 0.0
	return move.limit_length(1.0)


## Push with the swing, never against it. A constant push toward the target
## just props the monkey at an angle - an equilibrium, not a swing - so a
## bot at rest pushes only when hanging straight down, and otherwise lets
## gravity start the arc and then feeds it.
func _pump(player: Player, to_target: Vector2) -> float:
	if absf(player.velocity.x) > 30.0:
		return signf(player.velocity.x)
	var anchor: Vector2 = player.get(&"_swing_anchor")
	if absf(player.global_position.x - anchor.x) > 20.0:
		return 0.0
	return signf(to_target.x) if absf(to_target.x) > 1.0 else 1.0


func _should_jump(player: Player, to_target: Vector2) -> bool:
	if _jump_hold > 0.0:
		return false
	if not player.is_on_floor():
		return false
	# A spring only fires for a monkey landing on it or walking over it. A
	# bot that jumps on the way sails over the one thing that would lift it.
	if _near_pad(player):
		return false
	if _stuck_time > 0.6:
		return true
	# Up to a higher ledge: jump from close in, not from way back, or the
	# heavy monkeys run out of arc before they reach it. Never straight into
	# a ceiling, though: that is a bonk, and a bot that bonks keeps bonking.
	var reach := 60.0 + player.stats.run_speed() * 0.22
	if to_target.y < -70.0 and absf(to_target.x) < reach and not _ceiling(player):
		return true
	if _wall_ahead(player):
		return true
	# A gap is only worth jumping when the target is across it. When the
	# target is down in it - a stepping stone, a lower ledge - walking off
	# the edge is the move, and a full jump overshoots.
	# Jumping a gap only makes sense when the target is not below: a lower
	# target means drop down to it, and a full jump sails past.
	if _gap_ahead(player):
		if Net.mode == GameConfig.Mode.SLAP:
			return false
		return to_target.y < 40.0 or absf(to_target.x) > 170.0
	return false


## When to let go of the grip. On a vine: target below, drop to it;
## otherwise on the forward arc, which is where a release turns into
## distance. On a trunk: once hauled in, so the release is a pull-up hop.
## And never hang on for more than a few seconds, whatever is below.
func _should_release(player: Player, to_target: Vector2) -> bool:
	if _swing_time > 4.0:
		return true
	if player.swing_on_trunk:
		if to_target.y < -30.0:
			return _pulled_in(player)
		return true
	if _drop_to(player, to_target):
		return true
	return player.velocity.x * signf(to_target.x) > 260.0


## The target is under the vine: let go and fall onto it. A target below
## but well off to the side is swung toward instead - dropping straight
## down there lands in the gap between.
func _drop_to(player: Player, to_target: Vector2) -> bool:
	return to_target.y > 70.0 and absf(to_target.x) < 120.0 		and _ray(player, player.global_position, player.global_position + Vector2(0.0, 500.0))


## Grabbing is the grab button held in the air. A bot holds it when there is
## a vine in reach, or when the target is above and a trunk is how to get there.
## Holding for every whole flight would grab each pillar it passes.
func _wants_grab(player: Player, to_target: Vector2) -> bool:
	for area in player.vine_sensor.get_overlapping_areas():
		# A vine it would only drop straight off again is not worth taking.
		if _drop_to(player, to_target):
			break
		if _no_grab_time <= 0.0 or area != _left_vine:
			return true
	return to_target.y < -40.0 and _no_grab_time <= 0.0


func _pulled_in(player: Player) -> bool:
	return float(player.get(&"_swing_length")) <= player.swing_min_length + 6.0


## Knocked off the island: head for the middle, and spend the double jump
## on the way back up. Returns null while there is ground below to land on.
func _recover(player: Player) -> InputFrame:
	if player.is_on_floor() or player.state == Player.State.SWING:
		_recovery_jumped = false
		return null
	if _ray(player, player.global_position, player.global_position + Vector2(0.0, 900.0)):
		return null
	var frame := InputFrame.new()
	var home := Vector2(-signf(player.global_position.x), -0.8).normalized()
	frame.move = home
	frame.sprint_held = true
	# Held, so the double jump rises its full height, and grab held so it
	# takes any trunk, ledge or vine it reaches on the way back.
	frame.jump_held = true
	frame.grab_held = true
	if not _recovery_jumped and player.velocity.y > -100.0:
		frame.press(InputFrame.Action.JUMP)
		_recovery_jumped = true
	return frame


## Only solid rock is a ceiling: a one-way platform overhead is jumped
## straight through.
func _ceiling(player: Player) -> bool:
	var head := player.global_position + Vector2(0.0, -30.0)
	return _ray(player, head, head + Vector2(0.0, -110.0), GameConfig.LAYER_WORLD)


func _near_pad(player: Player) -> bool:
	for node in player.get_tree().get_nodes_in_group(&"bounce_pad"):
		var offset := (node as Node2D).global_position - player.global_position
		if absf(offset.x) < 110.0 and offset.y > -20.0 and offset.y < 90.0:
			return true
	return false


func _should_use_skill(player: Player, victim: Player) -> bool:
	if _skill_cooldown > 0.0 or player.skill_timer > 0.0:
		return false
	if _stuck_time > 1.2:
		return true
	if victim == null:
		return false
	return player.global_position.distance_to(victim.global_position) < AGGRO_RANGE


# --- World probes --------------------------------------------------

func _wall_ahead(player: Player) -> bool:
	var ahead := Vector2(float(player.facing) * WALL_PROBE, 0.0)
	return _ray(player, player.global_position, player.global_position + ahead)


func _gap_ahead(player: Player) -> bool:
	var edge := player.global_position + Vector2(float(player.facing) * GAP_PROBE, 0.0)
	return not _ray(player, edge, edge + Vector2(0.0, GAP_DEPTH))


## Ground probes see platforms too, so a ledge is not mistaken for a gap.
func _ray(player: Player, from: Vector2, to: Vector2, mask: int = GameConfig.LAYER_SOLID) -> bool:
	var space := player.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to, mask, [player.get_rid()])
	return not space.intersect_ray(query).is_empty()


# --- Opponents -----------------------------------------------------

func _opponents(player: Player, arena: Node) -> Array:
	var table: Variant = arena.get(&"players")
	if not (table is Dictionary):
		return []
	var out: Array = []
	for id in (table as Dictionary).keys():
		var other := (table as Dictionary)[id] as Player
		if other == null or other == player or other.is_ghost():
			continue
		# Teammates are not opponents. Outside 2v2 everyone has team -1.
		if player.team >= 0 and other.team == player.team:
			continue
		out.append(other)
	return out


func _nearest_opponent(player: Player, arena: Node, reach: float = AGGRO_RANGE) -> Player:
	var best: Player = null
	var best_dist := reach * reach
	for other in _opponents(player, arena):
		var candidate := other as Player
		var dist := player.global_position.distance_squared_to(candidate.global_position)
		if dist < best_dist:
			best_dist = dist
			best = candidate
	return best


func _richest_opponent(player: Player, arena: Node) -> Player:
	var best: Player = null
	var best_score := 0
	for other in _opponents(player, arena):
		var candidate := other as Player
		if candidate.bananas > best_score:
			best_score = candidate.bananas
			best = candidate
	return best
