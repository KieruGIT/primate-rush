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
const FONT_DISPLAY := "res://assets/kenney_ui-pack/Font/Kenney Future.ttf"
const FONT_UI := "res://assets/kenney_ui-pack/Font/Kenney Future Narrow.ttf"

# --- Palette -------------------------------------------------------
# Jungle at night: dark green-black behind, warm banana for whatever the
# player should press first, leaf green for "this one is selected".

const CANVAS := Color(0.055, 0.078, 0.067)      # the screen behind everything
const PANEL := Color(0.098, 0.133, 0.114)       # a card or a grouped block
const PANEL_HI := Color(0.133, 0.180, 0.153)    # a card that is selected
const EDGE := Color(0.204, 0.278, 0.231)        # panel borders and dividers
const INK := Color(0.918, 0.945, 0.910)         # primary text
const INK_DIM := Color(0.596, 0.659, 0.616)     # secondary text
const INK_DARK := Color(0.157, 0.180, 0.129)    # text on yellow and on grey
const BANANA := Color(1.0, 0.800, 0.0)          # primary action
const LEAF := Color(0.278, 0.788, 0.478)        # selected, good news
const SKY := Color(0.243, 0.678, 0.898)         # neutral action
const CORAL := Color(0.941, 0.302, 0.376)       # leave, locked, bad news

# Corner radius shared by every flat box, so panels and bars visibly belong
# to the same set even though the buttons come from a texture pack.
const RADIUS := 10

# Nine-patch margins for the pack's 192x64 rectangle buttons. The bottom is
# larger than the top because the "depth" variants carry a shadow lip there
# that must never be stretched.
const BTN_MARGIN_SIDE := 16
const BTN_MARGIN_TOP := 14
const BTN_MARGIN_BOTTOM := 18


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
	_label_variation(theme, &"Title", _font(FONT_DISPLAY), 44, INK)
	_label_variation(theme, &"Heading", _font(FONT_UI), 20, BANANA)
	_label_variation(theme, &"Subheading", _font(FONT_UI), 14, INK_DIM)
	_label_variation(theme, &"Muted", null, 14, INK_DIM)
	_label_variation(theme, &"Value", _font(FONT_UI), 18, INK)

	# HUD text sits on top of the game, where the background is whatever the
	# level happens to be. An outline is the only thing that keeps it legible
	# over both a bright sky and a dark trunk.
	_label_variation(theme, &"HudLabel", _font(FONT_UI), 17, INK)
	_label_variation(theme, &"HudValue", _font(FONT_UI), 22, INK)
	_label_variation(theme, &"HudBig", _font(FONT_DISPLAY), 64, BANANA)
	# Menu text laid straight over the jungle backdrop, not on a card.
	_label_variation(theme, &"Display", _font(FONT_DISPLAY), 30, INK)
	_label_variation(theme, &"DisplayBig", _font(FONT_DISPLAY), 64, BANANA)
	for type in [&"HudLabel", &"HudValue", &"HudBig", &"Display", &"DisplayBig"]:
		theme.set_color(&"font_outline_color", type, Color(0.0, 0.0, 0.0, 0.85))
		theme.set_constant(&"outline_size", type, 8)


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
	_button_variation(theme, &"PrimaryButton", "Yellow", INK_DARK, 22)
	_button_variation(theme, &"DangerButton", "Red", INK, 18)
	_button_variation(theme, &"QuietButton", "Grey", INK_DARK, 16)
	# The one button a menu is built around. Big enough to find with a thumb
	# without looking, which on a phone is the only way anyone presses it.
	_button_variation(theme, &"PlayButton", "Yellow", Color.WHITE, 46)
	theme.set_font(&"font", &"PlayButton", _font(FONT_DISPLAY))
	_button_variation(theme, &"NavButton", "Blue", Color.WHITE, 22)
	_button_variation(theme, &"GoButton", "Green", Color.WHITE, 24)
	# Game buttons read like game buttons: white type with a thick dark
	# outline, legible on any colour of button and any background.
	for type in [&"PlayButton", &"NavButton", &"GoButton", &"DangerButton", &"PrimaryButton"]:
		theme.set_color(&"font_outline_color", type, Color(0.13, 0.11, 0.10))
		theme.set_constant(&"outline_size", type, 10 if type == &"PlayButton" else 7)
	theme.set_color(&"font_color", &"PrimaryButton", Color.WHITE)
	theme.set_color(&"font_hover_color", &"PrimaryButton", Color.WHITE)
	theme.set_color(&"font_pressed_color", &"PrimaryButton", Color.WHITE)
	theme.set_color(&"font_hover_pressed_color", &"PrimaryButton", Color.WHITE)
	theme.set_color(&"font_focus_color", &"PrimaryButton", Color.WHITE)
	_build_tiles(theme)

	# A choice sits unselected in neutral grey and selected in leaf green.
	# A toggle button draws its pressed box whenever it is on, so "selected"
	# and "being clicked" are the same drawing and cannot disagree.
	theme.add_type(&"ChoiceButton")
	theme.set_type_variation(&"ChoiceButton", &"Button")
	_button_set(theme, &"ChoiceButton", "Grey", INK_DARK, INK, "Green")
	theme.set_font_size(&"font_size", &"ChoiceButton", 16)


## Big picture cards for choosing a mode, a map, a difficulty. Dark glass at
## rest so white text reads on them; a thick banana border when chosen.
static func _build_tiles(theme: Theme) -> void:
	theme.add_type(&"TileButton")
	theme.set_type_variation(&"TileButton", &"Button")
	var rest := _flat(Color(0.04, 0.08, 0.07, 0.78), Color(1, 1, 1, 0.16), 18)
	var hover := _flat(Color(0.07, 0.12, 0.10, 0.85), Color(1, 1, 1, 0.3), 18)
	var chosen := _flat(PANEL_HI, BANANA, 18)
	chosen.set_border_width_all(5)
	var off := _flat(Color(0.04, 0.06, 0.05, 0.45), Color(1, 1, 1, 0.08), 18)
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
	var hover := _button_box(color, "depth_gloss")
	hover.modulate_color = Color(1.14, 1.14, 1.14)
	# Pressed drops the depth lip and pushes the text down by the height of
	# that lip, so the button reads as having physically gone in.
	var pressed := _button_box(held, "gloss")
	pressed.content_margin_top = 18.0
	pressed.content_margin_bottom = 14.0
	var disabled := _button_box("Grey", "depth_flat")
	disabled.modulate_color = Color(1.0, 1.0, 1.0, 0.55)

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
	theme.set_color(&"font_disabled_color", type, Color(0.62, 0.65, 0.60, 0.7))
	theme.set_font_size(&"font_size", type, 18)
	theme.set_constant(&"h_separation", type, 10)


static func _button_box(color: String, style: String) -> StyleBox:
	var texture := _texture("%s/%s/Default/button_rectangle_%s.png" % [PACK, color, style])
	if texture == null:
		return _flat(PANEL_HI, EDGE)
	var box := StyleBoxTexture.new()
	box.texture = texture
	box.texture_margin_left = BTN_MARGIN_SIDE
	box.texture_margin_right = BTN_MARGIN_SIDE
	box.texture_margin_top = BTN_MARGIN_TOP
	box.texture_margin_bottom = BTN_MARGIN_BOTTOM
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 12.0
	box.content_margin_bottom = 20.0
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
	theme.set_stylebox(&"panel", &"Glass", _flat(Color(0.03, 0.06, 0.05, 0.62), Color(1, 1, 1, 0.12), 16))

	# Overlays sit on top of the running game, so they need a background dark
	# enough to read against a bright level and no border to fight with it.
	theme.add_type(&"Overlay")
	theme.set_type_variation(&"Overlay", &"PanelContainer")
	theme.set_stylebox(&"panel", &"Overlay", _flat(Color(0.031, 0.047, 0.039, 0.82), Color(0, 0, 0, 0), 14))


static func _flat(fill: Color, border: Color, radius: int = RADIUS) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2 if border.a > 0.0 else 0)
	box.set_corner_radius_all(radius)
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

	var track := _flat(Color(0.04, 0.06, 0.05), EDGE, 8)
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
	var back := _flat(Color(0.04, 0.06, 0.05), EDGE, 6)
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
		var track := _flat(Color(0.04, 0.06, 0.05, 0.6), Color(0, 0, 0, 0), 6)
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


static func _font(path: String) -> Font:
	if not ResourceLoader.exists(path):
		push_warning("UI font missing: %s" % path)
		return null
	return load(path) as Font
