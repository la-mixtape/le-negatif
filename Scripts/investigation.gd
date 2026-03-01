extends Control
class_name Investigation

## Investigation scene - displays a 2D image with magnifier tool.
## Supports clue discovery (click polygons, vignette HUD) and
## scene transitions via TransitionArea children.

# ─── Magnifier exports ───────────────────────────────────────────

## Maximum zoom level for the magnifier (e.g. 4 = 4x)
@export var max_zoom: float = 4.0

## Minimum zoom level for the magnifier (1 = no zoom)
@export var min_zoom: float = 2.0

## Size of the magnifier as a percentage of screen height
@export_range(0.05, 0.5) var magnifier_size_percent: float = 0.125

## Fade duration for magnifier show/hide
@export var fade_duration: float = 0.2

## Fraction of magnifier radius with uniform zoom (rest has quadratic falloff)
@export_range(0.0, 1.0) var lens_inner_radius: float = 0.80

## Strength of lens distortion at edges
@export_range(0.0, 3.0) var lens_distortion: float = 0.75

# ─── Investigation definition ────────────────────────────────────

## Shared investigation definition (deductions, metadata).
## Set this on both root and sub-scenes to the same .tres resource.
## At runtime, falls back to GameManager's active investigation if null.
@export var investigation_def_override: InvestigationDef = null

# ─── Deduction exports ──────────────────────────────────────────

## Duration for deduction image display fade-in/out (seconds)
@export var deduction_fade_duration: float = 0.4

## Width of white frame around the centered deduction image (pixels)
@export var deduction_frame_width: float = 8.0

## Size of the centered deduction image as fraction of screen height
@export_range(0.2, 0.8) var deduction_image_size_percent: float = 0.5

## Seconds to hold green-framed vignettes before showing deduction image
@export var deduction_hold_duration: float = 1.0

# ─── Transition exports ─────────────────────────────────────────

## Magnifier pulsation rate when a transition is available (pulses per second)
@export var transition_pulse_rate: float = 1.0

## Magnifier pulsation scale amplitude (fraction above 1.0)
@export var transition_pulse_amplitude: float = 0.05

# ─── Image zoom exports ──────────────────────────────────────

## Maximum zoom level for the full image (configurable per investigation)
@export var image_max_zoom: float = 2.0

## Zoom increment per scroll step
@export var image_zoom_speed: float = 0.1

## Pixel distance before a click becomes a drag (pan)
@export var pan_drag_threshold: float = 4.0

# ─── Constants ──────────────────────────────────────────────────

# Script references for type-safe child discovery
const _ClueScript = preload("res://scripts/clue.gd")
const _TAScript = preload("res://scripts/transition_area.gd")

# ─── Magnifier state ────────────────────────────────────────────

## Current zoom level
var current_zoom: float = 2.0

## Whether magnifier is currently active
var magnifier_active: bool = false

## Current magnifier alpha (0-1)
var magnifier_alpha: float = 0.0

## Target alpha for fade animation
var target_alpha: float = 0.0

## The active texture used for display and magnification
var _active_texture: Texture2D

## Tween for max-zoom pulsate feedback
var _pulsate_tween: Tween

## Transition-ready pulse state
var _transition_pulse_tween: Tween
var _is_transition_ready: bool = false

# ─── Image zoom state ─────────────────────────────────────────

## Current full-image zoom level (1.0 = no zoom)
var _image_zoom: float = 1.0

## Top-left content position visible in viewport (in unzoomed content pixels)
var _content_origin: Vector2 = Vector2.ZERO

## The node we apply zoom transforms to (references aspect_container)
var _zoom_container: Control

## Pan drag tracking
var _pan_start_pos: Vector2 = Vector2.ZERO
var _pan_last_pos: Vector2 = Vector2.ZERO
var _pan_active: bool = false

# ─── Deduction state ─────────────────────────────────────────────

var _max_clues_per_deduction: int = 3
var _deduction_defs: Dictionary = {}
var _deduction_clues: Dictionary = {}
var _completed_deductions: Dictionary = {}
var _deduction_overlay_active: bool = false

var _deduction_overlay: Control
var _deduction_overlay_panel: Control
var _deduction_overlay_image: TextureRect

# ─── Clue & interaction state ───────────────────────────────────

var _clue_keys: Dictionary = {}  # Node -> String (original path key, computed before reparenting)
var _clues: Array = []
var _transition_areas: Array = []

# ─── Nodes ──────────────────────────────────────────────────────

@onready var background: ColorRect = $Background
@onready var aspect_container: AspectRatioContainer = $AspectContainer
@onready var base_image: TextureRect = $AspectContainer/BaseImage
@onready var magnifier_container: Control = $MagnifierContainer
@onready var magnifier_circle: ColorRect = $MagnifierContainer/MagnifierCircle


# ─── Investigation definition helper ─────────────────────────────

func _get_investigation_def() -> InvestigationDef:
	if investigation_def_override:
		return investigation_def_override
	return GameManager.get_active_investigation()


func _build_clue_keys() -> void:
	"""Walk the tree BEFORE reparenting to record stable clue keys that match scan-time paths."""
	var found: Array = []
	_find_nodes_recursive(self, _ClueScript, found)
	for clue in found:
		_clue_keys[clue] = scene_file_path + "::" + str(get_path_to(clue))


func _get_clue_key(clue: Node) -> String:
	"""Return the stable key for a clue (precomputed before reparenting)."""
	return _clue_keys.get(clue, scene_file_path + "::" + str(get_path_to(clue)))


func _build_atlas_for_clue(clue: Node) -> AtlasTexture:
	"""Build an AtlasTexture for a clue's vignette region (stored for cross-scene persistence)."""
	var vignette: Rect2 = clue.get_vignette_rect_local()
	if not _active_texture or vignette.size == Vector2.ZERO:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = _active_texture
	var clue_xform: Transform2D = clue.get_transform()
	var zc_origin: Vector2 = clue_xform * vignette.position
	var zc_end: Vector2 = clue_xform * (vignette.position + vignette.size)
	atlas.region = _container_rect_to_image_rect(Rect2(zc_origin, zc_end - zc_origin))
	return atlas


# ─── Lifecycle ──────────────────────────────────────────────────

func _ready() -> void:
	# Read texture directly from BaseImage (set it in the scene editor)
	_active_texture = base_image.texture

	# Pass texture and lens parameters to the magnifier shader
	if _active_texture:
		var mat := magnifier_circle.material as ShaderMaterial
		mat.set_shader_parameter("magnified_texture", _active_texture)
		mat.set_shader_parameter("lens_inner_radius", lens_inner_radius)
		mat.set_shader_parameter("lens_distortion", lens_distortion)

	# Initialize magnifier as hidden
	magnifier_container.modulate.a = 0.0
	magnifier_active = false

	# Set up aspect ratio container for 16:9
	aspect_container.ratio = 16.0 / 9.0

	# Compute clue keys BEFORE reparenting so paths match scan-time discovery
	_build_clue_keys()

	# Wrap content in zoom container for scroll-based zoom/pan
	_setup_zoom_container()

	# Set up magnifier size
	update_magnifier_size()

	# Connect resize signal to handle letterboxing
	get_viewport().size_changed.connect(_on_viewport_resized)

	# Discover game objects placed as children
	_setup_clues()
	_setup_deductions()
	_setup_transition_areas()

	# Initialize persistent vignette HUD with slot count for this investigation
	InvestigationHUD.initialize(_max_clues_per_deduction)
	InvestigationHUD.set_hud_visible(true)

	# Build deduction completion overlay
	_setup_deduction_overlay()


func _input(event: InputEvent) -> void:
	# Block all input except click-to-dismiss while deduction overlay is shown
	if _deduction_overlay_active:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if not _pan_active:
				_dismiss_deduction_overlay()
				get_viewport().set_input_as_handled()
		return

	# Right-click toggles magnifier
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_toggle_magnifier()
		get_viewport().set_input_as_handled()
		return

	# Scroll wheel: magnifier zoom when active, otherwise full-image zoom
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if magnifier_active:
				zoom_out()
			else:
				_image_zoom_out()
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if magnifier_active:
				zoom_in()
			else:
				_image_zoom_in()
			get_viewport().set_input_as_handled()
			return

	# Click / pan-drag handling (left mouse button)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pan_start_pos = event.position
			_pan_last_pos = event.position
			_pan_active = false
		else:
			# Release: if we didn't drag, treat as a click
			if _pan_active:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			else:
				if _handle_click():
					if is_inside_tree():
						get_viewport().set_input_as_handled()
						return
			_pan_active = false
		return

	# Mouse motion: pan when dragging while zoomed
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _image_zoom > 1.0:
		if not _pan_active and event.position.distance_to(_pan_start_pos) > pan_drag_threshold:
			_pan_active = true
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		if _pan_active:
			var delta: Vector2 = event.position - _pan_last_pos
			_content_origin -= delta / _image_zoom
			_clamp_content_origin()
			_update_zoom_transform()
		_pan_last_pos = event.position
		if _pan_active:
			get_viewport().set_input_as_handled()
		return

	# Backspace to go back (sub-scene) or exit (root scene)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BACKSPACE:
			InvestigationHUD.navigate_back()
			if is_inside_tree():
				get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# Animate magnifier fade
	if magnifier_alpha != target_alpha:
		var fade_speed := 1.0 / fade_duration
		magnifier_alpha = move_toward(magnifier_alpha, target_alpha, fade_speed * delta)
		magnifier_container.modulate.a = magnifier_alpha

	# Update magnifier position to follow mouse every frame
	if magnifier_active and magnifier_alpha > 0:
		update_magnifier()

	# Pulse feedback when a transition is available
	_update_transition_pulse()


# ─── Image zoom ──────────────────────────────────────────────

func _setup_zoom_container() -> void:
	"""Apply zoom transforms directly to aspect_container. No reparenting of Controls."""
	_zoom_container = aspect_container

	# Move Investigation-direct clues/TAs into aspect_container so they zoom with the image
	var inv_children := get_children()
	for child in inv_children:
		if is_instance_of(child, _ClueScript) or is_instance_of(child, _TAScript):
			child.reparent(aspect_container)


func _image_zoom_in() -> void:
	var old_zoom := _image_zoom
	_image_zoom = minf(_image_zoom + image_zoom_speed, image_max_zoom)
	if _image_zoom != old_zoom:
		_zoom_toward_cursor(old_zoom)


func _image_zoom_out() -> void:
	var old_zoom := _image_zoom
	_image_zoom = maxf(_image_zoom - image_zoom_speed, 1.0)
	if _image_zoom != old_zoom:
		_zoom_toward_cursor(old_zoom)


func _zoom_toward_cursor(old_zoom: float) -> void:
	"""Adjust zoom and pan so the content under the cursor stays fixed."""
	var cursor_local := get_local_mouse_position()

	# Content position under cursor before zoom change
	var cursor_content := _content_origin + cursor_local / old_zoom

	# New content origin: keep cursor_content at cursor_local
	if _image_zoom > 1.0:
		_content_origin = cursor_content - cursor_local / _image_zoom
	else:
		_content_origin = Vector2.ZERO

	_clamp_content_origin()
	_update_zoom_transform()


func _clamp_content_origin() -> void:
	"""Ensure zoomed content fully covers the viewport (no empty space at edges)."""
	if _image_zoom <= 1.0:
		_content_origin = Vector2.ZERO
		return
	var container_size := _zoom_container.size
	var max_origin := container_size * (1.0 - 1.0 / _image_zoom)
	_content_origin = _content_origin.clamp(Vector2.ZERO, max_origin)


func _update_zoom_transform() -> void:
	"""Apply current _image_zoom and _content_origin via scale + pivot_offset."""
	_zoom_container.scale = Vector2(_image_zoom, _image_zoom)
	if _image_zoom > 1.0:
		_zoom_container.pivot_offset = _content_origin * _image_zoom / (_image_zoom - 1.0)
	else:
		_zoom_container.pivot_offset = Vector2.ZERO


# ─── Magnifier ──────────────────────────────────────────────────

func _toggle_magnifier() -> void:
	if magnifier_active:
		magnifier_active = false
		target_alpha = 0.0
	else:
		magnifier_active = true
		current_zoom = 2.0
		target_alpha = 1.0


func zoom_in() -> void:
	if not magnifier_active:
		return
	if current_zoom >= max_zoom:
		_pulsate_max_reached()
		return
	current_zoom = minf(current_zoom + 1.0, max_zoom)
	if current_zoom >= max_zoom:
		_pulsate_max_reached()


func zoom_out() -> void:
	if not magnifier_active:
		return
	current_zoom = maxf(current_zoom - 1.0, min_zoom)


func _pulsate_max_reached() -> void:
	if _pulsate_tween and _pulsate_tween.is_running():
		return
	_pulsate_tween = create_tween()
	_pulsate_tween.tween_property(magnifier_circle, "scale", Vector2(1.15, 1.15), 0.05)
	_pulsate_tween.tween_property(magnifier_circle, "scale", Vector2.ONE, 0.05)
	_pulsate_tween.tween_property(magnifier_circle, "scale", Vector2(1.15, 1.15), 0.05)
	_pulsate_tween.tween_property(magnifier_circle, "scale", Vector2.ONE, 0.05)


func update_magnifier() -> void:
	if not _active_texture:
		return

	var local_pos := base_image.get_local_mouse_position()
	var img_size := base_image.size

	if img_size.x <= 0 or img_size.y <= 0:
		magnifier_container.visible = false
		return

	if local_pos.x < 0 or local_pos.x > img_size.x or local_pos.y < 0 or local_pos.y > img_size.y:
		magnifier_container.visible = false
		return
	magnifier_container.visible = true

	# Position magnifier at cursor and ensure circle stays centered
	magnifier_container.position = get_global_mouse_position()
	magnifier_circle.position = -magnifier_circle.size / 2.0

	# Replicate Godot's exact "keep aspect covered" rendering
	var tex_size := _active_texture.get_size()
	var cover_scale := maxf(img_size.x / tex_size.x, img_size.y / tex_size.y)
	var scaled_tex := tex_size * cover_scale
	var ofs := ((img_size - scaled_tex) / 2.0).floor()

	# Map local mouse position to texture UV
	var center_uv := (local_pos - ofs) / scaled_tex
	center_uv = center_uv.clamp(Vector2.ZERO, Vector2.ONE)

	# Magnifier UV size at zoom=1
	var magnifier_diameter := magnifier_circle.size.x
	var magnifier_uv_size := Vector2(
		magnifier_diameter / scaled_tex.x,
		magnifier_diameter / scaled_tex.y
	)

	var mat := magnifier_circle.material as ShaderMaterial
	mat.set_shader_parameter("uv_center", center_uv)
	mat.set_shader_parameter("magnifier_uv_size", magnifier_uv_size)
	# Combine magnifier zoom with image zoom so magnifier always adds detail
	mat.set_shader_parameter("zoom", current_zoom * _image_zoom)


func update_magnifier_size() -> void:
	var canvas_height: float = size.y if size.y > 0 else get_viewport().size.y
	var magnifier_diameter: float = canvas_height * magnifier_size_percent * 2.0
	magnifier_circle.custom_minimum_size = Vector2(magnifier_diameter, magnifier_diameter)
	magnifier_circle.size = Vector2(magnifier_diameter, magnifier_diameter)
	magnifier_circle.pivot_offset = Vector2(magnifier_diameter, magnifier_diameter) / 2.0

	var half_size: float = magnifier_diameter / 2.0
	magnifier_circle.position = Vector2(-half_size, -half_size)


func _on_viewport_resized() -> void:
	if magnifier_circle:
		update_magnifier_size()
	if _zoom_container:
		_clamp_content_origin()
		_update_zoom_transform()


# ─── Coordinate conversion ──────────────────────────────────────

func _mouse_to_image_coords() -> Vector2:
	"""Convert current mouse position to original image pixel coordinates.
	Returns Vector2(-1, -1) if outside the visible image area."""
	if not _active_texture:
		return Vector2(-1, -1)

	var local_pos := base_image.get_local_mouse_position()
	var img_size := base_image.size

	if img_size.x <= 0 or img_size.y <= 0:
		return Vector2(-1, -1)

	var tex_size := _active_texture.get_size()
	var cover_scale := maxf(img_size.x / tex_size.x, img_size.y / tex_size.y)
	var scaled_tex := tex_size * cover_scale
	var ofs := ((img_size - scaled_tex) / 2.0).floor()

	var image_pos := (local_pos - ofs) / cover_scale

	if image_pos.x < 0 or image_pos.x >= tex_size.x or image_pos.y < 0 or image_pos.y >= tex_size.y:
		return Vector2(-1, -1)

	return image_pos


func _container_rect_to_image_rect(container_rect: Rect2) -> Rect2:
	"""Convert a rect in zoom container local space to image-pixel-space for AtlasTexture.region."""
	if not _active_texture:
		return Rect2()
	var img_size := base_image.size
	var tex_size := _active_texture.get_size()
	var cover_scale := maxf(img_size.x / tex_size.x, img_size.y / tex_size.y)
	var scaled_tex := tex_size * cover_scale
	var ofs := ((img_size - scaled_tex) / 2.0).floor()

	var image_origin := (container_rect.position - ofs) / cover_scale
	var image_size := container_rect.size / cover_scale
	return Rect2(image_origin, image_size)


# ─── Click handling ─────────────────────────────────────────────

func _handle_click() -> bool:
	"""Process a click event. Returns true if something was interacted with."""
	# Dismiss deduction overlay on any click
	if _deduction_overlay_active:
		_dismiss_deduction_overlay()
		return true

	# Check transition areas first (in Investigation local space)
	if _try_transition():
		return true

	# Check clue polygons (transform-agnostic via to_local)
	var global_mouse := get_global_mouse_position()
	for clue in _clues:
		var did: String = clue.deduction_id
		if not did.is_empty() and _completed_deductions.has(did):
			continue
		var clue_local: Vector2 = clue.to_local(global_mouse)
		if Geometry2D.is_point_in_polygon(clue_local, clue.polygon):
			_toggle_clue(clue)
			return true

	return false


# ─── Clue management ────────────────────────────────────────────

func _setup_clues() -> void:
	_find_nodes_recursive(self, _ClueScript, _clues)


func _toggle_clue(clue: Node) -> void:
	if GameManager.is_clue_selected(_get_clue_key(clue)):
		_deselect_clue(clue)
	elif GameManager.selected_clue_order.size() < _max_clues_per_deduction:
		_select_clue(clue)


func _select_clue(clue: Node) -> void:
	var atlas := _build_atlas_for_clue(clue)
	GameManager.select_clue(_get_clue_key(clue), clue.deduction_id, atlas, scene_file_path)
	# InvestigationHUD reacts to clue_selection_changed signal; wait for slide-in
	await InvestigationHUD.slot_animated
	_check_deduction_completion()


func _deselect_clue(clue: Node) -> void:
	GameManager.deselect_clue(_get_clue_key(clue))


func _setup_deductions() -> void:
	"""Build deduction lookups from InvestigationDef and local clues."""
	var inv_def := _get_investigation_def()
	if inv_def:
		for deduction in inv_def.deductions:
			if not deduction.deduction_id.is_empty():
				_deduction_defs[deduction.deduction_id] = deduction

	# Map LOCAL clues in this scene to their deduction IDs
	for clue in _clues:
		var did: String = clue.deduction_id
		if did.is_empty():
			continue
		if not _deduction_clues.has(did):
			_deduction_clues[did] = []
		_deduction_clues[did].append(clue)

	# Max vignette slots = largest clue count across all deductions (minimum 3)
	var max_count := 3
	if inv_def:
		for ded in inv_def.deductions:
			max_count = maxi(max_count, GameManager.get_required_clue_count(ded.deduction_id))
	for did in _deduction_clues:
		max_count = maxi(max_count, _deduction_clues[did].size())
	_max_clues_per_deduction = max_count

	# Pre-populate completed deductions from GameManager (persistence across scenes)
	for did in _deduction_defs:
		if GameManager.is_deduction_completed(did):
			_completed_deductions[did] = true


func _check_deduction_completion() -> void:
	"""Check if all required clues for any deduction are selected (cross-scene)."""
	for deduction_id in _deduction_defs:
		if _completed_deductions.has(deduction_id):
			continue
		if GameManager.check_deduction_completion(deduction_id):
			var clue_ids: Array[String] = GameManager.get_selected_clues_for_deduction(deduction_id)
			_resolve_deduction(deduction_id, clue_ids)
			return


func _resolve_deduction(deduction_id: String, clue_ids: Array[String]) -> void:
	"""Complete a deduction: turn frames green, hold, slide out, show deduction image."""
	_completed_deductions[deduction_id] = true
	GameManager.complete_deduction(deduction_id)

	# Turn all occupied vignette frames green
	InvestigationHUD.set_frame_colors(Color.GREEN)

	# Hold the green-framed vignettes on screen
	await get_tree().create_timer(deduction_hold_duration).timeout

	# Remove resolved clues from GameManager
	for cid in clue_ids:
		GameManager.deselect_clue(cid)

	# Reset frame colors back to white
	InvestigationHUD.reset_frame_colors()

	# Slide all vignettes out, then show deduction image
	InvestigationHUD.slide_all_out(func():
		var def: DeductionDef = _deduction_defs.get(deduction_id)
		if def and def.image:
			_show_deduction_overlay(def.image)
		else:
			_check_investigation_complete()
	)


func _check_investigation_complete() -> void:
	"""Check if all deductions in the investigation definition are completed."""
	var inv_def := _get_investigation_def()
	if not inv_def:
		return
	for ded in inv_def.deductions:
		if not GameManager.is_deduction_completed(ded.deduction_id):
			return
	GameManager.complete_investigation(inv_def.investigation_id)


# ─── Transition areas ───────────────────────────────────────────

func _setup_transition_areas() -> void:
	_find_nodes_recursive(self, _TAScript, _transition_areas)


func _find_nodes_recursive(node: Node, script: GDScript, results: Array) -> void:
	for child in node.get_children():
		if is_instance_of(child, script):
			results.append(child)
		else:
			_find_nodes_recursive(child, script, results)


func _try_transition() -> bool:
	var effective_zoom := _image_zoom * (current_zoom if magnifier_active else 1.0)
	var global_mouse := get_global_mouse_position()
	for ta_node in _transition_areas:
		var ta: TransitionArea = ta_node
		if effective_zoom < ta.required_zoom:
			continue
		var ta_local: Vector2 = ta.to_local(global_mouse)
		if _is_in_transition_zone(ta, ta_local):
			GameManager.navigate_to(ta.target_scene)
			return true
	return false


func _is_in_transition_zone(ta: TransitionArea, ta_local_pos: Vector2) -> bool:
	"""Check if ta_local_pos (in TA's local space) is in the inner activation zone."""
	var inner_half: Vector2 = ta.size * 0.25
	var inner_rect := Rect2(-inner_half, ta.size * 0.5)
	return inner_rect.has_point(ta_local_pos)


func _is_over_transition_area() -> bool:
	if not magnifier_active:
		return false
	var effective_zoom := _image_zoom * current_zoom
	var global_mouse := get_global_mouse_position()
	for ta_node in _transition_areas:
		var ta: TransitionArea = ta_node
		if effective_zoom < ta.required_zoom:
			continue
		var ta_local: Vector2 = ta.to_local(global_mouse)
		if _is_in_transition_zone(ta, ta_local):
			return true
	return false


func _update_transition_pulse() -> void:
	var over_ta := _is_over_transition_area()
	if over_ta == _is_transition_ready:
		return
	_is_transition_ready = over_ta
	if over_ta:
		_start_transition_pulse()
	else:
		_stop_transition_pulse()


func _start_transition_pulse() -> void:
	if _transition_pulse_tween:
		_transition_pulse_tween.kill()
	var half_duration := 0.5 / transition_pulse_rate
	var peak := Vector2.ONE * (1.0 + transition_pulse_amplitude)
	_transition_pulse_tween = create_tween().set_loops()
	_transition_pulse_tween.tween_property(magnifier_circle, "scale", peak, half_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_transition_pulse_tween.tween_property(magnifier_circle, "scale", Vector2.ONE, half_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_transition_pulse() -> void:
	if _transition_pulse_tween:
		_transition_pulse_tween.kill()
		_transition_pulse_tween = null
	magnifier_circle.scale = Vector2.ONE


# ─── Deduction overlay ─────────────────────────────────────────

func _setup_deduction_overlay() -> void:
	"""Build the centered deduction image overlay (hidden by default)."""
	_deduction_overlay = Control.new()
	_deduction_overlay.name = "DeductionOverlay"
	_deduction_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_deduction_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deduction_overlay.visible = false
	add_child(_deduction_overlay)

	# Semi-transparent background dimmer
	var dimmer := ColorRect.new()
	dimmer.name = "Dimmer"
	dimmer.color = Color(0, 0, 0, 0.5)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deduction_overlay.add_child(dimmer)

	# CenterContainer for auto-centering the panel
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deduction_overlay.add_child(center)

	# Panel holding frame + image
	_deduction_overlay_panel = Control.new()
	_deduction_overlay_panel.name = "DeductionPanel"
	_deduction_overlay_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_deduction_overlay_panel)

	# White frame
	var frame := ColorRect.new()
	frame.name = "Frame"
	frame.color = Color.WHITE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deduction_overlay_panel.add_child(frame)

	# Deduction image
	_deduction_overlay_image = TextureRect.new()
	_deduction_overlay_image.name = "DeductionImage"
	_deduction_overlay_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_deduction_overlay_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_deduction_overlay_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deduction_overlay_panel.add_child(_deduction_overlay_image)


func _show_deduction_overlay(texture: Texture2D) -> void:
	"""Display the deduction completion image centered on screen."""
	_deduction_overlay_active = true

	var img_height := size.y * deduction_image_size_percent
	var aspect := texture.get_size().x / texture.get_size().y
	var img_width := img_height * aspect
	var fw := deduction_frame_width

	var panel_size := Vector2(img_width + fw * 2.0, img_height + fw * 2.0)
	_deduction_overlay_panel.custom_minimum_size = panel_size
	_deduction_overlay_panel.size = panel_size

	# Frame fills the panel
	var frame := _deduction_overlay_panel.get_node("Frame") as ColorRect
	frame.position = Vector2.ZERO
	frame.size = panel_size

	# Image inset by frame width
	_deduction_overlay_image.position = Vector2(fw, fw)
	_deduction_overlay_image.size = Vector2(img_width, img_height)
	_deduction_overlay_image.texture = texture

	_deduction_overlay.modulate.a = 0.0
	_deduction_overlay.visible = true

	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_deduction_overlay, "modulate:a", 1.0, deduction_fade_duration)


func _dismiss_deduction_overlay() -> void:
	"""Fade out the deduction overlay, add thumbnail, and check investigation completion."""
	var completed_texture := _deduction_overlay_image.texture
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(_deduction_overlay, "modulate:a", 0.0, deduction_fade_duration)
	tween.tween_callback(func():
		_deduction_overlay.visible = false
		_deduction_overlay_image.texture = null
		_deduction_overlay_active = false
		if completed_texture:
			InvestigationHUD.add_completed_thumbnail(completed_texture)
		_check_investigation_complete()
	)
