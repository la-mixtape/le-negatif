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
