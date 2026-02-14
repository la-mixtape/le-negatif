extends Node

## Global game manager for state and progression tracking
## This is an autoload singleton accessible via GameManager

## Signal emitted when investigation changes
signal investigation_changed(investigation_id: String, sub_index: int)

## Signal emitted when a clue is discovered
signal clue_discovered(clue_id: String)

## Current investigation identifier
var current_investigation_id: String = ""

## Current sub-investigation index
var current_sub_investigation: int = 0

## Dictionary tracking discovered clues
var discovered_clues: Dictionary = {}

## Dictionary tracking completed investigations
var completed_investigations: Dictionary = {}


func _ready() -> void:
	# Initialize game state
	pass


func start_investigation(investigation_id: String, sub_index: int = 0) -> void:
	"""Begin a new investigation or resume at a specific sub-investigation"""
	current_investigation_id = investigation_id
	current_sub_investigation = sub_index
	investigation_changed.emit(investigation_id, sub_index)


func advance_sub_investigation() -> bool:
	"""Advance to the next sub-investigation. Returns true if advanced, false if at end"""
	current_sub_investigation += 1
	investigation_changed.emit(current_investigation_id, current_sub_investigation)
	return true


func complete_investigation(investigation_id: String = "") -> void:
	"""Mark an investigation as completed"""
	if investigation_id.is_empty():
		investigation_id = current_investigation_id
	completed_investigations[investigation_id] = true


func discover_clue(clue_id: String) -> void:
	"""Register a discovered clue"""
	if not discovered_clues.has(clue_id):
		discovered_clues[clue_id] = true
		clue_discovered.emit(clue_id)


func is_clue_discovered(clue_id: String) -> bool:
	"""Check if a clue has been discovered"""
	return discovered_clues.get(clue_id, false)


func is_investigation_completed(investigation_id: String) -> bool:
	"""Check if an investigation has been completed"""
	return completed_investigations.get(investigation_id, false)


func save_game() -> Dictionary:
	"""Return a dictionary of current game state for saving"""
	return {
		"current_investigation": current_investigation_id,
		"current_sub": current_sub_investigation,
		"clues": discovered_clues.duplicate(),
		"completed": completed_investigations.duplicate()
	}


func load_game(save_data: Dictionary) -> void:
	"""Load game state from a save dictionary"""
	current_investigation_id = save_data.get("current_investigation", "")
	current_sub_investigation = save_data.get("current_sub", 0)
	discovered_clues = save_data.get("clues", {}).duplicate()
	completed_investigations = save_data.get("completed", {}).duplicate()
