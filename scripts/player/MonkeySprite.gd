class_name MonkeySprite
extends Sprite2D

## Low-detail branch: chibi artwork baked by tools/art/simple_bake.py.
## The high-detail art (assets/monkeys/crisp) is locked artwork baked by tools/art/pixel_bake.py
## (area-averaged, palette-locked, 1px outline). The older nearest-neighbour
## bake in assets/monkeys/locked read as blurry noise at 2x.
## Pose indices retain the existing atlas contract for menus and gameplay.
const ART_DIR: String = "res://assets/monkeys/simple"
const CANVAS: int = 64
## In-match size: 4/3 world px per atlas px = 4 world px per art pixel of
## the low-detail chibis (was 2.0 = 6 px, too big on screen).
const PIXEL: float = 4.0 / 3.0
## Per-species size on top of PIXEL. 4/3 keeps the low-detail art on an even
## grid (3 atlas px per art px x 2 x 4/3 = 8 world px), so the gorilla reads
## as the big one without smeared pixels.
const SIZE: Dictionary = {&"gorilla": 1.25}
## Menus keep their own size ratio (drawn by MonkeyStage at whole scales).
const MENU_SIZE: Dictionary = {&"gorilla": 4.0 / 3.0}
const POSES: Dictionary = MonkeyFrames.POSES
const ANIMS: Dictionary = MonkeyFrames.ANIMS
const FRONT_POSES: Dictionary = POSES
const FRONT_ANIMS: Dictionary = ANIMS

const MonkeySkins = preload("res://scripts/player/MonkeySkins.gd")
static var _sheets: Dictionary = {}
static var _rig: Dictionary = {}
var current_pose: StringName = &"idle_0"
var species: StringName = &"macaque"
var skin: StringName = &"natural"
var anim: StringName = &"idle"
var speed_scale: float = 1.0
var paused: bool = false
## Menus use the same dimensional view and add occasional waves.
var front: bool = false
var _clock: float = 0.0
var _blink_in: float = 2.5
var _blinking: float = 0.0
var _wave_in: float = 4.0
var _anim_left: float = 0.0
var _index: Dictionary = {}


func setup(id: StringName, facing_camera: bool = false, skin_id: StringName = &"natural") -> void:
	species = id
	skin = skin_id
	front = facing_camera
	var sheet := sheet_for(id, skin_id)
	texture = sheet["texture"]
	_index = sheet["index"]
	hframes = MonkeyFrames.COLUMNS
	vframes = MonkeyFrames.ROWS
	centered = false
	offset = Vector2(-CANVAS * 0.5, -CANVAS)
	scale = Vector2.ONE * pixel_for(id)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	material = MonkeySkins.material_for(skin_id)
	anim = &"idle"
	_clock = 0.0
	_anim_left = 0.0
	_show(&"idle_0")


func play(next: StringName) -> void:
	if next == anim:
		return
	# Let the brief landing squash finish without holding up a jump or hit.
	if anim == &"land" and _anim_left > 0.0 and next in [&"idle", &"run"]:
		return
	anim = next if ANIMS.has(next) else &"idle"
	_clock = 0.0
	_anim_left = 0.0


func play_for(next: StringName, seconds: float) -> void:
	play(next)
	_anim_left = seconds


func _process(delta: float) -> void:
	if _anim_left > 0.0:
		_anim_left -= delta
		if _anim_left <= 0.0:
			play(&"idle")
	elif front and anim == &"idle":
		_wave_in -= delta
		if _wave_in <= 0.0:
			_wave_in = randf_range(4.0, 8.0)
			play_for(&"wave", 1.0)
	var spec: Dictionary = ANIMS.get(anim, ANIMS[&"idle"])
	var frames: Array = spec["frames"]
	if not paused:
		_clock += delta * float(spec["fps"]) * speed_scale
	var at := int(_clock)
	at = at % frames.size() if bool(spec["loop"]) else mini(at, frames.size() - 1)
	var pose: StringName = frames[at]
	if anim == &"idle":
		_blink_in -= delta
		if _blink_in <= 0.0:
			_blinking = 0.13
			_blink_in = randf_range(2.0, 4.5)
		if _blinking > 0.0:
			_blinking -= delta
			pose = &"blink"
	_show(pose)


func _show(pose: StringName) -> void:
	current_pose = pose
	frame = int(_index.get(pose, 0))


## Used by physics-timed moves so the baked pose follows the move exactly.
func show_progress(animation: StringName, progress: float) -> void:
	play(animation)
	var spec: Dictionary = ANIMS.get(animation, ANIMS[&"idle"])
	var frames: Array = spec["frames"]
	_clock = minf(clampf(progress, 0.0, 1.0) * frames.size(), frames.size() - 0.01)
	_show(frames[int(_clock)])


static func asset_id(id: StringName, skin_id: StringName = &"natural") -> String:
	var base := String(id) if MonkeyFrames.HEIGHTS.has(id) else "macaque"
	return base


static func sheet_for(id: StringName, skin_id: StringName = &"natural") -> Dictionary:
	var key := asset_id(id, skin_id)
	if _sheets.has(key):
		return _sheets[key]
	var made := {
		"texture": load_art("%s/%s/atlas.png" % [ART_DIR, key]),
		"index": POSES,
		"top": int(MonkeyFrames.HEIGHTS.get(id, 46)),
	}
	_sheets[key] = made
	return made


## Imported texture when the editor has imported it; otherwise the PNG is
## read straight off disk, so freshly baked art shows up without a reimport.
## Always nearest-filtered by the canvas default, never smoothed.
static func load_art(path: String) -> Texture2D:
	# A PNG re-baked after the editor imported it is newer than its .import:
	# read the file itself then, or the game shows the stale import.
	var fresh := FileAccess.get_modified_time(path) > FileAccess.get_modified_time(path + ".import") + 2
	if ResourceLoader.exists(path) and not fresh:
		var imported := load(path) as Texture2D
		if imported != null:
			return imported
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		push_warning("MonkeySprite: missing art %s" % path)
		return null
	return ImageTexture.create_from_image(img)


## Rig data for a species (pivots, hand_px), from the crisp bake.
static func rig_for(id: StringName) -> Dictionary:
	if _rig.is_empty():
		_rig = JSON.parse_string(FileAccess.get_file_as_string(ART_DIR + "/rig.json"))
	return _rig.get(asset_id(id), {})


static func front_sheet_for(id: StringName, skin_id: StringName = &"natural") -> Dictionary:
	return sheet_for(id, skin_id)


static func head_height(id: StringName) -> float:
	return float(MonkeyFrames.HEIGHTS.get(id, 46)) * pixel_for(id)


## World px per atlas px for this species.
static func pixel_for(id: StringName) -> float:
	return PIXEL * float(SIZE.get(id, 1.0))


## In sprite-local pixels, respecting the current body's facing and scale.
func shoulder_position() -> Vector2:
	if _rig.is_empty():
		_rig = JSON.parse_string(FileAccess.get_file_as_string(ART_DIR + "/rig.json"))
	var data: Dictionary = _rig.get(asset_id(species), {})
	var pivots: Dictionary = data.get("pivots", {})
	var at: Array = pivots.get(String(current_pose), [-8, -30])
	return Vector2(-float(at[0]) if flip_h else float(at[0]), float(at[1])) * scale
