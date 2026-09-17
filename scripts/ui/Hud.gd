extends CanvasLayer

# ============================================================
# HUD - connection state, monkey, movement state, race state.
#
# The movement state readout stays in the shipped build. In a game with five
# states and no animation yet, "why did that happen" is only answerable if
# you can see which state you were in when it happened.
# ============================================================

const GO_FLASH_SECONDS: float = 0.9

@onready var _title: Label = %Title
@onready var _info: Label = %Info
@onready var _center: Label = %Center
@onready var _board: Label = %Board

var _player: Player = null
var _race: RaceDirector = null
var _hoard: HoardDirector = null
var _center_timer: float = 0.0


func _ready() -> void:
	layer = 5
	_center.text = ""


func _process(delta: float) -> void:
	_bind()

	if _center_timer > 0.0:
		_center_timer -= delta
		if _center_timer <= 0.0:
			_center.text = ""

	_update_board()

	if _player == null or not is_instance_valid(_player):
		_title.text = "Monkey"
		_info.text = "waiting for spawn"
		return

	_title.text = "%s  #%d" % [_player.stats.display_name, _player.player_id]
	_info.text = "   ".join(_info_parts())


func _info_parts() -> PackedStringArray:
	var parts: PackedStringArray = [_mode_text(), _state_text(_player.state), "%d px/s" % int(_player.velocity.length()), _skill_text()]
	if _race != null and _race.is_running():
		parts.append("%.1fs" % _race.elapsed)
		parts.append("place %d of %d" % [_live_place(), _field_size()])
	if _hoard != null and _hoard.is_running():
		parts.append("%d bananas" % _player.bananas)
		parts.append("%d:%02d left" % [int(_hoard.time_left) / 60, int(_hoard.time_left) % 60])
		if _player.ability != &"":
			parts.append("%s %.1fs" % [String(_player.ability).replace("_", " "), _player.ability_timer])
	return parts


## Live standings. Sorted every frame rather than cached, because both
## orders change constantly: that is what hitting people is for.
func _update_board() -> void:
	var rows := _board_rows()
	if rows.is_empty():
		_board.text = ""
		return
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["sort"] > b["sort"])
	var lines: PackedStringArray = []
	for index in rows.size():
		var row: Dictionary = rows[index]
		lines.append("%d. %s  %s" % [index + 1, row["name"], row["detail"]])
	_board.text = "\n".join(lines)


func _board_rows() -> Array:
	var arena: Node = get_tree().get_first_node_in_group(&"arena")
	if arena == null:
		return []
	var table: Variant = arena.get(&"players")
	if not (table is Dictionary):
		return []
	var hoard_running := _hoard != null and _hoard.is_running()
	var race_running := _race != null and _race.is_running()
	if not hoard_running and not race_running:
		return []

	var rows: Array = []
	for id in (table as Dictionary).keys():
		var player := (table as Dictionary)[id] as Player
		if player == null:
			continue
		var label: String = player.display_label()
		if int(id) == Net.local_id():
			label += " (you)"
		if hoard_running:
			rows.append({"name": label, "sort": float(player.bananas), "detail": "%d" % player.bananas})
		else:
			var progress := _race.progress_of(int(id))
			rows.append({"name": label, "sort": progress, "detail": ""})
	return rows


func _skill_text() -> String:
	if _player.stats.skill_id == &"":
		return "no skill"
	var label := String(_player.stats.skill_id).replace("_", " ")
	if _player.skill_timer > 0.0:
		return "%s %.1fs" % [label, _player.skill_timer]
	return "%s ready" % label


func _bind() -> void:
	var arena: Node = get_tree().get_first_node_in_group(&"arena")
	if arena == null:
		_player = null
		_race = null
		return

	if _player == null or not is_instance_valid(_player):
		var table: Variant = arena.get(&"players")
		if table is Dictionary:
			_player = table.get(Net.local_id()) as Player

	if _race == null or not is_instance_valid(_race):
		_race = arena.get(&"race") as RaceDirector
		if _race != null:
			_race.countdown_changed.connect(_on_countdown)
			_race.race_began.connect(_on_race_began)
			_race.player_finished.connect(_on_player_finished)

	if _hoard == null or not is_instance_valid(_hoard):
		_hoard = arena.get(&"hoard") as HoardDirector
		if _hoard != null:
			_hoard.countdown_changed.connect(_on_countdown)
			_hoard.hoard_began.connect(_on_race_began)


## Live placement is recomputed rather than stored: it changes every time
## anyone gets knocked backwards, which is the entire point of hitting people.
func _live_place() -> int:
	if _race == null or _player == null:
		return 1
	var mine := _race.progress_of(_player.player_id)
	var arena: Node = get_tree().get_first_node_in_group(&"arena")
	var table: Variant = arena.get(&"players") if arena != null else null
	if not (table is Dictionary):
		return 1
	var ahead := 1
	for id in table.keys():
		if int(id) == _player.player_id:
			continue
		if _race.progress_of(int(id)) > mine:
			ahead += 1
	return ahead


func _field_size() -> int:
	var arena: Node = get_tree().get_first_node_in_group(&"arena")
	if arena == null:
		return 1
	var table: Variant = arena.get(&"players")
	return (table as Dictionary).size() if table is Dictionary else 1


func _on_countdown(value: int) -> void:
	_center.text = str(value) if value > 0 else "GO"
	_center_timer = GO_FLASH_SECONDS if value <= 0 else 2.0
	Sfx.play(&"beep" if value > 0 else &"go")


func _on_race_began() -> void:
	_center.text = "GO"
	_center_timer = GO_FLASH_SECONDS
	Sfx.play(&"go")


func _on_player_finished(player_id: int, place: int, seconds: float) -> void:
	if player_id != Net.local_id():
		return
	_center.text = "FINISHED  %d%s  -  %.2fs" % [place, _ordinal_suffix(place), seconds]
	_center_timer = 3.0
	Sfx.play(&"finish")


func _ordinal_suffix(place: int) -> String:
	match place:
		1:
			return "st"
		2:
			return "nd"
		3:
			return "rd"
	return "th"


func _mode_text() -> String:
	if not Net.is_online():
		return "local"
	return "host %d players" % Net.roster.size() if Net.is_host() else "client"


func _state_text(state: int) -> String:
	match state:
		Player.State.GROUND:
			return "ground"
		Player.State.AIR:
			return "air"
		Player.State.CLIMB:
			return "climb"
		Player.State.SWING:
			return "swing"
		Player.State.STUN:
			return "stunned"
	return "?"
