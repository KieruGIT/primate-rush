extends Control

# ============================================================
# PULL REEL - the Banana Pull reveal, rolled like a lucky box.
#
# A strip of items races past a marker, slows, and lands on what you got.
# The pull's results are decided before the reel starts (Loot.pull); the
# reel only shows them, and the items flashing past are drawn from the
# real odds so what you see matches what you can get.
#
# The roll starts fast and bleeds speed until it is crawling. Now and then
# it crawls right onto something big, sits there a heartbeat... and ticks
# one more tile over. (Or the other way round: it nearly stops short of a
# legendary and just creeps onto it.) Only the show varies; the result was
# already decided.
#
# Bananas rain behind it, heavier the more you rolled. The speed buttons
# (1x 2x 4x 8x) only change how fast the reel spins. SKIP lands every roll
# at once. Each landed item drops into the tray under the reel.
# ============================================================

signal closed

const BANANA_ICON = preload("res://scripts/ui/BananaIcon.gd")
const TILE := Vector2(120, 136)
const TILE_GAP := 8.0
## Tiles before the result: more for a single pull, so it rolls longer.
const FILLER_SINGLE := 58
const FILLER_MULTI := 30
const FILLER_AFTER := 6
## How often the reel fakes you out (nearly stops on the tile next door).
const TEASE_CHANCE_SINGLE := 0.32
const TEASE_CHANCE_MULTI := 0.18
const SPEEDS: Array[int] = [1, 2, 4, 8]

var results: Array = []
## Builds the tray card for a result (Menu._result_card), so the landed
## items look exactly like the ones on the Banana Pull tab.
var card_maker: Callable

var _index: int = 0
var _speed: int = 1
var _rolling: bool = false
var _done: bool = false
var _strip: HBoxContainer = null
var _window: Control = null
var _tray: HFlowContainer = null
var _tween: Tween = null
var _last_tick: int = -1
var _speed_buttons: Array[Button] = []
var _footer: HBoxContainer = null
var _rain: Array = []           # [position, fall speed, sway phase, size]
var _flash: ColorRect = null
var _headline: Label = null
var _result_at: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_speed = int(Profile.get_stat("roll_speed", 1))
	if not SPEEDS.has(_speed):
		_speed = 1
	# Rain: more bananas the more you rolled.
	var count := mini(14 + results.size() * 7, 90)
	var view := get_viewport_rect().size
	for i in count:
		_rain.append([Vector2(randf() * view.x, randf_range(-view.y, view.y)), randf_range(90.0, 260.0), randf() * TAU, randf_range(2.0, 4.0)])

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.08, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.show_behind_parent = true
	add_child(dim)
	var rain := _Rain.new()
	rain.reel = self
	rain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rain)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_top = 28.0
	column.offset_bottom = -24.0
	column.offset_left = 30.0
	column.offset_right = -30.0
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_headline = _text("ROLLING...", &"DisplayBig", 30)
	column.add_child(_headline)

	# The reel: a window with the strip sliding inside it, and a marker.
	var frame := PanelContainer.new()
	frame.theme_type_variation = &"Glass"
	frame.custom_minimum_size = Vector2(0, TILE.y + 36.0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(frame)
	_window = Control.new()
	_window.clip_contents = true
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_window)
	var marker := _Marker.new()
	marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.z_index = 2
	_window.add_child(marker)

	_tray = HFlowContainer.new()
	_tray.alignment = FlowContainer.ALIGNMENT_CENTER
	_tray.add_theme_constant_override(&"h_separation", 8)
	_tray.add_theme_constant_override(&"v_separation", 8)
	_tray.custom_minimum_size = Vector2(0, 150)
	_tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_tray)

	_footer = HBoxContainer.new()
	_footer.alignment = BoxContainer.ALIGNMENT_CENTER
	_footer.add_theme_constant_override(&"separation", 10)
	column.add_child(_footer)
	_footer.add_child(_text("SPEED", &"Display", 14))
	for s in SPEEDS:
		var b := _button("%dx" % s, &"ChoiceButton", Vector2(76, 56))
		b.toggle_mode = true
		b.pressed.connect(_set_speed.bind(s))
		_footer.add_child(b)
		_speed_buttons.append(b)
	var skip := _button("SKIP", &"PrimaryButton", Vector2(170, 56))
	skip.pressed.connect(_skip)
	_footer.add_child(skip)
	_refresh_speed()

	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	_flash.z_index = 5
	add_child(_flash)
	# A beat for the layout to settle (the stop point is measured from the
	# window's width) and for the rain to start.
	get_tree().create_timer(0.3).timeout.connect(_roll_next)


func _process(delta: float) -> void:
	var view := get_viewport_rect().size
	for drop in _rain:
		drop[0].y += float(drop[1]) * delta
		drop[2] += delta * 2.0
		if drop[0].y > view.y + 40.0:
			drop[0] = Vector2(randf() * view.x, -40.0)
	if _strip != null:
		_update_previews()
	# Tick as each tile crosses the marker, like a real reel clicking.
	if _rolling and _strip != null:
		var centre := _window.size.x * 0.5 - _strip.position.x
		var tile := int(centre / (TILE.x + TILE_GAP))
		if tile != _last_tick:
			_last_tick = tile
			Sfx.play(&"ui_click", 1.0 + minf(0.4, float(tile) * 0.006), -6.0)


func _set_speed(s: int) -> void:
	_speed = s
	Profile.set_stat("roll_speed", s)
	Sfx.play(&"ui_select")
	_refresh_speed()
	if _tween != null and _tween.is_running():
		_tween.set_speed_scale(float(_speed))


func _refresh_speed() -> void:
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(SPEEDS[i] == _speed)


## One roll: a fresh strip with the result placed where the reel stops.
func _roll_next() -> void:
	if _index >= results.size():
		_finish()
		return
	var result: Dictionary = results[_index]
	var rarity := int(result["rarity"])
	var single := results.size() == 1
	_result_at = FILLER_SINGLE if single else FILLER_MULTI
	# The fake-out: a big item parked right before a small result (it stops
	# on the big one, then ticks over), or a dud right before a big result
	# (it stops short, then creeps onto it). Not every time, or it stops
	# being a surprise.
	var tease := randf() < (TEASE_CHANCE_SINGLE if single else TEASE_CHANCE_MULTI)
	var bait: StringName = &""
	if tease:
		bait = _bait_for(rarity)
		tease = bait != &""
	if _strip != null:
		_strip.queue_free()
	_strip = HBoxContainer.new()
	_strip.add_theme_constant_override(&"separation", int(TILE_GAP))
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.position = Vector2(0.0, 14.0)
	_window.add_child(_strip)
	_window.move_child(_strip, 0)
	for i in _result_at + 1 + FILLER_AFTER:
		var id: StringName = _random_item()
		if i == _result_at:
			id = result["id"]
		elif tease and i == _result_at - 1:
			id = bait
		_strip.add_child(_tile(id))
	_headline.text = "ROLL %d / %d" % [_index + 1, results.size()] if results.size() > 1 else "ROLLING..."
	_rolling = true
	_last_tick = -1
	_tween = create_tween()
	_tween.set_speed_scale(float(_speed))
	var seconds := 5.2 if single else 2.4
	if tease:
		# Crawl to a stop near the far edge of the bait tile...
		_tween.tween_property(_strip, "position:x", _x_for(_result_at - 1, randf_range(0.3, 0.42)), seconds).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		# ...inch a little further, so it really looks like it is settling...
		_tween.tween_property(_strip, "position:x", _x_for(_result_at - 1, randf_range(0.47, 0.5)), randf_range(0.5, 0.8) if single else 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		# ...hold it...
		_tween.tween_interval(randf_range(0.15, 0.35) if single else 0.1)
		# ...and tip over onto the real one.
		_tween.tween_property(_strip, "position:x", _x_for(_result_at, randf_range(-0.36, -0.12)), 0.45 if single else 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		# Land somewhere inside the result's tile, not dead centre every time.
		_tween.tween_property(_strip, "position:x", _x_for(_result_at, randf_range(-0.38, 0.38)), seconds).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_land)


## Strip position that puts the marker at a point inside tile `index`:
## `across` is -0.5 (its left edge) to 0.5 (its right edge).
func _x_for(index: int, across: float) -> float:
	return -(index * (TILE.x + TILE_GAP) + TILE.x * (0.5 + across) - _window.size.x * 0.5)


## The item to park next to the result for a fake-out: something big when
## the result is small, a common when the result is big. Empty = no tease.
func _bait_for(result_rarity: int) -> StringName:
	var want: Array = []
	if result_rarity <= Loot.Rarity.RARE:
		want = [Loot.Rarity.LEGENDARY, Loot.Rarity.MYTHIC] if randf() < 0.35 else [Loot.Rarity.LEGENDARY]
	elif randf() < 0.6:
		want = [Loot.Rarity.COMMON]
	else:
		return &""
	var pool: Array = []
	for id in Loot.ITEMS.keys():
		if want.has(int(Loot.ITEMS[id]["rarity"])):
			pool.append(id)
	return pool[randi() % pool.size()] if not pool.is_empty() else &""


## Only tiles inside the window carry a live preview; the rest are just
## frames. A 60-tile strip of live previews would be a lot for a phone.
func _update_previews() -> void:
	var left := -_strip.position.x - TILE.x * 1.5
	# Spawned a few tiles early so particle effects are already going when
	# they slide into view.
	var right := -_strip.position.x + _window.size.x + TILE.x * 4.0
	var pitch := TILE.x + TILE_GAP
	for i in _strip.get_child_count():
		var tile := _strip.get_child(i)
		var x := float(i) * pitch
		tile.call(&"show_preview", x > left and x < right)


func _land() -> void:
	_rolling = false
	var result: Dictionary = results[_index]
	var rarity := int(result["rarity"])
	var colour: Color = Loot.RARITY_COLORS[rarity]
	var landed := _strip.get_child(_result_at) as Control
	landed.pivot_offset = TILE * 0.5
	var pop := landed.create_tween()
	pop.tween_property(landed, "scale", Vector2.ONE * 1.2, 0.08)
	pop.tween_property(landed, "scale", Vector2.ONE, 0.14)
	_flash_colour(colour, 0.45 if rarity == Loot.Rarity.MYTHIC else (0.3 if rarity == Loot.Rarity.LEGENDARY else 0.1))
	Sfx.play(&"finish" if rarity >= Loot.Rarity.LEGENDARY else &"ui_select")
	if rarity >= Loot.Rarity.LEGENDARY:
		_headline.text = "%s!" % Loot.RARITY_NAMES[rarity]
		_headline.add_theme_color_override(&"font_color", colour)
		# A burst of extra bananas for the big ones.
		var view := get_viewport_rect().size
		for i in 24:
			_rain.append([Vector2(randf() * view.x, -40.0 - randf() * 200.0), randf_range(200.0, 380.0), randf() * TAU, randf_range(3.0, 5.0)])
	_add_to_tray(result)
	_index += 1
	var wait := (0.9 if rarity >= Loot.Rarity.LEGENDARY else 0.35) / float(_speed)
	get_tree().create_timer(wait).timeout.connect(func() -> void:
		if not _done and is_inside_tree():
			_headline.remove_theme_color_override(&"font_color")
			_roll_next())


func _add_to_tray(result: Dictionary) -> void:
	if card_maker.is_valid():
		_tray.add_child(card_maker.call(result, false))


func _skip() -> void:
	if _done:
		return
	if _tween != null:
		_tween.kill()
	_rolling = false
	var best := 0
	while _index < results.size():
		var result: Dictionary = results[_index]
		best = maxi(best, int(result["rarity"]))
		_add_to_tray(result)
		_index += 1
	Sfx.play(&"finish" if best >= Loot.Rarity.LEGENDARY else &"ui_select")
	_finish()


func _finish() -> void:
	_done = true
	_rolling = false
	_headline.text = "YOU GOT"
	for child in _footer.get_children():
		child.queue_free()
	var nice := _button("NICE!", &"PlayButton", Vector2(260, 60))
	nice.pressed.connect(func() -> void:
		closed.emit()
		queue_free())
	_footer.add_child(nice)
	# Another go, right there: the same size pull again if you can afford it.
	var again := _button("ROLL AGAIN", &"PrimaryButton", Vector2(220, 60))
	again.disabled = not Loot.can_pull(results.size())
	again.pressed.connect(func() -> void:
		closed.emit()
		queue_free()
		var menu := get_parent()
		if menu != null and menu.has_method(&"_on_pull"):
			menu.call(&"_on_pull", results.size(), false))
	_footer.add_child(again)


## A filler item for the strip, drawn from the real odds.
func _random_item() -> StringName:
	var roll := randf() * 100.0
	var rarity := Loot.Rarity.COMMON
	if roll < Loot.ODDS[3]:
		rarity = Loot.Rarity.MYTHIC
	elif roll < Loot.ODDS[3] + Loot.ODDS[2]:
		rarity = Loot.Rarity.LEGENDARY
	elif roll < Loot.ODDS[3] + Loot.ODDS[2] + Loot.ODDS[1]:
		rarity = Loot.Rarity.RARE
	var pool: Array = []
	for id in Loot.ITEMS.keys():
		if int(Loot.ITEMS[id]["rarity"]) == rarity:
			pool.append(id)
	return pool[randi() % pool.size()] if not pool.is_empty() else Loot.ITEMS.keys()[0]


func _tile(id: StringName) -> Control:
	var tile := _Tile.new()
	tile.item_id = id
	tile.custom_minimum_size = TILE
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tile


func _flash_colour(colour: Color, strength: float) -> void:
	_flash.color = Color(colour, strength)
	var tween := _flash.create_tween()
	tween.tween_property(_flash, "color:a", 0.0, 0.4)


func _text(text: String, variation: StringName, size_px: int) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.add_theme_font_size_override(&"font_size", size_px)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, variation: StringName, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size = min_size
	return b


## Bananas falling behind everything, swaying a little.
class _Rain extends Control:
	var reel: Node = null

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if reel == null:
			return
		for drop in reel.get(&"_rain"):
			var at: Vector2 = drop[0] + Vector2(sin(float(drop[2])) * 12.0, 0.0)
			BANANA_ICON.draw_one(self, at.floor(), float(drop[3]))


## The pointer the reel stops under, top and bottom.
class _Marker extends Control:
	func _draw() -> void:
		var x := size.x * 0.5
		var c := Color8(255, 216, 74)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 12, 0), Vector2(x + 12, 0), Vector2(x, 16)]), c)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 12, size.y), Vector2(x + 12, size.y), Vector2(x, size.y - 16)]), c)
		draw_rect(Rect2(x - 1, 16, 2, size.y - 32), Color(c, 0.35))


## One item on the reel: a frame in its rarity colour, the item itself
## (live, like the gallery), and its name.
class _Tile extends Control:
	const PREVIEW = preload("res://scripts/ui/ItemPreview.gd")
	var item_id: StringName = &""
	var _preview: Control = null

	func show_preview(on: bool) -> void:
		if on and _preview == null:
			_preview = PREVIEW.new(item_id, Vector2(size.x - 8.0, size.y - 34.0))
			_preview.position = Vector2(4, 4)
			add_child(_preview)
		elif not on and _preview != null:
			_preview.queue_free()
			_preview = null

	func _draw() -> void:
		var entry: Dictionary = Loot.item(item_id)
		var rarity := int(entry.get("rarity", 0))
		var colour: Color = Loot.RARITY_COLORS[rarity]
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.09, 0.17))
		# A soft glow of the rarity colour behind the item.
		draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 34)), Color(colour, 0.12 + 0.06 * rarity))
		draw_rect(Rect2(Vector2.ZERO, size), colour, false, 4.0)
		draw_rect(Rect2(0, size.y - 8, size.x, 8), colour)
		var font := get_theme_default_font()
		var label_text := String(entry.get("name", "?")).to_upper()
		draw_string(font, Vector2(4, size.y - 15), label_text, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 10, Color.WHITE)
