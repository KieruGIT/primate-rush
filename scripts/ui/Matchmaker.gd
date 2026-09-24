extends Node

# ============================================================
# MATCHMAKER - what PLAY does in Classic and Ranked.
#
#   1. LISTEN   a couple of seconds listening for an open room on this
#               network with the same queue and mode. Found one: join it.
#   2. HOSTING  nobody out there, so open our own room and advertise it.
#               Anyone searching now joins us. If another searcher opened
#               a room at the same moment, the one with the higher address
#               folds into the lower one, so the two never sit apart.
#   3. START    the room fills to four, or the wait runs out. Empty seats
#               become AI and the match starts for everyone in it.
#
# LAN only, like the rest of the netcode: there is no server on the internet
# to meet strangers through. Players on the same wifi find each other; with
# nobody around, PLAY still starts a match within a few seconds, against AI.
# ============================================================

signal changed

enum Stage { IDLE, LISTEN, JOINING, JOINED, HOSTING, STARTING, PICKING }

## Once the room is settled everyone gets this long to choose a monkey.
const PICK_SECONDS: float = 10.0

const JOIN_TIMEOUT: float = 5.0

var stage: int = Stage.IDLE
## Seconds until the match starts with AI in the empty seats.
var time_left: float = 0.0
var status: String = ""

var _listen_left: float = 0.0
var _join_left: float = 0.0
## Seconds left in the monkey pick.
var pick_left: float = 0.0


func _ready() -> void:
	Net.connection_failed.connect(_on_join_failed)
	Net.roster_changed.connect(_on_roster_changed)
	Net.pick_started.connect(_on_pick_started)


func is_active() -> bool:
	return stage != Stage.IDLE


func people() -> int:
	if not Net.is_online():
		return 1
	var count := 0
	for id in Net.roster.keys():
		if int(id) > 0:
			count += 1
	return maxi(count, 1)


func begin() -> void:
	Net.leave()
	Discovery.stop_advertising()
	Discovery.start_listening()
	stage = Stage.LISTEN
	_listen_left = randf_range(GameConfig.MATCH_LISTEN_SECONDS.x, GameConfig.MATCH_LISTEN_SECONDS.y)
	time_left = _listen_left + GameConfig.MATCH_WAIT_SECONDS
	_say("Looking for players nearby...")


func cancel() -> void:
	if stage == Stage.IDLE:
		return
	stage = Stage.IDLE
	Net.leave()
	Discovery.stop_advertising()
	Discovery.start_listening()
	_say("")


func _process(delta: float) -> void:
	match stage:
		Stage.LISTEN:
			_listen_left -= delta
			time_left = maxf(time_left - delta, 0.0)
			var ip := Discovery.open_room(Net.queue, Net.mode)
			if not ip.is_empty():
				_join(ip)
			elif _listen_left <= 0.0 or not Discovery.is_listening():
				_host()
			changed.emit()
		Stage.JOINING:
			_join_left -= delta
			if _join_left <= 0.0:
				_host()
			changed.emit()
		Stage.JOINED:
			changed.emit()
		Stage.PICKING:
			pick_left = maxf(pick_left - delta, 0.0)
			changed.emit()
			# The host (or a solo player) starts when time is up. A client
			# waits for the host's start, which frees this menu.
			if pick_left <= 0.0 and (not Net.is_online() or Net.is_host()):
				stage = Stage.STARTING
				Net.start_match()
		Stage.HOSTING:
			time_left = maxf(time_left - delta, 0.0)
			var found := people()
			if found == 1:
				# Two searchers that both gave up listening at once each opened
				# a room. The higher address folds into the lower one.
				var other := Discovery.open_room(Net.queue, Net.mode)
				if not other.is_empty() and Discovery.address_less(other, Net.local_ip_hint()):
					_join(other)
					return
			if found >= GameConfig.NET_MAX_PLAYERS or time_left <= 0.0:
				_start()
			changed.emit()


func _join(ip: String) -> void:
	Net.searching = false
	Discovery.stop_advertising()
	var error := Net.join_game(ip, GameConfig.NET_DEFAULT_PORT)
	if not error.is_empty():
		_host()
		return
	stage = Stage.JOINING
	_join_left = JOIN_TIMEOUT
	_say("Found a room, joining...")


func _host() -> void:
	Net.leave()
	var error := Net.host_game()
	if not error.is_empty():
		# The port is taken (usually another copy of the game on this
		# machine). Nobody can join us, so skip straight to the AI match.
		_start()
		return
	Net.searching = true
	Discovery.start_advertising(true)
	Discovery.start_listening()
	stage = Stage.HOSTING
	_say("Waiting for players to join...")


## Skips the search: a party that is already full of friends goes straight
## to the monkey pick.
func start_now() -> void:
	_start()


## Everyone chooses early: end the pick now. Only the host (or solo) can.
func finish_pick() -> void:
	if stage == Stage.PICKING and (not Net.is_online() or Net.is_host()):
		pick_left = 0.0


func _start() -> void:
	stage = Stage.STARTING
	Net.searching = false
	var found := people()
	_say("Starting with %d player%s + AI" % [found, "" if found == 1 else "s"] if found < GameConfig.NET_MAX_PLAYERS else "Room full, starting!")
	if Net.queue == GameConfig.Queue.RANKED:
		# Ranked plays one rule set for everyone: a full field of fierce AI.
		Net.bot_skill = GameConfig.BotSkill.FIERCE
	if Net.is_online() and not Net.is_host():
		return
	stage = Stage.PICKING
	pick_left = PICK_SECONDS
	_say("Pick your monkey!")
	Net.begin_pick(PICK_SECONDS)


func _on_pick_started(seconds: float) -> void:
	if stage == Stage.IDLE:
		return
	stage = Stage.PICKING
	pick_left = seconds
	changed.emit()


func _on_roster_changed() -> void:
	if stage == Stage.JOINING and Net.link == Net.Link.CLIENT and not Net.roster.is_empty():
		stage = Stage.JOINED
		_say("In a room. The host starts soon.")
	if is_active():
		changed.emit()


func _on_join_failed() -> void:
	if stage == Stage.JOINING or stage == Stage.JOINED:
		_host()


func _say(text: String) -> void:
	status = text
	changed.emit()
