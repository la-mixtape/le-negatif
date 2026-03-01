extends Node

## Global game manager for state and progression tracking.
## This is an autoload singleton accessible via GameManager.
## Now scene-based (scenes/autoloads/game_manager.tscn) to support @export.

# ─── Signals ──────────────────────────────────────────────────

signal investigation_changed(investigation_id: String, sub_index: int)
signal clue_discovered(clue_id: String)
signal deduction_completed(deduction_id: String)
signal investigation_completed(investigation_id: String)
signal clue_selection_changed()
signal investigation_started
signal deduction_availability_changed(deduction_id: String, available: bool)

# ─── Investigation registry ──────────────────────────────────

## Master list of all available investigations (configure in the editor)
@export var investigations: Array[InvestigationDef] = []

# ─── Investigation state ─────────────────────────────────────

## Current investigation identifier
var current_investigation_id: String = ""

## Current sub-investigation index
var current_sub_investigation: int = 0

## The active InvestigationDef for the current playthrough
var _active_investigation: InvestigationDef = null

# ─── Persistence state ───────────────────────────────────────

## Dictionary tracking discovered clues
var discovered_clues: Dictionary = {}

## Dictionary tracking completed deductions
var completed_deductions: Dictionary = {}

## Dictionary tracking completed investigations
var completed_investigations: Dictionary = {}

## Navigation stack for scene transitions (backspace to go back)
var scene_stack: Array[String] = []

# ─── Cross-scene clue selection ──────────────────────────────

## Per-clue selection data stored as Dictionary:
##   { clue_id: String, deduction_ids: PackedStringArray, atlas_texture: AtlasTexture, scene_path: String }
## Keyed by clue_id.
var selected_clues: Dictionary = {}

## Ordered list of selected clue keys (drives vignette slot order)
var selected_clue_order: Array[String] = []

## Auto-discovered mapping of deduction_id -> Array[String] of clue keys
var _deduction_clue_registry: Dictionary = {}

## Tracks which deductions are currently available
var available_deductions: Dictionary = {}


func _ready() -> void:
	pass


# ─── Investigation lifecycle ─────────────────────────────────

func get_active_investigation() -> InvestigationDef:
	return _active_investigation


func start_new_investigation(investigation_id: String) -> void:
	"""Clear session state and navigate to the root scene of the given investigation."""
	_active_investigation = null
	for inv in investigations:
		if inv.investigation_id == investigation_id:
			_active_investigation = inv
			break
	if not _active_investigation:
		push_warning("GameManager: investigation '%s' not found in registry" % investigation_id)
		return

	current_investigation_id = investigation_id
	current_sub_investigation = 0

	# Clear per-investigation session state
	selected_clues.clear()
	selected_clue_order.clear()
	discovered_clues.clear()
	completed_deductions.clear()
	available_deductions.clear()
	scene_stack.clear()

	# Notify persistent HUD to clear before rebuilding
	investigation_started.emit()

	# Auto-discover clues across all scenes in the investigation tree
	_scan_investigation_tree()

	# Compute initial deduction availability
	evaluate_availability()

	navigate_to(_active_investigation.root_scene)


func start_investigation(investigation_id: String, sub_index: int = 0) -> void:
	"""Begin a new investigation or resume at a specific sub-investigation."""
	current_investigation_id = investigation_id
	current_sub_investigation = sub_index
	investigation_changed.emit(investigation_id, sub_index)


func advance_sub_investigation() -> bool:
	"""Advance to the next sub-investigation. Returns true if advanced, false if at end."""
	current_sub_investigation += 1
	investigation_changed.emit(current_investigation_id, current_sub_investigation)
	return true


func complete_investigation(investigation_id: String = "") -> void:
	"""Mark an investigation as completed."""
	if investigation_id.is_empty():
		investigation_id = current_investigation_id
	completed_investigations[investigation_id] = true
	investigation_completed.emit(investigation_id)


func is_investigation_completed(investigation_id: String) -> bool:
	"""Check if an investigation has been completed."""
	return completed_investigations.get(investigation_id, false)


# ─── Clue discovery ──────────────────────────────────────────

func discover_clue(clue_id: String) -> void:
	"""Register a discovered clue."""
	if not discovered_clues.has(clue_id):
		discovered_clues[clue_id] = true
		clue_discovered.emit(clue_id)


func is_clue_discovered(clue_id: String) -> bool:
	"""Check if a clue has been discovered."""
	return discovered_clues.get(clue_id, false)


# ─── Cross-scene clue selection ──────────────────────────────

func select_clue(clue_id: String, deduction_ids: PackedStringArray,
		atlas: AtlasTexture, scene_path: String) -> void:
	"""Register a clue selection with its vignette texture (survives scene changes)."""
	if selected_clues.has(clue_id):
		return
	selected_clues[clue_id] = {
		"clue_id": clue_id,
		"deduction_ids": deduction_ids,
		"atlas_texture": atlas,
		"scene_path": scene_path,
	}
	selected_clue_order.append(clue_id)
	clue_selection_changed.emit()


func deselect_clue(clue_id: String) -> void:
	"""Remove a clue from selection."""
	if selected_clues.has(clue_id):
		selected_clues.erase(clue_id)
		selected_clue_order.erase(clue_id)
		clue_selection_changed.emit()


func is_clue_selected(clue_id: String) -> bool:
	return selected_clues.has(clue_id)


func get_selected_clues_for_deduction(deduction_id: String) -> Array[String]:
	"""Return clue IDs currently selected that belong to a given deduction."""
	var result: Array[String] = []
	for cid in selected_clue_order:
		var sel: Dictionary = selected_clues[cid]
		var dids: PackedStringArray = sel["deduction_ids"]
		if dids.has(deduction_id):
			result.append(cid)
	return result


func check_deduction_completion(deduction_id: String) -> bool:
	"""Check if all auto-discovered clues for a deduction are selected."""
	if not _deduction_clue_registry.has(deduction_id):
		return false
	var required: Array = _deduction_clue_registry[deduction_id]
	if required.is_empty():
		return false
	for key in required:
		if not selected_clues.has(key):
			return false
	return true


func get_required_clue_count(deduction_id: String) -> int:
	"""Return the number of clues required to complete a deduction."""
	if _deduction_clue_registry.has(deduction_id):
		return _deduction_clue_registry[deduction_id].size()
	return 0


# ─── Scene tree scanning ─────────────────────────────────────

func _scan_investigation_tree() -> void:
	"""Scan all scenes in the active investigation to build the deduction-clue registry."""
	_deduction_clue_registry.clear()
	if not _active_investigation:
		return
	var visited: Array[String] = []
	_scan_scene(_active_investigation.root_scene, visited)
	print("[GameManager] Clue registry for '%s':" % _active_investigation.investigation_id)
	for did in _deduction_clue_registry:
		print("  %s -> %s" % [did, _deduction_clue_registry[did]])


func _scan_scene(scene_path: String, visited: Array[String]) -> void:
	"""Load a scene, extract Clue->deduction mappings, and recurse into TransitionAreas."""
	var resolved := _resolve_scene_path(scene_path)
	if resolved in visited:
		return
	visited.append(resolved)

	var packed := load(resolved) as PackedScene
	if not packed:
		push_warning("GameManager: failed to load scene '%s'" % resolved)
		return

	var instance := packed.instantiate()
	_collect_clues(instance, resolved, instance)
	_collect_transitions(instance, visited)
	instance.free()


func _collect_clues(node: Node, scene_path: String, scene_root: Node) -> void:
	"""Recursively find Clue nodes and register them in the deduction registry."""
	if node is Clue:
		var deduction_ids: PackedStringArray = node.get("deduction_ids")
		if deduction_ids and deduction_ids.size() > 0:
			var rel_path := str(scene_root.get_path_to(node))
			var key := scene_path + "::" + rel_path
			for deduction_id in deduction_ids:
				if not deduction_id.is_empty():
					if not _deduction_clue_registry.has(deduction_id):
						_deduction_clue_registry[deduction_id] = []
					_deduction_clue_registry[deduction_id].append(key)
	for child in node.get_children():
		_collect_clues(child, scene_path, scene_root)


func _collect_transitions(node: Node, visited: Array[String]) -> void:
	"""Recursively find TransitionArea nodes and scan their target scenes."""
	if node is TransitionArea:
		var target: String = node.target_scene
		if not target.is_empty():
			_scan_scene(target, visited)
	for child in node.get_children():
		_collect_transitions(child, visited)


func _resolve_scene_path(path: String) -> String:
	"""Convert a UID path to a file path for consistent key generation."""
	if path.begins_with("uid://"):
		var uid := ResourceUID.text_to_id(path)
		if uid != ResourceUID.INVALID_ID:
			return ResourceUID.get_id_path(uid)
	return path


# ─── Deduction completion ────────────────────────────────────

func complete_deduction(deduction_id: String) -> void:
	"""Register a completed deduction and re-evaluate availability."""
	if not completed_deductions.has(deduction_id):
		completed_deductions[deduction_id] = true
		deduction_completed.emit(deduction_id)
		evaluate_availability()


func is_deduction_completed(deduction_id: String) -> bool:
	"""Check if a deduction has been completed."""
	return completed_deductions.get(deduction_id, false)


# ─── Deduction availability ──────────────────────────────────

func evaluate_availability() -> void:
	"""Re-evaluate availability conditions for all deductions in the active investigation."""
	if not _active_investigation:
		return
	for ded in _active_investigation.deductions:
		var did := ded.deduction_id
		if did.is_empty():
			continue
		var was_available: bool = available_deductions.get(did, false)
		var now_available: bool = _evaluate_deduction_availability(ded)
		available_deductions[did] = now_available
		if was_available != now_available:
			deduction_availability_changed.emit(did, now_available)


func _evaluate_deduction_availability(ded: DeductionDef) -> bool:
	"""Check if a single deduction is available based on its condition."""
	if completed_deductions.has(ded.deduction_id):
		return true
	if ded.availability_condition == null:
		return true
	return ded.availability_condition.evaluate(completed_deductions)


func is_deduction_available(deduction_id: String) -> bool:
	"""Check if a deduction is currently available."""
	return available_deductions.get(deduction_id, true)


# ─── Navigation ──────────────────────────────────────────────

func navigate_to(scene_path: String) -> void:
	"""Push current scene onto stack and transition to target scene."""
	var current_path := get_tree().current_scene.scene_file_path
	if not current_path.is_empty():
		scene_stack.push_back(current_path)
	get_tree().change_scene_to_file(scene_path)


func go_back() -> bool:
	"""Pop the scene stack and return to previous scene. Returns false if stack is empty."""
	if scene_stack.is_empty():
		return false
	var previous: String = scene_stack.pop_back()
	get_tree().change_scene_to_file(previous)
	return true


# ─── Save / Load ─────────────────────────────────────────────

func save_game() -> Dictionary:
	"""Return a dictionary of current game state for saving."""
	return {
		"current_investigation": current_investigation_id,
		"current_sub": current_sub_investigation,
		"clues": discovered_clues.duplicate(),
		"deductions": completed_deductions.duplicate(),
		"completed": completed_investigations.duplicate(),
		"available": available_deductions.duplicate(),
		"scene_stack": scene_stack.duplicate(),
	}


func load_game(save_data: Dictionary) -> void:
	"""Load game state from a save dictionary."""
	current_investigation_id = save_data.get("current_investigation", "")
	current_sub_investigation = save_data.get("current_sub", 0)
	discovered_clues = save_data.get("clues", {}).duplicate()
	completed_deductions = save_data.get("deductions", {}).duplicate()
	completed_investigations = save_data.get("completed", {}).duplicate()
	available_deductions = save_data.get("available", {}).duplicate()
	var stack = save_data.get("scene_stack", [])
	scene_stack.clear()
	for path in stack:
		scene_stack.push_back(path)
	evaluate_availability()
