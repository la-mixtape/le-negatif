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

# --- NOUVELLE GESTION DU ZOOM (TWEEN) ---
func handle_zoom_input(event):
	var changed = false
	
	if event.is_action_pressed("zoom_in"):
		target_zoom += zoom_step
		changed = true
	elif event.is_action_pressed("zoom_out"):
		target_zoom -= zoom_step
		changed = true
	
	if changed:
		# On borne la cible
		target_zoom = clamp(target_zoom, min_zoom, max_zoom)
		start_zoom_tween()

func start_zoom_tween():
	# 1. Si un zoom est déjà en cours, on le tue pour commencer le nouveau (évite les conflits)
	if zoom_tween:
		zoom_tween.kill()
	
	# 2. On crée un nouveau Tween
	zoom_tween = create_tween()
	
	# 3. On configure la courbe "d'atterrissage"
	# TRANS_CUBIC ou TRANS_QUART donnent un effet "lourd" qui ralentit fort à la fin
	# EASE_OUT signifie : rapide au début, lent à la fin
	zoom_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# 4. On lance l'animation
	# On anime la propriété "zoom" de la "camera" vers la valeur "Vector2(target...)" en "zoom_duration" secondes
	zoom_tween.tween_property(camera, "zoom", Vector2(target_zoom, target_zoom), zoom_duration)

# --- DÉPLACEMENT (Reste inchangé) ---
func handle_keyboard_panning(delta):
	var direction = Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down")
	if direction != Vector2.ZERO:
		camera.position += direction * pan_speed * delta

func handle_mouse_panning(event):
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			camera.position -= event.relative / camera.zoom
