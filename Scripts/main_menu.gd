extends Control

# Appelé quand le nœud entre dans l'arbre de scène pour la première fois.
func _ready():
	# Ici, on connecte les signaux "pressed" (appuyé) des boutons à nos fonctions
	# Le signe $ permet d'accéder aux enfants du nœud par leur nom
	
	# Attention : Assurez-vous que vos boutons sont bien dans un VBoxContainer
	# Si vos boutons sont directement enfants de MainMenu, enlevez "VBoxContainer/" du chemin
	
	$VBoxContainer/BtnNewGame.pressed.connect(_on_new_game_pressed)
	$VBoxContainer/BtnContinue.pressed.connect(_on_continue_pressed)
	$VBoxContainer/BtnOptions.pressed.connect(_on_options_pressed)
	$VBoxContainer/BtnCredits.pressed.connect(_on_credits_pressed)
	$VBoxContainer/BtnQuit.pressed.connect(_on_quit_pressed)

	# Gestion du bouton Continuer (selon GDD : désactivé si pas de sauvegarde)
	# Pour l'instant on le désactive par défaut car on n'a pas encore de système de sauvegarde
	$VBoxContainer/BtnContinue.disabled = true

func _on_new_game_pressed():
	print("Lancement d'une nouvelle partie...")
	# Start test investigation for debugging
	print("Loading test investigation scene...")
	get_tree().change_scene_to_file("res://scenes/investigations/cliff_dwellers/investigation_cliff.tscn")

func _on_continue_pressed():
	print("Chargement de la partie...")
	# À implémenter plus tard

func _on_options_pressed():
	print("Ouverture des options...")
	# À implémenter plus tard (probablement ouvrir une popup)

func _on_credits_pressed():
	print("Affichage des crédits...")
	# À implémenter plus tard

func _on_quit_pressed():
	print("Fermeture du jeu.")
	get_tree().quit()
