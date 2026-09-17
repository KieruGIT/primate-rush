class_name RaceDirector
extends Node

# ============================================================
# RACE DIRECTOR - countdown, progress, placement.
#
# One director serves both maps. Progress is a dot product against the map's
# progress axis, so a left-to-right run and a bottom-to-top ascent are the
# same code with a different vector.
#
# Host authoritative throughout. A client that decided its own placement
# would be the single most rewarding thing in the game to cheat at.
# ============================================================

signal countdown_changed(value: int)
signal race_began
signal player_finished(player_id: int, place: int, seconds: float)
signal race_over(results: Array)

enum Phase { IDLE, COUNTDOWN, RUNNING, OVER }

## Long enough to read "3, 2, 1" and settle a thumb on the stick.
@export var countdown_seconds: float = 3.0
## After the first monkey finishes, everyone else gets this long before the
## results come up. Without it, one player who fell into a pit holds the
## whole lobby hostage.
@export var grace_seconds: float = 25.0

var phase: int = Phase.IDLE
var elapsed: float = 0.0

var _map: MapData = null
var _arena: Node = null
var _countdown_left: float = 0.0
var _last_announced: int = -1
var _finish_order: Array[int] = []
var _finish_times: Dictionary = {}
var _grace_left: float = -1.0


func setup(arena: Node, map: MapData) -> void:
	_arena = arena
	_map = map
	if map == null:
		# A map that failed to load is a bad build, not a bad race. Stay idle
		# rather than taking the whole match down with a null dereference.
		push_error("Race director has no map. Staying idle.")
		return
	var finish := map.finish_line()
	if finish != null and finish is FinishLine:
		(finish as FinishLine).crossed.connect(_on_finish_crossed)
	elif Net.mode == GameConfig.Mode.RACE:
		push_warning("Race on a map with no finish line: %s" % map.display_name)


func begin() -> void:
	phase = Phase.COUNTDOWN
	_countdown_left = countdown_seconds
	_last_announced = -1
	elapsed = 0.0
	_finish_order.clear()
	_finish_times.clear()
	_grace_left = -1.0


## Monkeys are frozen through the countdown. Letting people creep forward
## before GO turns the start of every race into a false-start argument.
func is_input_locked() -> bool:
	return phase == Phase.COUNTDOWN


func is_running() -> bool:
	return phase == Phase.RUNNING


func results() -> Array:
	var out: Array = []
	for id in _finish_order:
		out.append({"id": id, "time": float(_finish_times.get(id, 0.0)), "finished": true})
	# Everyone who did not finish is ranked by how far along they got, which
	# gives a last-place player a real placement instead of a blank.
	var unfinished: Array = []
	for id in _player_ids():
		if _finish_order.has(id):
			continue
		unfinished.append({"id": id, "time": 0.0, "finished": false, "progress": progress_of(id)})
	unfinished.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["progress"] > b["progress"])
	out.append_array(unfinished)
	return out


func progress_of(player_id: int) -> float:
	if _map == null or _arena == null:
		return 0.0
	var table: Variant = _arena.get(&"players")
	if not (table is Dictionary):
		return 0.0
	var player := table.get(player_id) as Player
	if player == null:
		return 0.0
	return _map.progress_of(player.global_position)


func _process(delta: float) -> void:
	if not _is_authority():
		return
	match phase:
		Phase.COUNTDOWN:
			_tick_countdown(delta)
		Phase.RUNNING:
			_tick_running(delta)
		_:
			pass


func _is_authority() -> bool:
	return not Net.is_online() or Net.is_host()


func _tick_countdown(delta: float) -> void:
	_countdown_left -= delta
	var shown := int(ceil(maxf(_countdown_left, 0.0)))
	if shown != _last_announced:
		_last_announced = shown
		_broadcast_countdown(shown)
	if _countdown_left <= 0.0:
		_broadcast_begin()


func _tick_running(delta: float) -> void:
	elapsed += delta
	if _grace_left > 0.0:
		_grace_left -= delta
		if _grace_left <= 0.0:
			_broadcast_over()
			return
	if not _finish_order.is_empty() and _finish_order.size() >= _player_ids().size():
		_broadcast_over()


func _player_ids() -> Array:
	if _arena == null:
		return []
	var table: Variant = _arena.get(&"players")
	return table.keys() if table is Dictionary else []


func _on_finish_crossed(player_id: int) -> void:
	if not _is_authority() or phase != Phase.RUNNING or _finish_order.has(player_id):
		return
	_finish_order.append(player_id)
	_finish_times[player_id] = elapsed
	if _finish_order.size() == 1:
		_grace_left = grace_seconds
	_broadcast_finish(player_id, _finish_order.size(), elapsed)


# --- Replication ---------------------------------------------------
# Every phase change goes out reliably. A dropped "GO" would leave a client
# frozen for the whole race, which is worse than any amount of drift.

func _broadcast_countdown(value: int) -> void:
	if Net.is_online():
		_net_countdown.rpc(value)
	_net_countdown(value)


@rpc("authority", "reliable")
func _net_countdown(value: int) -> void:
	phase = Phase.COUNTDOWN
	countdown_changed.emit(value)


func _broadcast_begin() -> void:
	if Net.is_online():
		_net_begin.rpc()
	_net_begin()


@rpc("authority", "reliable")
func _net_begin() -> void:
	phase = Phase.RUNNING
	elapsed = 0.0
	race_began.emit()


func _broadcast_finish(player_id: int, place: int, seconds: float) -> void:
	if Net.is_online():
		_net_finish.rpc(player_id, place, seconds)
	_net_finish(player_id, place, seconds)


@rpc("authority", "reliable")
func _net_finish(player_id: int, place: int, seconds: float) -> void:
	if not _finish_order.has(player_id):
		_finish_order.append(player_id)
	_finish_times[player_id] = seconds
	player_finished.emit(player_id, place, seconds)


func _broadcast_over() -> void:
	var payload := results()
	if Net.is_online():
		_net_over.rpc(payload)
	_net_over(payload)


@rpc("authority", "reliable")
func _net_over(payload: Array) -> void:
	phase = Phase.OVER
	race_over.emit(payload)
