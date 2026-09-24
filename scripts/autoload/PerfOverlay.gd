extends CanvasLayer

# ============================================================
# PERF OVERLAY - frame time on the phone, and switches for the effects.
#
# Hidden until asked for: tap the top-left corner three times quickly (or
# press F3 on a keyboard). Shows FPS, average and worst frame time over the
# last five seconds, the worst frame of the whole session, CPU time and draw
# calls, plus one button per optional effect so a phone can be tested
# with and without each of them.
#
# Every switch, and the render resolution, is saved to user://perf.cfg, so a
# setting that helps survives a restart and can be tried across a whole match.
#
# Effects register themselves with track(node, "name"). Turning a switch off
# hides every node in that group; a node that only draws part of itself
# (a torch's glow) instead implements _fx_refresh() and checks fx_on().
# ============================================================

signal fx_changed(fx: StringName, on: bool)

const SAVE_PATH := "user://perf.cfg"
const WINDOW_SECONDS: float = 5.0
const CORNER: float = 90.0
const TAPS_NEEDED: int = 3
const TAP_WINDOW: float = 0.9

## Display names, in button order.
const FX: Dictionary = {
	&"vignette": "Vignette",
	&"canopy": "Leaf canopy",
	&"fireflies": "Fireflies",
	&"bg_trees": "Background trees",
	&"panorama": "Far panorama",
	&"torch_glow": "Torch glow",
	&"water_glints": "Water glints",
}

## "native" renders at the phone's full resolution; "720p" renders the
## game at 1280x720 and scales the finished frame up to the screen.
const RESOLUTIONS: Array[StringName] = [&"native", &"720p"]

var resolution: StringName = &"native"
var _fx: Dictionary = {}

var _panel: PanelContainer = null
var _stats: Label = null
var _res_button: Button = null
var _fx_buttons: Dictionary = {}

var _frames: Array = []          # [usec timestamp, frame ms]
var _last_usec: int = 0
var _session_worst: float = 0.0
var _label_refresh: float = 0.0
var _taps: Array[float] = []


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key in FX.keys():
		_fx[key] = true
	_load()
	_apply_resolution()
	_build()
	_panel.visible = false


# --- Public API ----------------------------------------------------

func fx_on(fx: StringName) -> bool:
	return bool(_fx.get(fx, true))


## Puts `node` under switch `fx` and applies the current state to it.
func track(node: Node, fx: StringName) -> void:
	node.add_to_group(_group(fx))
	_apply_to(node, fx_on(fx))


func set_fx(fx: StringName, on: bool) -> void:
	_fx[fx] = on
	for node in get_tree().get_nodes_in_group(_group(fx)):
		_apply_to(node, on)
	_save()
	_refresh_buttons()
	fx_changed.emit(fx, on)


func set_resolution(value: StringName) -> void:
	resolution = value
	_apply_resolution()
	_save()
	_refresh_buttons()


func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_refresh_buttons()


# --- Measuring -----------------------------------------------------

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		var ms := (now - _last_usec) / 1000.0
		_frames.append([now, ms])
		# The first seconds after a load are not play: ignore them for the
		# session worst, or every match reports its own loading hitch.
		if Engine.get_process_frames() > 180:
			_session_worst = maxf(_session_worst, ms)
	_last_usec = now
	var cutoff := now - int(WINDOW_SECONDS * 1000000.0)
	while not _frames.is_empty() and int(_frames[0][0]) < cutoff:
		_frames.pop_front()
	if _panel == null or not _panel.visible:
		return
	_label_refresh -= delta
	if _label_refresh > 0.0:
		return
	_label_refresh = 0.25
	var total := 0.0
	var worst := 0.0
	var over_33 := 0
	for f in _frames:
		var ms: float = f[1]
		total += ms
		worst = maxf(worst, ms)
		if ms > 33.4:
			over_33 += 1
	var count := maxi(_frames.size(), 1)
	var avg := total / count
	_stats.text = "FPS %d   avg %.1f ms\nworst (5s) %.1f ms   session %.1f ms\nslow frames (5s) %d\nCPU process %.1f ms   physics %.1f ms\ndraw calls %d   %s" % [
		Engine.get_frames_per_second(), avg, worst, _session_worst, over_33,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		_render_size_text(),
	]


func _render_size_text() -> String:
	var size := get_viewport().get_visible_rect().size
	var window := DisplayServer.window_get_size()
	if resolution == &"720p":
		return "render %dx%d -> %dx%d" % [int(size.x), int(size.y), window.x, window.y]
	return "render %dx%d" % [window.x, window.y]


# --- Opening it ----------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F3:
		toggle()
		return
	var at := Vector2(-1, -1)
	if event is InputEventScreenTouch and event.pressed:
		at = (event as InputEventScreenTouch).position
	elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		at = (event as InputEventMouseButton).position
	if at.x < 0.0 or at.x > CORNER or at.y > CORNER:
		return
	var now := Time.get_ticks_msec() / 1000.0
	_taps.append(now)
	while not _taps.is_empty() and now - _taps[0] > TAP_WINDOW:
		_taps.pop_front()
	if _taps.size() >= TAPS_NEEDED:
		_taps.clear()
		toggle()


# --- Building the panel --------------------------------------------

func _build() -> void:
	_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.02, 0.04, 0.06, 0.86)
	box.border_color = Color(1.0, 0.8, 0.2, 0.9)
	box.set_border_width_all(2)
	box.set_content_margin_all(10)
	_panel.add_theme_stylebox_override(&"panel", box)
	_panel.position = Vector2(12, 12)
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	_panel.add_child(column)

	_stats = Label.new()
	_stats.add_theme_font_size_override(&"font_size", 16)
	_stats.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.75))
	column.add_child(_stats)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 6)
	column.add_child(grid)

	_res_button = _make_button(grid, func() -> void:
		var i := RESOLUTIONS.find(resolution)
		set_resolution(RESOLUTIONS[(i + 1) % RESOLUTIONS.size()]))
	for key in FX.keys():
		var fx: StringName = key
		_fx_buttons[fx] = _make_button(grid, func() -> void: set_fx(fx, not fx_on(fx)))

	var close := _make_button(column, toggle)
	close.text = "Close (triple-tap corner to reopen)"
	_refresh_buttons()


func _make_button(parent: Node, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(230, 44)
	b.add_theme_font_size_override(&"font_size", 16)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b


func _refresh_buttons() -> void:
	if _res_button == null:
		return
	_res_button.text = "Resolution: %s" % ("Full" if resolution == &"native" else "720p")
	for key in _fx_buttons.keys():
		var b: Button = _fx_buttons[key]
		b.text = "%s: %s" % [FX[key], "ON" if fx_on(key) else "OFF"]
		b.modulate = Color.WHITE if fx_on(key) else Color(1.0, 0.6, 0.6)


# --- Applying ------------------------------------------------------

func _group(fx: StringName) -> StringName:
	return StringName("fx_" + String(fx))


func _apply_to(node: Node, on: bool) -> void:
	if node.has_method(&"_fx_refresh"):
		node.call(&"_fx_refresh")
	elif node is CanvasItem:
		(node as CanvasItem).visible = on


## Full resolution keeps Godot's canvas_items stretch: everything is drawn
## straight at the screen's size. 720p switches the root to viewport stretch,
## so the game draws 1280x720 (widened to the screen's aspect) and the
## finished frame is scaled up. Touch positions are mapped by Godot either way.
func _apply_resolution() -> void:
	var root := get_tree().root
	if resolution == &"720p":
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	else:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("render", "resolution", String(resolution))
	for key in _fx.keys():
		cfg.set_value("fx", String(key), bool(_fx[key]))
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var res := StringName(String(cfg.get_value("render", "resolution", "native")))
	if RESOLUTIONS.has(res):
		resolution = res
	for key in FX.keys():
		_fx[key] = bool(cfg.get_value("fx", String(key), true))
