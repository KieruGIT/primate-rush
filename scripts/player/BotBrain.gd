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
const ATTACK_RANGE: float = 78.0

## Lower is sloppier. Scales reaction delays rather than movement speed, so
## an easy bot is slow to react, not visibly crippled.
var skill_level: float = 1.0

var _jump_hold: float = 0.0
var _attack_cooldown: float = 0.0
var _skill_cooldown: float = 0.0
var _stuck_time: float = 0.0
var _unstick_dir: float = 0.0
var _last_x: float = 0.0


func think(player: Player, arena: Node, delta: float) -> InputFrame:
	_tick_cooldowns(delta)
	_update_stuck(player, delta)

	var target := _pick_target(player, arena)
	var to_target := target - player.global_position

	var frame := InputFrame.new()
	frame.move = _steer(player, to_target)
	frame.jump_held = _jump_hold > 0.0

	if _should_jump(player, to_target):
		frame.press(InputFrame.Button.JUMP)
		# Held for a moment afterwards, because the jump cut in Player means
		# a tapped jump is a short hop and bots need the full arc to clear
		# the gaps the level designer built for a full arc.
		_jump_hold = 0.24
		frame.jump_held = true

	var victim := _nearest_opponent(player, arena)
	if victim != null and _attack_cooldown <= 0.0:
		var offset := victim.global_position - player.global_position
		if offset.length() < ATTACK_RANGE and signf(offset.x) == signf(float(player.facing)):
			frame.press(InputFrame.Button.ATTACK)
			_attack_cooldown = 0.55 / maxf(skill_level, 0.3)

	if _should_use_skill(player, victim):
		frame.press(InputFrame.Button.SKILL)
		_skill_cooldown = 2.5 / maxf(skill_level, 0.3)

	return frame


func _tick_cooldowns(delta: float) -> void:
	_jump_hold = maxf(_jump_hold - delta, 0.0)
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_skill_cooldown = maxf(_skill_cooldown - delta, 0.0)


func _update_stuck(player: Player, delta: float) -> void:
	if absf(player.global_position.x - _last_x) < 4.0 and player.state != Player.State.SWING:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
		_unstick_dir = 0.0
	_last_x = player.global_position.x
	if _stuck_time > 0.9 and _unstick_dir == 0.0:
		# Commit to one direction for a while instead of re-deciding every
		# frame, which is how a bot ends up vibrating against a wall.
		_unstick_dir = -signf(float(player.facing))


# --- Targets -------------------------------------------------------

func _pick_target(player: Player, arena: Node) -> Vector2:
	match Net.mode:
		GameConfig.Mode.HOARD:
			return _hoard_target(player, arena)
		GameConfig.Mode.RACE:
			return _race_target(player, arena)
	return _free_play_target(player, arena)


func _race_target(player: Player, arena: Node) -> Vector2:
	var map := arena.get(&"map") as MapData
	if map == null:
		return player.global_position + Vector2(400.0, 0.0)
	var finish := map.finish_line()
	if finish != null:
		return finish.global_position
	return player.global_position + map.progress_axis.normalized() * 600.0


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
	if _unstick_dir != 0.0:
		move.x = _unstick_dir

	# Vertical intent drives climbing and rope length, both of which are
	# contextual in Player. The bot just says "up" and lets the monkey
	# decide whether that means a wall or a vine.
	if to_target.y < -60.0:
		move.y = -1.0
	elif to_target.y > 120.0 and player.state == Player.State.SWING:
		move.y = 1.0

	# Pump the swing in the direction of travel instead of toward the target,
	# or a bot on a vine fights its own pendulum and hangs there.
	if player.state == Player.State.SWING and absf(player.velocity.x) > 40.0:
		move.x = signf(player.velocity.x)
	return move.limit_length(1.0)


func _should_jump(player: Player, to_target: Vector2) -> bool:
	if _jump_hold > 0.0:
		return false
	if player.state == Player.State.SWING:
		# Release at the top of the forward arc, which is where a release
		# actually converts the swing into distance.
		return player.velocity.x * signf(to_target.x) > 260.0
	if not player.is_on_floor():
		return false
	if _stuck_time > 0.6:
		return true
	if to_target.y < -70.0 and absf(to_target.x) < 260.0:
		return true
	return _wall_ahead(player) or _gap_ahead(player)


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


func _ray(player: Player, from: Vector2, to: Vector2) -> bool:
	var space := player.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to, GameConfig.LAYER_WORLD, [player.get_rid()])
	return not space.intersect_ray(query).is_empty()


# --- Opponents -----------------------------------------------------

func _opponents(player: Player, arena: Node) -> Array:
	var table: Variant = arena.get(&"players")
	if not (table is Dictionary):
		return []
	var out: Array = []
	for id in (table as Dictionary).keys():
		var other := (table as Dictionary)[id] as Player
		if other != null and other != player and not other.is_ghost():
			out.append(other)
	return out


func _nearest_opponent(player: Player, arena: Node) -> Player:
	var best: Player = null
	var best_dist := AGGRO_RANGE * AGGRO_RANGE
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
