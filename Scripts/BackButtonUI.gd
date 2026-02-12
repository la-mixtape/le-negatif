extends CanvasLayer

## Back button UI that appears when the user can navigate back through the scene stack.
## Positioned in the top-left corner for easy access.

@onready var back_button: Button = $BackButton

func _ready():
	# Connect button signal
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

	# Initial visibility update
	update_visibility()

func _process(_delta):
	# Continuously update visibility based on stack depth
	update_visibility()

func update_visibility():
	"""Shows or hides the back button based on whether we can go back."""
	if back_button:
		back_button.visible = GameManager.can_go_back()

func _on_back_pressed():
	"""Handles back button click."""
	if GameManager.can_go_back():
		print("[BackButtonUI] Back button pressed")
		GameManager.return_to_previous_scene()
