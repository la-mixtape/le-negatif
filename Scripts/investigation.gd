extends Control
class_name Investigation

## Investigation scene - displays a 2D image with magnifier tool.
## Supports clue discovery (click polygons, vignette HUD) and
## scene transitions via TransitionArea children.

# ─── Magnifier exports ───────────────────────────────────────────

## Maximum zoom level for the magnifier
@export var max_zoom: float = 8.0

## Minimum zoom level for the magnifier
@export var min_zoom: float = 1.0

## Size of the magnifier as a percentage of screen height
@export_range(0.05, 0.5) var magnifier_size_percent: float = 0.125

## Fade duration for magnifier show/hide
@export var fade_duration: float = 0.2

## Fraction of magnifier radius with uniform zoom (rest has quadratic falloff)
@export_range(0.0, 1.0) var lens_inner_radius: float = 0.80

## Strength of lens distortion at edges
@export_range(0.0, 3.0) var lens_distortion: float = 0.75

# ─── Constants ──────────────────────────────────────────────────

const MAX_SELECTED_CLUES := 3
const VIGNETTE_SLOT_WIDTH := 250.0
const VIGNETTE_SLIDE_DURATION := 0.3

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

# ─── Clue & interaction state ───────────────────────────────────

var _clues: Array = []
var _transition_areas: Array = []
var _selected_clues: Array = []

# ─── Vignette HUD ──────────────────────────────────────────────

var _vignette_hud: Control
var _vignette_slots: Array[Control] = []
var _vignette_images: Array[TextureRect] = []
var _vignette_tweens: Array = []

# ─── Nodes ──────────────────────────────────────────────────────

@onready var background: ColorRect = $Background
@onready var aspect_container: AspectRatioContainer = $AspectContainer
@onready var base_image: TextureRect = $AspectContainer/BaseImage
@onready var magnifier_container: Control = $MagnifierContainer
@onready var magnifier_circle: ColorRect = $MagnifierContainer/MagnifierCircle


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

	# Set up magnifier size
	update_magnifier_size()

	# Connect resize signal to handle letterboxing
	get_viewport().size_changed.connect(_on_viewport_resized)

	# Discover game objects placed as children
	_setup_clues()
	_setup_transition_areas()

	# Build vignette HUD for clue display
	_setup_vignette_hud()


func _input(event: InputEvent) -> void:
	# Zoom control: scroll wheel / E/A keys (via input map) and +/- keys
	var is_zoom_in := event.is_action_pressed("zoom_in")
	var is_zoom_out := event.is_action_pressed("zoom_out")
	if event is InputEventKey and event.pressed and not event.echo:
		if event.unicode == 43 or event.keycode == KEY_KP_ADD:
			is_zoom_in = true
		elif event.unicode == 45 or event.keycode == KEY_KP_SUBTRACT:
			is_zoom_out = true

	if is_zoom_in:
		zoom_in()
		get_viewport().set_input_as_handled()
		return
	if is_zoom_out and magnifier_active:
		zoom_out()
		get_viewport().set_input_as_handled()
		return

	# Click for clue/transition interaction
	if event.is_action_pressed("click"):
		if _handle_click():
			get_viewport().set_input_as_handled()
			return

	# Backspace to go back to previous investigation
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BACKSPACE:
			if GameManager.go_back():
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


# ─── Magnifier ──────────────────────────────────────────────────

func zoom_in() -> void:
	if not magnifier_active:
		magnifier_active = true
		current_zoom = 2.0
		target_alpha = 1.0
		return
	if current_zoom >= max_zoom:
		_pulsate_max_reached()
		return
	current_zoom = minf(current_zoom * 2.0, max_zoom)
	if current_zoom >= max_zoom:
		_pulsate_max_reached()


func zoom_out() -> void:
	current_zoom = maxf(current_zoom / 2.0, min_zoom)
	if current_zoom <= min_zoom:
		magnifier_active = false
		target_alpha = 0.0


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
	mat.set_shader_parameter("zoom", current_zoom)


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
	_update_vignette_layout()


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


func _local_rect_to_image_rect(inv_rect: Rect2) -> Rect2:
	"""Convert a rect in Investigation local space to image-pixel-space for AtlasTexture.region."""
	if not _active_texture:
		return Rect2()
	var img_size := base_image.size
	var tex_size := _active_texture.get_size()
	var cover_scale := maxf(img_size.x / tex_size.x, img_size.y / tex_size.y)
	var scaled_tex := tex_size * cover_scale
	var ofs := ((img_size - scaled_tex) / 2.0).floor()

	# Investigation local space → BaseImage local space
	var base_offset := base_image.global_position - global_position
	var bi_origin := inv_rect.position - base_offset

	# BaseImage local → image pixel coords (inverse of cover-scale transform)
	var image_origin := (bi_origin - ofs) / cover_scale
	var image_size := inv_rect.size / cover_scale
	return Rect2(image_origin, image_size)


# ─── Click handling ─────────────────────────────────────────────

func _handle_click() -> bool:
	"""Process a click event. Returns true if something was interacted with."""
	# Check transition areas first (in Investigation local space)
	if _try_transition():
		return true

	# Check clue polygons (in Investigation local space, like transition areas)
	var local_pos := get_local_mouse_position()
	for clue in _clues:
		if GameManager.is_clue_discovered(clue.clue_id):
			continue
		# Polygon2D polygon points are offsets from clue.position — translate to Investigation space
		var world_poly := PackedVector2Array()
		for point in clue.polygon:
			world_poly.append(point + clue.position)
		if Geometry2D.is_point_in_polygon(local_pos, world_poly):
			_toggle_clue(clue)
			return true

	return false


# ─── Clue management ────────────────────────────────────────────

func _setup_clues() -> void:
	for child in get_children():
		if child is _ClueScript:
			_clues.append(child)


func _toggle_clue(clue: Node) -> void:
	if clue in _selected_clues:
		_deselect_clue(clue)
	elif _selected_clues.size() < MAX_SELECTED_CLUES:
		_select_clue(clue)


func _select_clue(clue: Node) -> void:
	_selected_clues.append(clue)
	_rebuild_vignette_display()
	_check_chain_resolution()


func _deselect_clue(clue: Node) -> void:
	var index := _selected_clues.find(clue)
	if index == -1:
		return
	_selected_clues.remove_at(index)
	_rebuild_vignette_display()


func _check_chain_resolution() -> void:
	"""Check if selected clues form a complete chain and resolve it."""
	if _selected_clues.size() < 2:
		return

	# Build lookup of selected clues by ID
	var selected_by_id: Dictionary = {}
	for clue in _selected_clues:
		selected_by_id[clue.clue_id] = clue

	# Find clues pointed to as "next" by another selected clue
	var pointed_to: Dictionary = {}
	for clue in _selected_clues:
		if not clue.next_clue_id.is_empty() and selected_by_id.has(clue.next_clue_id):
			pointed_to[clue.next_clue_id] = true

	# Try each potential chain start (not pointed to by another selected clue)
	for clue in _selected_clues:
		if pointed_to.has(clue.clue_id):
			continue

		# Walk chain from this start
		var chain: Array = [clue]
		var current: Node = clue
		while not current.next_clue_id.is_empty() and selected_by_id.has(current.next_clue_id):
			current = selected_by_id[current.next_clue_id]
			chain.append(current)

		# Complete chain: last clue has no successor and chain has 2+ clues
		if current.next_clue_id.is_empty() and chain.size() >= 2:
			_resolve_chain(chain)
			return


func _resolve_chain(chain: Array) -> void:
	"""Mark all clues in a completed chain as discovered."""
	for clue in chain:
		GameManager.discover_clue(clue.clue_id)

	for clue in chain:
		var idx := _selected_clues.find(clue)
		if idx != -1:
			_selected_clues.remove_at(idx)

	_rebuild_vignette_display()
	_check_investigation_complete()


func _check_investigation_complete() -> void:
	for clue in _clues:
		if not GameManager.is_clue_discovered(clue.clue_id):
			return
	GameManager.complete_investigation(scene_file_path)


# ─── Transition areas ───────────────────────────────────────────

func _setup_transition_areas() -> void:
	for child in get_children():
		if child is _TAScript:
			_transition_areas.append(child)


func _try_transition() -> bool:
	var effective_zoom := current_zoom if magnifier_active else 1.0
	var local_pos := get_local_mouse_position()
	for ta in _transition_areas:
		if effective_zoom < ta.required_zoom:
			continue
		# Active zone: central 50% of the transition rect (centered on node position)
		var ta_rect := Rect2(ta.position - ta.size / 2.0, ta.size)
		var center: Vector2 = ta_rect.get_center()
		var inner_size: Vector2 = ta_rect.size * 0.5
		var inner_rect := Rect2(center - inner_size / 2.0, inner_size)
		if inner_rect.has_point(local_pos):
			GameManager.navigate_to(ta.target_scene)
			return true
	return false


# ─── Vignette HUD ──────────────────────────────────────────────

func _setup_vignette_hud() -> void:
	_vignette_hud = Control.new()
	_vignette_hud.name = "VignetteHUD"
	_vignette_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_vignette_hud)

	var slot_height := size.y / float(MAX_SELECTED_CLUES)
	for i in MAX_SELECTED_CLUES:
		var slot := Control.new()
		slot.name = "VignetteSlot%d" % i
		slot.clip_contents = true
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.position = Vector2(size.x - VIGNETTE_SLOT_WIDTH, i * slot_height)
		slot.size = Vector2(VIGNETTE_SLOT_WIDTH, slot_height)
		_vignette_hud.add_child(slot)
		_vignette_slots.append(slot)

		var img := TextureRect.new()
		img.name = "VignetteImage"
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.size = Vector2(VIGNETTE_SLOT_WIDTH, slot_height)
		img.position = Vector2(VIGNETTE_SLOT_WIDTH, 0)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(img)
		_vignette_images.append(img)
		_vignette_tweens.append(null)


func _update_vignette_layout() -> void:
	if not _vignette_hud:
		return
	var slot_height := size.y / float(MAX_SELECTED_CLUES)
	for i in MAX_SELECTED_CLUES:
		_vignette_slots[i].position = Vector2(size.x - VIGNETTE_SLOT_WIDTH, i * slot_height)
		_vignette_slots[i].size = Vector2(VIGNETTE_SLOT_WIDTH, slot_height)
		_vignette_images[i].size = Vector2(VIGNETTE_SLOT_WIDTH, slot_height)


func _rebuild_vignette_display() -> void:
	for i in MAX_SELECTED_CLUES:
		var img := _vignette_images[i]

		# Kill any running tween for this slot
		if _vignette_tweens[i]:
			_vignette_tweens[i].kill()

		if i < _selected_clues.size():
			var clue: Node = _selected_clues[i]
			# Set vignette texture from polygon AABB region
			var vignette: Rect2 = clue.get_vignette_rect_local()
			if _active_texture and vignette.size != Vector2.ZERO:
				var atlas := AtlasTexture.new()
				atlas.atlas = _active_texture
				var inv_rect := Rect2(clue.position + vignette.position, vignette.size)
				atlas.region = _local_rect_to_image_rect(inv_rect)
				img.texture = atlas
			# Slide in from right
			var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(img, "position", Vector2.ZERO, VIGNETTE_SLIDE_DURATION)
			_vignette_tweens[i] = tween
		else:
			if img.texture:
				# Slide out to the right
				var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
				tween.tween_property(img, "position", Vector2(VIGNETTE_SLOT_WIDTH, 0), VIGNETTE_SLIDE_DURATION)
				tween.tween_callback(func(): img.texture = null)
				_vignette_tweens[i] = tween
			else:
				img.position = Vector2(VIGNETTE_SLOT_WIDTH, 0)
