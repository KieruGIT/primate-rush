class_name UiTheme
extends RefCounted

# ============================================================
# UI THEME - one Theme, built in code from the Kenney UI pack.
#
# Built in GDScript rather than saved as a .tres for the same reason the
# netcode avoids MultiplayerSynchronizer: a theme resource is a few hundred
# lines of scene text that no review can read, and every colour and margin in
# it is a decision worth seeing in a diff. Here the palette is a dozen
# constants at the top and every widget is four lines.
#
# Applied once to the root Window by Boot, which is the only node that
# outlives everything else, so the lobby and the arena share it without
# either one owning it.
#
# Every texture is loaded with a null guard. A missing asset must degrade to
# a plain rounded box, not take the game down before the lobby is on screen.
# ============================================================

const PACK := "res://assets/kenney_ui-pack/PNG"
# Low-detail design: the Primate Rush mock fonts (assets/fonts/FONTS.md).
const FONT_DISPLAY := "res://assets/fonts/PressStart2P.ttf"
const FONT_UI := "res://assets/fonts/PixelifySans-Bold.ttf"
const FONT_BODY := "res://assets/fonts/PixelifySans-Regular.ttf"

# --- Palette -------------------------------------------------------
# Primate Rush key art (output/ui-concepts/primate-rush-ui-v1.png): dark
# navy night, jade for "selected", gold for the thing to press, carved wood
# for navigation, mossy stone for frames. Chunky pixel blocks, not glossy.

const CANVAS := Color8(11, 16, 36)              # the screen behind everything
const PANEL := Color8(10, 14, 30)               # a card or a grouped block (mock #0a0e1e)
const PANEL_HI := Color8(22, 34, 74)            # inset box / selected (mock #16224a)
const NAVY_BTN := Color8(42, 51, 88)            # neutral button face (mock #2a3358)
const EDGE := Color8(30, 22, 18)                # low-detail mock: ink frame round every panel
const INK := Color8(244, 233, 207)              # primary text (cream)
const INK_DIM := Color8(159, 180, 232)          # secondary text (moon blue)
const INK_DARK := Color8(26, 15, 10)            # text on gold and on stone
const BANANA := Color8(255, 200, 58)            # primary action (gold)
const LEAF := Color8(69, 179, 107)              # selected, good news (jade)
const SKY := Color8(58, 123, 213)               # neutral action
const CORAL := Color8(224, 80, 74)              # leave, locked, bad news
const WOOD := Color8(138, 90, 46)               # carved-wood navigation
const OUTLINE := Color8(26, 15, 10)             # every edge (mock #1a0f0a)

# Pixel-art corners: nearly square, so boxes sit with the sprites.
const RADIUS := 0

## Face, lip (the darker 3D bottom) for each button colour the screens ask
## for. Names are the Kenney pack's, kept so no screen needs to change.
const BUTTON_COLORS := {
	"Yellow": [Color8(255, 200, 58), Color8(212, 138, 18)],
	"Green": [Color8(79, 154, 58), Color8(40, 96, 34)],
	"Blue": [Color8(42, 51, 88), Color8(28, 36, 68)],
	"Red": [Color8(224, 80, 74), Color8(150, 40, 38)],
	"Grey": [Color8(88, 94, 118), Color8(44, 48, 66)],
	"Sky": [Color8(58, 123, 213), Color8(36, 85, 158)],
	"Wood": [Color8(138, 90, 46), Color8(92, 58, 28)],
}

# Nine-patch margins for the pack's 192x64 rectangle buttons. The bottom is
# larger than the top because the "depth" variants carry a shadow lip there
# that must never be stretched.
const BTN_MARGIN_SIDE := 16
const BTN_MARGIN_TOP := 14
const BTN_MARGIN_BOTTOM := 18


## Boot applies the theme to the window. A screen run on its own (F6 in the
## editor) never goes through Boot, so each top-level screen calls this and
## gets the same look either way.
##
## Screens sit under Boot, a plain Node, and Godot does not pass a theme
## from the window through a non-Control parent. So the theme goes on each
## screen itself: on a Control directly, and on every Control child of a
## CanvasLayer (including ones added later).
static var _shared: Theme = null


static func shared() -> Theme:
	if _shared == null:
		_shared = build()
	return _shared


static func ensure(node: Node) -> void:
	var theme := shared()
	var window := node.get_window()
	if window != null and window.theme == null:
		window.theme = theme
	if node is Control:
		(node as Control).theme = theme
		return
	for child in node.get_children():
		if child is Control and (child as Control).theme == null:
			(child as Control).theme = theme
	if not node.child_entered_tree.is_connected(UiTheme._theme_child):
		node.child_entered_tree.connect(UiTheme._theme_child)


static func _theme_child(child: Node) -> void:
	if child is Control and (child as Control).theme == null:
		(child as Control).theme = shared()


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = _font(FONT_UI)
	theme.default_font_size = 16

	_build_labels(theme)
	_build_buttons(theme)
	_build_panels(theme)
	_build_inputs(theme)
	_build_bars(theme)
	_build_scroll(theme)
	return theme


# --- Text ----------------------------------------------------------

static func _build_labels(theme: Theme) -> void:
	theme.set_color(&"font_color", &"Label", INK)
	theme.set_font_size(&"font_size", &"Label", 16)
	theme.set_constant(&"line_spacing", &"Label", 4)

	# Variations rather than per-node overrides: a heading that changes size
	# should change everywhere at once, and a .tscn full of
	# theme_override_font_sizes is how that stops being true.
	_label_variation(theme, &"Title", _font(FONT_DISPLAY), 28, INK)
	_label_variation(theme, &"Heading", _font(FONT_UI), 20, BANANA)
	_label_variation(theme, &"Subheading", _font(FONT_UI), 16, INK_DIM)
	_label_variation(theme, &"Muted", null, 16, INK_DIM)
	_label_variation(theme, &"Value", _font(FONT_UI), 18, INK)
	# Sentences: control descriptions, tips, status lines. A pixel font at
	# 15 px turns "C" into "O" and "J" into "I", so running text gets a
	# plain, smooth sans instead.
	_label_variation(theme, &"Body", body_font(), 17, INK)

	# HUD text sits on top of the game, where the background is whatever the
	# level happens to be. An outline is the only thing that keeps it legible
	# over both a bright sky and a dark trunk.
	_label_variation(theme, &"HudLabel", _font(FONT_UI), 17, INK)
	_label_variation(theme, &"HudValue", _font(FONT_DISPLAY), 20, INK)
	_label_variation(theme, &"HudBig", _font(FONT_DISPLAY), 56, BANANA)
	# Menu text laid straight over the jungle backdrop, not on a card.
	_label_variation(theme, &"Display", _font(FONT_DISPLAY), 18, INK)
	_label_variation(theme, &"DisplayBig", _font(FONT_DISPLAY), 36, BANANA)
	for type in [&"HudLabel", &"HudValue", &"HudBig"]:
		theme.set_color(&"font_outline_color", type, Color(OUTLINE, 0.9))
		theme.set_constant(&"outline_size", type, 6)
	# Mock titles: no outline, a hard ink drop shadow on the pixel grid.
	for type in [&"Display", &"DisplayBig", &"Title"]:
		theme.set_color(&"font_shadow_color", type, OUTLINE)
		theme.set_constant(&"shadow_offset_x", type, 3)
		theme.set_constant(&"shadow_offset_y", type, 3)
	theme.set_color(&"font_shadow_color", &"DisplayBig", Color8(150, 78, 10))


static func _label_variation(theme: Theme, type: StringName, font: Font, size: int, color: Color) -> void:
	theme.add_type(type)
	theme.set_type_variation(type, &"Label")
	if font != null:
		theme.set_font(&"font", type, font)
	theme.set_font_size(&"font_size", type, size)
	theme.set_color(&"font_color", type, color)


# --- Buttons -------------------------------------------------------

static func _build_buttons(theme: Theme) -> void:
	_button_set(theme, &"Button", "Blue", INK, INK)
	theme.set_font(&"font", &"Button", _font(FONT_DISPLAY))
	_button_variation(theme, &"PrimaryButton", "Yellow", INK_DARK, 16)
	_button_variation(theme, &"DangerButton", "Red", Color.WHITE, 14)
	_button_variation(theme, &"QuietButton", "Wood", Color.WHITE, 13)
	# The one button a menu is built around. Big enough to find with a thumb
	# without looking, which on a phone is the only way anyone presses it.
	_button_variation(theme, &"PlayButton", "Yellow", INK_DARK, 28)
	_button_variation(theme, &"NavButton", "Wood", Color.WHITE, 15)
	_button_variation(theme, &"GoButton", "Yellow", INK_DARK, 18)
	_button_variation(theme, &"GreenButton", "Green", Color.WHITE, 15)
	_button_variation(theme, &"NavyButton", "Blue", INK, 14)
	# Mock buttons: dark ink type on gold, white type with an ink drop shadow
	# on every other colour. No outlines.
	for type in [&"Button", &"DangerButton", &"QuietButton", &"NavButton", &"GreenButton", &"NavyButton"]:
		theme.set_color(&"font_shadow_color", type, OUTLINE)
		theme.set_constant(&"shadow_offset_x", type, 2)
		theme.set_constant(&"shadow_offset_y", type, 2)
	_build_tiles(theme)

	# A choice sits unselected in neutral grey and selected in leaf green.
	# A toggle button draws its pressed box whenever it is on, so "selected"
	# and "being clicked" are the same drawing and cannot disagree.
	theme.add_type(&"ChoiceButton")
	theme.set_type_variation(&"ChoiceButton", &"Button")
	_button_set(theme, &"ChoiceButton", "Blue", INK, INK_DARK, "Yellow")
	theme.set_font_size(&"font_size", &"ChoiceButton", 12)


## Big picture cards for choosing a mode, a map, a difficulty. Dark glass at
## rest so white text reads on them; a thick banana border when chosen.
static func _build_tiles(theme: Theme) -> void:
	theme.add_type(&"TileButton")
	theme.set_type_variation(&"TileButton", &"Button")
	var rest := _flat(Color(PANEL, 0.88), EDGE, 18)
	var hover := _flat(Color(PANEL, 0.95), Color8(90, 100, 140), 18)
	var chosen := _flat(PANEL, BANANA, 18)
	chosen.set_border_width_all(4)
	var off := _flat(Color(PANEL, 0.45), Color(EDGE, 0.4), 18)
	theme.set_stylebox(&"normal", &"TileButton", rest)
	theme.set_stylebox(&"hover", &"TileButton", hover)
	theme.set_stylebox(&"pressed", &"TileButton", chosen)
	theme.set_stylebox(&"hover_pressed", &"TileButton", chosen)
	theme.set_stylebox(&"disabled", &"TileButton", off)
	theme.set_stylebox(&"focus", &"TileButton", _focus_box())
	for key in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		theme.set_color(key, &"TileButton", INK)


static func _button_variation(theme: Theme, type: StringName, color: String, ink: Color, size: int) -> void:
	theme.add_type(type)
	theme.set_type_variation(type, &"Button")
	_button_set(theme, type, color, ink, ink)
	theme.set_font_size(&"font_size", type, size)


## `color` is the resting colour and `on_color` the one used while held or,
## for a toggle, while selected. They are the same for ordinary buttons.
static func _button_set(theme: Theme, type: StringName, color: String, ink: Color, on_ink: Color, on_color: String = "") -> void:
	var held := on_color if not on_color.is_empty() else color
	var normal := _button_box(color, "depth_gloss")
	var tones: Array = BUTTON_COLORS.get(color, BUTTON_COLORS["Blue"])
	var hover := pixel_button((tones[0] as Color).lightened(0.1), tones[1])
	# Pressed drops the depth lip and pushes the text down by the height of
	# that lip, so the button reads as having physically gone in.
	var pressed := _button_box(held, "gloss")
	var disabled := pixel_button(Color8(52, 58, 80), Color8(34, 38, 56))

	theme.set_stylebox(&"normal", type, normal)
	theme.set_stylebox(&"hover", type, hover)
	theme.set_stylebox(&"pressed", type, pressed)
	theme.set_stylebox(&"hover_pressed", type, pressed)
	theme.set_stylebox(&"disabled", type, disabled)
	theme.set_stylebox(&"focus", type, _focus_box())

	theme.set_color(&"font_color", type, ink)
	theme.set_color(&"font_hover_color", type, ink)
	theme.set_color(&"font_pressed_color", type, on_ink)
	theme.set_color(&"font_hover_pressed_color", type, on_ink)
	theme.set_color(&"font_focus_color", type, ink)
	theme.set_color(&"font_disabled_color", type, Color(0.62, 0.65, 0.72, 0.8))
	theme.set_font_size(&"font_size", type, 14)
	theme.set_constant(&"h_separation", type, 10)


## Chunky pixel button: flat face, dark outline, a thick darker lip along
## the bottom for depth. "gloss" (pressed) drops the lip so it reads pushed.
static var _box_cache: Dictionary = {}


static func _button_box(color: String, style: String) -> StyleBox:
	var pair: Array = BUTTON_COLORS.get(color, BUTTON_COLORS["Blue"])
	return pixel_button(pair[0], pair[1], style == "gloss")


## Mock button, drawn as pixels: 3px ink outline, flat face, a light top
## edge and a darker lip along the bottom. Pressed drops the lip and pushes
## the label down, so it reads as physically pressed in. Nine-sliced, so
## any size keeps the same 3px edges.
static func pixel_button(face: Color, lip: Color, pressed: bool = false) -> StyleBoxTexture:
	var key := "%s|%s|%s" % [face.to_html(), lip.to_html(), pressed]
	if _box_cache.has(key):
		return _box_cache[key]
	var p := 3
	var size := 16 * p
	var lip_h := 0 if pressed else 2 * p
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(p, 0, size - 2 * p, size), OUTLINE)
	img.fill_rect(Rect2i(0, p, size, size - 2 * p), OUTLINE)
	img.fill_rect(Rect2i(p, p, size - 2 * p, size - 2 * p), lip)
	img.fill_rect(Rect2i(p, p, size - 2 * p, size - 2 * p - lip_h), face)
	if pressed:
		img.fill_rect(Rect2i(p, p, size - 2 * p, p), lip)
	else:
		img.fill_rect(Rect2i(p, p, size - 2 * p, p), face.lightened(0.3))
	var box := StyleBoxTexture.new()
	box.texture = ImageTexture.create_from_image(img)
	box.texture_margin_left = 2 * p
	box.texture_margin_right = 2 * p
	box.texture_margin_top = 2 * p
	box.texture_margin_bottom = 2 * p + lip_h
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.content_margin_top = 10.0 + (lip_h if pressed else 0) + (2 * p if pressed else 0)
	box.content_margin_bottom = 10.0 + lip_h
	_box_cache[key] = box
	return box


## Keyboard focus is drawn as an outline over the button rather than as a
## different button, so tabbing through never changes what a control looks
## like it does.
static func _focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = BANANA
	box.set_border_width_all(3)
	box.set_corner_radius_all(RADIUS)
	box.set_expand_margin_all(2.0)
	return box


# --- Panels --------------------------------------------------------

static func _build_panels(theme: Theme) -> void:
	theme.set_stylebox(&"panel", &"Panel", _flat(PANEL, EDGE))
	theme.set_stylebox(&"panel", &"PanelContainer", _flat(PANEL, EDGE))

	theme.add_type(&"Card")
	theme.set_type_variation(&"Card", &"PanelContainer")
	theme.set_stylebox(&"panel", &"Card", _flat(PANEL, EDGE, 18))

	theme.add_type(&"CardHighlight")
	theme.set_type_variation(&"CardHighlight", &"PanelContainer")
	var lit := _flat(PANEL_HI, BANANA, 18)
	lit.set_border_width_all(3)
	theme.set_stylebox(&"panel", &"CardHighlight", lit)

	# Glass: a card that lets the backdrop show through, for menus laid over
	# the jungle rather than over a flat colour.
	theme.add_type(&"Glass")
	theme.set_type_variation(&"Glass", &"PanelContainer")
	theme.set_stylebox(&"panel", &"Glass", _flat(Color(PANEL, 0.9), EDGE, 16))
	# Inset box inside a panel (mock hero card top, skill box).
	theme.add_type(&"Inset")
	theme.set_type_variation(&"Inset", &"PanelContainer")
	var inset := _flat(PANEL_HI, Color(0, 0, 0, 0), 0)
	theme.set_stylebox(&"panel", &"Inset", inset)

	# Overlays sit on top of the running game, so they need a background dark
	# enough to read against a bright level and no border to fight with it.
	theme.add_type(&"Overlay")
	theme.set_type_variation(&"Overlay", &"PanelContainer")
	theme.set_stylebox(&"panel", &"Overlay", _flat(Color(CANVAS, 0.88), EDGE, 14))


static func _flat(fill: Color, border: Color, radius: int = RADIUS) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(3 if border.a > 0.0 else 0)
	# The mock's faint cream inner line, as a 2px inset shadow-free border
	# would need a second box; a soft outer glow in ink keeps the edge crisp.
	box.shadow_color = Color(OUTLINE, 0.6) if border.a > 0.0 else Color(0, 0, 0, 0)
	box.shadow_size = 0
	box.shadow_offset = Vector2(3, 3)
	# Pixel look: the old 10-18px rounded glass becomes near-square blocks.
	box.set_corner_radius_all(mini(radius, RADIUS))
	box.anti_aliasing = false
	box.set_content_margin_all(14.0)
	return box


# --- Text fields and sliders ---------------------------------------

static func _build_inputs(theme: Theme) -> void:
	var field := _nine("%s/Extra/Default/input_rectangle.png" % PACK, 16, 14, 16, 14)
	if field == null:
		theme.set_stylebox(&"normal", &"LineEdit", _flat(PANEL_HI, EDGE))
	else:
		field.content_margin_left = 16.0
		field.content_margin_right = 16.0
		field.content_margin_top = 12.0
		field.content_margin_bottom = 12.0
		theme.set_stylebox(&"normal", &"LineEdit", field)
	theme.set_stylebox(&"focus", &"LineEdit", _focus_box())
	theme.set_color(&"font_color", &"LineEdit", INK_DARK)
	theme.set_color(&"font_placeholder_color", &"LineEdit", Color(0.42, 0.45, 0.50, 0.8))
	theme.set_color(&"caret_color", &"LineEdit", INK_DARK)
	theme.set_color(&"selection_color", &"LineEdit", Color(SKY.r, SKY.g, SKY.b, 0.45))
	theme.set_font_size(&"font_size", &"LineEdit", 16)

	var track := _flat(CANVAS, EDGE, 8)
	track.set_content_margin_all(0.0)
	track.content_margin_top = 6.0
	track.content_margin_bottom = 6.0
	theme.set_stylebox(&"slider", &"HSlider", track)
	var filled := _flat(LEAF, Color(0, 0, 0, 0), 8)
	filled.set_content_margin_all(0.0)
	theme.set_stylebox(&"grabber_area", &"HSlider", filled)
	theme.set_stylebox(&"grabber_area_highlight", &"HSlider", filled)
	var knob := _texture("%s/Blue/Default/slide_hangle.png" % PACK)
	if knob != null:
		theme.set_icon(&"grabber", &"HSlider", knob)
		theme.set_icon(&"grabber_highlight", &"HSlider", knob)
		theme.set_icon(&"grabber_disabled", &"HSlider", knob)

	var checked := _texture("%s/Green/Default/check_square_color_checkmark.png" % PACK)
	var unchecked := _texture("%s/Grey/Default/check_square_grey.png" % PACK)
	if checked != null and unchecked != null:
		theme.set_icon(&"checked", &"CheckBox", checked)
		theme.set_icon(&"unchecked", &"CheckBox", unchecked)
	theme.set_color(&"font_color", &"CheckBox", INK)


# --- Meters --------------------------------------------------------

static func _build_bars(theme: Theme) -> void:
	var back := _flat(CANVAS, EDGE, 6)
	back.set_content_margin_all(0.0)
	var fill := _flat(LEAF, Color(0, 0, 0, 0), 6)
	fill.set_content_margin_all(0.0)
	theme.set_stylebox(&"background", &"ProgressBar", back)
	theme.set_stylebox(&"fill", &"ProgressBar", fill)
	theme.set_color(&"font_color", &"ProgressBar", INK)

	# A stat bar is a progress bar with no number on it. The number is the
	# thing nobody reads; the length is the thing everybody reads.
	theme.add_type(&"StatBar")
	theme.set_type_variation(&"StatBar", &"ProgressBar")
	theme.set_stylebox(&"background", &"StatBar", back)
	theme.set_stylebox(&"fill", &"StatBar", fill)


# --- Scrolling -----------------------------------------------------

static func _build_scroll(theme: Theme) -> void:
	theme.set_stylebox(&"panel", &"ScrollContainer", StyleBoxEmpty.new())
	for axis in [&"VScrollBar", &"HScrollBar"]:
		var track := _flat(Color(CANVAS, 0.6), Color(0, 0, 0, 0), 6)
		track.set_content_margin_all(0.0)
		theme.set_stylebox(&"scroll", axis, track)
		var grab := _flat(EDGE, Color(0, 0, 0, 0), 6)
		grab.set_content_margin_all(0.0)
		theme.set_stylebox(&"grabber", axis, grab)
		var grab_lit := _flat(LEAF, Color(0, 0, 0, 0), 6)
		grab_lit.set_content_margin_all(0.0)
		theme.set_stylebox(&"grabber_highlight", axis, grab_lit)
		theme.set_stylebox(&"grabber_pressed", axis, grab_lit)


# --- Loading -------------------------------------------------------

static func _nine(path: String, left: int, top: int, right: int, bottom: int) -> StyleBoxTexture:
	var texture := _texture(path)
	if texture == null:
		return null
	var box := StyleBoxTexture.new()
	box.texture = texture
	box.texture_margin_left = left
	box.texture_margin_top = top
	box.texture_margin_right = right
	box.texture_margin_bottom = bottom
	return box


static func _texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("UI texture missing: %s" % path)
		return null
	return load(path) as Texture2D


static var _font_cache: Dictionary = {}
static var _body_font: Font = null


## A clean system sans for reading, smoothed rather than pixel-crisp. Named
## per platform: Segoe UI on Windows, Roboto on Android, then fallbacks.
static func body_font() -> Font:
	if _body_font == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Segoe UI", "Roboto", "Noto Sans", "Helvetica Neue", "Arial", "sans-serif"])
		font.font_weight = 600
		font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		font.hinting = TextServer.HINTING_LIGHT
		font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		_body_font = font
	return _body_font


## Pixel fonts, crisp: no antialiasing, no hinting, whole-pixel placement.
## A font the editor has not imported yet is read straight off disk.
static func _font(path: String) -> Font:
	if _font_cache.has(path):
		return _font_cache[path]
	var font: FontFile = null
	if ResourceLoader.exists(path):
		font = load(path) as FontFile
	if font == null and FileAccess.file_exists(path):
		font = FontFile.new()
		if font.load_dynamic_font(ProjectSettings.globalize_path(path)) != OK:
			font = null
	if font == null:
		push_warning("UI font missing: %s" % path)
		return null
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_font_cache[path] = font
	return font