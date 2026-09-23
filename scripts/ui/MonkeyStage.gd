class_name MonkeyStage
extends Control

# ============================================================
# MONKEY STAGE - one big animated monkey standing on a pedestal.
#
# The home screen's centrepiece and the loading screen's player cards. The
# monkey is the same rig the arena uses, scaled up by a whole number so the
# pixels stay square, and it stands on the bottom-centre of this control
# whatever size a container gives it.
# ============================================================

## World pixels per art pixel. Whole numbers only, or the pixels go uneven.
@export var pixel_scale: int = 6
@export var pedestal: bool = true
## Slot colour for the pedestal rim. Clear means the menu's banana yellow.
@export var rim: Color = Color(0, 0, 0, 0)

var monkey_id: StringName = &""
var _sprite: MonkeySprite = null
var _locked: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	resized.connect(_place)


func set_monkey(id: StringName, locked: bool = false) -> void:
	monkey_id = id
	_locked = locked
	if _sprite == null:
		_sprite = MonkeySprite.new()
		add_child(_sprite)
	# Menus show the monkey facing you.
	_sprite.setup(id, true)
	# Low-detail art is already 3 atlas px per art px, so menus use a third
	# of the scale (whole numbers only) to keep the chunky pixels mock-sized.
	_sprite.scale = Vector2.ONE * float(maxi(1, roundi(pixel_scale / 2.0))) * float(MonkeySprite.MENU_SIZE.get(id, 1.0))
	# A locked monkey is a muted silhouette, but it must still read on the shop
	# card: showing the shape is the purchase pitch. Near-black disappeared into
	# the glass panel on dim phone screens and looked like a missing asset.
	_sprite.modulate = Color(0.34, 0.39, 0.35, 0.92) if locked else Color.WHITE
	_sprite.play(&"idle")
	_place()
	queue_redraw()


## Plays a pose on the stage monkey - a little hop when it is picked.
func cheer() -> void:
	if _sprite == null:
		return
	_sprite.play_for(&"cheer", 0.5)
	var tween := create_tween()
	var rest := _sprite.position
	tween.tween_property(_sprite, "position", rest + Vector2(0, -pixel_scale * 5.0), 0.14).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sprite, "position", rest, 0.16).set_ease(Tween.EASE_IN)



func _place() -> void:
	if _sprite != null:
		_sprite.position = Vector2(size.x * 0.5, size.y - (pixel_scale * 3.0 if pedestal else 0.0))
	queue_redraw()


func _draw() -> void:
	if not pedestal:
		return
	var center := Vector2(size.x * 0.5, size.y - pixel_scale * 3.0)
	var radius := Vector2(pixel_scale * 16.0, pixel_scale * 4.0)
	var edge: Color = rim if rim.a > 0.0 else UiTheme.BANANA
	_ellipse(center + Vector2(0, pixel_scale * 2.0), radius * 1.08, Color(0, 0, 0, 0.35))
	_ellipse(center + Vector2(0, pixel_scale * 1.2), radius, edge.darkened(0.45))
	_ellipse(center, radius, edge)
	_ellipse(center, radius * Vector2(0.9, 0.78), Color8(40, 64, 52))


func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		points.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	draw_colored_polygon(points, color)
