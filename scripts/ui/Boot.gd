extends Node

# ============================================================
# BOOT - scene router, and the one owner of the UI theme.
#
# The lobby and the arena are swapped in as children of a root that never
# unloads, instead of using change_scene_to_file. Changing the whole scene
# tree while ENet packets are in flight is how you get RPCs delivered to a
# node that no longer exists, and that failure looks like a netcode bug
# rather than a lifecycle one.
#
# The theme is applied to the root Window rather than to each screen. Godot
# inherits a theme down the whole tree from there, so a lobby, an arena HUD
# and a pause overlay spawned three different ways all pick it up without
# any of them holding a reference to it.
# ============================================================

const SPLASH_SCENE := preload("res://scenes/Splash.tscn")
const MENU_SCENE := preload("res://scenes/Menu.tscn")
const LOADING_SCENE := preload("res://scenes/MatchLoading.tscn")
const ARENA_SCENE := preload("res://scenes/Main.tscn")

var _current: Node = null


func _ready() -> void:
	_apply_theme()
	Net.match_started.connect(_show_loading)
	Net.match_ended.connect(_show_menu)
	Net.server_disconnected.connect(_show_menu)
	var splash := _swap(SPLASH_SCENE)
	splash.connect(&"finished", _show_menu)


func _apply_theme() -> void:
	get_window().theme = UiTheme.build()
	# Every button in the game clicks, including ones built at runtime by the
	# lobby and the results screen. Connecting here rather than at each call
	# site means a button added later is audible without anyone remembering.
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().root.find_children("*", "BaseButton", true, false):
		_on_node_added(node)


func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	if button == null or button.pressed.is_connected(_on_any_button):
		return
	button.pressed.connect(_on_any_button)
	# Every button squishes when pressed and springs back, the small bit of
	# give that makes a phone game's buttons feel like buttons.
	button.button_down.connect(_squish.bind(button, 0.93, 0.06))
	button.button_up.connect(_squish.bind(button, 1.0, 0.18))


func _squish(button: BaseButton, to: float, seconds: float) -> void:
	if not is_instance_valid(button) or not button.is_inside_tree():
		return
	button.pivot_offset = button.size * 0.5
	var tween := button.create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * to, seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_any_button() -> void:
	Sfx.play(&"ui_click")


func _show_menu() -> void:
	_swap(MENU_SCENE)


## Every seat's card fills before the round, on every machine. See
## MatchLoading for what the bars actually measure.
func _show_loading() -> void:
	var loading := _swap(LOADING_SCENE)
	loading.connect(&"finished", _show_arena)


## Swapped fresh every time, so a rematch is a clean arena rather than a
## pile of state left over from the round that just ended.
func _show_arena() -> void:
	_swap(ARENA_SCENE)


func _swap(scene: PackedScene) -> Node:
	if _current != null:
		_current.queue_free()
		# Freed nodes linger until the end of the frame, so the old arena
		# would otherwise still answer group lookups the new one needs.
		remove_child(_current)
	_current = scene.instantiate()
	add_child(_current)
	return _current
