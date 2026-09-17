extends Control

# Draw-only child of TouchControls. Kept separate because a CanvasLayer
# cannot draw, and the parent owns all the input state worth drawing.


func _draw() -> void:
	var controls := get_parent()
	if controls != null and controls.has_method(&"draw_surface"):
		controls.call(&"draw_surface")
