extends Node
## Banana Rush on Banana Grove: are bananas resting on blocks (not in
## them), and does a monkey at the far edge fall off when knocked out?

const ARENA := preload("res://scenes/Main.tscn")

func _ready() -> void:
	get_window().theme = UiTheme.shared()
	Net.leave()
	Net.local_monkey = &"gorilla"
	Net.set_match_config(&"map_d", GameConfig.Mode.HOARD)
	Net.set_bot_count(3)
	Net.start_match()
	var arena := ARENA.instantiate()
	add_child(arena)
	await get_tree().process_frame
	arena.set(&"bots", {})
	await _wait(10.0)
	var space := get_viewport().world_2d.direct_space_state
	var probe := PhysicsPointQueryParameters2D.new()
	probe.collision_mask = GameConfig.LAYER_SOLID
	var inside := 0
	var total := 0
	for p in get_tree().get_nodes_in_group(&"pickup"):
		total += 1
		probe.position = (p as Node2D).global_position + Vector2(0, 16)
		if not space.intersect_point(probe, 1).is_empty():
			inside += 1
	var values := []
	for p in get_tree().get_nodes_in_group(&"pickup"):
		values.append((p as Pickup).value)
	_note("after 10 s: pickups %d %s, sunk into a block %d" % [total, values, inside])
	_shot("hoard_bananas")
	var players: Dictionary = arena.get(&"players")
	var me: Player = players.get(1)
	var dummy: Player = null
	for pid in players.keys():
		if int(pid) < 0:
			dummy = players[pid]
	dummy.global_position = Vector2(-1540, 440)
	dummy.velocity = Vector2.ZERO
	me.global_position = Vector2(-1440, 440)
	await _wait(0.5)
	_shot("hoard_edge")
	dummy.take_hit(1, Vector2(-900, -200), 0.45)
	await _wait(1.5)
	_note("dummy after hit at %s (ground edge x=-1600, kill below y=1100)" % dummy.global_position)
	_shot("hoard_pushed")
	# First to the target ends the round.
	var hoard: HoardDirector = arena.get(&"hoard")
	_note("hoard: target %d, interval %.1f, cap %d, pickups now %d" % [hoard.win_target, hoard.spawn_interval, hoard.max_pickups, get_tree().get_nodes_in_group(&"pickup").size()])
	# A hit on a carrier: one to the attacker, one knocked loose.
	hoard.scores[int(dummy.player_id)] = 5
	hoard.scores[1] = 0
	hoard.call(&"_send", &"scores", [hoard.scores.duplicate()])
	var before := get_tree().get_nodes_in_group(&"pickup").size()
	dummy.global_position = me.global_position + Vector2(80, 0)
	dummy.take_hit(1, Vector2(300, -100), 0.45)
	await _wait(0.2)
	_note("steal: me %d, victim %d, pickups %d -> %d" % [int(hoard.scores.get(1, 0)), int(hoard.scores.get(int(dummy.player_id), 0)), before, get_tree().get_nodes_in_group(&"pickup").size()])
	_shot("hoard_steal")
	hoard.scores[int(dummy.player_id)] = 6
	hoard.scores[1] = 27
	hoard.steal_bananas(int(dummy.player_id), 1, 1.0)
	await _wait(0.3)
	_note("after reaching %d: phase %d (OVER=%d)" % [int(hoard.scores[1]), hoard.phase, HoardDirector.Phase.OVER])
	await _wait(1.5)
	_shot("hoard_win")
	get_tree().quit()


func _note(line: String) -> void:
	print("HOARDPROBE " + line)
	var f := FileAccess.open("res://output/qa/hoard_probe.txt", FileAccess.READ_WRITE if FileAccess.file_exists("res://output/qa/hoard_probe.txt") else FileAccess.WRITE)
	f.seek_end()
	f.store_line(line)
	f.close()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name_key: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://output/qa/ui_%s.png" % name_key)
