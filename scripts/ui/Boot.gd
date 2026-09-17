extends Node

# ============================================================
# BOOT - scene router.
#
# The lobby and the arena are swapped in as children of a root that never
# unloads, instead of using change_scene_to_file. Changing the whole scene
# tree while ENet packets are in flight is how you get RPCs delivered to a
# node that no longer exists, and that failure looks like a netcode bug
# rather than a lifecycle one.
# ============================================================

const LOBBY_SCENE := preload("res://scenes/Lobby.tscn")
const ARENA_SCENE := preload("res://scenes/Main.tscn")

var _current: Node = null


func _ready() -> void:
	Net.match_started.connect(_show_arena)
	Net.match_ended.connect(_show_lobby)
	Net.server_disconnected.connect(_show_lobby)
	GameInput.pause_requested.connect(_on_pause_requested)
	_show_lobby()


func _show_lobby() -> void:
	_swap(LOBBY_SCENE)


## Swapped fresh every time, so a rematch is a clean arena rather than a
## pile of state left over from the round that just ended.
func _show_arena() -> void:
	_swap(ARENA_SCENE)


func _on_pause_requested() -> void:
	# Escape leaves the match rather than opening a menu. A pause menu is not
	# worth building for a demo where the round is the whole session.
	if _current != null and _current.is_in_group(&"arena"):
		Net.leave()
		_show_lobby()


func _swap(scene: PackedScene) -> Node:
	if _current != null:
		_current.queue_free()
		# Freed nodes linger until the end of the frame, so the old arena
		# would otherwise still answer group lookups the new one needs.
		remove_child(_current)
	_current = scene.instantiate()
	add_child(_current)
	return _current
