extends Node

# ============================================================
# BOT RACE - dev only. Four bots race a map headless; prints who finished,
# how long it took, how often they fell, and where the stragglers stalled.
#
#   godot --headless --fixed-fps 60 res://tools/BotRace.tscn -- --map=map_a
#       [--seconds=180] [--skill=1] [--cast=gorilla,capuchin,...]
#
# A level is only finished when the AI can finish it: a solo race against
# three bots stuck on the second ledge is not a race. This is the check
# that makes "bigger maps" safe to build, and it runs in seconds because
# headless with a fixed step never waits for the clock.
# ============================================================

const ARENA := preload("res://scenes/Main.tscn")

var _map: StringName = &"map_a"
var _limit_seconds: float = 180.0
var _cast: Array[StringName] = [&"gorilla", &"orangutan", &"macaque", &"capuchin"]
var _arena: Node = null
var _elapsed: float = 0.0
var _finished: Dictionary = {}      # id -> seconds
var _best: Dictionary = {}          # id -> best progress
var _falls: Dictionary = {}         # id -> count
var _was_low: Dictionary = {}
var _trail: Dictionary = {}         # id -> Array of [time, position]
var _done: bool = false
var _slap: bool = false


var _lines: PackedStringArray = []


func _say(line: Variant) -> void:
	print(line)
	_lines.append(str(line))
	preload("res://tools/qa_log.gd").write("bot_race_%s" % _map, _lines)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var skill := GameConfig.BotSkill.NORMAL
	var arguments := OS.get_cmdline_user_args()
	# Launched without arguments (from an editor or a remote runner), read
	# them from output/qa/bot_race_args.txt instead, one line, space separated.
	if arguments.is_empty() and FileAccess.file_exists("res://output/qa/bot_race_args.txt"):
		arguments = FileAccess.get_file_as_string("res://output/qa/bot_race_args.txt").strip_edges().split(" ", false)
	for argument in arguments:
		if argument.begins_with("--map="):
			_map = StringName(argument.trim_prefix("--map="))
		elif argument.begins_with("--seconds="):
			_limit_seconds = float(argument.trim_prefix("--seconds="))
		elif argument.begins_with("--skill="):
			skill = int(argument.trim_prefix("--skill="))
		elif argument == "--slap":
			_slap = true
		elif argument.begins_with("--cast="):
			_cast.clear()
			for id in argument.trim_prefix("--cast=").split(","):
				_cast.append(StringName(id))

	Net.leave()
	Net.map_id = _map
	Net.mode = GameConfig.Mode.SLAP if _slap else GameConfig.Mode.RACE
	if _slap:
		_map = &"map_c"
		Net.map_id = _map
	Net.bot_skill = skill
	Net.roster.clear()
	for i in _cast.size():
		Net.roster[-(i + 1)] = {"monkey": _cast[i], "hat": &"none", "slot": i, "bot": true, "name": String(_cast[i])}
	_arena = ARENA.instantiate()
	add_child(_arena)
	if _slap:
		var slap: SlapDirector = _arena.get(&"slap")
		slap.scores_changed.connect(func(scores: Array) -> void:
			_say("  KO!  %s %d - %d %s   at %.1fs" % [GameConfig.TEAM_NAMES[0], scores[0], scores[1], GameConfig.TEAM_NAMES[1], _elapsed])
			var table: Dictionary = _arena.get(&"players")
			for id in table.keys():
				var p := table[id] as Player
				_say("      %-10s team %d  at %s  v %s  %s  dmg %d" % [_name(id), p.team, p.global_position.round(), p.velocity.round(), Player.State.keys()[p.state], int(p.slap_damage)]))
		slap.slap_over.connect(func(results: Array) -> void:
			_say("SLAP OVER at %.0fs: %s" % [_elapsed, results])
			_done = true
			get_tree().quit(0))
		_say("slap: %s" % ", ".join(_cast))
		return
	var race: RaceDirector = _arena.get(&"race")
	# Nobody gets cut off by the grace timer: the question is whether each
	# bot can finish at all, not whether it beat the leader by enough.
	race.set(&"grace_seconds", 100000.0)
	race.player_finished.connect(_on_finished)
	_say("bot race: %s, %s, %.0fs limit" % [_map, ", ".join(_cast), _limit_seconds])


func _on_finished(player_id: int, place: int, seconds: float) -> void:
	_finished[player_id] = seconds
	_say("  finished  %-10s  place %d  %6.1fs" % [_name(player_id), place, seconds])


func _physics_process(delta: float) -> void:
	if _done or _arena == null:
		return
	_elapsed += delta
	var players: Dictionary = _arena.get(&"players")
	var map: MapData = _arena.get(&"map")
	for id in players.keys():
		var player := players[id] as Player
		var low := player.global_position.y > map.kill_depth
		if low and not bool(_was_low.get(id, false)):
			_falls[id] = int(_falls.get(id, 0)) + 1
		_was_low[id] = low
		if not low:
			_best[id] = maxf(float(_best.get(id, -INF)), map.progress_of(player.global_position))
		if int(_elapsed * 60.0) % 120 == 0:
			if not _trail.has(id):
				_trail[id] = []
			(_trail[id] as Array).append([_elapsed, player.global_position.round()])
	if _slap:
		if _elapsed >= _limit_seconds + 10.0:
			_say("SLAP never ended")
			get_tree().quit(1)
		return
	if _finished.size() >= players.size() or _elapsed >= _limit_seconds:
		_report(players, map)


func _report(players: Dictionary, map: MapData) -> void:
	_done = true
	var finish := map.finish_line()
	var goal := map.progress_of(finish.global_position) if finish != null else 0.0
	_say("--- bot race results (%.0fs simulated) ---" % _elapsed)
	for id in players.keys():
		var status := "FINISHED %.1fs" % float(_finished[id]) if _finished.has(id) else "stuck"
		_say("  %-10s %-16s best %6.0f / %6.0f   falls %d" % [_name(id), status, float(_best.get(id, 0.0)), goal, int(_falls.get(id, 0))])
		if not _finished.has(id):
			var trail: Array = _trail.get(id, [])
			var tail := trail.slice(maxi(trail.size() - 8, 0))
			var points: PackedStringArray = []
			for sample in tail:
				points.append("%s" % [sample[1]])
			_say("      last positions: %s" % "  ".join(points))
			var brain: BotBrain = (_arena.get(&"bots") as Dictionary).get(id)
			var player := players[id] as Player
			if brain != null:
				_say("      state %s  route point %d  target %s  velocity %s  input %s" % [Player.State.keys()[player.state], int(brain.get(&"_route_index")), brain.get(&"_target"), player.velocity.round(), (player.get(&"_input") as InputFrame).move])
				for c in player.get_slide_collision_count():
					var hit := player.get_slide_collision(c)
					_say("      touching %s at %s normal %s" % [hit.get_collider().name if hit.get_collider() else "?", hit.get_position().round(), hit.get_normal()])
	_say("BOT RACE %s: %d of %d finished" % ["OK" if _finished.size() == players.size() else "PARTIAL", _finished.size(), players.size()])
	get_tree().quit(0 if _finished.size() == players.size() else 1)


func _name(id: int) -> String:
	var entry: Dictionary = Net.roster.get(id, {})
	return String(entry.get("name", str(id)))
