class_name SlapFist
extends Node2D

# A deliberately oversized, foreshortened fist.  It is drawn in layers so
# the attack reads like a chunky 3D object even though the game stays 2D.

const TOTAL_TIME := 0.38
const WINDUP_END := 0.08
const STRIKE_END := 0.18

var _time: float = TOTAL_TIME
var _direction: float = 1.0
var _fur := Color(0.53, 0.31, 0.18)
var _impact_time: float = 0.0


func play(direction: int, fur: Color) -> void:
	_direction = 1.0 if direction >= 0 else -1.0
	_fur = fur
	_time = 0.0
	_impact_time = 0.0
	visible = true
	queue_redraw()


func impact() -> void:
	_impact_time = 0.13
	queue_redraw()


func _process(delta: float) -> void:
	if _time >= TOTAL_TIME:
		visible = false
		return
	_time += delta
	_impact_time = maxf(_impact_time - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	if _time >= TOTAL_TIME:
		return
	var strike := clampf((_time - WINDUP_END) / (STRIKE_END - WINDUP_END), 0.0, 1.0)
	var recover := clampf((_time - STRIKE_END) / (TOTAL_TIME - STRIKE_END), 0.0, 1.0)
	var windup := clampf(_time / WINDUP_END, 0.0, 1.0)
	# Back first, then snap well past the normal hand.  The overshoot is the
	# visual hit; recovery eases it back without leaving a giant glove parked.
	var reach := lerpf(-12.0, 0.0, windup)
	if _time >= WINDUP_END:
		reach = lerpf(0.0, 28.0, _ease_out_back(strike))
	if _time >= STRIKE_END:
		reach = lerpf(28.0, 8.0, recover * recover)
	var size_burst := lerpf(0.76, 0.92, windup)
	if _time >= WINDUP_END:
		size_burst = lerpf(0.92, 1.30, sin(strike * PI * 0.5))
	if _time >= STRIKE_END:
		size_burst = lerpf(1.30, 0.72, recover)

	draw_set_transform(Vector2(_direction * reach, -7.0), 0.0, Vector2(_direction * size_burst, size_burst))
	var outline := Color(0.105, 0.065, 0.06, 0.98)
	var shade := _fur.darkened(0.34)
	var mid := _fur.lightened(0.08)
	var light := _fur.lightened(0.38)

	# Motion smears sit behind the arm and grow only through the strike.
	if strike > 0.02 and recover < 0.7:
		var trail_alpha := (1.0 - recover) * strike
		draw_colored_polygon(PackedVector2Array([
			Vector2(-43, -15), Vector2(8, -12), Vector2(8, 11), Vector2(-34, 18)
		]), Color(1.0, 0.78, 0.28, 0.13 * trail_alpha))
		draw_line(Vector2(-50, -23), Vector2(-9, -20), Color(1, 0.94, 0.68, 0.55 * trail_alpha), 4.0)
		draw_line(Vector2(-43, 24), Vector2(-4, 19), Color(1, 0.58, 0.20, 0.42 * trail_alpha), 5.0)

	# Tapered forearm and its underside give the hand a volume and direction.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-9, -10), Vector2(32, -16), Vector2(41, 17), Vector2(-9, 11)
	]), outline)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-7, -7), Vector2(31, -12), Vector2(37, 13), Vector2(-7, 8)
	]), mid)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-5, 3), Vector2(37, 7), Vector2(37, 14), Vector2(-5, 8)
	]), shade)

	# Palm mass: dark silhouette, warm face, lower plane and top highlight.
	draw_circle(Vector2(43, 0), 25.0, outline)
	draw_circle(Vector2(43, -1), 21.5, mid)
	draw_colored_polygon(PackedVector2Array([
		Vector2(23, 4), Vector2(63, 2), Vector2(58, 18), Vector2(34, 21)
	]), shade)
	draw_arc(Vector2(41, -2), 17.0, PI * 1.08, PI * 1.78, 12, light, 4.0)

	# Four knuckles make the silhouette unmistakably a fist, not a ball.
	for i in 4:
		var p := Vector2(29.0 + i * 10.2, -17.0 - absf(1.5 - i) * 1.5)
		draw_circle(p, 9.0, outline)
		draw_circle(p + Vector2(-0.5, 1.0), 6.5, mid if i > 0 else light)
		draw_arc(p + Vector2(-1, 0), 4.7, PI, PI * 1.75, 6, light, 2.0)

	# Folded thumb crosses the palm in a separate shaded plane.
	draw_circle(Vector2(51, 8), 11.5, outline)
	draw_colored_polygon(PackedVector2Array([
		Vector2(38, 2), Vector2(57, 0), Vector2(62, 9), Vector2(52, 16), Vector2(39, 11)
	]), _fur.lightened(0.13))
	draw_line(Vector2(43, 5), Vector2(55, 8), shade, 3.0)

	if _impact_time > 0.0:
		var burst := 1.0 - _impact_time / 0.13
		var center := Vector2(69, -2)
		for angle in [-1.05, -0.5, 0.0, 0.5, 1.05]:
			var direction := Vector2.from_angle(angle)
			draw_line(center + direction * (24.0 + burst * 6.0), center + direction * (39.0 + burst * 18.0), Color(1, 0.93, 0.48, 1.0 - burst), 5.0)


func _ease_out_back(value: float) -> float:
	var c := 1.70158
	var x := value - 1.0
	return 1.0 + (c + 1.0) * x * x * x + c * x * x
