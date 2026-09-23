class_name CheckLog
extends RefCounted

## Appends check lines to output/qa-handoff/checks.log so runs launched
## without a console still leave a verdict behind.
const PATH := "res://output/qa-handoff/checks.log"


static func line(text: String) -> void:
	var path := ProjectSettings.globalize_path(PATH)
	var file := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line("%s  %s" % [Time.get_datetime_string_from_system(), text])
