extends Node2D

# ============================================================
# ARENA - owns the monkeys, the map, the respawn rule, and the snapshot wire.
#
# One arena script serves offline, host, and client. The difference is only
# who simulates: offline and host spawn and simulate everyone, a client
# spawns the same bodies but drives only its own and replays the rest.
#
# The map is swapped into MapSlot rather than the arena being rebuilt per
# level, so a new level is one scene file and nothing else.
#
# No death and no health, per the design spine. Falling out of the world
# costs you a short delay and sends you back to your last checkpoint. The
# delay is the entire punishment.
# ============================================================

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const TOUCH_CONTROLS_SCENE := preload("res://scenes/TouchControls.tscn")
const HUD_SCENE := preload("res://scenes/Hud.tscn")
const RESULTS_SCENE := preload("res://scenes/Results.tscn")
const PAUSE_SCENE := preload("res://scenes/Pause.tscn")

## Forces the on-screen stick and buttons on desktop, for layout work.
@export var force_touch_controls: bool = false

var players: Dictionary = {}           # player_id -> Player
## Bot id -> BotBrain. Host side only: a client receives bots as ordinary
## monkeys in snapshots, because to the netcode that is what they are.
var bots: Dictionary = {}
var map: MapData = null

var _checkpoints: Dictionary = {}      # player_id -> Vector2
var _respawning: Dictionary = {}       # player_id -> bool
var _local_id: int = 1
var _idle_frame: InputFrame = InputFrame.new()
## Latch so one fall counts once, rather than once per frame spent below.
var _local_below_kill: bool = false
## Set once the round is decided. From then on nothing in the arena moves,
## thinks or makes a sound: the results screen sits over a frozen tableau
## instead of bots still punching each other behind it.
var _over: bool = false

@onready var _map_slot: Node2D = $MapSlot
@onready var _player_root: Node2D = $Players
@onready var _pickup_root: Node2D = $Pickups
@onready var race: RaceDirector = $RaceDirector
@onready var hoard: HoardDirector = $HoardDirector
@onready var slap: SlapDirector = $SlapDirector


func _ready() -> void:
	add_to_group(&"arena")
	GameInput.pause_requested.connect(_toggle_pause)
	_local_id = Net.local_id()
	Net.arena = self
	_load_map()
	_spawn_ui()
	_spawn_all_players()
	_start_mode()


func _exit_tree() -> void:
	# An overlay that paused the tree must not take the pause with it when
	# the arena is freed, or the lobby comes back frozen.
	get_tree().paused = false
	if Net.arena == self:
		Net.arena = null


func _toggle_pause() -> void:
	if _over:
		return
	var existing := get_node_or_null(^"Pause")
	if existing != null:
		existing.call(&"resume")
		return
	var overlay := PAUSE_SCENE.instantiate()
	overlay.name = "Pause"
	add_child(overlay)


func _load_map() -> void:
	var scene := GameConfig.load_map(Net.map_id)
	if scene == null:
		push_error("Map %s failed to load." % Net.map_id)
		return
	map = scene.instantiate() as MapData
	_map_slot.add_child(map)


func _spawn_ui() -> void:
	add_child(HUD_SCENE.instantiate())
	if force_touch_controls or OS.has_feature("mobile"):
		add_child(TOUCH_CONTROLS_SCENE.instantiate())


func _start_mode() -> void:
	race.setup(self, map)
	hoard.setup(self, map, _pickup_root)
	slap.setup(self)
	if map == null:
		return
	race.race_over.connect(_on_match_over)
	hoard.hoard_over.connect(_on_match_over)
	slap.slap_over.connect(_on_match_over)

	# Only the host counts down. Clients follow the broadcast, otherwise four
	# machines each start their own round a few frames apart.
	if Net.is_online() and not Net.is_host():
		return
	match Net.mode:
		GameConfig.Mode.RACE:
			race.begin()
		GameConfig.Mode.HOARD:
			hoard.begin()
		GameConfig.Mode.SLAP:
			slap.begin()
		_:
			pass


func _on_match_over(results: Array) -> void:
	if _over:
		return
	_freeze_arena()
	_record_career(results)
	var overlay := RESULTS_SCENE.instantiate()
	add_child(overlay)
	if overlay.has_method(&"show_results"):
		overlay.call(&"show_results", results)


## Stops every monkey, bot brain, pickup and director. The arena node itself
## keeps running only so the results overlay (its child) still works.
func _freeze_arena() -> void:
	_over = true
	bots.clear()
	for id in players.keys():
		var player := players[id] as Player
		if player == null:
			continue
		player.velocity = Vector2.ZERO
		player.process_mode = Node.PROCESS_MODE_DISABLED
	for node in [_player_root, _pickup_root, race, hoard, slap]:
		if node != null:
			(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var pause := get_node_or_null(^"Pause")
	if pause != null:
		pause.queue_free()
	get_tree().paused = false


func _record_career(results: Array) -> void:
	for index in results.size():
		var entry: Variant = results[index]
		if not (entry is Dictionary) or int((entry as Dictionary).get("id", -1)) != _local_id:
			continue
		var row: Dictionary = entry
		var place := index + 1
		if Net.queue == GameConfig.Queue.RANKED:
			Profile.record_ranked(GameConfig.ranked_delta(Net.mode, place, results.size(), row))
		if Net.mode == GameConfig.Mode.HOARD:
			Profile.record_hoard(place, results.size(), int(row.get("score", 0)))
		elif Net.mode == GameConfig.Mode.RACE:
			Profile.record_race(
				Net.map_id, place, results.size(),
				float(row.get("time", 0.0)), bool(row.get("finished", false))
			)
		return


# --- Spawning ------------------------------------------------------

func _spawn_all_players() -> void:
	if Net.roster.is_empty():
		# Arena opened without a roster, which means a solo session that
		# skipped the lobby. Spawn the one monkey and carry on.
		_spawn_player(1, Net.local_monkey, 0, Net.local_hat)
		return
	for peer_id in Net.roster.keys():
		var entry: Dictionary = Net.roster[peer_id]
		var is_bot := bool(entry.get("bot", false))
		_spawn_player(
			int(peer_id), entry["monkey"], int(entry["slot"]),
			entry.get("hat", &"none"), is_bot, String(entry.get("name", ""))
		)
		if is_bot and _is_authority():
			# Difficulty is host-side only, because the brain itself is: a
			# client never runs one and has nothing to disagree with.
			var brain := BotBrain.new()
			brain.skill_level = GameConfig.bot_skill_level(Net.bot_skill)
			bots[int(peer_id)] = brain


func _spawn_player(id: int, monkey_id: StringName, slot: int, hat_id: StringName = &"none", is_bot: bool = false, bot_name: String = "") -> Player:
	if players.has(id):
		return players[id]
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = "Player_%d" % id
	# Set before the tree readies it, so the name label is right the first
	# time rather than being corrected a frame later.
	player.is_bot = is_bot
	player.bot_name = bot_name
	player.team = GameConfig.team_of(slot) if Net.mode == GameConfig.Mode.SLAP else -1
	player.setup(GameConfig.get_monkey(monkey_id), id, id == _local_id, GameConfig.tint_for_index(slot), hat_id)
	player.position = _spawn_position(slot)
	if map != null and player.camera != null:
		# Whole numbers only. A zoom of 0.78 puts 1.56 screen pixels on each
		# art pixel, so every pixel in the game is alternately one and two
		# wide - the single loudest way for pixel art to look wrong.
		player.camera.zoom = Vector2.ONE * maxf(roundf(map.camera_zoom), 1.0)
	_player_root.add_child(player)
	players[id] = player
	if id == _local_id:
		# Career stats track this machine's player only. Each client writes
		# its own file and none of it is authoritative for anything.
		player.hit_landed.connect(func(_target_id: int) -> void: Profile.bump("hits_landed"))
		player.hit_taken.connect(func(_attacker_id: int, _force: Vector2) -> void: Profile.bump("hits_taken"))
	_checkpoints[id] = player.position
	_respawning[id] = false
	return player


func _spawn_position(slot: int) -> Vector2:
	if map == null:
		return Vector2(160.0, 400.0) + Vector2(72.0, 0.0) * float(slot)
	return map.spawn_point + map.spawn_stride * float(slot)


func despawn_player(id: int) -> void:
	if not players.has(id):
		return
	players[id].queue_free()
	players.erase(id)
	bots.erase(id)
	_checkpoints.erase(id)
	_respawning.erase(id)


# --- Per-tick routing ----------------------------------------------

func _physics_process(delta: float) -> void:
	if _over:
		# Still drain the local input queue, so presses made on the results
		# screen do not pile up and fire in the next round.
		GameInput.take_local_frame()
		return
	_route_input(delta)
	_track_local_fall()
	if _is_authority():
		_check_falls()


func _is_authority() -> bool:
	return not Net.is_online() or Net.is_host()


func _route_input(delta: float) -> void:
	var local_frame := GameInput.take_local_frame()
	if _input_locked():
		# Intent is dropped rather than buffered during the countdown, so a
		# player mashing jump on "3" does not launch on "GO".
		local_frame = _idle_frame

	# The local monkey always gets its intent directly, even on a client.
	# Waiting for the host to echo your own jump back is exactly the lag
	# that makes a LAN game feel worse than a local one.
	var local_player := players.get(_local_id) as Player
	if local_player != null:
		local_player.feed_input(local_frame)

	if Net.is_online() and not Net.is_host():
		Net.send_local_input(local_frame)
		return

	for id in players.keys():
		if int(id) == _local_id:
			continue
		var frame := _idle_frame
		if not _input_locked():
			frame = _brain_or_remote_input(int(id), delta)
		players[id].feed_input(frame)


## Bots and remote players are the same thing from here: a source of frames.
func _brain_or_remote_input(id: int, delta: float) -> InputFrame:
	var brain := bots.get(id) as BotBrain
	if brain != null:
		return brain.think(players[id] as Player, self, delta)
	return Net.take_remote_input(id)


## Counted locally rather than in _begin_respawn, which only runs on the
## host. A client falling into a pit should see its own fall counted.
func _track_local_fall() -> void:
	var player := players.get(_local_id) as Player
	if player == null:
		return
	var limit := map.kill_depth if map != null else 1400.0
	if not _local_below_kill and player.global_position.y > limit:
		_local_below_kill = true
		Profile.bump("falls")
	elif _local_below_kill and player.global_position.y < limit - 200.0:
		_local_below_kill = false


func _input_locked() -> bool:
	return race.is_input_locked() or hoard.is_input_locked() or slap.is_input_locked()


func _check_falls() -> void:
	var limit := map.kill_depth if map != null else 1400.0
	for id in players.keys():
		if bool(_respawning.get(id, false)):
			continue
		var player := players[id] as Player
		# Past the blast line to either side counts too, on maps that have
		# one: a slap that sends you flying sideways is as final as the sea.
		var blasted := map != null and map.blast_half_width > 0.0 and absf(player.global_position.x) > map.blast_half_width
		if player.global_position.y > limit or blasted:
			_begin_respawn(int(id))


func _begin_respawn(id: int) -> void:
	if _over:
		return
	_respawning[id] = true
	slap.player_fell(id)
	var player := players.get(id) as Player
	if player == null:
		return
	# Parked far below rather than freed: freeing and reinstancing a body
	# mid-match invalidates every reference the netcode is holding.
	var limit := map.kill_depth if map != null else 1400.0
	player.velocity = Vector2.ZERO
	player.global_position = Vector2(0.0, limit + 4000.0)
	await get_tree().create_timer(GameConfig.RESPAWN_DELAY).timeout
	if not is_instance_valid(player):
		return
	if _over:
		return
	player.respawn_at(_checkpoints.get(id, _spawn_position(0)))
	_respawning[id] = false


## Called by Checkpoint areas. Host authoritative: a client claiming a
## checkpoint it never reached would be the cheapest possible cheat.
func set_checkpoint(id: int, point: Vector2) -> void:
	if not _is_authority():
		return
	_checkpoints[id] = point


# --- Snapshot wire (host -> clients) -------------------------------

func collect_snapshot() -> Dictionary:
	if _over:
		return {}
	var out: Dictionary = {}
	for id in players.keys():
		out[id] = players[id].get_net_state()
	return out


func apply_snapshot(snapshot: Dictionary) -> void:
	if _over:
		return
	for id in snapshot.keys():
		var pid := int(id)
		var player := players.get(pid) as Player
		if player == null:
			# A monkey the host knows about and this client does not: the
			# roster arrived after the arena loaded, so fill the gap rather
			# than dropping the player until the next scene change.
			var entry: Dictionary = Net.roster.get(pid, {"monkey": &"gibbon", "hat": &"none", "slot": players.size()})
			player = _spawn_player(
				pid, entry["monkey"], int(entry["slot"]),
				entry.get("hat", &"none"), bool(entry.get("bot", false))
			)
		player.apply_net_state(snapshot[id])


func apply_remote_hit(target_id: int, force: Vector2, stun: float, attacker_id: int) -> void:
	if _over:
		return
	var player := players.get(target_id) as Player
	if player != null:
		player.take_hit(attacker_id, force, stun)
	# A client resolves no hits of its own, so its landed hits are only
	# knowable from the host's broadcast.
	if attacker_id == _local_id:
		Profile.bump("hits_landed")


func apply_remote_ability(target_id: int, ability_id: StringName, duration: float) -> void:
	if _over:
		return
	var player := players.get(target_id) as Player
	if player != null:
		player.set_ability(ability_id, duration)
