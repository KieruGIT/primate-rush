extends Node

# ============================================================
# SFX - sound, synthesised at startup, with no audio files.
#
# The project has no art and no audio budget, but silence hides real
# information: you cannot hear that your hit connected, that a jump was
# short, or that someone picked up the banana you were running at. These are
# short waveforms built into AudioStreamWAV buffers when the game loads -
# a few hundred kilobytes of RAM, nothing on disk, nothing to license.
#
# They are placeholders in the same sense the coloured rectangles are: the
# call sites are what matter, and swapping in recorded audio later means
# replacing the buffers, not finding every place a sound should play.
# ============================================================

const RATE: int = 22050
## Enough voices that a four-monkey pile-up does not cut itself off, few
## enough that nothing is ever queued.
const VOICES: int = 10

var _sounds: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_sounds()
	for index in VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = &"Master"
		add_child(player)
		_pool.append(player)
	set_volume(float(Profile.get_stat("volume", 0.7)))


func play(id: StringName, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var stream: AudioStreamWAV = _sounds.get(id)
	if stream == null or _pool.is_empty():
		return
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
	_sounds[&"jump"] = _sweep(330.0, 540.0, 0.11, 0.0, 6.0)
	_sounds[&"land"] = _sweep(150.0, 90.0, 0.10, 0.55, 14.0)
	_sounds[&"swing"] = _sweep(240.0, 180.0, 0.18, 0.15, 5.0)
	_sounds[&"grab"] = _sweep(420.0, 660.0, 0.09, 0.0, 9.0)
	_sounds[&"attack"] = _sweep(700.0, 300.0, 0.08, 0.35, 16.0)
	_sounds[&"hit"] = _sweep(190.0, 70.0, 0.22, 0.7, 9.0)
	_sounds[&"pickup"] = _sweep(700.0, 1040.0, 0.10, 0.0, 10.0)
	_sounds[&"lucky"] = _sweep(520.0, 1300.0, 0.20, 0.0, 5.0)
	_sounds[&"beep"] = _sweep(620.0, 620.0, 0.10, 0.0, 7.0)
	_sounds[&"go"] = _sweep(880.0, 1180.0, 0.28, 0.0, 3.5)
	_sounds[&"finish"] = _sweep(660.0, 1320.0, 0.45, 0.0, 2.5)


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
