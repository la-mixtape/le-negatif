extends Control

## Investigation selection screen — lists available root investigations from GameManager.

@onready var list_container: VBoxContainer = $ScrollContainer/VBoxContainer
@onready var back_button: Button = $BtnBack


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	_populate_list()


func _populate_list() -> void:
	for inv_def in GameManager.investigations:
		var card := _create_card(inv_def)
		list_container.add_child(card)


func _create_card(inv_def: InvestigationDef) -> Control:
	var card := HBoxContainer.new()
	card.custom_minimum_size.y = 120.0

	# Vignette thumbnail
	if inv_def.vignette_texture:
		var tex_rect := TextureRect.new()
		tex_rect.texture = inv_def.vignette_texture
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex_rect.custom_minimum_size = Vector2(160, 100)
		card.add_child(tex_rect)

	# Text column
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = inv_def.display_name
	title.add_theme_font_size_override("font_size", 28)
	text_col.add_child(title)

	if not inv_def.description.is_empty():
		var desc := Label.new()
		desc.text = inv_def.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 18)
		text_col.add_child(desc)

	if GameManager.is_investigation_completed(inv_def.investigation_id):
		var badge := Label.new()
		badge.text = "Completed"
		badge.add_theme_font_size_override("font_size", 16)
		badge.modulate = Color(0.4, 1.0, 0.4)
		text_col.add_child(badge)

	card.add_child(text_col)

	# Play button
	var btn := Button.new()
	btn.text = "Play"
	btn.add_theme_font_size_override("font_size", 24)
	btn.custom_minimum_size.x = 100.0
	btn.pressed.connect(_on_investigation_selected.bind(inv_def.investigation_id))
	card.add_child(btn)

	return card


func _on_investigation_selected(investigation_id: String) -> void:
	GameManager.start_new_investigation(investigation_id)


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")
