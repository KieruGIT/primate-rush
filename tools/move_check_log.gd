extends "res://tools/move_check.gd"

## MoveCheck that also writes each verdict to output/qa-handoff/checks.log.
var _count: int = 0


func _check(label: String, ok: bool, detail: String) -> void:
	super(label, ok, detail)
	_count += 1
	CheckLog.line("MOVE %s  %s  %s" % ["ok  " if ok else "FAIL", label, detail])
	if _count == 9:
		CheckLog.line("MOVE CHECK %s" % ("OK" if _failures == 0 else "FAIL (%d)" % _failures))
