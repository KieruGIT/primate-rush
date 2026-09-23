extends "res://tools/capture_ui.gd"

# ============================================================
# CRISP CAPTURE - dev only. The real screens (arena, a live punch, the
# monkey picker, home) captured through capture_ui.gd, but with a fixed
# output folder so it runs as a plain scene launch with no arguments.
#   output/qa-handoff/shots/shot_<key>.png
# ============================================================

const CRISP_SHOTS := ["game_a", "game_b", "game_c", "slap_demo", "home", "monkeys", "play_ai", "results"]


func _ready() -> void:
	var out := ProjectSettings.globalize_path("res://output/qa-handoff/shots")
	DirAccess.make_dir_recursive_absolute(out)
	for key in CRISP_SHOTS:
		await _shoot(key, String(SHOTS[key]), out)
	get_tree().quit()
