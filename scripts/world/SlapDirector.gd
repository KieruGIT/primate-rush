class_name SlapDirector
extends Node

# ============================================================
# 2v2 SLAP - two teams, rounds, one life each per round.
#
# Everyone starts a round on the island. Leaving it (into the water, or
# off either side past the blast line) knocks that monkey out of the round:
# it watches its teammate until the round ends. A team is beaten when both
# of its monkeys are out, so a lone survivor can still win it 1v2.
#
# First team to SLAP_ROUNDS_TO_WIN rounds wins the match (best of three).
# A round that runs out of time goes to the team with more monkeys
# standing; if that is level, to the team that has taken less damage.
#
# Host authoritative, replicated like the hoard: the host decides who went
# in, who won the round and what the score is, and every machine shows it.
# ============================================================

signal countdown_changed(value: int)
signal slap_began
signal scores_changed(scores: Array)
signal time_changed(seconds_left: float)
signal slap_over(results: Array)
## A monkey is out for the rest of this round.
signal player_out(player_id: int)
## A round is decided: the winning team (-1 for a draw) and the new score.
signal round_won(team: int, scores: Array)
## Everyone goes back on the island for the next round.
signal round_reset(round_number: int)

enum Phase { IDLE, COUNTDOWN, RUNNING, ROUND_END, OVER }

@export var countdown_seconds: float = 3.0
## The pause on the round result before everyone is put back.
@export var round_end_seconds: float = 2.5

var phase: int = Phase.IDLE
var time_left: float = 0.0
## Rounds won by each team, index is the team.
var scores: Array[int] = [0, 0]
var round_number: int = 1
## Monkeys knocked out of the current round, by player id.
var out: Dictionary = {}

var _arena: Node = null
var _countdown_left: float = 0.0
var _round_end_left: float = 0.0
var _last_announced: int = -1
var _time_broadcast: float = 0.0


func _ready() -> void:
	add_to_group(&"slap_director")


func setup(arena: Node) -> void:
	_arena = arena


func begin() -> void:
	scores = [0, 0]
	round_number = 1
	_start_countdown()


func _start_countdown() -> void:
	phase = Phase.COUNTDOWN
	_countdown_left = countdown_seconds
	_last_announced = -1
	time_left = GameConfig.SLAP_ROUND_SECONDS
	out.clear()


func is_input_locked() -> bool:
	return phase == Phase.COUNTDOWN or phase == Phase.ROUND_END


func is_running() -> bool:
	return phase == Phase.RUNNING


func is_out(player_id: int) -> bool:
	return out.has(player_id)


## Called by the arena when a monkey leaves the island. Host only.
func player_fell(player_id: int) -> void:
	if not _is_authority():
		return
	if phase != Phase.RUNNING and phase != Phase.ROUND_END:
		return
	var player := _player(player_id)
	if player == null or player.team < 0 or out.has(player_id):
		return
	_send(&"out", [player_id])
	if phase != Phase.RUNNING:
		return
	var standing := _standing()
	if standing[0] == 0 or standing[1] == 0:
		# Both gone on the same frame is a draw; otherwise the team with
		# someone left takes the round.
		var winner := -1
		if standing[0] > 0:
			winner = 0
		elif standing[1] > 0:
			winner = 1
		_end_round(winner)


## Monkeys still in the round, per team.
func _standing() -> Array[int]:
	var count: Array[int] = [0, 0]
	for id in _player_ids():
		var player := _player(int(id))
		if player == null or player.team < 0 or out.has(int(id)):
			continue
		count[player.team] += 1
	return count


func _end_round(winner: int) -> void:
	var next := scores.duplicate()
	if winner >= 0:
		next[winner] += 1
	_send(&"round", [winner, next])
	if winner >= 0 and next[winner] >= GameConfig.SLAP_ROUNDS_TO_WIN:
		_send(&"over", [results()])


## When the clock runs out: more monkeys standing wins; level on that,
## less damage taken wins; level on both, nobody scores and it is replayed.
func _time_up_winner() -> int:
	var standing := _standing()
	if standing[0] != standing[1]:
		return 0 if standing[0] > standing[1] else 1
	var damage: Array[float] = [0.0, 0.0]
	for id in _player_ids():
		var player := _player(int(id))
		if player == null or player.team < 0 or out.has(int(id)):
			continue
		damage[player.team] += player.slap_damage
	if absf(damage[0] - damage[1]) < 1.0:
		return -1
	return 0 if damage[0] < damage[1] else 1


## One row per monkey, winners first. Each row carries its team and the
## team's round wins, so the results screen can say who won as a team.
func results() -> Array:
	var winner := 0 if scores[0] >= scores[1] else 1
	var draw := scores[0] == scores[1]
	var rows: Array = []
	for id in _player_ids():
		var player := _player(int(id))
		var team := player.team if player != null else 0
		rows.append({"id": int(id), "team": team, "score": scores[team], "won": not draw and team == winner, "draw": draw})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]))
	return rows


func _process(delta: float) -> void:
	if not _is_authority():
		return
	match phase:
		Phase.COUNTDOWN:
			_countdown_left -= delta
			var shown := int(ceil(maxf(_countdown_left, 0.0)))
			if shown != _last_announced:
				_last_announced = shown
				_send(&"countdown", [shown])
			if _countdown_left <= 0.0:
				_send(&"begin", [])
		Phase.RUNNING:
			time_left = maxf(time_left - delta, 0.0)
			_time_broadcast -= delta
			if _time_broadcast <= 0.0:
				_time_broadcast = 0.5
				_send(&"time", [time_left])
			if time_left <= 0.0:
				_end_round(_time_up_winner())
		Phase.ROUND_END:
			_round_end_left -= delta
			if _round_end_left <= 0.0:
				_send(&"reset", [round_number + 1])
				_start_countdown()


func _is_authority() -> bool:
	return not Net.is_online() or Net.is_host()


func _player_ids() -> Array:
	if _arena == null:
		return []
	var table: Variant = _arena.get(&"players")
	return table.keys() if table is Dictionary else []


func _player(player_id: int) -> Player:
	if _arena == null:
		return null
	var table: Variant = _arena.get(&"players")
	if not (table is Dictionary):
		return null
	return table.get(player_id) as Player


# --- Replication ---------------------------------------------------

func _send(event: StringName, args: Array) -> void:
	var callables := {
		&"countdown": &"_net_countdown",
		&"begin": &"_net_begin",
		&"time": &"_net_time",
		&"out": &"_net_out",
		&"round": &"_net_round",
		&"reset": &"_net_reset",
		&"over": &"_net_over",
	}
	var method: StringName = callables[event]
	if Net.is_online():
		var forwarded: Array = [method]
		forwarded.append_array(args)
		callv(&"rpc", forwarded)
	callv(method, args)


@rpc("authority", "reliable")
func _net_countdown(value: int) -> void:
	phase = Phase.COUNTDOWN
	countdown_changed.emit(value)


@rpc("authority", "reliable")
func _net_begin() -> void:
	phase = Phase.RUNNING
	slap_began.emit()


@rpc("authority", "unreliable_ordered")
func _net_time(seconds: float) -> void:
	time_left = seconds
	time_changed.emit(seconds)


@rpc("authority", "reliable")
func _net_out(player_id: int) -> void:
	out[player_id] = true
	player_out.emit(player_id)


@rpc("authority", "reliable")
func _net_round(winner: int, new_scores: Array) -> void:
	scores = [int(new_scores[0]), int(new_scores[1])]
	phase = Phase.ROUND_END
	_round_end_left = round_end_seconds
	round_won.emit(winner, scores)
	scores_changed.emit(scores)


@rpc("authority", "reliable")
func _net_reset(next_round: int) -> void:
	round_number = next_round
	out.clear()
	round_reset.emit(next_round)


@rpc("authority", "reliable")
func _net_over(payload: Array) -> void:
	if phase == Phase.OVER:
		return
	phase = Phase.OVER
	slap_over.emit(payload)
