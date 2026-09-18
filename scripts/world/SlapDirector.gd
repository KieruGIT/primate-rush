class_name SlapDirector
extends Node

# ============================================================
# 2v2 SLAP - two teams, one small island, slap the others into the sea.
#
# A knock-out is anyone leaving the island for good: into the water, or off
# either side past the blast line. The other team scores it. First team to
# SLAP_TARGET_KOS wins; if the clock runs out first, the higher score wins.
#
# Nobody is eliminated. A monkey that goes in is back on its own side of the
# island a moment later with its damage reset, because sitting out is the
# one thing a party game must never ask of anybody.
#
# Host authoritative, replicated like the hoard: the host decides who went
# in and what the score is, and every machine just shows it.
# ============================================================

signal countdown_changed(value: int)
signal slap_began
signal scores_changed(scores: Array)
signal time_changed(seconds_left: float)
signal slap_over(results: Array)

enum Phase { IDLE, COUNTDOWN, RUNNING, OVER }

@export var countdown_seconds: float = 3.0

var phase: int = Phase.IDLE
var time_left: float = 0.0
## KOs scored by each team, index is the team.
var scores: Array[int] = [0, 0]

var _arena: Node = null
var _countdown_left: float = 0.0
var _last_announced: int = -1
var _time_broadcast: float = 0.0


func _ready() -> void:
	add_to_group(&"slap_director")


func setup(arena: Node) -> void:
	_arena = arena


func begin() -> void:
	phase = Phase.COUNTDOWN
	_countdown_left = countdown_seconds
	_last_announced = -1
	time_left = GameConfig.SLAP_ROUND_SECONDS
	scores = [0, 0]


func is_input_locked() -> bool:
	return phase == Phase.COUNTDOWN


func is_running() -> bool:
	return phase == Phase.RUNNING


## Called by the arena when a monkey leaves the island. Host only.
func player_fell(player_id: int) -> void:
	if not _is_authority() or phase != Phase.RUNNING:
		return
	var player := _player(player_id)
	if player == null or player.team < 0:
		return
	var scorer := 1 - player.team
	scores[scorer] += 1
	_send(&"scores", [scores.duplicate()])
	if scores[scorer] >= GameConfig.SLAP_TARGET_KOS:
		_send(&"over", [results()])


## One row per monkey, winners first. Each row carries its team and the
## team's score, so the results screen can say who won as a team.
func results() -> Array:
	var winner := 0 if scores[0] >= scores[1] else 1
	var draw := scores[0] == scores[1]
	var out: Array = []
	for id in _player_ids():
		var player := _player(int(id))
		var team := player.team if player != null else 0
		out.append({"id": int(id), "team": team, "score": scores[team], "won": not draw and team == winner, "draw": draw})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]))
	return out


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
				_send(&"over", [results()])


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
		&"scores": &"_net_scores",
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
func _net_scores(new_scores: Array) -> void:
	scores = [int(new_scores[0]), int(new_scores[1])]
	scores_changed.emit(scores)


@rpc("authority", "reliable")
func _net_over(payload: Array) -> void:
	if phase == Phase.OVER:
		return
	phase = Phase.OVER
	slap_over.emit(payload)
