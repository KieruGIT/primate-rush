extends Node

# ============================================================
# NET SMOKE - a real host and a real client, two processes, localhost.
#
#   godot --headless --fixed-fps 60 res://tools/NetSmoke.tscn -- host
#   godot --headless --fixed-fps 60 res://tools/NetSmoke.tscn -- client
#
# Networking is the part of this project that static checks cannot touch at
# all: it only exists once two machines disagree. The host fills the match
# with bots so there is real movement to replicate, and the client asserts
# that it sees four monkeys and that they move - which is only true if the
# roster, the spawn path and the snapshot stream all work.
# ============================================================

const ARENA := preload("res://scenes/Main.tscn")
const SETTLE_TICKS: int = 90
const RUN_TICKS: int = 420
const TIMEOUT_TICKS: int = 1800

var _role: String = "host"
var _arena: Node = null
var _ticks: int = 0
var _run_ticks: int = 0
var _started: bool = false
var _first_positions: Dictionary = {}
var _failures: Array[String] = []


func _ready() -> void:
	_role = "client" if OS.get_cmdline_user_args().has("client") else "host"
	Net.match_started.connect(_on_match_started)
	Net.connection_failed.connect(func() -> void: _fail("connection refused"))

	if _role == "host":
		var error := Net.host_game()
		if not error.is_empty():
			_fail(error)
			return
		Net.local_monkey = &"gorilla"
		Net.set_match_config(&"map_a", GameConfig.Mode.RACE)
		Net.set_bot_count(2)
		print("host: listening on %d" % GameConfig.NET_DEFAULT_PORT)
	else:
		Net.local_monkey = &"capuchin"
		var error := Net.join_game("127.0.0.1")
		if not error.is_empty():
			_fail(error)
			return
		print("client: connecting")


func _physics_process(_delta: float) -> void:
	_ticks += 1
	if _ticks > TIMEOUT_TICKS:
		_fail("timed out after %d ticks (started=%s)" % [TIMEOUT_TICKS, _started])
		_report()
		return

	# The host waits for the client to register before starting, so the
	# roster the arena spawns from already has both people in it.
	if _role == "host" and not _started and _ticks > SETTLE_TICKS:
		if Net.roster.size() >= 2:
			print("host: roster %d, starting" % Net.roster.size())
			Net.start_match()
		elif _ticks > SETTLE_TICKS * 6:
			_fail("client never registered, roster is %d" % Net.roster.size())
			_report()
		return

	if _arena == null:
		return
	_run_ticks += 1
	if _run_ticks == 1:
		_snapshot_positions()
	if _run_ticks >= RUN_TICKS:
		_check()
		_report()


func _on_match_started() -> void:
	_started = true
	_arena = ARENA.instantiate()
	add_child(_arena)
	print("%s: arena up" % _role)


func _snapshot_positions() -> void:
	var players: Dictionary = _arena.get("players")
	for id in players.keys():
		_first_positions[id] = (players[id] as Node2D).global_position


func _check() -> void:
	var players: Dictionary = _arena.get("players")
	# Host, client and two bots. A client that sees fewer has a roster or a
	# spawn problem; one that sees more is spawning ghosts from snapshots.
	if players.size() != 4:
		_fail("%s sees %d monkeys, expected 4" % [_role, players.size()])

	var moved := 0
	for id in players.keys():
		var before: Vector2 = _first_positions.get(id, Vector2.ZERO)
		if (players[id] as Node2D).global_position.distance_to(before) > 24.0:
			moved += 1
	# On the client this is the real assertion: nothing here simulates other
	# monkeys, so if they moved, host snapshots are arriving and applying.
	if moved == 0:
		_fail("%s saw nobody move in %d ticks" % [_role, RUN_TICKS])
	print("%s: %d monkeys, %d moved" % [_role, players.size(), moved])


func _fail(reason: String) -> void:
	_failures.append(reason)


func _report() -> void:
	if _failures.is_empty():
		print("NET SMOKE OK (%s)" % _role)
		get_tree().quit(0)
		return
	for failure in _failures:
		print("NET SMOKE FAIL (%s): %s" % [_role, failure])
	get_tree().quit(1)
