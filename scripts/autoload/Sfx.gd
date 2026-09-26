extends Node

# ============================================================
# SFX - gameplay sound synthesised at startup, interface sound from the pack.
#
# The project has no audio budget, but silence hides real information: you
# cannot hear that your hit connected, that a jump was short, or that someone
# picked up the banana you were running at. Every gameplay cue is a short
# waveform built into an AudioStreamWAV buffer when the game loads - a few
# hundred kilobytes of RAM, nothing on disk, nothing to license.
#
# Interface clicks are the exception. A menu tap is a transient, which is the
# one shape a sine sweep cannot fake, and the UI pack ships three of them.
# Those load from disk with a synthesised blip as the fallback, so a stripped
# assets folder costs the game a nicer click and nothing else.
# ============================================================

const RATE: int = 22050
const UI_SOUND_DIR := "res://assets/kenney_ui-pack/Sounds"
## Kenney Interface Sounds and Impact Sounds, both CC0. Real recordings for
## everything a synth does badly: taps, impacts, footsteps.
const SOUND_DIR := "res://assets/kenney_sounds"
## Enough voices that a four-monkey pile-up does not cut itself off, few
## enough that nothing is ever queued.
const VOICES: int = 10

var _sounds: Dictionary = {}           # id -> AudioStream or Array of variants
## Per-sound level in dB. A UI tap heard fifty times a session sits well
## under a slap heard five times a round.
var _gain: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0

## Background music: one looping track at a time, crossfaded. "lobby" for
## the menus and results, "battle" in a match. Jungle loops made for this
## game (tools/music/compose_jungle.py), so there is nothing to license.
const MUSIC_DIR := "res://assets/music"
## Music sits under the effects, so a slap is never lost in it.
const MUSIC_DB: float = -9.0
var _music: AudioStreamPlayer = null
var _music_id: StringName = &""
var _music_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_sounds()
	for index in VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = &"Master"
		add_child(player)
		_pool.append(player)
	_music = AudioStreamPlayer.new()
	_music.bus = &"Master"
	_music.volume_db = -80.0
	add_child(_music)
	set_volume(float(Profile.get_stat("volume", 0.7)))


## Starts a track (fading from whatever was playing). Same track: nothing.
func play_music(id: StringName) -> void:
	if id == _music_id or _music == null:
		return
	var stream := _load_music(id)
	if stream == null:
		return
	_music_id = id
	if _music_tween != null:
		_music_tween.kill()
	_music_tween = create_tween()
	if _music.playing:
		_music_tween.tween_property(_music, "volume_db", -40.0, 0.35)
	_music_tween.tween_callback(func() -> void:
		_music.stream = stream
		_music.volume_db = -40.0
		_music.play())
	_music_tween.tween_property(_music, "volume_db", MUSIC_DB, 0.6)


func stop_music() -> void:
	_music_id = &""
	if _music != null:
		_music.stop()


func _load_music(id: StringName) -> AudioStream:
	var path := "%s/music_%s.ogg" % [MUSIC_DIR, id]
	var stream: AudioStreamOggVorbis = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStreamOggVorbis
	elif FileAccess.file_exists(path):
		# Not imported yet (fresh from git): read the file itself.
		stream = AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
	if stream == null:
		if id != &"battle":
			return _load_music(&"battle")
		push_warning("Music missing: %s" % path)
		return null
	stream.loop = true
	return stream


func _exit_tree() -> void:
	# Released on the way out, or the audio server is still holding every
	# playback when the object database is checked at exit and each one is
	# reported as a leak - noise that would bury a real one later.
	for player in _pool:
		player.stop()
		player.stream = null
	if _music != null:
		_music.stop()
		_music.stream = null
	_sounds.clear()


func play(id: StringName, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var entry: Variant = _sounds.get(id)
	if entry == null or _pool.is_empty():
		return
	var stream: AudioStream = null
	if entry is Array:
		# A different take each time, slightly repitched: the same slap five
		# times in a row is what makes game audio sound cheap.
		stream = (entry as Array)[randi() % (entry as Array).size()]
		pitch *= randf_range(0.93, 1.07)
	else:
		stream = entry
	volume_db += float(_gain.get(id, 0.0))
	# Round robin rather than "find a free one": the oldest voice is the
	# right one to steal, and searching every frame for a free player is
	# work for no benefit at this scale.
	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = stream
	player.pitch_scale = clampf(pitch, 0.4, 2.5)
	player.volume_db = volume_db
	player.play()


func set_volume(linear: float) -> void:
	var clamped := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(clamped, 0.0001)))
	AudioServer.set_bus_mute(0, clamped <= 0.001)


func get_volume() -> float:
	return clampf(float(Profile.get_stat("volume", 0.7)), 0.0, 1.0)


# --- Sound design --------------------------------------------------
#
# Deliberately terse. Every sound is a pitch sweep, a noise burst, or both,
# with an exponential decay, because that covers every cue this game needs
# and stays readable as a table.

func _build_sounds() -> void:
	# Synthesised: short tonal cues a sweep does well. Softer than before -
	# less noise, lower level - because they play constantly.
	_sounds[&"jump"] = _sweep(300.0, 460.0, 0.10, 0.0, 7.0)
	_sounds[&"swing"] = _sweep(240.0, 180.0, 0.16, 0.08, 6.0)
	_sounds[&"grab"] = _sweep(420.0, 620.0, 0.07, 0.0, 10.0)
	_sounds[&"bounce"] = _sweep(220.0, 760.0, 0.20, 0.0, 6.0)
	_sounds[&"dash"] = _sweep(700.0, 260.0, 0.11, 0.25, 12.0)
	_sounds[&"pickup"] = _sweep(700.0, 1040.0, 0.09, 0.0, 11.0)
	_sounds[&"lucky"] = _sweep(520.0, 1300.0, 0.20, 0.0, 5.0)
	_sounds[&"beep"] = _sweep(620.0, 620.0, 0.10, 0.0, 7.0)
	_sounds[&"go"] = _sweep(880.0, 1180.0, 0.28, 0.0, 3.5)
	_gain.merge({&"jump": -7.0, &"swing": -6.0, &"grab": -6.0, &"dash": -7.0, &"pickup": -4.0, &"beep": -4.0})

	# Recorded: impacts, feet and the interface.
	_sounds[&"hit"] = _files(["impactPunch_medium_000", "impactPunch_medium_001", "impactPunch_medium_002", "impactPunch_medium_003"], _sweep(190.0, 70.0, 0.2, 0.6, 9.0))
	_sounds[&"slap"] = _files(["impactPunch_heavy_000", "impactPunch_heavy_001"], _sweep(1400.0, 400.0, 0.07, 0.9, 20.0))
	_sounds[&"attack"] = _files(["impactGeneric_light_000", "impactGeneric_light_001"], _sweep(700.0, 300.0, 0.08, 0.35, 16.0))
	_sounds[&"land"] = _files(["impactSoft_medium_000", "impactSoft_medium_001", "impactSoft_medium_002"], _sweep(150.0, 90.0, 0.10, 0.55, 14.0))
	_sounds[&"step"] = _files(["footstep_grass_000", "footstep_grass_001", "footstep_grass_002", "footstep_grass_003"], null)
	_sounds[&"finish"] = _files(["ui_confirmation_002"], _sweep(660.0, 1320.0, 0.45, 0.0, 2.5))
	_sounds[&"ui_click"] = _files(["ui_click_002"], _file("click-a.ogg", _sweep(900.0, 620.0, 0.05, 0.25, 22.0)))
	_sounds[&"ui_select"] = _files(["ui_select_002"], _file("switch-a.ogg", _sweep(520.0, 780.0, 0.07, 0.1, 16.0)))
	_sounds[&"ui_deny"] = _files(["ui_error_004"], _file("tap-b.ogg", _sweep(300.0, 170.0, 0.14, 0.3, 12.0)))
	_sounds[&"ui_back"] = _files(["ui_back_002"], null)
	_gain.merge({&"ui_click": -14.0, &"ui_select": -9.0, &"ui_deny": -8.0, &"ui_back": -10.0,
		&"attack": -10.0, &"land": -9.0, &"step": -20.0, &"finish": -6.0, &"hit": -1.0})


## Loads recorded variants from SOUND_DIR. Missing files are skipped, and
## with none found the fallback plays instead, so a stripped build still
## has sound.
func _files(names: Array, fallback: AudioStream) -> Variant:
	var found: Array = []
	for name in names:
		var path := "%s/%s.ogg" % [SOUND_DIR, name]
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream != null:
				found.append(stream)
	if found.is_empty():
		return fallback
	return found if found.size() > 1 else found[0]


func _file(name: String, fallback: AudioStream) -> AudioStream:
	var path := "%s/%s" % [UI_SOUND_DIR, name]
	if not ResourceLoader.exists(path):
		return fallback
	var stream := load(path) as AudioStream
	return stream if stream != null else fallback


## One voice: a sine sweeping from start to end, mixed with `noise` worth of
## white noise, under an exponential decay of `falloff`.
func _sweep(start_hz: float, end_hz: float, seconds: float, noise: float, falloff: float) -> AudioStreamWAV:
	var samples := int(RATE * seconds)
	var bytes := PackedByteArray()
	bytes.resize(samples * 2)
	var phase := 0.0
	for index in samples:
		var t := float(index) / float(samples)
		var hz := lerpf(start_hz, end_hz, t)
		phase += TAU * hz / float(RATE)
		var tone := sin(phase) * (1.0 - noise)
		var grit := randf_range(-1.0, 1.0) * noise
		var envelope := exp(-falloff * t)
		# Headroom at 0.55: ten voices at full scale would clip the bus the
		# moment four monkeys land at once.
		var value := clampf((tone + grit) * envelope * 0.55, -1.0, 1.0)
		bytes.encode_s16(index * 2, int(value * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream
