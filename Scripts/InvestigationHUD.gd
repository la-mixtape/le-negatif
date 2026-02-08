extends CanvasLayer

@onready var slot1 = $MarginContainer/VBoxContainer/Slot1
@onready var slot2 = $MarginContainer/VBoxContainer/Slot2
@onready var slot3 = $MarginContainer/VBoxContainer/Slot3

func _ready():
	clear_slots()

func update_slot(slot_index: int, texture: Texture2D):
	if slot_index == 0:
		slot1.texture = texture
		slot1.visible = true
	elif slot_index == 1:
		slot2.texture = texture
		slot2.visible = true
	elif slot_index == 2:
		slot3.texture = texture
		slot3.visible = true		

func clear_slots():
	slot1.texture = null
	slot1.visible = false
	slot2.texture = null
	slot2.visible = false
	slot3.texture = null
	slot3.visible = false
	
func clear_slot(index: int):
	if index == 0:
		slot1.texture = null
		slot1.visible = false
	elif index == 1:
		slot2.texture = null
		slot2.visible = false
	elif index == 2:
		slot3.texture = null
		slot3.visible = false
