extends Node


# Variables pour stocker l'avancement
var current_scene_name: String = ""
var deductions_found: Array = [] # Liste des déductions trouvées
var is_drag_active: bool = false # Pour gérer le drag & drop plus tard

func _ready():
	print("GameManager initialisé.")

# Fonction pour ajouter une déduction (sera utilisée plus tard selon le GDD)
func add_deduction(deduction_id: String):
	if deduction_id not in deductions_found:
		deductions_found.append(deduction_id)
		print("Nouvelle déduction trouvée : " + deduction_id)
