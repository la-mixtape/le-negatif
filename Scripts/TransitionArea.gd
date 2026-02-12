class_name TransitionArea
extends Area2D

## A zone that triggers scene transitions when it occupies a certain percentage of the screen.
## Used for deep-zoom navigation between investigation scenes.

# Signals
signal transition_triggered(target_scene_path: String)
signal back_transition_triggered()

# Export properties
@export var target_scene_path: String = ""  ## Path to the scene to transition to
@export var transition_threshold_in: float = 0.8  ## Coverage threshold to enter (80%)
@export var transition_threshold_out: float = 0.33  ## Coverage threshold to go back (33%)
@export var feedback_start_threshold: float = 0.75  ## When to show visual feedback
@export var transition_delay: float = 0.5  ## Delay before auto-transition (seconds)

# Reference to the ReferenceRect child that defines the transition zone
@onready var reference_rect: ReferenceRect = null

# Visual feedback
var border_shader = preload("res://Resources/dashed_border.gdshader")
var highlight_rect: ColorRect = null
var pulse_tween: Tween = null

# State tracking
var is_transition_ready: bool = false  # True when threshold reached, waiting for timer
var transition_timer: float = 0.0  # Countdown timer before transition
var visual_feedback_active: bool = false  # Is visual feedback currently showing
var last_coverage: float = 0.0  # For debugging
var cooldown_timer: float = 0.0  # Cooldown after transitions to prevent immediate re-trigger
var is_disabled: bool = false  # Temporarily disable during scene transitions
var was_above_threshold: bool = false  # Track if this area was previously zoomed into

func _ready():
	# Find the ReferenceRect child
	for child in get_children():
		if child is ReferenceRect:
			reference_rect = child
			break

	if not reference_rect:
		push_error("TransitionArea '%s' has no ReferenceRect child!" % name)

	# Create highlight border for visual feedback
	highlight_rect = ColorRect.new()
	highlight_rect.name = "TransitionHighlight"
	highlight_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	highlight_rect.set_as_top_level(true)  # Ignore parent transforms

	# Configure shader for pulsing border effect
	var shader_mat = ShaderMaterial.new()
	shader_mat.shader = border_shader
	shader_mat.set_shader_parameter("color", Color(0.0, 1.0, 1.0, 1.0))  # Cyan
	shader_mat.set_shader_parameter("line_width", 3.0)
	shader_mat.set_shader_parameter("dash_size", 10.0)
	shader_mat.set_shader_parameter("gap_size", 10.0)
	shader_mat.set_shader_parameter("velocity", 50.0)
	highlight_rect.material = shader_mat

	add_child(highlight_rect)
	highlight_rect.visible = false

	# Add to group for easy discovery
	add_to_group("transition_areas")

func _process(delta):
	if not reference_rect:
		return

	# Update cooldown timer
	if cooldown_timer > 0:
		cooldown_timer -= delta
		if cooldown_timer <= 0:
			print("[TransitionArea] Cooldown expired, transitions re-enabled")

	# Don't process if disabled or in cooldown or game is transitioning
	if is_disabled or cooldown_timer > 0 or GameManager.is_transitioning:
		return

	# Calculate screen coverage
	var coverage = calculate_screen_coverage()
	last_coverage = coverage

	# Handle visual feedback based on coverage
	if coverage >= feedback_start_threshold and coverage < transition_threshold_in:
		# Show pulsing border, intensity based on proximity to threshold
		var intensity = (coverage - feedback_start_threshold) / (transition_threshold_in - feedback_start_threshold)
		show_visual_feedback(intensity)
		visual_feedback_active = true
		was_above_threshold = true  # Mark that we've been zoomed into
		_adjust_highlight_rect()  # Update position/size continuously
	elif coverage >= transition_threshold_in and not is_transition_ready:
		# Reached transition threshold - start countdown
		is_transition_ready = true
		transition_timer = transition_delay
		was_above_threshold = true  # Mark that we've been zoomed into
		show_visual_feedback(1.0)  # Max intensity
		_adjust_highlight_rect()
		print("[TransitionArea] Threshold reached: %.2f%% coverage, starting %.1fs timer" % [coverage * 100, transition_delay])
	elif coverage < feedback_start_threshold:
		# Below feedback threshold
		if visual_feedback_active:
			hide_visual_feedback()
			visual_feedback_active = false

	# Update highlight rect position if feedback is active (accounts for camera movement)
	if visual_feedback_active:
		_adjust_highlight_rect()

	# Handle transition timer countdown
	if is_transition_ready:
		transition_timer -= delta
		if transition_timer <= 0:
			print("[TransitionArea] Timer expired, triggering transition to: %s" % target_scene_path)
			emit_signal("transition_triggered", target_scene_path)
			is_transition_ready = false  # Prevent re-triggering
			hide_visual_feedback()
			visual_feedback_active = false
			is_disabled = true  # Disable during transition

	# Handle backward transition
	# Only trigger if this area was previously zoomed into (was_above_threshold)
	if coverage < transition_threshold_out and not is_transition_ready and was_above_threshold:
		if GameManager.get_current_depth() > 0:
			print("[TransitionArea] Coverage dropped to %.2f%%, triggering back transition" % [coverage * 100])
			emit_signal("back_transition_triggered")
			# Disable and add cooldown to prevent immediate re-trigger
			is_disabled = true
			hide_visual_feedback()
			visual_feedback_active = false
			is_transition_ready = true
			was_above_threshold = false  # Reset flag
			cooldown_timer = 2.0  # 2 second cooldown

func calculate_screen_coverage() -> float:
	"""
	Calculates what percentage of the viewport is occupied by the ReferenceRect.
	Returns a value between 0.0 (not visible) and 1.0 (fills entire screen).
	"""
	var camera = get_viewport().get_camera_2d()
	if not camera or not reference_rect:
		return 0.0

	# Get viewport size
	var viewport_size = get_viewport().get_visible_rect().size
	var viewport_area = viewport_size.x * viewport_size.y

	if viewport_area == 0:
		return 0.0

	# Get ReferenceRect corners in global space
	var rect_global_transform = reference_rect.get_global_transform_with_canvas()
	var rect_size = reference_rect.size

	# Transform corners to screen space (accounting for camera)
	var corners = [
		Vector2(0, 0),
		Vector2(rect_size.x, 0),
		Vector2(rect_size.x, rect_size.y),
		Vector2(0, rect_size.y)
	]

	var screen_corners = []
	for corner in corners:
		var world_pos = rect_global_transform * corner
		# Convert world position to screen position accounting for camera
		var screen_pos = (world_pos - camera.get_screen_center_position()) * camera.zoom + viewport_size / 2
		screen_corners.append(screen_pos)

	# Calculate bounding box in screen space
	var min_x = INF
	var max_x = -INF
	var min_y = INF
	var max_y = -INF

	for screen_corner in screen_corners:
		min_x = min(min_x, screen_corner.x)
		max_x = max(max_x, screen_corner.x)
		min_y = min(min_y, screen_corner.y)
		max_y = max(max_y, screen_corner.y)

	# Clamp to viewport bounds (handle partial off-screen)
	min_x = clamp(min_x, 0, viewport_size.x)
	max_x = clamp(max_x, 0, viewport_size.x)
	min_y = clamp(min_y, 0, viewport_size.y)
	max_y = clamp(max_y, 0, viewport_size.y)

	# Calculate on-screen area
	var screen_width = max(0, max_x - min_x)
	var screen_height = max(0, max_y - min_y)
	var screen_area = screen_width * screen_height

	# Return coverage ratio
	return screen_area / viewport_area

func show_visual_feedback(intensity: float):
	"""
	Shows visual feedback (pulsing border) with given intensity (0.0 to 1.0).
	Intensity affects the opacity and pulsing speed.
	"""
	if not highlight_rect or not reference_rect:
		return

	# Position and size the highlight to match the ReferenceRect
	_adjust_highlight_rect()

	# Make visible
	highlight_rect.visible = true

	# Update color intensity (fade from transparent to bright cyan)
	var mat = highlight_rect.material as ShaderMaterial
	if mat:
		var alpha = 0.3 + (intensity * 0.7)  # 0.3 to 1.0 alpha
		mat.set_shader_parameter("color", Color(0.0, 1.0, 1.0, alpha))

	# Create pulsing animation
	if pulse_tween:
		pulse_tween.kill()

	pulse_tween = create_tween()
	pulse_tween.set_loops()
	pulse_tween.set_ease(Tween.EASE_IN_OUT)
	pulse_tween.set_trans(Tween.TRANS_SINE)

	# Pulse the line width (faster pulse at higher intensity)
	var pulse_speed = 0.5 - (intensity * 0.2)  # 0.5s to 0.3s
	pulse_tween.tween_method(
		func(width): mat.set_shader_parameter("line_width", width),
		2.0,
		5.0,
		pulse_speed
	)
	pulse_tween.tween_method(
		func(width): mat.set_shader_parameter("line_width", width),
		5.0,
		2.0,
		pulse_speed
	)

func hide_visual_feedback():
	"""
	Hides the visual feedback.
	"""
	if highlight_rect:
		highlight_rect.visible = false

	if pulse_tween:
		pulse_tween.kill()
		pulse_tween = null

func _adjust_highlight_rect():
	"""
	Positions and sizes the highlight rect to match the ReferenceRect bounds.
	"""
	if not highlight_rect or not reference_rect:
		return

	var rect_global = reference_rect.get_global_rect()

	# Set position and size
	highlight_rect.global_position = rect_global.position
	highlight_rect.size = rect_global.size

	# Pass size to shader for proper border rendering
	var mat = highlight_rect.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("rect_size", rect_global.size)

func reset_transition_state():
	"""
	Resets the transition state (useful after a transition completes).
	Adds a cooldown period to prevent immediate re-triggering.
	"""
	is_transition_ready = false
	transition_timer = 0.0
	cooldown_timer = 2.0  # 2 second cooldown after restoration
	is_disabled = false
	was_above_threshold = false  # Reset the tracking flag
	if visual_feedback_active:
		hide_visual_feedback()
		visual_feedback_active = false
	print("[TransitionArea] State reset with 2s cooldown")
