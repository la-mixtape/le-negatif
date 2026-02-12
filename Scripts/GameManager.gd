extends Node


# Variables pour stocker l'avancement
var current_scene_name: String = ""
var deductions_found: Array = [] # Liste des déductions trouvées
var is_drag_active: bool = false # Pour gérer le drag & drop plus tard

# Scene transition stack management
var scene_stack: Array[Dictionary] = []  # Stack of scene states for back navigation
var current_scene: Node = null  # Reference to the currently active scene
var is_transitioning: bool = false  # Prevent transitions during animation
const MAX_SCENE_DEPTH: int = 10  # Maximum nesting depth to prevent memory issues

func _ready():
	print("GameManager initialisé.")

# Fonction pour ajouter une déduction (sera utilisée plus tard selon le GDD)
func add_deduction(deduction_id: String):
	if deduction_id not in deductions_found:
		deductions_found.append(deduction_id)
		print("Nouvelle déduction trouvée : " + deduction_id)

# ============================================================================
# SCENE TRANSITION STACK MANAGEMENT
# ============================================================================

func push_scene_state(state: Dictionary) -> void:
	"""
	Saves the current scene state to the stack.
	Frees the oldest scene if depth exceeds MAX_SCENE_DEPTH.
	"""
	scene_stack.append(state)
	print("[GameManager] Pushed scene state. Stack depth: %d" % scene_stack.size())

	# Free oldest scenes if we exceed max depth
	if scene_stack.size() > MAX_SCENE_DEPTH:
		var oldest_state = scene_stack.pop_front()
		if oldest_state.has("scene_instance") and oldest_state["scene_instance"]:
			oldest_state["scene_instance"].queue_free()
		print("[GameManager] Max depth exceeded, freed oldest scene")

func pop_scene_state() -> Dictionary:
	"""
	Removes and returns the top scene state from the stack.
	Returns an empty dictionary if the stack is empty.
	"""
	if scene_stack.is_empty():
		push_warning("[GameManager] Attempted to pop from empty scene stack")
		return {}

	var state = scene_stack.pop_back()
	print("[GameManager] Popped scene state. Stack depth: %d" % scene_stack.size())
	return state

func get_current_depth() -> int:
	"""Returns the current scene stack depth."""
	return scene_stack.size()

func can_go_back() -> bool:
	"""Returns true if we can navigate back (stack not empty and not transitioning)."""
	return scene_stack.size() > 0 and not is_transitioning

func transition_to_scene(target_path: String, from_scene: Node2D) -> void:
	"""
	Main transition orchestrator - transitions from current scene to a new scene.
	Saves the current scene state to the stack and loads the new scene.
	"""
	if is_transitioning:
		push_warning("[GameManager] Transition already in progress, ignoring")
		return

	if target_path.is_empty():
		push_error("[GameManager] Target scene path is empty!")
		return

	print("[GameManager] Starting transition from '%s' to '%s'" % [from_scene.name, target_path])
	is_transitioning = true

	# Cancel active zoom tweens in the current scene
	if from_scene.has_method("cancel_zoom_tween"):
		from_scene.cancel_zoom_tween()

	# Collect current scene state
	var camera_obj = from_scene.get("camera")
	var state = {
		"scene_path": from_scene.scene_file_path,
		"camera_position": camera_obj.position if camera_obj else Vector2.ZERO,
		"camera_zoom": camera_obj.zoom.x if camera_obj else 1.0,
		"selected_objects": from_scene.selected_objects.duplicate() if from_scene.get("selected_objects") else [],
		"found_chains": from_scene.found_chains.duplicate() if from_scene.get("found_chains") else [],
		"scene_instance": from_scene
	}

	# Save to stack
	push_scene_state(state)

	# Create fade-out animation
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(from_scene, "modulate:a", 0.0, 0.3)
	# Slight zoom-in effect during transition
	if camera_obj:
		var current_zoom = camera_obj.zoom.x
		tween.tween_property(camera_obj, "zoom", Vector2(current_zoom * 1.2, current_zoom * 1.2), 0.3)

	await tween.finished

	# Remove current scene from tree (keep in memory via stack)
	var root = get_tree().root
	from_scene.get_parent().remove_child(from_scene)

	# Load and instantiate new scene
	var new_scene_resource = load(target_path)
	if not new_scene_resource:
		push_error("[GameManager] Failed to load scene: %s" % target_path)
		is_transitioning = false
		return

	var new_scene = new_scene_resource.instantiate()

	# Add new scene to tree
	root.add_child(new_scene)
	current_scene = new_scene  # Track the active scene

	# Set camera to default position (centered) and zoom (1.0)
	var new_camera = new_scene.get("camera")
	if new_camera:
		new_camera.position = new_scene.get_viewport_rect().size / 2
		new_camera.zoom = Vector2(1.0, 1.0)

	# Start with scene invisible, then fade in
	new_scene.modulate.a = 0.0
	var fade_in_tween = create_tween()
	fade_in_tween.tween_property(new_scene, "modulate:a", 1.0, 0.3)

	await fade_in_tween.finished

	# Update current scene name
	current_scene_name = target_path

	is_transitioning = false
	print("[GameManager] Transition complete. Current depth: %d" % get_current_depth())

func return_to_previous_scene() -> void:
	"""
	Returns to the previous scene by popping from the stack and restoring state.
	"""
	if is_transitioning:
		push_warning("[GameManager] Transition already in progress, ignoring")
		return

	if not can_go_back():
		push_warning("[GameManager] No scene to return to!")
		return

	print("[GameManager] Returning to previous scene...")
	is_transitioning = true

	# Make sure we have a current scene to remove
	if not current_scene or not is_instance_valid(current_scene):
		push_error("[GameManager] No valid current scene to remove!")
		is_transitioning = false
		return

	print("[GameManager] Removing scene: %s" % current_scene.name)

	# Fade out current scene
	var tween = create_tween()
	tween.tween_property(current_scene, "modulate:a", 0.0, 0.3)
	await tween.finished

	# Remove and free current scene
	current_scene.get_parent().remove_child(current_scene)
	current_scene.queue_free()

	# Pop previous scene state from stack
	var state = pop_scene_state()

	# Re-add previous scene from memory
	var previous_scene = state["scene_instance"]
	get_tree().root.add_child(previous_scene)
	current_scene = previous_scene  # Update current scene reference

	print("[GameManager] Restored scene: %s" % previous_scene.name)

	# Restore camera state
	var prev_camera = previous_scene.get("camera")
	if prev_camera:
		prev_camera.position = state["camera_position"]
		prev_camera.zoom = Vector2(state["camera_zoom"], state["camera_zoom"])

	# Restore HUD state (selected objects)
	if previous_scene.has_method("restore_hud_state"):
		previous_scene.restore_hud_state(state["selected_objects"])

	# Restore found chains
	if previous_scene.get("found_chains") != null:
		previous_scene.found_chains = state["found_chains"]

	# Fade in restored scene
	previous_scene.modulate.a = 0.0
	var fade_in_tween = create_tween()
	fade_in_tween.tween_property(previous_scene, "modulate:a", 1.0, 0.3)

	await fade_in_tween.finished

	# Smoothly zoom out to below threshold if needed
	if prev_camera:
		# Check if any TransitionArea would be too zoomed in
		var needs_zoom_out = false
		var target_zoom_level = state["camera_zoom"]

		for area in get_tree().get_nodes_in_group("transition_areas"):
			if area.has_method("calculate_screen_coverage"):
				var coverage = area.calculate_screen_coverage()
				# If coverage is above (threshold - 5%), zoom out
				if coverage > (area.transition_threshold_in - 0.05):
					needs_zoom_out = true
					# Calculate zoom factor to reduce coverage by ~20%
					# Since coverage scales with zoom^2 (area), reducing zoom by 0.85x reduces coverage significantly
					target_zoom_level = state["camera_zoom"] * 0.85
					print("[GameManager] Coverage %.2f%% too high, will zoom out to %.2fx" % [coverage * 100, target_zoom_level])
					break

		if needs_zoom_out:
			# Smooth zoom out animation
			var zoom_out_tween = create_tween()
			zoom_out_tween.set_ease(Tween.EASE_OUT)
			zoom_out_tween.set_trans(Tween.TRANS_QUAD)
			zoom_out_tween.tween_property(
				prev_camera,
				"zoom",
				Vector2(target_zoom_level, target_zoom_level),
				0.5
			)
			await zoom_out_tween.finished
			print("[GameManager] Auto zoom-out complete")

	# Update current scene name
	current_scene_name = state["scene_path"]

	# Reset transition areas in the restored scene
	for area in get_tree().get_nodes_in_group("transition_areas"):
		if area.has_method("reset_transition_state"):
			area.reset_transition_state()

	is_transitioning = false
	print("[GameManager] Return complete. Current depth: %d" % get_current_depth())
