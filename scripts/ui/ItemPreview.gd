extends Control

# ============================================================
# ITEM PREVIEW - a live little picture of one shop or gacha item.
#
# Effects play for real, looped inside the box: a trail circles, a punch or
# climb effect bursts every second, a win effect rains down. Skins show a
# monkey wearing them, hats sit on a head. So a reward is something you see,
# not a line of text.
# ============================================================

const COSMETIC_FX = preload("res://scripts/player/CosmeticFx.gd")
const BANANA_ICON = preload("res://scripts/ui/BananaIcon.gd")

var item_id: StringName = &""
var _t: float = 0.0
var _clock: float = 0.0
var _trail: CPUParticles2D = null
var _host: Node2D = null


func _init(id: StringName = &"", min_size: Vector2 = Vector2(96, 96)) -> void:
	item_id = id
	custom_minimum_size = min_size
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	_host = Node2D.new()
	add_child(_host)
	var entry: Dictionary = Loot.item(item_id)
	var slot: StringName = entry.get("slot", &"")
	match slot:
		&"trail":
			_trail = COSMETIC_FX._make_trail(item_id)
			_trail.position = Vector2.ZERO
			_host.add_child(_trail)
		&"skin":
			var stage := MonkeyStage.new()
			stage.pixel_scale = 2
			stage.pedestal = false
			stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			add_child(stage)
			stage.set_monkey(&"gorilla", false, entry.get("look", &"natural"))
		&"hat":
			var hat := Headwear.new()
			var info: Dictionary = GameConfig.get_hat(entry.get("look", &"none"))
			hat.apply(info["style"], info["color"], 36.0)
			hat.name = "Hat"
			_host.add_child(hat)
		&"win":
			_play_win()


func _process(delta: float) -> void:
	_t += delta
	var entry: Dictionary = Loot.item(item_id)
	var slot: StringName = entry.get("slot", &"")
	var centre := size * 0.5
	match slot:
		&"trail":
			# Round and round, so the trail streams behind a moving point.
			var at := centre + Vector2(cos(_t * 4.0), sin(_t * 4.0) * 0.6) * size * 0.28
			var before := _trail.position
			_trail.position = at
			_trail.direction = (before - at).normalized() if before != at else Vector2.LEFT
		&"punch", &"climb":
			_clock -= delta
			if _clock <= 0.0:
				_clock = 0.9
				COSMETIC_FX.burst(_host, item_id, global_position + centre)
		&"win":
			_clock -= delta
			if _clock <= -2.6:
				_clock = 0.0
				_play_win()
		&"hat":
			var hat := _host.get_node_or_null("Hat") as Node2D
			if hat != null:
				hat.position = Vector2(centre.x, centre.y - 4.0)
	queue_redraw()


func _play_win() -> void:
	for child in _host.get_children():
		child.queue_free()
	COSMETIC_FX.play_win(_host, item_id, size)


func _draw() -> void:
	var entry: Dictionary = Loot.item(item_id)
	if entry.get("slot", &"") == &"hat":
		# A plain head under the hat.
		var c := size * 0.5
		draw_rect(Rect2(c + Vector2(-18, -4), Vector2(36, 32)), Color(0.45, 0.30, 0.20))
		draw_rect(Rect2(c + Vector2(-13, 6), Vector2(26, 18)), Color(0.85, 0.68, 0.52))
		draw_rect(Rect2(c + Vector2(-9, 11), Vector2(5, 5)), Color(0.1, 0.07, 0.05))
		draw_rect(Rect2(c + Vector2(4, 11), Vector2(5, 5)), Color(0.1, 0.07, 0.05))
