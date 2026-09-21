extends Node

# ============================================================
# PIXEL AUDIT - dev only. Measures how many screen pixels one art pixel
# actually occupies in an image, and whether that number is a whole one.
#
#   godot --headless res://tools/PixelAudit.tscn -- --images=A.png,B.jpg
#
# "Pixel perfect" is a measurable property, not an opinion: in real pixel
# art every colour change lands on a multiple of the block size. So for each
# candidate block size the audit counts what share of horizontal colour
# transitions fall on that grid. A clean 2x render scores ~1.0 at 2 and
# nothing else comes close. A fractional camera zoom - 1.35, say, which puts
# 2.7 screen pixels on each art pixel - scores badly at every whole number,
# because the pixels are alternately two and three wide.
#
# Tolerance is there for JPEG: compression shifts colours slightly, so an
# exact-equality test finds transitions that are not really there.
# ============================================================

const MAX_BLOCK: int = 8
## Colour distance below which two pixels count as the same colour.
const TOLERANCE: float = 0.06


func _ready() -> void:
	var images: PackedStringArray = []
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--images="):
			images = argument.trim_prefix("--images=").split(",")
	for path in images:
		_audit(path)
	get_tree().quit()


func _audit(path: String) -> void:
	var image := Image.load_from_file(path)
	if image == null:
		print("audit: cannot read %s" % path)
		return
	var w := image.get_width()
	var h := image.get_height()
	var edges: Array[int] = []
	# Sample rows across the middle of the frame, where the art is.
	for i in 60:
		var y := int(float(h) * (0.15 + 0.7 * float(i) / 59.0))
		var last := image.get_pixel(0, y)
		for x in range(1, w):
			var here := image.get_pixel(x, y)
			if _differs(last, here):
				edges.append(x)
			last = here
	if edges.is_empty():
		print("audit: %s - no detail found" % path.get_file())
		return

	var best_block := 1
	var best_score := 0.0
	var scores: PackedStringArray = []
	for block in range(1, MAX_BLOCK + 1):
		var hits := 0
		for x in edges:
			if x % block == 0:
				hits += 1
		var score := float(hits) / float(edges.size())
		# A block of 1 trivially scores 1.0, so it is reported but never wins.
		scores.append("%d:%.2f" % [block, score])
		if block > 1 and score > best_score:
			best_score = score
			best_block = block
	print("%-22s %5dx%-5d edges=%-6d  best block=%d (%.0f%% aligned)   all=[%s]" % [
		path.get_file(), w, h, edges.size(), best_block, best_score * 100.0, " ".join(scores)])


func _differs(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > TOLERANCE
