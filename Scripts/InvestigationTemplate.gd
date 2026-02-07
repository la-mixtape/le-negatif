extends Node2D

# --- CONFIGURATION ---
@export_group("Déplacement (Pan)")
@export var pan_speed: float = 600.0

@export_group("Zoom")
@export var zoom_step: float = 0.2     # Saut de zoom (un peu plus grand pour bien sentir l'effet)
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.5
@export var zoom_duration: float = 0.4 # Temps en secondes pour effectuer le zoom (plus c'est long, plus "l'atterrissage" est visible)

# --- VARIABLES INTERNES ---
var target_zoom: float = 1.0
var zoom_tween: Tween # On garde une référence au Tween pour pouvoir l'annuler si on re-scrolle vite

# --- RÉFÉRENCES ---
@onready var camera = $Camera2D
@onready var background = $Background

func _ready():
	target_zoom = camera.zoom.x

func _process(delta):
	# On garde le Pan dans le process car c'est un mouvement continu
	handle_keyboard_panning(delta)

func _unhandled_input(event):
	handle_zoom_input(event)
	handle_mouse_panning(event)

func handle_zoom_input(event):
	var changed = false
	
	if event.is_action_pressed("zoom_in"):
		target_zoom += zoom_step
		changed = true
	elif event.is_action_pressed("zoom_out"):
		target_zoom -= zoom_step
		changed = true
	
	if changed:
		# 1. On borne la cible
		target_zoom = clamp(target_zoom, min_zoom, max_zoom)
		
		# 2. On capture l'état INITIAL (avant le mouvement)
		var start_zoom = camera.zoom.x
		var start_pos = camera.position
		
		# Le point du monde sous la souris (l'Ancre)
		var mouse_world_anchor = get_global_mouse_position()
		
		# La distance vectorielle entre l'Ancre et la Caméra au départ
		# C'est ce vecteur qu'on va devoir réduire proportionnellement au zoom
		var start_offset = start_pos - mouse_world_anchor
		
		start_zoom_tween(start_zoom, target_zoom, mouse_world_anchor, start_offset)

func start_zoom_tween(start_z: float, end_z: float, anchor: Vector2, start_offset: Vector2):
	if zoom_tween:
		zoom_tween.kill()
	
	zoom_tween = create_tween()
	
	# "TRANS_BACK" donne le petit effet de rebond. 
	# Si vous trouvez ça trop "vivant", remplacez par TRANS_CUBIC ou TRANS_QUART pour du très doux.
	zoom_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	
	# On anime une méthode personnalisée au lieu d'une propriété
	# Cela garantit que Zoom et Position sont mis à jour EXACTEMENT en même temps
	zoom_tween.tween_method(
		_apply_zoom_step.bind(anchor, start_offset, start_z), 
		start_z, 
		end_z, 
		zoom_duration
	)

# Cette fonction est appelée par le Tween à chaque image
func _apply_zoom_step(current_zoom_val: float, anchor: Vector2, start_offset: Vector2, start_z: float):
	# A. Appliquer le Zoom
	camera.zoom = Vector2(current_zoom_val, current_zoom_val)
	
	# B. Calculer la Position exacte pour garder l'Ancre fixe
	# Mathématique : La distance Caméra-Ancre doit être divisée par le facteur de grossissement
	var zoom_factor = current_zoom_val / start_z
	var new_offset = start_offset / zoom_factor
	
	camera.position = anchor + new_offset
# --- DÉPLACEMENT (Reste inchangé) ---
func handle_keyboard_panning(delta):
	var direction = Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down")
	if direction != Vector2.ZERO:
		camera.position += direction * pan_speed * delta

func handle_mouse_panning(event):
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			camera.position -= event.relative / camera.zoom
