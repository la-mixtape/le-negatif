extends CanvasLayer

@onready var slot1_container = $MarginContainer/VBoxContainer/Slot1
@onready var slot2_container = $MarginContainer/VBoxContainer/Slot2
@onready var slot3_container = $MarginContainer/VBoxContainer/Slot3

var active_tweens = {}

func _ready():
	clear_slots()

func update_slot(slot_index: int, texture: Texture2D):
	var slot_control = null
	
	if slot_index == 0: slot_control = slot1_container
	elif slot_index == 1: slot_control = slot2_container
	elif slot_index == 2: slot_control = slot3_container
	
	if slot_control:
		# On cherche la "Carte" (le Panel qui bouge)
		var card_node = slot_control.get_node_or_null("Card")
		
		if card_node:
			# On cherche le "Visual" (l'image à l'intérieur de la carte)
			var visual_node = card_node.get_node_or_null("Visual")
			
			if visual_node:
				visual_node.texture = texture
				
				# On rend le Slot et la Carte visibles
				slot_control.visible = true
				card_node.visible = true
				
				# On anime LA CARTE (qui contient l'image)
				animate_entry(card_node)
				animate_floating(card_node)

func clear_slots():
	_reset_slot(slot1_container)
	_reset_slot(slot2_container)
	_reset_slot(slot3_container)

func _reset_slot(slot_control: Control):
	slot_control.visible = false
	
	var card_node = slot_control.get_node_or_null("Card")
	if card_node:
		# Reset visuel
		var visual = card_node.get_node_or_null("Visual")
		if visual: visual.texture = null
		
		# Arrêt des animations
		if active_tweens.has(card_node):
			active_tweens[card_node].kill()
			active_tweens.erase(card_node)
		
		# Reset Transform sur la CARTE
		card_node.position = Vector2(
			(slot_control.size.x - card_node.size.x) / 2, 
			(slot_control.size.y - card_node.size.y) / 2
		) # On recentre manuellement si besoin, ou Vector2.ZERO si ancré
		
		card_node.rotation = 0
		card_node.scale = Vector2.ONE

# --- ANIMATIONS ---

# Dans InvestigationHUD.gd

func animate_card_arrival(start_screen_rect: Rect2, slot_index: int, texture: Texture2D):
	var slot_control = null
	if slot_index == 0: slot_control = slot1_container
	elif slot_index == 1: slot_control = slot2_container
	elif slot_index == 2: slot_control = slot3_container
	
	if not slot_control: return

	# --- 1. PRÉPARATION DE LA DESTINATION (La vraie carte) ---
	var real_card = slot_control.get_node_or_null("Card")
	if real_card:
		var visual = real_card.get_node_or_null("Visual")
		if visual: visual.texture = texture
	
	# IMPORTANT : On rend le slot visible pour que le layout se calcule
	slot_control.visible = true 
	
	# ASTUCE : Au lieu de cacher la vraie carte (visible=false), on la rend transparente.
	# Comme ça, elle occupe sa vraie place dans la colonne, et target_pos sera correct.
	real_card.visible = true
	real_card.modulate.a = 0.0 # Alpha à 0 = invisible mais présent physiquement
	
	# On force une mise à jour immédiate du layout pour être sûr que la position est bonne
	# (Parfois nécessaire si le slot vient juste d'apparaître)
	if slot_control.get_parent() is Container:
		slot_control.get_parent().queue_sort()
	
	# --- 2. CRÉATION DU FLYER (La carte volante) ---
	var flyer = real_card.duplicate()
	add_child(flyer)
	flyer.visible = true
	flyer.modulate.a = 1.0 # Le flyer, lui, doit être bien visible !
	flyer.rotation = 0
	flyer.pivot_offset = Vector2.ZERO
	
	var flyer_visual = flyer.get_node_or_null("Visual")
	if flyer_visual: flyer_visual.texture = texture
	
	# Positionnement et taille initiale (Sur l'objet cliqué)
	var target_size = real_card.size
	# Sécurité pour éviter une division par zéro si la carte n'est pas encore redimensionnée
	if target_size == Vector2.ZERO: target_size = Vector2(100, 140) 
	var tween = create_tween()
	
	# A. Pause statique (Le joueur réalise ce qu'il a pris)
	tween.tween_interval(1.0)
	flyer.size = target_size
	
	var start_scale_x = start_screen_rect.size.x / target_size.x
	var start_scale_y = start_screen_rect.size.y / target_size.y
	
	flyer.scale = Vector2(start_scale_x, start_scale_y)
	flyer.global_position = start_screen_rect.position
	
	# --- 3. ANIMATION ---

	
	# B. Mouvement vers le slot
	tween.set_parallel(true)
	
	# On récupère la position FINALE exacte maintenant que le layout est calé
	var target_pos = real_card.global_position
	
	# Mouvement : CUBIC + IN_OUT donne un mouvement plus naturel (lent au début, rapide, lent à la fin)
	tween.tween_property(flyer, "global_position", target_pos, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	
	# Changement d'échelle : On le fait un peu plus vite pour que la carte ait sa taille finale avant de se poser
	tween.tween_property(flyer, "scale", Vector2.ONE, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Rotation : Petit effet sympa, on remet la rotation à 0 proprement
	tween.tween_property(flyer, "rotation", 0.0, 0.8)
	
	# --- 4. ARRIVÉE ---
	tween.chain().tween_callback(func():
		flyer.queue_free()          # On supprime la fausse carte
		real_card.modulate.a = 1.0  # On rend la vraie carte opaque
		animate_floating(real_card) # On lance l'animation de flottaison (idle)
	)


func animate_entry(node: Control):
	# Animation de "Pop" à l'apparition
	node.scale = Vector2(0.1, 0.1)
	node.modulate.a = 0.0
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "modulate:a", 1.0, 0.3)
	
	# Petite rotation aléatoire pour faire naturel (comme une photo jetée sur une table)
	var random_rot = randf_range(-3.0, 3.0)
	node.rotation_degrees = random_rot

func animate_floating(node: Control):
	# Si un tween de flottaison existe déjà, on le tue
	if active_tweens.has(node):
		active_tweens[node].kill()
	
	var tween = create_tween().set_loops()
	active_tweens[node] = tween
	
	# Délai aléatoire pour que les 3 objets ne flottent pas exactement en même temps (effet robotique)
	var random_delay = randf_range(0.0, 1.0)
	tween.tween_interval(random_delay)
	
	# Mouvement de haut en bas (respiration)
	# Note: On utilise la position relative (.as_relative()) pour ne pas casser le layout
	var float_distance = 6.0 # Pixels
	var duration = 2.5 # Secondes
	
	tween.tween_property(node, "position:y", -float_distance, duration).as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "position:y", float_distance, duration).as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
signal failure_animation_finished

func trigger_failure_animation():
	var active_cards = []
	
	# On récupère les cartes actives dans les slots
	for container in [slot1_container, slot2_container, slot3_container]:
		if container.visible:
			var card = container.get_node_or_null("Card")
			if card:
				active_cards.append(card)
	
	# S'il n'y a rien à animer, on finit tout de suite
	if active_cards.is_empty():
		failure_animation_finished.emit()
		return

	# On crée un tween unique qui gère tout (ou on attend un timer)
	var shake_duration = 0.5
	
	for card in active_cards:
		# 1. On tue le tween de flottaison (douceur) pour prendre le contrôle
		if active_tweens.has(card):
			active_tweens[card].kill()
			active_tweens.erase(card)
		
		# 2. Création du tween de secousse
		var tween = create_tween()
		
		# On fait trembler la carte plusieurs fois
		var shake_count = 10 
		var intensity = 10.0 # Force du tremblement en pixels
		
		# Feedback couleur : on flashe en rouge
		# tween.tween_property(card, "modulate", Color(1, 0.3, 0.3), 0.1)
		
		# Boucle de secousses
		for i in range(shake_count):
			# On déplace aléatoirement autour de la position actuelle
			var random_offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
			tween.tween_property(card, "position", random_offset, shake_duration / shake_count).as_relative()
		
		# Retour à la couleur normale à la fin
		tween.tween_property(card, "modulate", Color.WHITE, 0.1)

	# 3. On attend que ça finisse avant de tout nettoyer
	await get_tree().create_timer(shake_duration + 0.1).timeout
	
	# 4. On nettoie visuellement
	clear_slots()
	emit_signal("failure_animation_finished")
