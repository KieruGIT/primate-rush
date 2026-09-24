extends Node

# ============================================================
# PROFILE - local career stats.
#
# The design doc is explicit that ranked comes last and that the game ships
# with casual lobbies and local stat tracking first. This is that tracking:
# a flat config file on this device, no account, no backend, no server to
# trust. When there is a backend, this becomes the thing it syncs, not the
# thing it replaces.
#
# Everything here records the local player only. Each machine writes its own
# career, which is also why none of it is authoritative for anything: these
# numbers decide nothing in a match.
# ============================================================

signal stats_changed

const PATH: String = "user://profile.cfg"
const SECTION: String = "career"

var data: Dictionary = {}


func _ready() -> void:
	_load()


func get_stat(key: String, fallback: Variant = 0) -> Variant:
	return data.get(key, fallback)


func set_stat(key: String, value: Variant) -> void:
	data[key] = value
	_save()


func bump(key: String, amount: int = 1) -> void:
	data[key] = int(data.get(key, 0)) + amount
	_save()


## Called once per finished race, on the machine of the player it describes.
func record_race(map_id: StringName, place: int, field_size: int, seconds: float, finished: bool) -> void:
	data["races"] = int(data.get("races", 0)) + 1
	if place == 1 and field_size > 1:
		data["race_wins"] = int(data.get("race_wins", 0)) + 1
	if finished:
		# Only a completed run sets a record. A "best time" you got by
		# falling off the map at the finish line is not a best time.
		var key := "best_%s" % map_id
		var previous := float(data.get(key, 0.0))
		if previous <= 0.0 or seconds < previous:
			data[key] = seconds
	_save()
	stats_changed.emit()


func record_hoard(place: int, field_size: int, score: int) -> void:
	data["hoards"] = int(data.get("hoards", 0)) + 1
	data["bananas"] = int(data.get("bananas", 0)) + score
	if place == 1 and field_size > 1:
		data["hoard_wins"] = int(data.get("hoard_wins", 0)) + 1
	_save()
	stats_changed.emit()


## Rank points never drop below zero: a bad evening costs progress, not a
## debt you have to climb out of before the bar moves again.
func record_ranked(delta: int) -> void:
	data["rp"] = maxi(int(data.get("rp", 0)) + delta, 0)
	data["rp_last"] = delta
	data["ranked_matches"] = int(data.get("ranked_matches", 0)) + 1
	_save()
	stats_changed.emit()


## Chosen look. The skin is per monkey (a golden gorilla and a snow gibbon
## at once); the accessory is one choice worn by whoever you pick.
func skin_for(monkey: StringName) -> StringName:
	return StringName(str(data.get("skin_%s" % monkey, "natural")))


func set_skin_for(monkey: StringName, skin: StringName) -> void:
	data["skin_%s" % monkey] = String(skin)
	_save()


func accessory() -> StringName:
	return StringName(str(data.get("hat", "none")))


func set_accessory(hat: StringName) -> void:
	data["hat"] = String(hat)
	_save()


func best_time(map_id: StringName) -> float:
	return float(data.get("best_%s" % map_id, 0.0))


func summary_line() -> String:
	var races := int(data.get("races", 0))
	var hoards := int(data.get("hoards", 0))
	if races == 0 and hoards == 0:
		return "No rounds played yet."
	var parts: PackedStringArray = [
		"%d races, %d won" % [races, int(data.get("race_wins", 0))],
		"%d hoards, %d won" % [hoards, int(data.get("hoard_wins", 0))],
		"%d bananas" % int(data.get("bananas", 0)),
		"%d hits landed, %d taken" % [int(data.get("hits_landed", 0)), int(data.get("hits_taken", 0))],
		"%d falls" % int(data.get("falls", 0)),
	]
	for map_id in GameConfig.map_ids():
		var best := best_time(map_id)
		if best > 0.0:
			parts.append("%s best %.2fs" % [GameConfig.MAP_NAMES.get(map_id, String(map_id)), best])
	return "   ".join(parts)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	if not cfg.has_section(SECTION):
		return
	for key in cfg.get_section_keys(SECTION):
		data[key] = cfg.get_value(SECTION, key)


func _save() -> void:
	var cfg := ConfigFile.new()
	for key in data.keys():
		cfg.set_value(SECTION, str(key), data[key])
	# Ignoring the error deliberately: a career file that cannot be written
	# is a bad day, not a reason to interrupt a match.
	cfg.save(PATH)
