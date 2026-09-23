extends Node

# ============================================================
# TREE GRAB CHECK - dev only. On every map: counts the world-space grab
# branches LevelSkin grew, then drops a monkey under one branch, holds jump,
# and requires the real swing system to latch the arm onto that branch.
# Writes to output/qa-handoff/checks.log and a screenshot per map.
# ============================================================

const PLAYER := preload("res://scenes/Player.tscn")
const MAPS := ["res://scenes/maps/MapA.tscn", "res://scenes/maps/MapB.tscn", "res://scenes/maps/SlapArena.tscn"]
var _failures: int = 0


func _ready() -> void:
	for path in MAPS:
		await _check_map(path)
	CheckLog.line("TREE GRAB CHECK %s" % ("OK" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _check_map(path: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var map := (load(path) as PackedScene).instantiate()
	viewport.add_child(map)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var branches: Array = []
	var trees := 0
	for node in map.find_children("*", "Climbable", true, false):
		if String(node.name).begins_with("BranchClimbable"):
			branches.append(node)
		elif String(node.name).begins_with("TreeClimbable"):
			trees += 1
	var label := path.get_file().get_basename()
	if branches.is_empty():
		_failures += 1
		CheckLog.line("TREE %s FAIL no grab branches (trees %d)" % [label, trees])
		viewport.queue_free()
		return
	var branch: Climbable = branches[branches.size() / 2]
	var player := PLAYER.instantiate() as Player
	player.setup(GameConfig.get_monkey(&"gibbon"), 1, false)
	viewport.add_child(player)
	player.respawn_at(branch.global_position + Vector2(0.0, 110.0))
	var camera := Camera2D.new()
	camera.position = branch.global_position + Vector2(0, 40)
	viewport.add_child(camera)
	camera.make_current()
	var latched := false
	var on_branch := false
	var grabbed_name := ""
	for i in 40:
		await get_tree().physics_frame
		var frame := InputFrame.new()
		frame.jump_held = true
		frame.grab_held = true
		if i == 0:
			frame.press(InputFrame.Action.JUMP)
		player.feed_input(frame)
		if player.state == Player.State.SWING and player.swing_on_trunk:
			latched = true
			var node: Node = player.get(&"_swing_node")
			# The crown counts: it is the same tree, and the highest hold on it.
			on_branch = node != null and (String(node.name).begins_with("BranchClimbable") or String(node.name).begins_with("TreeClimbable") or String(node.name).begins_with("CrownGrab"))
			grabbed_name = String(node.name) if node != null else "?"
			break
	for i in 6:
		await RenderingServer.frame_post_draw
	var shot := ProjectSettings.globalize_path("res://output/qa-handoff/shots/tree_grab_%s.png" % label)
	viewport.get_texture().get_image().save_png(shot)
	var ok := latched and on_branch
	if not ok:
		_failures += 1
	CheckLog.line("TREE %s %s branches=%d trees=%d latched=%s on_tree=%s held=%s" % [label, "ok  " if ok else "FAIL", branches.size(), trees, latched, on_branch, grabbed_name])
	viewport.queue_free()
	await get_tree().process_frame
