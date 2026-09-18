extends Control

# ============================================================
# MATCH LOADING - every player's card, filling up, before the round.
#
# The MOBA loading screen: one card per seat with the monkey, the name and a
# bar. The local bar tracks this machine building the arena for real - the
# map is loaded on a thread while the cards are up. Other people's bars are
# paced to finish with it, and bots load quickly, because they are bots.
#
# Everyone waits for the slowest bar and then a short beat, so the round
# starts after you have seen who you are up against, not while the screen
# is still fading in.
# ============================================================

signal finished

const MIN_SECONDS: float = 2.6
const HOLD_SECONDS: float = 0.45

var _bars: Dictionary = {}          # roster id -> {"bar": ProgressBar, "rate": float, "value": float, "label": Label}
var _elapsed: float = 0.0
var _map_path: String = ""
var _map_ready: bool = false
var _held: float = 0.0
var _done: bool = false
## Held so the finished load stays in the resource cache until the arena
## asks for the same path a moment later.
var _map_resource: Resource = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := MenuBackdrop.new()
	backdrop.animate = false
	add_child(backdrop)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_top = 24.0
	column.offset_bottom = -24.0
	column.offset_left = 30.0
	column.offset_right = -30.0
	column.add_theme_constant_override(&"separation", 16)
	add_child(column)

	var mode_name: String = GameConfig.MODE_NAMES[Net.mode]
	var map_name: String = GameConfig.MAP_NAMES.get(Net.map_id, String(Net.map_id))
	column.add_child(_centered(mode_name.to_upper(), &"DisplayBig", 56))
	column.add_child(_centered(map_name.to_upper(), &"Display", 24))

	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override(&"separation", 18)
	column.add_child(cards)

	var ids: Array = Net.roster.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return int(Net.roster[a]["slot"]) < int(Net.roster[b]["slot"]))
	var slap := Net.mode == GameConfig.Mode.SLAP
	for i in ids.size():
		if slap and i == 2:
			# Teams face each other across a VS, the way every versus
			# loading screen has done it since arcades.
			var vs := _centered("VS", &"DisplayBig", 72)
			vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cards.add_child(vs)
		cards.add_child(_card(int(ids[i]), Net.roster[ids[i]]))

	var tip := _centered("TIP: " + String(_tip()).to_upper(), &"Subheading", 16)
	column.add_child(tip)

	_map_path = String(GameConfig.MAP_PATHS.get(Net.map_id, GameConfig.MAP_PATHS[&"map_a"]))
	if ResourceLoader.load_threaded_request(_map_path) != OK:
		_map_ready = true


func _tip() -> String:
	match Net.mode:
		GameConfig.Mode.RACE:
			return "The leader is the easiest monkey to catch. Everyone is chasing them."
		GameConfig.Mode.HOARD:
			return "A capuchin's dash steals bananas from whoever it passes through."
		GameConfig.Mode.SLAP:
			return "Your damage number climbs with every slap. Keep yours low and theirs high."
	return "Swing, release at the bottom, fly. Then do it again, faster."


func _card(id: int, entry: Dictionary) -> Control:
	var slot := int(entry["slot"])
	var tint := GameConfig.tint_for_index(slot)
	if Net.mode == GameConfig.Mode.SLAP:
		tint = GameConfig.TEAM_COLORS[GameConfig.team_of(slot)]
	var is_bot := bool(entry.get("bot", false))
	var is_you := id == Net.local_id()

	var card := PanelContainer.new()
	card.theme_type_variation = &"CardHighlight" if is_you else &"Glass"
	card.custom_minimum_size = Vector2(250 if Net.mode == GameConfig.Mode.SLAP else 270, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	card.add_child(box)

	var stripe := ColorRect.new()
	stripe.color = tint
	stripe.custom_minimum_size = Vector2(0, 8)
	box.add_child(stripe)

	var stage := MonkeyStage.new()
	stage.pixel_scale = 6
	stage.rim = tint
	stage.custom_minimum_size = Vector2(0, 300)
	box.add_child(stage)
	stage.set_monkey(StringName(entry["monkey"]))

	var stats := GameConfig.get_monkey(StringName(entry["monkey"]))
	var who := String(entry.get("name", ""))
	if who.is_empty():
		who = "YOU" if is_you else "PLAYER %d" % (slot + 1)
	var name_label := _centered(who.to_upper(), &"Display", 26)
	name_label.add_theme_color_override(&"font_color", tint.lightened(0.2))
	box.add_child(name_label)
	var tag := "AI · %s" % GameConfig.BOT_SKILL_NAMES[Net.bot_skill] if is_bot else stats.display_name
	box.add_child(_centered(tag.to_upper(), &"Subheading", 15))

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.custom_minimum_size = Vector2(0, 18)
	var fill := StyleBoxFlat.new()
	fill.bg_color = tint
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override(&"fill", fill)
	box.add_child(bar)
	var state := _centered("LOADING", &"Heading", 15)
	box.add_child(state)

	# Bots are quick; people are paced to land around the local bar.
	var rate := randf_range(1.2, 1.8) if is_bot else randf_range(0.42, 0.6)
	_bars[id] = {"bar": bar, "rate": rate, "value": 0.0, "label": state, "local": is_you}
	return card


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if not _map_ready:
		var status := ResourceLoader.load_threaded_get_status(_map_path)
		_map_ready = status != ResourceLoader.THREAD_LOAD_IN_PROGRESS

	var all_full := true
	for id in _bars.keys():
		var row: Dictionary = _bars[id]
		var target := minf(1.0, float(row["value"]) + delta * float(row["rate"]) * randf_range(0.4, 1.6))
		# Nobody finishes before the minimum time, and the local bar never
		# claims full while its own map is still loading.
		target = minf(target, _elapsed / MIN_SECONDS)
		if bool(row["local"]) and not _map_ready:
			target = minf(target, 0.92)
		row["value"] = target
		(row["bar"] as ProgressBar).value = target
		if target >= 1.0:
			(row["label"] as Label).text = "READY"
			(row["label"] as Label).add_theme_color_override(&"font_color", UiTheme.LEAF)
		else:
			all_full = false
	if all_full:
		_held += delta
		if _held >= HOLD_SECONDS:
			_done = true
			if not _map_path.is_empty() and ResourceLoader.load_threaded_get_status(_map_path) == ResourceLoader.THREAD_LOAD_LOADED:
				# Collect it so the arena's own load() is a cache hit.
				_map_resource = ResourceLoader.load_threaded_get(_map_path)
			finished.emit()


func _centered(text: String, variation: StringName, font_size: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font_size > 0:
		label.add_theme_font_size_override(&"font_size", font_size)
	return label
