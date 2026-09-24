extends RefCounted
## Writes a check's result to res://output/qa/<name>.log, so a run started
## from another machine can be read back after Godot has quit.

static func write(name: String, lines: PackedStringArray) -> void:
	DirAccess.make_dir_recursive_absolute("res://output/qa")
	var f := FileAccess.open("res://output/qa/%s.log" % name, FileAccess.WRITE)
	if f == null:
		return
	f.store_line(Time.get_datetime_string_from_system())
	for line in lines:
		f.store_line(line)
	f.close()
