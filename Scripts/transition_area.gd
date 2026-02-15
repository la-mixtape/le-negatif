@tool
extends Node2D
class_name TransitionArea

## A rectangular zone within an investigation that transitions to another scene.
## Must be placed as a direct child of an Investigation scene.
## The rect is centered on the Node2D position (drag in the 2D viewport).
## The player must be zoomed to the required level and click within 50% of
## the rect's center to trigger the transition. Backspace returns to the previous scene.

## Size of the transition zone (centered on the Node2D position)
@export var size: Vector2 = Vector2(100, 100):
	set(value):
		size = value
		queue_redraw()

## Minimum zoom level required to activate this transition
@export var required_zoom: float = 4.0

## Path to the target investigation scene
@export_file("*.tscn") var target_scene: String = ""


func _draw() -> void:
	if not Engine.is_editor_hint():
		return

	var half := size / 2.0
	# Full rect (blue)
	draw_rect(Rect2(-half, size), Color(0.2, 0.6, 1.0, 0.25))
	draw_rect(Rect2(-half, size), Color(0.2, 0.6, 1.0, 0.8), false, 2.0)
	# Inner 50% activation zone (yellow)
	var inner_half := half * 0.5
	var inner_size := size * 0.5
	draw_rect(Rect2(-inner_half, inner_size), Color(1.0, 0.8, 0.2, 0.2))
	draw_rect(Rect2(-inner_half, inner_size), Color(1.0, 0.8, 0.2, 0.6), false, 1.0)
