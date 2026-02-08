extends Area2D
class_name InteractableObject

# --- SIGNAUX ---
# Emis quand le joueur clique sur cet objet
signal object_clicked(obj_ref)

# --- PROPRIÉTÉS ---
@export var object_id: String = "" # L'ID unique (ex: "couteau", "sang")

# Références visuelles (Optionnel : si vous avez un sprite ou un polygone pour le survol)
# Pour l'instant, on va utiliser 'modulate' pour teinter l'objet
@onready var visual_node = $VisualFeedback if has_node("VisualFeedback") else null

# --- ÉTATS ---
enum State { IDLE, HOVER, SELECTED, COMPLETED }
var current_state = State.IDLE

func _ready():
	# Connexion des signaux natifs de l'Area2D
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	# Configuration initiale
	if visual_node:
		visual_node.visible = false

# --- GESTION DES ENTRÉES ---
func _input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("object_clicked", self)

# --- GESTION DES ÉTATS VISUELS ---
func set_state(new_state):
	# On ne change pas l'état si l'objet est déjà "terminé" (Completed), sauf reset forcé
	if current_state == State.COMPLETED and new_state != State.COMPLETED:
		return
		
	current_state = new_state
	_update_visuals()

func _update_visuals():
	if visual_node == null: return # Sécurité si pas de feedback visuel configuré
	
	match current_state:
		State.IDLE:
			visual_node.visible = false
			visual_node.modulate = Color(1, 1, 1, 1) # Blanc normal
		State.HOVER:
			visual_node.visible = true
			visual_node.modulate = Color(1, 1, 1, 0.5) # Blanc semi-transparent
		State.SELECTED:
			visual_node.visible = true
			visual_node.modulate = Color(1, 0.8, 0.2, 0.8) # Orange "En attente"
		State.COMPLETED:
			visual_node.visible = false # Ou une autre couleur "froide" selon le GDD

# --- CALLBACKS SOURIS ---
func _on_mouse_entered():
	if current_state == State.IDLE:
		set_state(State.HOVER)

func _on_mouse_exited():
	if current_state == State.HOVER:
		set_state(State.IDLE)

# Fonction pour marquer l'objet comme "Fini" (toutes chaînes trouvées)
func set_completed():
	set_state(State.COMPLETED)
