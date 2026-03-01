@tool
extends Polygon2D
class_name Clue

## Clickable area within an investigation that represents a discoverable clue.
## Must be placed as a direct child of an Investigation scene.
## Uses Polygon2D's built-in polygon for the clickable area (edit with the polygon editor).
## The polygon is only visible in the editor; at runtime it is transparent.
## The vignette region is defined by vignette_offset + vignette_extent exports.

## Label shown in the Inspector when no deduction is assigned
const _EMPTY_LABEL := "(Empty)"

## Backing store for the deductions this clue belongs to
var _deduction_ids: PackedStringArray = PackedStringArray()

## Center of the vignette square relative to the Clue origin
@export var vignette_offset: Vector2 = Vector2.ZERO:
	set(value):
		vignette_offset = value
		queue_redraw()

## Half-size of the vignette square
@export var vignette_extent: float = 50.0:
	set(value):
		vignette_extent = maxf(value, 1.0)
		queue_redraw()

## Moves the node's position to the polygon centroid and recenters vertices
@export_tool_button("Reset Xform", "ToolMove") var _reset_xform = _center_transform


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		notify_property_list_changed()


func _ready() -> void:
	if Engine.is_editor_hint():
		color = Color(0.2, 0.8, 0.2, 0.2)
	else:
		color = Color.TRANSPARENT


func _set(property: StringName, value: Variant) -> bool:
	var prop_str := str(property)
	# Backward compat: old single deduction_id from .tscn files
	if property == &"deduction_id":
		var id_str := "" if str(value) == _EMPTY_LABEL else str(value)
		if not id_str.is_empty():
			_deduction_ids = PackedStringArray([id_str])
		else:
			_deduction_ids = PackedStringArray()
		return true
	if prop_str.begins_with("deduction_ids/"):
		var idx := int(prop_str.get_slice("/", 1))
		var id_str := "" if str(value) == _EMPTY_LABEL else str(value)
		while _deduction_ids.size() <= idx:
			_deduction_ids.append("")
		_deduction_ids[idx] = id_str
		# Trim trailing empty entries
		while _deduction_ids.size() > 0 and _deduction_ids[-1].is_empty():
			_deduction_ids.resize(_deduction_ids.size() - 1)
		notify_property_list_changed()
		return true
	return false


func _get(property: StringName) -> Variant:
	var prop_str := str(property)
	# Backward compat for code reading old property
	if property == &"deduction_id":
		if _deduction_ids.size() > 0:
			return _deduction_ids[0]
		return ""
	if property == &"deduction_ids":
		return _deduction_ids
	if prop_str.begins_with("deduction_ids/"):
		var idx := int(prop_str.get_slice("/", 1))
		if idx < _deduction_ids.size():
			var val := _deduction_ids[idx]
			if Engine.is_editor_hint() and val.is_empty():
				return _EMPTY_LABEL
			return val
		if Engine.is_editor_hint():
			return _EMPTY_LABEL
		return ""
	return null


func _get_property_list() -> Array[Dictionary]:
	var all_ids := PackedStringArray()
	if Engine.is_editor_hint() and is_inside_tree():
		all_ids = _get_investigation_deduction_ids()

	var props: Array[Dictionary] = []
	# Show existing entries + one empty slot for adding
	var count := _deduction_ids.size()
	for i in range(count + 1):
		# Exclude IDs already used in other slots
		var available := PackedStringArray()
		for id in all_ids:
			var used := false
			for j in range(count):
				if j != i and j < _deduction_ids.size() and _deduction_ids[j] == id:
					used = true
					break
			if not used:
				available.append(id)
		var hint_string := _EMPTY_LABEL
		if available.size() > 0:
			hint_string = _EMPTY_LABEL + "," + ",".join(available)
		props.append({
			"name": "deduction_ids/" + str(i),
			"type": TYPE_STRING,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": hint_string,
			"usage": PROPERTY_USAGE_DEFAULT,
		})
	return props


func _get_investigation_deduction_ids() -> PackedStringArray:
	"""Walk up the tree to find the parent Investigation and return its deduction IDs."""
	var ids := PackedStringArray()
	var node := get_parent()
	while node:
		if node is Investigation:
			var inv_def = node.get("investigation_def_override")
			if inv_def:
				for d in inv_def.deductions:
					if d is DeductionDef and not d.deduction_id.is_empty():
						if not ids.has(d.deduction_id):
							ids.append(d.deduction_id)
			break
		node = node.get_parent()
	return ids


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	# Polygon outline (green) — fill is handled by Polygon2D
	if polygon.size() >= 3:
		var outline := PackedVector2Array(polygon)
		outline.append(polygon[0])
		draw_polyline(outline, Color(0.2, 0.8, 0.2, 0.8), 2.0)
	# Vignette square preview (orange)
	var vr := get_vignette_rect_local()
	if vr.size != Vector2.ZERO:
		draw_rect(vr, Color(1.0, 0.6, 0.2, 0.2))
		draw_rect(vr, Color(1.0, 0.6, 0.2, 0.8), false, 2.0)


func get_vignette_rect_local() -> Rect2:
	"""Returns the vignette square in Clue local space from offset + extent."""
	return Rect2(
		vignette_offset - Vector2(vignette_extent, vignette_extent),
		Vector2(vignette_extent * 2, vignette_extent * 2)
	)


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
