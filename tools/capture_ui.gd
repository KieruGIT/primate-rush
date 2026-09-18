extends Node

# ============================================================
# CAPTURE UI - dev only. Renders a screen at a real resolution and writes a
# PNG, so a layout change can be looked at without opening the editor and
# without a human describing what they see.
#
# Runs the screen inside a SubViewport rather than the main window: the shot
# is then exactly the design resolution whatever the window happens to be.
# ============================================================

const SHOTS := {
	"lobby": "res://scenes/Lobby.tscn",
	"game_a": "res://scenes/Main.tscn|map_a",
	"game_b": "res://scenes/Main.tscn|map_b",
	"overview_a": "res://scenes/maps/MapA.tscn|overview",
	"overview_b": "res://scenes/maps/MapB.tscn|overview",
}

const SIZE := Vector2i(1280, 720)
## Long enough for the theme to apply, the rows to build and one layout pass
## to settle. A shot taken on the first frame catches every container at zero.
const SETTLE_SECONDS := 1.2


func _ready() -> void:
	var out: String = "user://"
	var only: PackedStringArray = []
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
		elif argument.begins_with("--shots="):
			only = argument.trim_prefix("--shots=").split(",")

	for key in SHOTS.keys():
		if only.is_empty() or only.has(String(key)):
			await _shoot(String(key), String(SHOTS[key]), out)
	get_tree().quit()


func _shoot(key: String, path: String, out: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	add_child(viewport)
	# "scene|extra": a map id for the arena, or "overview" for a whole level
	# framed by one zoomed-out camera.
	var extra := ""
	if path.contains("|"):
		extra = path.get_slice("|", 1)
		path = path.get_slice("|", 0)
	if extra.begins_with("map_"):
		Net.map_id = StringName(extra)
		Net.roster.clear()
	var screen: Node = load(path).instantiate()
	# Set on the screen itself, not on the root window the way Boot does it.
	# A SubViewport is not a Window, so a theme on the real one never reaches
	# in here, and the shot would quietly come back in the engine default.
	if screen is Control:
		(screen as Control).theme = UiTheme.build()
	viewport.add_child(screen)
	if extra == "overview":
		_frame_whole_map(viewport, screen as Node2D)

	var elapsed := 0.0
	while elapsed < SETTLE_SECONDS:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	await RenderingServer.frame_post_draw

	var file := "%s/shot_%s.png" % [out.trim_suffix("/"), key]
	var error := viewport.get_texture().get_image().save_png(file)
	print("capture %s -> %s (%d)" % [key, file, error])
	viewport.queue_free()


## Fits every visible piece of a level into the shot. Walks CanvasItems for
## their rects rather than trusting one background, which overhangs the level.
func _frame_whole_map(viewport: SubViewport, map: Node2D) -> void:
	var bounds := Rect2()
	var first := true
	for node in map.find_children("*", "CollisionShape2D", true, false):
		var shape := node as CollisionShape2D
		if shape.shape == null:
			continue
		var rect := shape.shape.get_rect()
		rect.position += shape.global_position
		bounds = rect if first else bounds.merge(rect)
		first = false
	bounds = bounds.grow(120.0)
	var camera := Camera2D.new()
	camera.position = bounds.get_center()
	var fit: float = minf(SIZE.x / bounds.size.x, SIZE.y / bounds.size.y)
	camera.zoom = Vector2(fit, fit)
	viewport.add_child(camera)
	camera.make_current()
