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
	"splash": "res://scenes/Splash.tscn",
	"home": "res://scenes/Menu.tscn|page0",
	"monkeys": "res://scenes/Menu.tscn|page1",
	"play_mode": "res://scenes/Menu.tscn|page2",
	"play_map": "res://scenes/Menu.tscn|page2step1",
	"play_ai": "res://scenes/Menu.tscn|page2step2",
	"party": "res://scenes/Menu.tscn|page3",
	"shop": "res://scenes/Menu.tscn|page4",
	"settings": "res://scenes/Menu.tscn|page5",
	"loading": "res://scenes/MatchLoading.tscn|cast",
	"loading_slap": "res://scenes/MatchLoading.tscn|slapcast",
	"results": "res://scenes/Results.tscn|results",
	"game_a": "res://scenes/Main.tscn|map_a",
	"game_b": "res://scenes/Main.tscn|map_b",
	"game_c": "res://scenes/Main.tscn|map_c",
	"slap_demo": "res://scenes/Main.tscn|slap_demo",
	"overview_a": "res://scenes/maps/MapA.tscn|overview",
	"overview_b": "res://scenes/maps/MapB.tscn|overview",
}

const SIZE := Vector2i(1280, 720)
## Long enough for the theme to apply, the rows to build and one layout pass
## to settle. A shot taken on the first frame catches every container at zero.
const SETTLE_FRAMES := 72


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
	if only.has("sheets"):
		_dump_sheets(out)
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
	if extra.begins_with("map_") or extra.ends_with("cast") or extra == "slap_demo":
		Net.mode = GameConfig.Mode.SLAP if extra == "slapcast" or extra == "map_c" or extra == "slap_demo" else GameConfig.Mode.RACE
		if extra.begins_with("map_"):
			Net.map_id = StringName(extra)
		elif extra == "slap_demo":
			Net.map_id = &"map_c"
		# A full lobby of different monkeys, three of them bots, so the shot
		# shows the roster side by side and something is always moving.
		Net.roster.clear()
		var cast: Array[StringName] = [&"macaque", &"gorilla", &"capuchin", &"orangutan"]
		for slot in cast.size():
			Net.roster[slot + 1] = {"monkey": cast[slot], "hat": &"none", "slot": slot, "bot": slot > 0, "name": ["", "Mango", "Kiwi", "Pip"][slot]}
	elif extra == "results":
		Net.mode = GameConfig.Mode.RACE
		Net.map_id = &"map_a"
		Net.roster = {
			1: {"monkey": &"macaque", "hat": &"none", "slot": 0, "name": ""},
			-1: {"monkey": &"gorilla", "hat": &"none", "slot": 1, "bot": true, "name": "Mango"},
			-2: {"monkey": &"capuchin", "hat": &"none", "slot": 2, "bot": true, "name": "Kiwi"},
			-3: {"monkey": &"orangutan", "hat": &"none", "slot": 3, "bot": true, "name": "Pip"},
		}
	var screen: Node = load(path).instantiate()
	if screen.get(&"force_touch_controls") != null:
		screen.set(&"force_touch_controls", true)
	# Set on the screen itself, not on the root window the way Boot does it.
	# A SubViewport is not a Window, so a theme on the real one never reaches
	# in here, and the shot would quietly come back in the engine default.
	if screen is Control:
		(screen as Control).theme = UiTheme.build()
	viewport.add_child(screen)
	if extra == "results":
		screen.call(&"show_results", [
			{"id": 1, "time": 37.20, "finished": true},
			{"id": -1, "time": 39.84, "finished": true},
			{"id": -2, "time": 44.12, "finished": true},
			{"id": -3, "time": 0.0, "finished": false},
		])
	if extra.begins_with("page"):
		# Menu pages: jump straight to one, and to a step inside PLAY.
		var parts := extra.trim_prefix("page").split("step")
		screen.call(&"_show", int(parts[0]), false)
		if parts.size() > 1:
			screen.call(&"_set_step", int(parts[1]))
	var shared_theme := UiTheme.build()
	for node in screen.find_children("*", "Control", true, false):
		if not (node.get_parent() is Control):
			(node as Control).theme = shared_theme
	if extra == "overview":
		_frame_whole_map(viewport, screen as Node2D)

	# Headless rendering can report a zero process delta on Windows. Counting
	# frames keeps capture automation deterministic, and the draw barrier keeps
	# rapid batch captures from reading a half-laid-out render-thread frame.
	for _frame in SETTLE_FRAMES:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	if extra == "slap_demo":
		# Freeze a real active frame, not a hand-authored mock. This keeps the
		# combat readability check in the same capture loop as the menus.
		var monkeys := screen.find_children("*", "Player", true, false)
		if not monkeys.is_empty():
			(monkeys[0] as Player).call(&"_try_attack")
			for _frame in 7:
				await get_tree().process_frame
				await RenderingServer.frame_post_draw

	var file := "%s/shot_%s.png" % [out.trim_suffix("/"), key]
	var error := viewport.get_texture().get_image().save_png(file)
	print("capture %s -> %s (%d)" % [key, file, error])
	# The capture loop owns this isolated viewport outright. Free it now so a
	# previous screen cannot survive one deferred frame into the next shot.
	viewport.free()


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


## Every monkey's generated sprite sheet, one species per row, scaled up so
## single pixels are visible. Asked for with --shots=sheets.
func _dump_sheets(out: String) -> void:
	const ZOOM := 4
	var species: Array[StringName] = [&"gorilla", &"gibbon", &"macaque", &"orangutan", &"capuchin"]
	var cell := MonkeySprite.CANVAS * ZOOM
	var sheet := Image.create_empty(cell * MonkeySprite.POSES.size(), cell * species.size() * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(120, 170, 190))
	for row in species.size():
		for pass_index in 2:
			var source: Dictionary = MonkeySprite.front_sheet_for(species[row]) if pass_index == 1 else MonkeySprite.sheet_for(species[row])
			var image: Image = (source["texture"] as Texture2D).get_image()
			image.resize(image.get_width() * ZOOM, image.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
			sheet.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(0, (row * 2 + pass_index) * cell))
	var file := "%s/shot_sheets.png" % out.trim_suffix("/")
	print("capture sheets -> %s (%d)" % [file, sheet.save_png(file)])
