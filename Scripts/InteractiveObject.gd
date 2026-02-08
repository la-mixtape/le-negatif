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

# Retourne le rectangle (x, y, w, h) qui englobe le visuel de l'objet
# Ce rectangle est en coordonnées LOCALES par rapport à la scène (Global)
func get_panel_rect() -> Rect2:
	if visual_node == null:
		# Fallback : on retourne un carré de 100x100 autour de la position
		return Rect2(global_position - Vector2(50,50), Vector2(100,100))
	
	# Si c'est un Polygon2D, on calcule sa bounding box
	if visual_node is Polygon2D:
		var min_vec = Vector2(INF, INF)
		var max_vec = Vector2(-INF, -INF)
		
		# Le polygon est en local, on doit ajouter la position globale de l'objet
		for point in visual_node.polygon:
			# On applique la transformation (scale/rotation) du polygon s'il y en a
			var world_point = visual_node.to_global(point)
			min_vec.x = min(min_vec.x, world_point.x)
			min_vec.y = min(min_vec.y, world_point.y)
			max_vec.x = max(max_vec.x, world_point.x)
			max_vec.y = max(max_vec.y, world_point.y)
			
		var size = max_vec - min_vec
		# On ajoute une petite marge (padding) de 20px pour que ça respire
		return Rect2(min_vec - Vector2(10,10), size + Vector2(20,20))
		
	# Si c'est un Sprite ou autre, on essaie d'utiliser get_rect()
	if visual_node.has_method("get_rect"):
		var r = visual_node.get_rect()
		r.position += global_position
		return r
		
	return Rect2(global_position, Vector2(100,100))
