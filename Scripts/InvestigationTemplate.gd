extends Node2D

# --- CONFIGURATION ---
# Vitesse de déplacement de la caméra (pixels par seconde)
@export var pan_speed: float = 600.0
# Vitesse du zoom
@export var zoom_speed: float = 0.1
# Zoom minimum (vue large) et maximum (très gros plan)
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.5

# Références aux nœuds
@onready var camera = $Camera2D
@onready var background = $Background

# --- BOUCLE PRINCIPALE (S'exécute à chaque image) ---
func _process(delta):
	handle_panning(delta)

# --- GESTION DES ENTRÉES (Clavier/Souris) ---
func _unhandled_input(event):
	handle_zooming(event)

# Fonction pour déplacer la caméra (Pan)
func handle_panning(delta):
	# On récupère la direction selon les touches pressées (défini dans Input Map)
	# Cela renvoie un vecteur (ex: (1, 0) pour droite, (0, -1) pour haut)
	var direction = Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down")
	
	# Si on appuie sur une touche, on bouge la caméra
	if direction != Vector2.ZERO:
		camera.position += direction * pan_speed * delta

# Fonction pour gérer le Zoom
func handle_zooming(event):
	# Si on roule la molette vers le haut (Zoom In)
	if event.is_action_pressed("zoom_in"):
		apply_zoom(zoom_speed)
	
	# Si on roule la molette vers le bas (Zoom Out)
	elif event.is_action_pressed("zoom_out"):
		apply_zoom(-zoom_speed)

# Fonction utilitaire pour appliquer le zoom proprement
func apply_zoom(amount):
	# On calcule le nouveau zoom
	var new_zoom = camera.zoom.x + amount
	
	# On empêche de dépasser les limites (clamp)
	new_zoom = clamp(new_zoom, min_zoom, max_zoom)
	
	# On applique la nouvelle valeur aux axes X et Y de la caméra
	camera.zoom = Vector2(new_zoom, new_zoom)
