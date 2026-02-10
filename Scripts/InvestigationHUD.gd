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

func animate_card_arrival(start_screen_rect: Rect2, slot_index: int, texture: Texture2D):
	var slot_control = null
	if slot_index == 0: slot_control = slot1_container
	elif slot_index == 1: slot_control = slot2_container
	elif slot_index == 2: slot_control = slot3_container
	
	if not slot_control: return

	# 1. Préparation de la destination
	var real_card = slot_control.get_node_or_null("Card")
	if real_card:
		var visual = real_card.get_node_or_null("Visual")
		if visual: visual.texture = texture
	
	slot_control.visible = true 
	real_card.visible = false 
	
	# 2. Création du Flyer
	var flyer = real_card.duplicate()
	add_child(flyer)
	flyer.visible = true
	
	# On s'assure que le flyer n'a pas de transformation résiduelle
	flyer.rotation = 0
	flyer.pivot_offset = Vector2.ZERO # Important pour que le positionnement soit précis
	
	var flyer_visual = flyer.get_node_or_null("Visual")
	if flyer_visual: 
		flyer_visual.texture = texture
		# On s'assure que le visuel remplit bien le flyer pour le calcul de scale
		# (Dépend de votre setup UI, mais souvent nécessaire)
	
	# --- C'EST ICI QUE LA MAGIE OPÈRE ---
	
	# A. On force la taille native du flyer pour le calcul
	# (On suppose que la taille de base du prefab Card est la taille "1.0")
	var target_size = real_card.size
	flyer.size = target_size
	
	# B. Calcul de l'échelle de départ
	# On veut que (target_size * start_scale) = start_screen_rect.size
	# Donc start_scale = start_screen_rect.size / target_size
	# On prend le max ou la moyenne des axes pour garder les proportions si l'aspect ratio diffère
	var start_scale_x = start_screen_rect.size.x / target_size.x
	var start_scale_y = start_screen_rect.size.y / target_size.y
	# On utilise un scale uniforme basé sur la largeur pour éviter les déformations bizarres,
	# ou un scale vectoriel si vous voulez que ça stretch. Essayons Vectoriel pour "matcher" exactement.
	var start_scale = Vector2(start_scale_x, start_scale_y)
	
	# C. Positionnement initial
	flyer.scale = start_scale
	flyer.global_position = start_screen_rect.position
	
	# 3. L'Animation
	var tween = create_tween().set_parallel(true)
	
	# Cible
	slot_control.get_parent().queue_sort() 
	var target_pos = real_card.global_position
	
	# Mouvement vers le slot
	tween.tween_property(flyer, "global_position", target_pos, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	
	# Changement d'échelle vers 1.0 (Taille normale de l'UI)
	tween.tween_property(flyer, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	
	# Nettoyage
	tween.chain().tween_callback(func():
		flyer.queue_free()
		real_card.visible = true
		animate_floating(real_card)
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
