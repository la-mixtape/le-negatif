extends CanvasLayer

# --- OPTIONS DU MENU ---
var use_legacy_hud: bool = false

# --- REFERENCES UI ---
@onready var check_legacy = $PanelContainer/VBoxContainer/Check_LegacyHUD

func _ready():
	# Initialiser l'état visuel de la checkbox
	check_legacy.button_pressed = use_legacy_hud
	
	# Connecter le signal
	check_legacy.toggled.connect(_on_legacy_hud_toggled)
	
	# S'assurer que le menu est caché au début
	visible = false

func _input(event):
	# Touche pour ouvrir le menu (ex: F1 ou TAB)
	if event.is_action_pressed("toggle_debug"): # Pensez à ajouter cette action dans l'Input Map
		visible = not visible

func _on_legacy_hud_toggled(toggled_on: bool):
	use_legacy_hud = toggled_on
	print("Mode Legacy HUD : ", use_legacy_hud)
