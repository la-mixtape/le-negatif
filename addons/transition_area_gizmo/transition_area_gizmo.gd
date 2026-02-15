@tool
extends EditorPlugin

## Editor plugin that adds drag handles to TransitionArea nodes.
## Four handles on each edge midpoint (rect is centered on the node).
## Also handles click-to-select on the drawn rect area via _input(),
## since _edit_get_rect is not exposed to GDScript in Godot 4.6.

const HANDLE_RADIUS := 6.0
const HANDLE_HIT_RADIUS := 12.0
const HANDLE_COLOR := Color(1.0, 1.0, 1.0)
const HANDLE_BORDER := Color(0.2, 0.6, 1.0)

const _TAScript = preload("res://scripts/transition_area.gd")

# Handle indices: 0=right, 1=bottom, 2=left, 3=top
enum Handle { RIGHT, BOTTOM, LEFT, TOP }

var _edited_ta: Node2D = null
var _dragging_handle := -1
var _drag_start_size := Vector2.ZERO
var _viewport_container: Control = null


# ─── Lifecycle ───────────────────────────────────────────────

func _enter_tree() -> void:
	call_deferred(&"_cache_viewport_container")


func _cache_viewport_container() -> void:
	var vp := EditorInterface.get_editor_viewport_2d()
	if vp and vp.get_parent() is Control:
		_viewport_container = vp.get_parent() as Control


# ─── Click-to-select via _input() ────────────────────────────

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	if not _viewport_container:
		return

	# Only handle clicks inside the 2D viewport area
	var vp_rect: Rect2 = _viewport_container.get_global_rect()
	if not vp_rect.has_point(event.position):
		return

	# Convert to viewport-local coordinates
	var local_click: Vector2 = event.position - vp_rect.position
	var clicked_ta := _find_ta_at(local_click)
	if clicked_ta:
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(clicked_ta)
		# Consume the event so the editor doesn't override our selection
		get_viewport().set_input_as_handled()


# ─── Selection (for handle editing once a TA is selected) ────

func _handles(object: Object) -> bool:
	return object is _TAScript


func _edit(object: Object) -> void:
	if object is _TAScript:
		_edited_ta = object as Node2D
	else:
		_edited_ta = null
	update_overlays()


func _make_visible(visible: bool) -> void:
	if not visible:
		_edited_ta = null
		_dragging_handle = -1
	update_overlays()


# ─── Coordinate helpers ─────────────────────────────────────

func _get_editor_transform() -> Transform2D:
	return _edited_ta.get_viewport_transform() * _edited_ta.get_global_transform()


func _local_to_screen(local_pos: Vector2) -> Vector2:
	return _get_editor_transform() * local_pos


func _screen_to_local(screen_pos: Vector2) -> Vector2:
	return _get_editor_transform().affine_inverse() * screen_pos


# ─── Drawing ─────────────────────────────────────────────────

func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if not _edited_ta or not _edited_ta.is_inside_tree():
		return

	var handle_positions := _get_handle_screen_positions()
	for pos in handle_positions:
		overlay.draw_circle(pos, HANDLE_RADIUS + 1.5, HANDLE_BORDER)
		overlay.draw_circle(pos, HANDLE_RADIUS, HANDLE_COLOR)


func _get_handle_screen_positions() -> PackedVector2Array:
	var h: Vector2 = _edited_ta.size / 2.0
	return PackedVector2Array([
		_local_to_screen(Vector2(h.x, 0.0)),    # right
		_local_to_screen(Vector2(0.0, h.y)),     # bottom
		_local_to_screen(Vector2(-h.x, 0.0)),    # left
		_local_to_screen(Vector2(0.0, -h.y)),    # top
	])


# ─── Input (handle dragging, only active when a TA is selected) ─

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not _edited_ta or not _edited_ta.is_inside_tree():
		return false

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var handles := _get_handle_screen_positions()
			for i in handles.size():
				if event.position.distance_to(handles[i]) <= HANDLE_HIT_RADIUS:
					_dragging_handle = i
					_drag_start_size = _edited_ta.size
					return true
		else:
			if _dragging_handle >= 0:
				_commit_drag()
				_dragging_handle = -1
				return true

	if event is InputEventMouseMotion and _dragging_handle >= 0:
		var local_pos := _screen_to_local(event.position)
		var new_size: Vector2 = _edited_ta.size
		if _dragging_handle == Handle.RIGHT or _dragging_handle == Handle.LEFT:
			new_size.x = maxf(1.0, absf(local_pos.x) * 2.0)
		elif _dragging_handle == Handle.BOTTOM or _dragging_handle == Handle.TOP:
			new_size.y = maxf(1.0, absf(local_pos.y) * 2.0)
		_edited_ta.size = new_size
		update_overlays()
		return true

	return false


# ─── Scene search ────────────────────────────────────────────

func _find_ta_at(screen_pos: Vector2) -> Node2D:
	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return null
	var tas: Array = []
	_collect_tas(root, tas)
	for ta in tas:
		if not ta.is_inside_tree():
			continue
		var xform: Transform2D = ta.get_viewport_transform() * ta.get_global_transform()
		var local_pos: Vector2 = xform.affine_inverse() * screen_pos
		var half: Vector2 = ta.size / 2.0
		if absf(local_pos.x) <= half.x and absf(local_pos.y) <= half.y:
			return ta
	return null


func _collect_tas(node: Node, result: Array) -> void:
	if node is _TAScript:
		result.append(node)
	for child in node.get_children():
		_collect_tas(child, result)


# ─── Undo / Redo ─────────────────────────────────────────────

func _commit_drag() -> void:
	var ur := get_undo_redo()
	ur.create_action("Resize TransitionArea")
	ur.add_do_property(_edited_ta, "size", _edited_ta.size)
	ur.add_do_method(self, &"update_overlays")
	ur.add_undo_property(_edited_ta, "size", _drag_start_size)
	ur.add_undo_method(self, &"update_overlays")
	ur.commit_action(false)
