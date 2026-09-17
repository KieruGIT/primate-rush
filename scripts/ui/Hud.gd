extends CanvasLayer

# ============================================================
# HUD - connection state, local monkey, and a state readout.
#
# The state readout stays in the shipped build. In a game with five movement
# states and no animation, "why did that happen" is answered by being able
# to see which state you were in.
# ============================================================

@onready var _title: Label = $Root/Top/Title
@onready var _info: Label = $Root/Top/Info

var _player: Player = null


func _ready() -> void:
	layer = 5


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _find_local_player()
		if _player == null:
			_title.text = "Monkey"
			_info.text = "waiting for spawn"
			return

	_title.text = "%s  #%d" % [_player.stats.display_name, _player.player_id]
	_info.text = "%s   %s   %s" % [_mode_text(), _state_text(_player.state), _speed_text()]


func _find_local_player() -> Player:
	var arena: Node = get_tree().get_first_node_in_group(&"arena")
	if arena == null:
		return null
	# Fetched by name rather than typed access: the HUD should not care what
	# arena script is running, only that it keeps a player table.
	var table: Variant = arena.get(&"players")
	if table is Dictionary:
		return table.get(Net.local_id()) as Player
	return null


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


func _speed_text() -> String:
	return "%d px/s" % int(_player.velocity.length())
