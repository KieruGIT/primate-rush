extends CanvasLayer

# ============================================================
# PAUSE - resume or leave, without dropping the match by accident.
#
# Esc used to quit the match outright, which is a rough thing to do to
# somebody who tapped it to see what it did.
#
# The tree is only actually paused offline. In a networked match, pausing
# the tree stops the ENet polling with it, so one player opening a menu
# would stall everyone else's game. Online this is just an overlay, and the
# match keeps running behind it - which is also the honest behaviour: the
# other three monkeys are not going to wait for you.
# ============================================================

@onready var _resume: Button = %ResumeButton
@onready var _leave: Button = %LeaveButton
@onready var _note: Label = %Note
@onready var _volume: HSlider = %Volume
@onready var _volume_label: Label = %VolumeLabel


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resume.pressed.connect(resume)
	_leave.pressed.connect(_on_leave)
	_volume.value = Sfx.get_volume()
	_volume.value_changed.connect(_on_volume_changed)
	_update_volume_label(_volume.value)
	if not Net.is_online():
		get_tree().paused = true
	_note.text = "The match is still running." if Net.is_online() else "Paused."


func resume() -> void:
	get_tree().paused = false
	queue_free()


## Saved as it moves rather than on close, so a player who alt-tabs out of a
## match keeps the setting they just picked.
func _on_volume_changed(value: float) -> void:
	Sfx.set_volume(value)
	Profile.set_stat("volume", value)
	_update_volume_label(value)


func _update_volume_label(value: float) -> void:
	_volume_label.text = "Volume  %d / 10" % int(round(value * 10.0))


func _on_leave() -> void:
	get_tree().paused = false
	Net.leave_match()
	queue_free()
