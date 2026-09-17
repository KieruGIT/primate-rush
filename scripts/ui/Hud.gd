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

var _player: Player = null
var _race: RaceDirector = null
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

	if _player == null or not is_instance_valid(_player):
		_title.text = "Monkey"
		_info.text = "waiting for spawn"
		return

	_title.text = "%s  #%d" % [_player.stats.display_name, _player.player_id]
	_info.text = "   ".join(_info_parts())


func _info_parts() -> PackedStringArray:
	var parts: PackedStringArray = [_mode_text(), _state_text(_player.state), "%d px/s" % int(_player.velocity.length())]
	if _race != null and _race.is_running():
		parts.append("%.1fs" % _race.elapsed)
		parts.append("place %d of %d" % [_live_place(), _field_size()])
	return parts


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


func _on_race_began() -> void:
	_center.text = "GO"
	_center_timer = GO_FLASH_SECONDS


func _on_player_finished(player_id: int, place: int, seconds: float) -> void:
	if player_id != Net.local_id():
		return
	_center.text = "FINISHED  %d%s  -  %.2fs" % [place, _ordinal_suffix(place), seconds]
	_center_timer = 3.0


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
