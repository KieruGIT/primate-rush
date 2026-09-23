extends "res://tools/climb_check.gd"

## ClimbCheck that also writes its verdict to output/qa-handoff/checks.log.


func _physics_process(delta: float) -> void:
	if _ticks == 419:
		var climbed := _start_y - _best_y
		var ok := _grabbed_trunk and climbed > 250.0
		CheckLog.line("CLIMB grabbed=%s climbed=%.0f  CLIMB CHECK %s" % [_grabbed_trunk, climbed, "OK" if ok else "FAIL"])
	super(delta)
