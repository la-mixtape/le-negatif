extends Node2D

# --- CONFIGURATION ---
@onready var background = $BackgroundTemplate
var hud_scene = preload("res://Scenes/InvestigationHUD.tscn")
var hud_instance = null

@export_group("Déplacement (Pan)")
@export var pan_speed: float = 600.0

@export_group("Zoom")
@export var zoom_step: float = 0.2     # Saut de zoom (un peu plus grand pour bien sentir l'effet)
@export var min_zoom: float = 0.5
@export var max_zoom: float = 5
@export var zoom_duration: float = 0.4 # Temps en secondes pour effectuer le zoom (plus c'est long, plus "l'atterrissage" est visible)

# --- VARIABLES INTERNES ---
var target_zoom: float = 1.0
var zoom_tween: Tween # On garde une référence au Tween pour pouvoir l'annuler si on re-scrolle vite
var valid_chains = [
	["DefaultObjectA", "DefaultObjectC"], 
	["objet_C", "objet_A"] # Note: objet_A fait partie de 2 chaînes
]
# Liste des chaînes déjà trouvées par le joueur
var found_chains = []

var selected_objects: Array[InteractiveObject] = [] 
const MAX_SLOTS = 4


# --- RÉFÉRENCES ---
@onready var camera = $Camera2D

func _ready():
	target_zoom = camera.zoom.x
	
	hud_instance = hud_scene.instantiate()
	add_child(hud_instance) # On l'ajoute à la scène
	
	connect_all_objects()

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
	zoom_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	
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
	
# --- DÉPLACEMENT ---
func handle_keyboard_panning(delta):
	var direction = Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down")
	if direction != Vector2.ZERO:
		camera.position += direction * pan_speed * delta

func handle_mouse_panning(event):
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			camera.position -= event.relative / camera.zoom

func connect_all_objects():
	# On cherche tous les noeuds enfants qui sont des InteractableObject
	# (Assurez-vous que vos objets sont bien des enfants de la scène ou dans un dossier spécifique)
	var interactables = find_children("*", "Area2D") # Ou un groupe spécifique
	
	for obj in interactables:
		if obj is InteractiveObject:
			obj.object_clicked.connect(_on_object_clicked)

# Fonction utilitaire pour créer la texture découpée
func create_crop_texture(obj: InteractiveObject) -> AtlasTexture:
	var atlas = AtlasTexture.new()
	# Assurez-vous que 'background' est bien votre Sprite2D principal
	var bg_sprite = $BackgroundTemplate 
	atlas.atlas = bg_sprite.texture 
	
	# 1. Récupération du rectangle cible (Global)
	var global_rect = obj.get_panel_rect()
	
	# 2. Conversion Monde -> Sprite Local
	# On annule la position, rotation et scale du Sprite pour retrouver les coordonnée brutes
	var to_local = bg_sprite.get_global_transform().affine_inverse()
	
	var top_left = to_local * global_rect.position
	var bottom_right = to_local * (global_rect.position + global_rect.size)
	var local_rect = Rect2(top_left, bottom_right - top_left)
	
	# 3. Gestion de l'origine (Centered)
	if bg_sprite.centered:
		var tex_size = bg_sprite.texture.get_size()
		local_rect.position += tex_size / 2.0
	
	# 4. SÉCURITÉ : Clamper le rectangle pour qu'il ne sorte pas de l'image
	# (Évite les bugs d'affichage ou les textures vides)
	var tex_w = bg_sprite.texture.get_width()
	var tex_h = bg_sprite.texture.get_height()
	
	# Si le rectangle est invalide ou nul, on force une petite zone de test au centre pour éviter d'afficher tout le fond
	if local_rect.size.x <= 1 or local_rect.size.y <= 1:
		print("Attention: Rect invalide pour ", obj.name, ". Utilisation fallback.")
		local_rect = Rect2(tex_w/2 - 50, tex_h/2 - 50, 100, 100)
	
	atlas.region = local_rect
	return atlas

# --- CŒUR DU GAMEPLAY : LE CLIC ---
func _on_object_clicked(clicked_obj: InteractiveObject):
	print("Objet cliqué : ", clicked_obj.object_id)
	
	# 1. Gestion de la désélection (si on clique sur un objet déjà dans la liste)
	if clicked_obj in selected_objects:
		cancel_selection() # On annule tout pour simplifier, ou vous pouvez retirer juste celui-ci
		return

	# 2. Sécurité : Si on est déjà plein (ne devrait pas arriver si on gère bien le reset)
	if selected_objects.size() >= MAX_SLOTS:
		print("Slots pleins.")
		return

	# 3. Ajout de l'objet à la sélection
	selected_objects.append(clicked_obj)
	clicked_obj.set_state(InteractiveObject.State.SELECTED)
	
	# 4. Mise à jour du HUD
	# L'index est la taille - 1 (ex: 1er objet = index 0, 2eme = index 1...)
	var slot_index = selected_objects.size() - 1
	var crop = create_crop_texture(clicked_obj)
	hud_instance.update_slot(slot_index, crop)
	
	print("HUD: Objet ajouté au slot ", slot_index)
	
	# 5. Vérification des chaînes
	check_deduction_chain()

# --- GESTION DES ÉTATS ET VALIDATION ---

func cancel_selection():
	# On remet tous les objets sélectionnés en état normal
	for obj in selected_objects:
		obj.set_state(InteractiveObject.State.IDLE)
	
	selected_objects.clear()
	hud_instance.clear_slots()
	print("Sélection annulée.")

func check_deduction_chain():
	# On convertit la sélection actuelle en liste d'IDs pour comparer
	var current_ids = []
	for obj in selected_objects:
		current_ids.append(obj.object_id)
	
	var found_chain_index = -1
	
	# On parcourt toutes les chaînes valides configurées
	for i in range(valid_chains.size()):
		var chain = valid_chains[i]
		
		# Condition 1 : La taille doit correspondre (ex: on ne valide pas une chaîne de 3 avec seulement 2 objets)
		if chain.size() == current_ids.size():
			
			# Condition 2 : Tous les éléments de la chaîne doivent être présents (l'ordre n'importe pas ici)
			var match_all = true
			for id in chain:
				if not current_ids.has(id):
					match_all = false
					break
			
			if match_all:
				# C'est une combinaison valide !
				if not found_chains.has(i):
					found_chain_index = i
				else:
					print("Cette déduction a déjà été trouvée.")
					cancel_selection()
					return
				break
	
	# --- RÉSULTAT ---
	if found_chain_index != -1:
		validate_chain_multi(found_chain_index)
	
	elif selected_objects.size() >= MAX_SLOTS:
			# CAS D'ERREUR : Les slots sont pleins et aucune chaîne n'a été trouvée
			print("Mauvaise combinaison !")
			
			# 1. On bloque les interactions temporairement (optionnel mais conseillé)
			# set_process_input(false) 
			
			# 2. On lance l'animation de tremblement et on ATTEND qu'elle finisse
			await hud_instance.trigger_failure_animation()
			
			# 3. Une fois l'animation finie, on annule la sélection logique
			cancel_selection()
		
		# set_process_input(true)

func validate_chain_multi(index_in_list: int):
	print("SUCCÈS ! Déduction trouvée !")
	found_chains.append(index_in_list)
	
	# On traite tous les objets de la sélection
	for obj in selected_objects:
		obj.set_state(InteractiveObject.State.IDLE)
		check_object_completion(obj) # Vérifie si l'objet est "fini" (Cold)
	
	# Nettoyage
	selected_objects.clear()
	
	# Délai avant de vider le HUD pour laisser le joueur voir le résultat
	await get_tree().create_timer(2.0).timeout
	hud_instance.clear_slots()

func check_object_completion(obj: InteractiveObject):
	# Vérifie si cet objet a encore des chaînes à découvrir
	var still_active = false
	for i in range(valid_chains.size()):
		# Si l'objet est dans cette chaîne ET que cette chaîne n'est pas trouvée
		if valid_chains[i].has(obj.object_id) and not found_chains.has(i):
			still_active = true
			break
	
	if not still_active:
		obj.set_completed()
		print("Objet ", obj.object_id, " entièrement résolu (Cold).")
