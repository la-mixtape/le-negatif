@tool
extends EditorPlugin

## Editor plugin that adds drag handles to Clue nodes for the vignette region.
## Center handle moves vignette_offset; edge handles resize vignette_extent.

const HANDLE_RADIUS := 6.0
const HANDLE_HIT_RADIUS := 12.0
const CENTER_COLOR := Color(1.0, 0.6, 0.2)
const EDGE_COLOR := Color(1.0, 1.0, 1.0)
const HANDLE_BORDER := Color(1.0, 0.6, 0.2)
const RECT_OUTLINE := Color(1.0, 0.6, 0.2, 0.8)

const _ClueScript = preload("res://scripts/clue.gd")

enum Handle { CENTER, RIGHT, BOTTOM, LEFT, TOP }

var _edited_clue: Node2D = null
var _dragging_handle := -1
var _drag_start_offset := Vector2.ZERO
var _drag_start_extent := 0.0


# ─── Selection ───────────────────────────────────────────────

func _handles(object: Object) -> bool:
	return object is _ClueScript


func _edit(object: Object) -> void:
	if object is _ClueScript:
		_edited_clue = object as Node2D
	else:
		_edited_clue = null
	update_overlays()


func _make_visible(visible: bool) -> void:
	if not visible:
		_edited_clue = null
		_dragging_handle = -1
	update_overlays()


# ─── Coordinate helpers ─────────────────────────────────────

func _get_editor_transform() -> Transform2D:
	return _edited_clue.get_viewport_transform() * _edited_clue.get_global_transform()


func _local_to_screen(local_pos: Vector2) -> Vector2:
	return _get_editor_transform() * local_pos


func _screen_to_local(screen_pos: Vector2) -> Vector2:
	return _get_editor_transform().affine_inverse() * screen_pos


# ─── Drawing ────────────────────────────────────────────────

func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if not _edited_clue or not _edited_clue.is_inside_tree():
		return

	# Draw handles
	var positions := _get_handle_screen_positions()
	# Center handle (orange)
	overlay.draw_circle(positions[Handle.CENTER], HANDLE_RADIUS + 1.5, HANDLE_BORDER)
	overlay.draw_circle(positions[Handle.CENTER], HANDLE_RADIUS, CENTER_COLOR)
	# Edge handles (white)
	for i in range(1, positions.size()):
		overlay.draw_circle(positions[i], HANDLE_RADIUS + 1.5, HANDLE_BORDER)
		overlay.draw_circle(positions[i], HANDLE_RADIUS, EDGE_COLOR)


func _get_handle_screen_positions() -> PackedVector2Array:
	var o: Vector2 = _edited_clue.vignette_offset
	var e: float = _edited_clue.vignette_extent
	return PackedVector2Array([
		_local_to_screen(o),                      # center
		_local_to_screen(o + Vector2(e, 0.0)),    # right
		_local_to_screen(o + Vector2(0.0, e)),    # bottom
		_local_to_screen(o + Vector2(-e, 0.0)),   # left
		_local_to_screen(o + Vector2(0.0, -e)),   # top
	])


# ─── Input (handle dragging) ────────────────────────────────

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not _edited_clue or not _edited_clue.is_inside_tree():
		return false

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var handles := _get_handle_screen_positions()
			for i in handles.size():
				if event.position.distance_to(handles[i]) <= HANDLE_HIT_RADIUS:
					_dragging_handle = i
					_drag_start_offset = _edited_clue.vignette_offset
					_drag_start_extent = _edited_clue.vignette_extent
					return true
		else:
			if _dragging_handle >= 0:
				_commit_drag()
				_dragging_handle = -1
				return true

	if event is InputEventMouseMotion and _dragging_handle >= 0:
		var local_pos := _screen_to_local(event.position)
		if _dragging_handle == Handle.CENTER:
			_edited_clue.vignette_offset = local_pos
		else:
			var diff := (local_pos - _edited_clue.vignette_offset).abs()
			_edited_clue.vignette_extent = maxf(diff.x, diff.y)
		update_overlays()
		return true

	return false


# ─── Undo / Redo ────────────────────────────────────────────

func _commit_drag() -> void:
	var ur := get_undo_redo()
	if _dragging_handle == Handle.CENTER:
		ur.create_action("Move Vignette Offset")
		ur.add_do_property(_edited_clue, "vignette_offset", _edited_clue.vignette_offset)
		ur.add_do_method(self, &"update_overlays")
		ur.add_undo_property(_edited_clue, "vignette_offset", _drag_start_offset)
		ur.add_undo_method(self, &"update_overlays")
	else:
		ur.create_action("Resize Vignette Extent")
		ur.add_do_property(_edited_clue, "vignette_extent", _edited_clue.vignette_extent)
		ur.add_do_method(self, &"update_overlays")
		ur.add_undo_property(_edited_clue, "vignette_extent", _drag_start_extent)
		ur.add_undo_method(self, &"update_overlays")
	ur.commit_action(false)
