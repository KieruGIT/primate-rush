extends Node
## Dev only: exports the Android preset from outside the editor by running
## this same Godot binary headless. Output and log land in build/.
func _ready() -> void:
	var godot := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var apk := project + "/build/PrimateRush-v1.2.apk"
	var log := project + "/build/export-v1.2.log"
	var line := 'set "GRADLE_USER_HOME=D:\\.gradle" && "%s" --headless --path "%s" --export-debug "Android" "%s" > "%s" 2>&1 && echo EXPORT_OK >> "%s" || echo EXPORT_FAILED >> "%s"' % [godot, project, apk, log, log, log]
	var pid := OS.create_process("cmd.exe", ["/c", line])
	print("EXPORT started pid=", pid, " godot=", godot)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()
