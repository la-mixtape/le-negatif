extends Control
class_name Investigation

## Investigation scene - displays a 2D image with magnifier tool
## Maintains 16:9 aspect ratio with letterboxing

## The image texture to investigate
@export var image_texture: Texture2D

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

## Nodes (set via @onready after scene is built)
@onready var background: ColorRect = $Background
@onready var aspect_container: AspectRatioContainer = $AspectContainer
@onready var base_image: TextureRect = $AspectContainer/BaseImage
@onready var magnifier_container: Control = $MagnifierContainer
@onready var magnifier_circle: ColorRect = $MagnifierContainer/MagnifierCircle


func _ready() -> void:
	print("[Investigation] Starting investigation scene")
	print("[Investigation] Viewport size: ", get_viewport().size)

	# Determine the active texture:
	# - BaseImage scene override takes precedence (set in the editor on the node)
	# - Falls back to image_texture export (set on the Investigation root)
	if base_image.texture:
		_active_texture = base_image.texture
		if image_texture and image_texture != base_image.texture:
			print("[Investigation] WARNING: image_texture export (", image_texture.resource_path, ") differs from BaseImage texture (", base_image.texture.resource_path, "). Using BaseImage texture.")
		print("[Investigation] Using BaseImage texture: ", _active_texture.resource_path, " ", _active_texture.get_size())
	elif image_texture:
		_active_texture = image_texture
		base_image.texture = _active_texture
		print("[Investigation] Using image_texture export: ", _active_texture.resource_path, " ", _active_texture.get_size())
	else:
		print("[Investigation] WARNING: No image texture assigned!")

	# Pass the texture to the magnifier shader
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

	print("[Investigation] Ready! Press M to toggle magnifier, scroll wheel to zoom")


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
	elif is_zoom_out and magnifier_active:
		zoom_out()
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


func zoom_in() -> void:
	if not magnifier_active:
		magnifier_active = true
		current_zoom = 2.0
		target_alpha = 1.0
		print("[Investigation] Magnifier enabled (zoom: 2.0x)")
		return
	if current_zoom >= max_zoom:
		_pulsate_max_reached()
		return
	current_zoom = minf(current_zoom * 2.0, max_zoom)
	print("[Investigation] Zoom in: ", current_zoom, "x")
	if current_zoom >= max_zoom:
		_pulsate_max_reached()


func zoom_out() -> void:
	current_zoom = maxf(current_zoom / 2.0, min_zoom)
	print("[Investigation] Zoom out: ", current_zoom, "x")
	if current_zoom <= min_zoom:
		magnifier_active = false
		target_alpha = 0.0
		print("[Investigation] Magnifier disabled (zoom reached 1.0x)")


func _pulsate_max_reached() -> void:
	if _pulsate_tween and _pulsate_tween.is_running():
		return
	_pulsate_tween = create_tween()
	_pulsate_tween.tween_property(magnifier_circle, "scale", Vector2(1.15, 1.15), 0.05)
	_pulsate_tween.tween_property(magnifier_circle, "scale", Vector2.ONE, 0.05)
	_pulsate_tween.tween_property(magnifier_circle, "scale", Vector2(1.15, 1.15), 0.05)
	_pulsate_tween.tween_property(magnifier_circle, "scale", Vector2.ONE, 0.05)


var _debug_logged: bool = false


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

	# Replicate Godot's exact "keep aspect covered" (stretch_mode 5) rendering.
	# Godot source: scale = max(size.x/tex.x, size.y/tex.y), ofs = floor((size - scaled) / 2)
	var tex_size := _active_texture.get_size()
	var cover_scale := maxf(img_size.x / tex_size.x, img_size.y / tex_size.y)
	var scaled_tex := tex_size * cover_scale
	var ofs := ((img_size - scaled_tex) / 2.0).floor()

	# Map local mouse position → texture UV (matching Godot's draw_texture_rect_region)
	var center_uv := (local_pos - ofs) / scaled_tex
	center_uv = center_uv.clamp(Vector2.ZERO, Vector2.ONE)

	# Magnifier UV size at zoom=1
	var magnifier_diameter := magnifier_circle.size.x
	var magnifier_uv_size := Vector2(
		magnifier_diameter / scaled_tex.x,
		magnifier_diameter / scaled_tex.y
	)

	# Debug log (one-shot)
	if not _debug_logged:
		_debug_logged = true
		print("[Investigation] DEBUG update_magnifier:")
		print("  local_pos=", local_pos, " img_size=", img_size)
		print("  tex_size=", tex_size, " cover_scale=", cover_scale)
		print("  scaled_tex=", scaled_tex, " ofs=", ofs)
		print("  center_uv=", center_uv, " magnifier_uv_size=", magnifier_uv_size)
		print("  simple_uv=", local_pos / img_size)
		print("  magnifier_diameter=", magnifier_diameter, " zoom=", current_zoom)
		print("  circle.position=", magnifier_circle.position, " circle.size=", magnifier_circle.size)
		print("  circle.global_position=", magnifier_circle.global_position)

	var mat := magnifier_circle.material as ShaderMaterial
	mat.set_shader_parameter("uv_center", center_uv)
	mat.set_shader_parameter("magnifier_uv_size", magnifier_uv_size)
	mat.set_shader_parameter("zoom", current_zoom)


func update_magnifier_size() -> void:
	# Use the root Control's canvas-space height (not viewport pixel height)
	var canvas_height: float = size.y if size.y > 0 else get_viewport().size.y
	var magnifier_diameter: float = canvas_height * magnifier_size_percent * 2.0
	magnifier_circle.custom_minimum_size = Vector2(magnifier_diameter, magnifier_diameter)
	magnifier_circle.size = Vector2(magnifier_diameter, magnifier_diameter)
	magnifier_circle.pivot_offset = Vector2(magnifier_diameter, magnifier_diameter) / 2.0

	# Center the circle on the container position
	var half_size: float = magnifier_diameter / 2.0
	magnifier_circle.position = Vector2(-half_size, -half_size)

	print("[Investigation] Magnifier size updated: ", magnifier_diameter, "px (", magnifier_size_percent * 100, "% of screen height)")


func _on_viewport_resized() -> void:
	print("[Investigation] Viewport resized to: ", get_viewport().size)

	if magnifier_circle:
		update_magnifier_size()
