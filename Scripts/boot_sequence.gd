extends Control

## Boot sequence screen that shows splash images/text in sequence
## Each image can be skipped with any input, or auto-advances after a timeout

## Array of text placeholders (replace with actual image paths later)
@export var splash_screens: Array[String] = [
	"Le Mouvement Présente",
	"Le Négatif",
	"Powered by Godot"
]

## Duration in seconds for each splash screen
@export var display_duration: float = 3.0

## Path to the main menu scene
@export_file("*.tscn") var main_menu_path: String = "res://scenes/menus/main_menu.tscn"

## Current splash screen index
var current_index: int = 0

## Timer tracking how long current splash has been displayed
var current_timer: float = 0.0

## Label to display the splash text
@onready var splash_label: Label = $SplashLabel


func _ready() -> void:
	# Show first splash screen
	show_current_splash()


func _input(event: InputEvent) -> void:
	# Skip to next on any key press or mouse button
	if event is InputEventKey and event.pressed:
		advance_splash()
	elif event is InputEventMouseButton and event.pressed:
		advance_splash()


func _process(delta: float) -> void:
	# Auto-advance after duration
	current_timer += delta
	if current_timer >= display_duration:
		advance_splash()


func show_current_splash() -> void:
	"""Display the current splash screen"""
	if current_index < splash_screens.size():
		splash_label.text = splash_screens[current_index]
		current_timer = 0.0
	else:
		# All splashes shown, transition to main menu
		transition_to_main_menu()


func advance_splash() -> void:
	"""Move to the next splash screen"""
	current_index += 1
	show_current_splash()


func transition_to_main_menu() -> void:
	"""Load the main menu scene"""
	get_tree().change_scene_to_file(main_menu_path)
