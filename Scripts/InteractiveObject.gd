extends Area2D
class_name InteractiveObject

# --- SIGNAUX ---
signal object_clicked(obj_ref)

# --- PROPRIÉTÉS ---
@export var object_id: String = ""

# Faites glisser votre Polygon2D (ou Sprite) ici dans l'inspecteur
@export var visual_node: CanvasItem 

# --- ÉTATS ---
enum State { IDLE, HOVER, SELECTED, COMPLETED }
var current_state = State.IDLE

func _ready():
	# Sécurité : Si vous avez oublié d'assigner le noeud dans l'inspecteur,
	# on essaie de le trouver par son nom par défaut.
	if visual_node == null:
		visual_node = get_node_or_null("VisualFeedback")
	
	# Initialisation de l'affichage
	if visual_node:
		visual_node.visible = false
	else:
		push_warning("Attention : Aucun visual_node assigné pour l'objet " + name)

	# Connexions
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("object_clicked", self)

# --- GESTION DES ÉTATS ---
func set_state(new_state):
	if current_state == State.COMPLETED and new_state != State.COMPLETED:
		return
	current_state = new_state
	_update_visuals()

func _update_visuals():
	if visual_node == null: return
	
	match current_state:
		State.IDLE:
			visual_node.visible = false
			visual_node.modulate = Color(1, 1, 1, 1)
		State.HOVER:
			visual_node.visible = true
			visual_node.modulate = Color(1, 1, 1, 0.5) # Semi-transparent
		State.SELECTED:
			visual_node.visible = true
			visual_node.modulate = Color(1, 0.8, 0.2, 0.8) # Orange
		State.COMPLETED:
			visual_node.visible = false # Ou une autre indication "Cold"

func _on_mouse_entered():
	if current_state == State.IDLE:
		set_state(State.HOVER)

func _on_mouse_exited():
	if current_state == State.HOVER:
		set_state(State.IDLE)

func set_completed():
	set_state(State.COMPLETED)
