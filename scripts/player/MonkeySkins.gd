extends RefCounted

# ============================================================
# MONKEY SKINS - recolours for the monkey art.
#
# One small shader instead of a baked sheet per skin: it re-dyes the fur and
# face to a skin's hue while leaving the dark outline and the whites of the
# eyes alone, so every skin keeps the same crisp pixel art. Materials are
# cached per skin, so four gorillas in Lava share one.
#
# Loaded with preload() rather than a class_name, so it works before the
# editor has rescanned global classes. The skin list itself lives in
# GameConfig.SKINS, next to the hats.
# ============================================================

const SHADER_CODE := """
shader_type canvas_item;

uniform float target_hue = 0.0;
uniform float hue_mix = 0.0;
uniform float sat_add = 0.0;
uniform float sat_mul = 1.0;
uniform float val_mul = 1.0;

// The node's modulate, carried from the vertex stage so the art is read
// straight from TEXTURE and tinted exactly once.
varying vec4 tint_color;

void vertex() {
	tint_color = COLOR;
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 hsv = rgb2hsv(c.rgb);
	// Outline (very dark) and eye whites (bright and grey) keep their colour.
	bool outline = hsv.z < 0.2;
	bool eye = hsv.z > 0.9 && hsv.y < 0.12;
	if (!outline && !eye) {
		float hue = mix(hsv.x, target_hue, hue_mix);
		float sat = clamp(hsv.y * sat_mul + sat_add, 0.0, 1.0);
		float val = clamp(hsv.z * val_mul, 0.0, 1.0);
		c.rgb = hsv2rgb(vec3(hue, sat, val));
	}
	COLOR = c * tint_color;
}
"""

static var _shader: Shader = null
static var _materials: Dictionary = {}


## The material for a skin, or null for the natural colours.
static func material_for(skin_id: StringName) -> Material:
	if skin_id == &"" or skin_id == &"natural":
		return null
	if _materials.has(skin_id):
		return _materials[skin_id]
	var skin: Dictionary = GameConfig.get_skin(skin_id)
	var params: Dictionary = skin.get("params", {})
	if params.is_empty():
		return null
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = _shader
	for key in params.keys():
		material.set_shader_parameter(StringName(key), params[key])
	_materials[skin_id] = material
	return material


## A flat swatch colour for a skin, for buttons.
static func swatch(skin_id: StringName) -> Color:
	var skin: Dictionary = GameConfig.get_skin(skin_id)
	return skin.get("swatch", Color8(150, 106, 64))
