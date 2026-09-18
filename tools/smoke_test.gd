extends Node

# ============================================================
# SMOKE TEST - runs the real game headless and fails on any error.
#
#   godot --headless --fixed-fps 60 res://tools/Smoke.tscn
#
# Run as a scene rather than with --script, because a bare script MainLoop
# skips autoload registration and every singleton in the project would be
# an unknown identifier.
#
# Every mode on every map, with bots, for a few hundred physics ticks each.
# It does not judge whether the game is fun. It proves the thing boots, the
# scenes instance, the directors run, the monkeys move and nothing throws,
# which is the check a text-only workflow otherwise cannot make at all.
# ============================================================

const ARENA := preload("res://scenes/Main.tscn")
const TICKS_PER_CASE: int = 240

var _cases: Array = []
var _case: Dictionary = {}
var _arena: Node = null
var _ticks: int = 0
var _failures: Array[String] = []
var _notes: Array[String] = []


func _ready() -> void:
	# Keep ticking even if a scene under test pauses the tree, which Pause
	# does by design.
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _instance_every_scene()
	for mode in [GameConfig.Mode.FREE_PLAY, GameConfig.Mode.RACE, GameConfig.Mode.HOARD, GameConfig.Mode.SLAP]:
		for map_id in GameConfig.maps_for_mode(mode):
			_cases.append({"map": map_id, "mode": mode})
	print("smoke: %d cases, %d ticks each" % [_cases.size(), TICKS_PER_CASE])
	_next_case()


## Instancing every scene once is how a broken node path or a missing unique
## name gets caught: those only fail when the scene actually readies, and the
## mode cases below never open the lobby, the pause menu or the results.
func _instance_every_scene() -> void:
	var skipped := ["Main.tscn"]
	for path in _scene_paths("res://scenes"):
		if path.get_file() in skipped:
			continue
		var scene: PackedScene = load(path)
		if scene == null:
			_failures.append("%s failed to load" % path)
			continue
		var node := scene.instantiate()
		add_child(node)
		await get_tree().process_frame
		node.queue_free()
		await get_tree().process_frame
		get_tree().paused = false
	_notes.append("instanced every scene under res://scenes")


func _scene_paths(root: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for name in DirAccess.get_files_at(root):
		if name.ends_with(".tscn"):
			out.append(root.path_join(name))
	for dir_name in DirAccess.get_directories_at(root):
		out.append_array(_scene_paths(root.path_join(dir_name)))
	return out


func _physics_process(_delta: float) -> void:
	if _arena == null:
		return
	_ticks += 1
	if _ticks < TICKS_PER_CASE:
		return
	_finish_case()
	_next_case()


func _next_case() -> void:
	if _cases.is_empty():
		_report()
		get_tree().quit(1 if not _failures.is_empty() else 0)
		return
	_case = _cases.pop_front()
	Net.leave()
	Net.local_monkey = &"gibbon"
	Net.local_hat = &"cap"
	Net.set_match_config(_case["map"], _case["mode"])
	Net.set_bot_count(3)
	# start_match builds the offline roster the arena spawns from, so this is
	# the same path the lobby takes rather than a test-only shortcut.
	Net.start_match()
	_arena = ARENA.instantiate()
	add_child(_arena)
	_ticks = 0


func _finish_case() -> void:
	var label := "%s / %s" % [_case["map"], GameConfig.MODE_NAMES[_case["mode"]]]
	var players: Dictionary = _arena.get("players")
	if players.size() != 4:
		_failures.append("%s: expected 4 monkeys, got %d" % [label, players.size()])

	var moved := 0
	var alive := 0
	for id in players.keys():
		var player: Node = players[id]
		if not is_instance_valid(player):
			_failures.append("%s: player %d was freed mid-match" % [label, int(id)])
			continue
		alive += 1
		if player.global_position.distance_to(_spawn_of(int(id))) > 40.0:
			moved += 1
	# Nobody moving means the level or the brain is broken, and a screenshot
	# would not have told us that either.
	if moved == 0:
		_failures.append("%s: nobody moved in %d ticks" % [label, TICKS_PER_CASE])

	if _case["mode"] == GameConfig.Mode.RACE and int(_arena.get("race").get("phase")) == 0:
		_failures.append("%s: race director never left idle" % label)
	if _case["mode"] == GameConfig.Mode.HOARD and int(_arena.get("hoard").get("phase")) == 0:
		_failures.append("%s: hoard director never left idle" % label)

	_notes.append("%s: %d monkeys, %d moved" % [label, alive, moved])
	_arena.queue_free()
	_arena = null


func _spawn_of(id: int) -> Vector2:
	var map: Node = _arena.get("map")
	var slot := int(Net.roster.get(id, {}).get("slot", 0))
	return map.spawn_point + map.spawn_stride * float(slot)


func _report() -> void:
	print("--- smoke results ---")
	for note in _notes:
		print("  " + note)
	if _failures.is_empty():
		print("SMOKE OK")
		return
	print("SMOKE FAILURES:")
	for failure in _failures:
		print("  - " + failure)
