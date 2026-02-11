extends Area2D
class_name InteractiveObject

# --- SIGNAUX ---
signal object_clicked(obj_ref)

# --- PROPRIÉTÉS ---
@export var object_id: String = ""

# Faites glisser votre Polygon2D (ou Sprite) ici dans l'inspecteur
@export var visual_node: CanvasItem 

@export var manual_crop_frame: ReferenceRect

var border_shader = preload("res://Resources/dashed_border.gdshader") 
var highlight_rect: ColorRect = null

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

# On crée dynamiquement un ColorRect qui servira de bordure
	highlight_rect = ColorRect.new()
	highlight_rect.name = "HighlightBorder"
	highlight_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE # Important pour ne pas bloquer le clic
	
	# Configuration du Shader
	var shader_mat = ShaderMaterial.new()
	shader_mat.shader = border_shader
	highlight_rect.material = shader_mat
	
	add_child(highlight_rect)
	highlight_rect.visible = false # Caché par défaut

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
	if visual_node:
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
	if highlight_rect:
		match current_state:
			State.HOVER, State.SELECTED:
				highlight_rect.visible = true
				_adjust_highlight_rect() # On s'assure qu'il est bien placé
				
				# Optionnel : Changer la couleur ou vitesse selon l'état
				if current_state == State.SELECTED:
					(highlight_rect.material as ShaderMaterial).set_shader_parameter("color", Color(0.2, 1.0, 0.2)) # Vert si sélectionné ?
				else:
					(highlight_rect.material as ShaderMaterial).set_shader_parameter("color", Color(1.0, 0.8, 0.2)) # Orange au survol
					
			State.IDLE, State.COMPLETED:
				highlight_rect.visible = false

func _adjust_highlight_rect():
	var rect_global = get_panel_rect() 
	
	# Conversion position globale -> locale
	var local_pos = to_local(rect_global.position)
	
	highlight_rect.position = local_pos
	highlight_rect.size = rect_global.size
	
	# --- AJOUT CRUCIAL ---
	# On envoie la taille réelle au shader pour qu'il dessine les bords correctement
	var mat = highlight_rect.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("rect_size", highlight_rect.size)

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
	# Priorité absolue au cadre manuel s'il est assigné
	if manual_crop_frame != null:
		# On récupère le rectangle global défini par le ReferenceRect
		return manual_crop_frame.get_global_rect()
	
	# --- Fallback : Méthode automatique (si pas de cadre manuel) ---
	if visual_node is Polygon2D:
		var min_vec = Vector2(INF, INF)
		var max_vec = Vector2(-INF, -INF)
		for point in visual_node.polygon:
			var world_point = visual_node.to_global(point)
			min_vec.x = min(min_vec.x, world_point.x)
			min_vec.y = min(min_vec.y, world_point.y)
			max_vec.x = max(max_vec.x, world_point.x)
			max_vec.y = max(max_vec.y, world_point.y)
		return Rect2(min_vec, max_vec - min_vec)
		
	# Fallback ultime (carré par défaut)
	return Rect2(global_position - Vector2(50,50), Vector2(100,100))
