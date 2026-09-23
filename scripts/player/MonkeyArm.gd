class_name MonkeyArm
extends RefCounted

## One authored arm for both punches and grabs. Only the shaft stretches;
## the hand keeps its baked pixel size as the shoulder moves away from the
## anchor. Drawn at the same 2x art scale as the body so both share one
## pixel grid (a differently scaled arm is what makes art look smeared).
static var _textures: Dictionary = {}

static func texture_for(species: StringName, grip: bool = true) -> Texture2D:
	var key := "%s/arm_%s" % [MonkeySprite.asset_id(species), "grip" if grip else "reach"]
	if not _textures.has(key):
		_textures[key] = MonkeySprite.load_art("%s/%s.png" % [MonkeySprite.ART_DIR, key])
	return _textures[key]


static func hand_pixels(species: StringName, grip: bool) -> float:
	var hands: Array = MonkeySprite.rig_for(species).get("hand_px", [14, 12, 13])
	return float(hands[1] if grip else hands[0])


## thickness scales the shaft across its width (the punch arm is drawn
## chunkier than the grab arm); hand_scale scales the hand both ways.
static func draw_arm(canvas: CanvasItem, species: StringName, shoulder: Vector2, hand: Vector2, grip: bool = true, facing: int = 1, tint: Color = Color.WHITE, hand_scale: float = 1.0, thickness: float = 1.0) -> void:
	var texture := texture_for(species, grip)
	var delta := hand - shoulder
	var length := delta.length()
	if texture == null or length < 2.0:
		return
	var source := texture.get_size()
	var hand_source := minf(hand_pixels(species, grip), source.x - 2.0)
	var px := MonkeySprite.pixel_for(species)
	var hand_width := hand_source * px * hand_scale
	var height := source.y * px * thickness
	var hand_height := source.y * px * hand_scale
	var shaft := maxf(length - hand_width, 0.0)
	canvas.draw_set_transform(shoulder, delta.angle(), Vector2(1.0, -1.0 if facing < 0 else 1.0))
	if shaft > 0.0:
		canvas.draw_texture_rect_region(texture, Rect2(0, -height * 0.5, shaft, height), Rect2(0, 0, source.x - hand_source, source.y), tint)
	canvas.draw_texture_rect_region(texture, Rect2(shaft, -hand_height * 0.5, hand_width, hand_height), Rect2(source.x - hand_source, 0, hand_source, source.y), tint)
	canvas.draw_set_transform(Vector2.ZERO)
