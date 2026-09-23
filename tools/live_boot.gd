extends Node

# LIVE BOOT - dev only. Runs the real Boot flow (splash -> menu) exactly as
# the game starts, then saves what the window shows to
# output/qa-handoff/shots/live_menu.png. Catches theme problems that the
# capture tool hides, because it themes screens itself.

func _ready() -> void:
	add_child((load("res://scenes/Boot.tscn") as PackedScene).instantiate())
	await get_tree().create_timer(7.0).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://output/qa-handoff/shots/live_menu.png"))
	get_tree().quit()
