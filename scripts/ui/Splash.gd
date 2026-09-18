extends Control

# ============================================================
# SPLASH - the loading screen you see on launch.
#
# Not a fake progress bar. Every monkey's sprite sheet and portrait is built
# here, one per step, so the home screen never hitches building them the
# first time you swipe through the roster. It holds a minimum time on top of
# that, because a logo that flashes for a tenth of a second reads as a bug.
# ============================================================

signal finished

const MIN_SECONDS: float = 1.8
const TIPS: Array[String] = [
	"Let go of a vine at the bottom of the swing for the most speed.",
	"Nobody dies. Falling just costs you time.",
	"A stunned monkey is an open door. Walk through it.",
	"Wall jumps push you away from the wall. Use it to climb gaps.",
	"Gorillas hit hardest. Capuchins steal bananas on the dash.",
]

var _steps: Array[Callable] = []
var _done_steps: int = 0
var _elapsed: float = 0.0
var _bar: ProgressBar
var _runner: MonkeySprite
var _left: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 18)
	add_child(column)

	var title := Label.new()
	title.text = "MONKEY SLAP"
	title.theme_type_variation = &"DisplayBig"
	title.add_theme_font_size_override(&"font_size", 104)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var tag := Label.new()
	tag.text = "NOBODY DIES. YOU JUST GET KNOCKED AROUND."
	tag.theme_type_variation = &"Display"
	tag.add_theme_font_size_override(&"font_size", 20)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(tag)

	# The bar is a branch, and a monkey runs along it as it fills.
	var track := Control.new()
	track.custom_minimum_size = Vector2(620, 110)
	column.add_child(track)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.position = Vector2(0, 84)
	_bar.size = Vector2(620, 20)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.BANANA
	fill.set_corner_radius_all(8)
	_bar.add_theme_stylebox_override(&"fill", fill)
	track.add_child(_bar)
	_runner = MonkeySprite.new()
	track.add_child(_runner)
	_runner.setup(&"capuchin")
	_runner.scale = Vector2.ONE * 3.0
	_runner.play(&"run")
	_runner.position = Vector2(0, 84)

	var tip := Label.new()
	tip.text = "TIP: " + TIPS[randi() % TIPS.size()].to_upper()
	tip.theme_type_variation = &"Subheading"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(tip)

	for id in GameConfig.roster_ids():
		_steps.append(MonkeySprite.sheet_for.bind(id))
		_steps.append(MonkeyPortrait.texture.bind(id))
	_steps.append(func() -> void: Sfx.play(&"ui_select"))


func _process(delta: float) -> void:
	_elapsed += delta
	# One unit of work per frame keeps the runner moving while it happens.
	if _done_steps < _steps.size():
		_steps[_done_steps].call()
		_done_steps += 1
	var work := float(_done_steps) / maxf(float(_steps.size()), 1.0)
	var time := clampf(_elapsed / MIN_SECONDS, 0.0, 1.0)
	var shown := minf(work, time)
	_bar.value = shown
	_runner.position.x = shown * _bar.size.x
	if shown >= 1.0 and not _left:
		_left = true
		finished.emit()
