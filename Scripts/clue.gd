@tool
extends Polygon2D
class_name Clue

## Clickable area within an investigation that represents a discoverable clue.
## Must be placed as a direct child of an Investigation scene.
## Uses Polygon2D's built-in polygon for the clickable area (edit with the polygon editor).
## The polygon is only visible in the editor; at runtime it is transparent.
## The vignette region is computed automatically from the polygon AABB + padding.

## Unique identifier for this clue
@export var clue_id: String = ""

## Fraction of the polygon AABB to pad on each side for the vignette region
@export var vignette_padding: Vector2 = Vector2(0.05, 0.05):
	set(value):
		vignette_padding = value
		queue_redraw()

## ID of the next clue in the assembly sequence (empty = end of chain)
@export var next_clue_id: String = ""

## Moves the node's position to the polygon centroid and recenters vertices
@export_tool_button("Reset Xform", "ToolMove") var _reset_xform = _center_transform


func _ready() -> void:
	if Engine.is_editor_hint():
		color = Color(0.2, 0.8, 0.2, 0.2)
	else:
		color = Color.TRANSPARENT


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	# Polygon outline (green) — fill is handled by Polygon2D
	if polygon.size() >= 3:
		var outline := PackedVector2Array(polygon)
		outline.append(polygon[0])
		draw_polyline(outline, Color(0.2, 0.8, 0.2, 0.8), 2.0)
	# Vignette rect preview (orange)
	var vr := get_vignette_rect_local()
	if vr.size != Vector2.ZERO:
		draw_rect(vr, Color(1.0, 0.6, 0.2, 0.2))
		draw_rect(vr, Color(1.0, 0.6, 0.2, 0.8), false, 2.0)


func get_vignette_rect_local() -> Rect2:
	"""Returns the vignette rect in Clue local space (polygon AABB + padding)."""
	if polygon.size() < 3:
		return Rect2()
	var min_pt := Vector2(polygon[0])
	var max_pt := Vector2(polygon[0])
	for i in range(1, polygon.size()):
		min_pt.x = minf(min_pt.x, polygon[i].x)
		min_pt.y = minf(min_pt.y, polygon[i].y)
		max_pt.x = maxf(max_pt.x, polygon[i].x)
		max_pt.y = maxf(max_pt.y, polygon[i].y)
	var aabb := Rect2(min_pt, max_pt - min_pt)
	var expand := aabb.size * vignette_padding
	return aabb.grow_individual(expand.x, expand.y, expand.x, expand.y)


func _center_transform() -> void:
	"""Move position to polygon centroid and recenter vertices around origin."""
	if polygon.size() < 1:
		return
	var centroid := Vector2.ZERO
	for point in polygon:
		centroid += point
	centroid /= polygon.size()
	# Move position by centroid transformed to parent space (handles rotation/scale)
	position += transform.basis_xform(centroid)
	# Subtract centroid from all vertices (in local space)
	var new_polygon := PackedVector2Array()
	for point in polygon:
		new_polygon.append(point - centroid)
	polygon = new_polygon
