extends Node
## One-off: moves asset packs and code the low-detail game never loads into
## _unused/ (ignored by Godot and git), so exports and git stay lean. Moving
## instead of deleting keeps everything recoverable.

const ROOT := "res://"
const MOVE := [
	"assets/opp_jungle",
	"assets/freegameassets",
	"assets/environment/approved",
	"assets/monkeys/crisp",
	"assets/monkeys/locked",
	"assets/monkeys/gorilla",
	"assets/monkeys/capuchin",
	"assets/monkeys/gibbon",
	"assets/monkeys/macaque",
	"assets/monkeys/orangutan",
	"assets/monkeys/macaque_moss",
	"assets/monkeys/macaque_rose",
	"assets/kenney_ui-pack",
	"assets/kenney_sounds/ui_switch_002.ogg",
	"assets/kenney_sounds/ui_switch_002.ogg.import",
	"scripts/world/OppSkin.gd",
	"scripts/world/OppSkin.gd.uid",
	"tools/art_mock.gd",
	"tools/art_mock.gd.uid",
	"tools/ArtMock.tscn",
]
## The only files the game uses from the Kenney UI pack: put back after the
## pack is moved out.
const KEEP_FROM_UI_PACK := [
	"PNG/Extra/Default/input_rectangle.png",
	"PNG/Blue/Default/slide_hangle.png",
	"PNG/Green/Default/check_square_color_checkmark.png",
	"PNG/Grey/Default/check_square_grey.png",
	"License.txt",
]

var _log: PackedStringArray = []


func _ready() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	var trash := root.path_join("_unused")
	DirAccess.make_dir_recursive_absolute(trash)
	var marker := FileAccess.open(trash.path_join(".gdignore"), FileAccess.WRITE)
	if marker != null:
		marker.close()
	for rel in MOVE:
		var from := root.path_join(rel)
		if not (DirAccess.dir_exists_absolute(from) or FileAccess.file_exists(from)):
			_log.append("skip (not there) %s" % rel)
			continue
		var to := trash.path_join(rel)
		DirAccess.make_dir_recursive_absolute(to.get_base_dir())
		var err := DirAccess.rename_absolute(from, to)
		_log.append("%s %s" % ["moved" if err == OK else "FAILED %d" % err, rel])
	var pack_from := trash.path_join("assets/kenney_ui-pack")
	var pack_to := root.path_join("assets/kenney_ui-pack")
	for rel in KEEP_FROM_UI_PACK:
		for suffix in ["", ".import"]:
			var src: String = pack_from.path_join(rel) + suffix
			if not FileAccess.file_exists(src):
				continue
			var dst: String = pack_to.path_join(rel) + suffix
			DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
			var err := DirAccess.copy_absolute(src, dst)
			_log.append("%s kenney_ui-pack/%s%s" % ["kept" if err == OK else "COPY FAILED %d" % err, rel, suffix])
	var f := FileAccess.open("res://output/qa-handoff/checks.log", FileAccess.READ_WRITE)
	if f != null:
		f.seek_end()
		for line in _log:
			f.store_line("%s  DEBLOAT %s" % [Time.get_datetime_string_from_system(), line])
		f.close()
	for line in _log:
		print("DEBLOAT ", line)
	get_tree().quit()
