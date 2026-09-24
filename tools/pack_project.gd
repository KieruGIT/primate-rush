extends Node
## Dev only: zips the project source (scripts, scenes, assets, config) into
## output/project_src.zip so a build machine can export it. Skips caches,
## git, build output and assets nothing uses.

const SKIP := [".godot", ".git", ".gitops-local", ".claude", "output", "android", "build",
	"design_backup", "reference", "freegameassets", "docs", ".github", "_unused"]
var _count := 0


func _ready() -> void:
	var out := ProjectSettings.globalize_path("res://output/project_src.zip")
	var zip := ZIPPacker.new()
	if zip.open(out) != OK:
		print("PACK FAILED open")
		get_tree().quit(1)
		return
	_walk(zip, "res://")
	zip.close()
	print("PACK OK %d files" % _count)
	get_tree().quit()


func _walk(zip: ZIPPacker, dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = true
	for f in da.get_files():
		if f in ["secrets.cfg"] or f.ends_with(".apk") or f.ends_with(".zip") or f.ends_with(".bundle"):
			continue
		var path := dir.path_join(f)
		var bytes := FileAccess.get_file_as_bytes(path)
		zip.start_file(path.trim_prefix("res://"))
		zip.write_file(bytes)
		zip.close_file()
		_count += 1
	for d in da.get_directories():
		if d in SKIP:
			continue
		_walk(zip, dir.path_join(d))
