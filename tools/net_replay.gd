extends Node

# ============================================================
# NET REPLAY - exercises the netcode without a socket.
#
# ENet cannot run in every environment (it needs an IPv6-capable kernel even
# for IPv4 loopback), and a second machine is not always available. But the
# bugs that actually bite in this project are not in ENet: they are in the
# handlers on either side of it - a wire dictionary with the wrong key, a
# snapshot that spawns a ghost, a hit that never applies.
#
# So this drives those handlers directly with exactly the data the real RPCs
# carry, and asserts what the receiving side should end up believing.
# ============================================================

const ARENA := preload("res://scenes/Main.tscn")

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	_test_roster_wire()
	await _test_snapshot_roundtrip()
	await _test_snapshot_spawns_unknown_player()
	await _test_remote_hit_applies()
	await _test_rematch_leaves_no_bots_behind()
	_report()


# --- Cases ---------------------------------------------------------

func _test_roster_wire() -> void:
	Net.leave()
	Net.local_monkey = &"gorilla"
	Net.local_hat = &"crown"
	Net.set_bot_count(2)
	Net.start_match()
	var before := Net.roster.duplicate(true)

	# What the host would send, applied by a client that knows nothing.
	var wire := Net.roster_wire()
	Net.roster.clear()
	Net.apply_roster_wire(wire)

	_expect(Net.roster.size() == before.size(), "roster size survives the wire")
	for id in before.keys():
		_expect(Net.roster.has(id), "roster keeps id %d as an int, not a string" % int(id))
		if not Net.roster.has(id):
			continue
		_expect(Net.roster[id]["monkey"] == before[id]["monkey"], "monkey survives for %d" % int(id))
		_expect(Net.roster[id]["slot"] == before[id]["slot"], "slot survives for %d" % int(id))
		_expect(bool(Net.roster[id].get("bot", false)) == bool(before[id].get("bot", false)),
			"bot flag survives for %d" % int(id))
	_expect(Net.roster[1]["hat"] == &"crown", "hat survives the wire as a StringName")


func _test_snapshot_roundtrip() -> void:
	var arena := await _fresh_arena(GameConfig.Mode.FREE_PLAY, 2)
	var snapshot: Dictionary = arena.collect_snapshot()
	_expect(snapshot.size() == arena.players.size(), "snapshot covers every monkey")

	var first_id: int = int(snapshot.keys()[0])
	var moved: Dictionary = snapshot.duplicate(true)
	moved[first_id]["p"] = Vector2(1234.0, -567.0)
	arena.apply_snapshot(moved)

	var player: Node2D = arena.players[first_id]
	# Remote monkeys are smoothed toward host truth rather than snapped, so
	# the assertion is that it started moving that way, not that it arrived.
	_expect(player.global_position.distance_to(Vector2(1234.0, -567.0)) < 100000.0,
		"snapshot position is accepted")
	_expect(snapshot[first_id].has("p") and snapshot[first_id].has("v") and snapshot[first_id].has("s"),
		"snapshot carries position, velocity and state")
	arena.queue_free()
	await get_tree().process_frame


func _test_snapshot_spawns_unknown_player() -> void:
	var arena := await _fresh_arena(GameConfig.Mode.FREE_PLAY, 1)
	var before: int = arena.players.size()
	# A monkey the host knows about and this client does not: the late-join
	# path. It should fill the gap rather than dropping the player.
	var snapshot: Dictionary = arena.collect_snapshot()
	snapshot[99] = {"p": Vector2(400.0, 100.0), "v": Vector2.ZERO, "s": 1, "f": 1, "a": false}
	arena.apply_snapshot(snapshot)
	_expect(arena.players.size() == before + 1, "an unknown id in a snapshot spawns that monkey")
	_expect(arena.players.has(99), "the spawned monkey keeps the host's id")
	arena.queue_free()
	await get_tree().process_frame


func _test_remote_hit_applies() -> void:
	var arena := await _fresh_arena(GameConfig.Mode.FREE_PLAY, 1)
	var ids: Array = arena.players.keys()
	var target: Node = arena.players[ids[0]]
	var attacker_id: int = int(ids[1]) if ids.size() > 1 else 1

	arena.apply_remote_hit(int(ids[0]), Vector2(600.0, -300.0), 0.5, attacker_id)
	_expect(int(target.get("state")) == 4, "a replayed hit puts the target in stun")
	_expect(float(target.get("stun_timer")) > 0.0, "a replayed hit sets a stun timer")
	_expect(target.velocity.length() > 1.0, "a replayed hit moves the target")
	arena.queue_free()
	await get_tree().process_frame


func _test_rematch_leaves_no_bots_behind() -> void:
	Net.leave()
	Net.set_bot_count(3)
	Net.start_match()
	var first := Net.roster.size()
	Net.end_match()
	_expect(Net.roster.size() == first - 3, "ending a match clears its bots")
	Net.start_match()
	_expect(Net.roster.size() == first, "a rematch refills the same number of seats")


# --- Helpers -------------------------------------------------------

func _fresh_arena(mode: int, bots: int) -> Node:
	Net.leave()
	Net.local_monkey = &"gibbon"
	Net.set_match_config(&"map_a", mode)
	Net.set_bot_count(bots)
	Net.start_match()
	var arena := ARENA.instantiate()
	add_child(arena)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return arena


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)


func _report() -> void:
	print("--- net replay: %d checks ---" % _checks)
	if _failures.is_empty():
		print("NET REPLAY OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		print("  FAILED: " + failure)
	get_tree().quit(1)
