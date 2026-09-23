extends "res://tools/smoke_test.gd"

const CheckLog = preload("res://tools/check_log.gd")

# Smoke test that also writes its verdict to
# output/monkey-animation-prototype/integration/smoke-crisp.log, for runs
# launched without a console to read.


func _report() -> void:
	super()
	var lines: PackedStringArray = ["--- smoke results ---"]
	for note in _notes:
		lines.append("  " + note)
	lines.append("SMOKE OK" if _failures.is_empty() else "SMOKE FAILURES:")
	for failure in _failures:
		lines.append("  - " + failure)
	for l in lines:
		CheckLog.line("SMOKE " + l)
	var path := ProjectSettings.globalize_path("res://output/monkey-animation-prototype/integration/smoke-crisp.log")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines) + "\n")
