extends CanvasLayer

## Persistent investigation HUD that survives scene transitions.
## Displays a Back/Exit button (top-left), selected clue vignettes (right side),
## and completed deduction thumbnails (bottom-right).
## Registered as an autoload singleton (InvestigationHUD).

# ─── Signals ──────────────────────────────────────────────────

signal slot_animated

# ─── Constants ────────────────────────────────────────────────

const VIGNETTE_IMAGE_SIZE := 200.0
const VIGNETTE_MARGIN := 32.0
const VIGNETTE_GAP := 12.0
const VIGNETTE_SLIDE_DURATION := 0.3
const VIGNETTE_FRAME_WIDTH := 4.0
const VIGNETTE_HOVER_OPACITY := 0.2
const VIGNETTE_HOVER_DURATION := 0.5

const COMPLETED_THUMB_SIZE := 64.0
const COMPLETED_THUMB_FRAME := 2.0
const COMPLETED_THUMB_GAP := 8.0
const COMPLETED_THUMB_MARGIN := 32.0
const COMPLETED_THUMB_SLIDE_DURATION := 0.3

const NAV_BUTTON_MARGIN := 32.0
const NAV_BUTTON_FONT_SIZE := 24

const QUESTIONS_BUTTON_MARGIN := 32.0
const QUESTIONS_BUTTON_FONT_SIZE := 24
const QUESTIONS_LIST_FONT_SIZE := 48
const QUESTIONS_FADE_DURATION := 0.3

# ─── State ────────────────────────────────────────────────────

var _max_slots: int = 3
var _initialized: bool = false

# Tracks which clue keys are currently displayed (for diff-based updates)
var _displayed_keys: Array[String] = []

# ─── UI nodes ─────────────────────────────────────────────────

var _root: Control
var _vignette_slots: Array[Control] = []
var _vignette_panels: Array[Control] = []
var _vignette_frames: Array[ColorRect] = []
var _vignette_images: Array[TextureRect] = []
var _vignette_tweens: Array = []
var _vignette_hover_tweens: Array = []

var _nav_button: Button

var _questions_button: Button
var _questions_overlay: Control
var _questions_label: RichTextLabel
var _questions_overlay_active: bool = false

var _completed_tray: Control
var _completed_thumbs: Array[Control] = []


func _ready() -> void:
	# Create the root Control that holds all HUD elements
	_root = Control.new()
	_root.name = "HUDRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Back/Exit navigation button (top-left corner)
	_nav_button = Button.new()
	_nav_button.name = "NavButton"
	_nav_button.position = Vector2(NAV_BUTTON_MARGIN, NAV_BUTTON_MARGIN)
	_nav_button.add_theme_font_size_override("font_size", NAV_BUTTON_FONT_SIZE)
	_nav_button.add_theme_color_override("font_color", Color.WHITE)
	_nav_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_nav_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	# Semi-transparent background via StyleBoxFlat
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0, 0, 0, 0.3)
	btn_style.set_corner_radius_all(4)
	btn_style.set_content_margin_all(8)
	_nav_button.add_theme_stylebox_override("normal", btn_style)
	var btn_hover := btn_style.duplicate()
	btn_hover.bg_color = Color(0, 0, 0, 0.5)
	_nav_button.add_theme_stylebox_override("hover", btn_hover)
	var btn_pressed := btn_style.duplicate()
	btn_pressed.bg_color = Color(0, 0, 0, 0.6)
	_nav_button.add_theme_stylebox_override("pressed", btn_pressed)
	_nav_button.text = "Exit"
	_nav_button.pressed.connect(_on_nav_button_pressed)
	_root.add_child(_nav_button)

	# Questions button (top-center)
	_questions_button = Button.new()
	_questions_button.name = "QuestionsButton"
	_questions_button.add_theme_font_size_override("font_size", QUESTIONS_BUTTON_FONT_SIZE)
	_questions_button.add_theme_color_override("font_color", Color.WHITE)
	_questions_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_questions_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	var q_style := StyleBoxFlat.new()
	q_style.bg_color = Color(0, 0, 0, 0.3)
	q_style.set_corner_radius_all(4)
	q_style.set_content_margin_all(8)
	_questions_button.add_theme_stylebox_override("normal", q_style)
	var q_hover := q_style.duplicate()
	q_hover.bg_color = Color(0, 0, 0, 0.5)
	_questions_button.add_theme_stylebox_override("hover", q_hover)
	var q_pressed := q_style.duplicate()
	q_pressed.bg_color = Color(0, 0, 0, 0.6)
	_questions_button.add_theme_stylebox_override("pressed", q_pressed)
	_questions_button.text = "Questions"
	_questions_button.pressed.connect(_on_questions_button_pressed)
	_root.add_child(_questions_button)
	_update_questions_button_position()

	# Questions overlay (full-screen dimmer + centered label list, hidden by default)
	_setup_questions_overlay()

	# Start hidden until an investigation scene activates us
	_root.visible = false

	# React to clue selection changes
	GameManager.clue_selection_changed.connect(sync_display)
	GameManager.investigation_started.connect(_on_investigation_started)
	GameManager.deduction_completed.connect(_on_deduction_completed_hud)

	# Handle viewport resize
	get_viewport().size_changed.connect(_on_viewport_resized)


# ─── Public API ───────────────────────────────────────────────

func initialize(max_slots: int) -> void:
	"""Build slot UI for the current investigation. Safe to call multiple times."""
	if _initialized and _max_slots == max_slots:
		return

	_clear_slots()
	_max_slots = max_slots
	_initialized = true
	_displayed_keys.clear()

	_setup_slots()
	_setup_completed_tray()

	# Sync with existing GameManager state (no animation for already-visible items)
	_sync_immediate()


func set_hud_visible(visible_flag: bool) -> void:
	_root.visible = visible_flag
	if visible_flag:
		_update_nav_button_text()


func sync_display() -> void:
	"""Diff-based update: only animate new/removed slots."""
	if not _initialized:
		return

	var target_keys: Array[String] = GameManager.selected_clue_order
	var slot_size := VIGNETTE_IMAGE_SIZE + VIGNETTE_FRAME_WIDTH * 2.0

	# Find which keys are new vs unchanged vs removed
	var new_displayed: Array[String] = []
	for i in target_keys.size():
		if i >= _max_slots:
			break
		new_displayed.append(target_keys[i])

	# Slide out removed slots (keys in _displayed_keys but not in new_displayed)
	for i in range(_displayed_keys.size() - 1, -1, -1):
		if i >= _vignette_panels.size():
			continue
		var key := _displayed_keys[i]
		if not new_displayed.has(key):
			# Slide out
			var panel := _vignette_panels[i]
			var img := _vignette_images[i]
			if _vignette_tweens[i]:
				_vignette_tweens[i].kill()
			var tween := _root.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tween.tween_property(panel, "position", Vector2(slot_size, 0), VIGNETTE_SLIDE_DURATION)
			tween.tween_callback(func(): img.texture = null)
			_vignette_tweens[i] = tween

	# Slide in new slots (keys in new_displayed but not in _displayed_keys)
	for i in new_displayed.size():
		if i >= _vignette_panels.size():
			break
		var key := new_displayed[i]
		if not _displayed_keys.has(key):
			# New slot: set texture and slide in
			var sel: Dictionary = GameManager.selected_clues[key]
			var atlas: AtlasTexture = sel["atlas_texture"]
			var panel := _vignette_panels[i]
			var img := _vignette_images[i]

			if atlas:
				img.texture = atlas

			if _vignette_tweens[i]:
				_vignette_tweens[i].kill()
			var tween := _root.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(panel, "position", Vector2.ZERO, VIGNETTE_SLIDE_DURATION)
			tween.tween_callback(func(): slot_animated.emit())
			_vignette_tweens[i] = tween
		else:
			# Key unchanged but might be at a different index — update texture in place
			var sel: Dictionary = GameManager.selected_clues[key]
			var atlas: AtlasTexture = sel["atlas_texture"]
			if atlas:
				_vignette_images[i].texture = atlas
			# Ensure panel is visible (no animation)
			_vignette_panels[i].position = Vector2.ZERO

	# Clear any slots beyond the new count
	for i in range(new_displayed.size(), _max_slots):
		if i >= _vignette_panels.size():
			break
		if _vignette_images[i].texture and not _displayed_keys.has(""):
			_vignette_images[i].texture = null
			_vignette_panels[i].position = Vector2(slot_size, 0)

	_displayed_keys = new_displayed.duplicate()


func set_frame_colors(color: Color) -> void:
	"""Set all occupied vignette frames to the given color."""
	for i in _displayed_keys.size():
		if i < _vignette_frames.size():
			_vignette_frames[i].color = color


func reset_frame_colors() -> void:
	"""Reset all vignette frames to white."""
	for i in _max_slots:
		if i < _vignette_frames.size():
			_vignette_frames[i].color = Color.WHITE


func slide_all_out(on_complete: Callable) -> void:
	"""Slide all occupied vignette panels out to the right, then call on_complete."""
	var slot_size := VIGNETTE_IMAGE_SIZE + VIGNETTE_FRAME_WIDTH * 2.0
	var any_visible := false

	var tween := _root.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.set_parallel(true)
	for i in _max_slots:
		if i >= _vignette_panels.size():
			break
		if _vignette_tweens[i]:
			_vignette_tweens[i].kill()
		if _vignette_images[i].texture:
			any_visible = true
			tween.tween_property(
				_vignette_panels[i], "position",
				Vector2(slot_size, 0), VIGNETTE_SLIDE_DURATION
			)

	if any_visible:
		tween.chain().tween_callback(func():
			for j in _max_slots:
				if j < _vignette_images.size():
					_vignette_images[j].texture = null
			_displayed_keys.clear()
			on_complete.call()
		)
	else:
		_displayed_keys.clear()
		on_complete.call()


func add_completed_thumbnail(texture: Texture2D, animate: bool = true) -> void:
	"""Add a framed thumbnail to the completed deductions tray."""
	var fw := COMPLETED_THUMB_FRAME
	var thumb_total := COMPLETED_THUMB_SIZE + fw * 2.0

	var thumb := Control.new()
	thumb.name = "CompletedThumb%d" % _completed_thumbs.size()
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.size = Vector2(thumb_total, thumb_total)
	_completed_tray.add_child(thumb)

	var frame := ColorRect.new()
	frame.color = Color.WHITE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size = Vector2(thumb_total, thumb_total)
	thumb.add_child(frame)

	var img := TextureRect.new()
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.position = Vector2(fw, fw)
	img.size = Vector2(COMPLETED_THUMB_SIZE, COMPLETED_THUMB_SIZE)
	img.texture = texture
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.add_child(img)

	_completed_thumbs.append(thumb)
	_update_completed_tray_layout(animate)


func clear() -> void:
	"""Reset all HUD state for a new investigation."""
	_clear_slots()
	_initialized = false
	_displayed_keys.clear()


func navigate_back() -> void:
	"""Handle Back/Exit navigation. Exit clears HUD and returns to menu."""
	if _is_on_root_scene():
		clear()
		_root.visible = false
		GameManager.go_back()
	else:
		GameManager.go_back()


# ─── Internal ─────────────────────────────────────────────────

func _is_on_root_scene() -> bool:
	"""True when on the investigation root scene (stack only has the menu entry)."""
	return GameManager.scene_stack.size() <= 1


func _update_nav_button_text() -> void:
	"""Set button text based on whether we're on root or sub-scene."""
	_nav_button.text = "Exit" if _is_on_root_scene() else "Back"


func _on_nav_button_pressed() -> void:
	navigate_back()


func _on_investigation_started() -> void:
	clear()


func _on_deduction_completed_hud(_deduction_id: String) -> void:
	_update_questions_button_visibility()


func _sync_immediate() -> void:
	"""Set all slots to match GameManager state WITHOUT animation."""
	var target_keys: Array[String] = GameManager.selected_clue_order
	var slot_size := VIGNETTE_IMAGE_SIZE + VIGNETTE_FRAME_WIDTH * 2.0

	for i in _max_slots:
		if i >= _vignette_panels.size():
			break
		if i < target_keys.size():
			var key := target_keys[i]
			var sel: Dictionary = GameManager.selected_clues[key]
			var atlas: AtlasTexture = sel["atlas_texture"]
			if atlas:
				_vignette_images[i].texture = atlas
			_vignette_panels[i].position = Vector2.ZERO
		else:
			_vignette_images[i].texture = null
			_vignette_panels[i].position = Vector2(slot_size, 0)

	_displayed_keys.clear()
	for i in mini(target_keys.size(), _max_slots):
		_displayed_keys.append(target_keys[i])

	# Pre-populate completed thumbnails from GameManager
	var inv_def = GameManager.get_active_investigation()
	if inv_def:
		for ded in inv_def.deductions:
			if GameManager.is_deduction_completed(ded.deduction_id):
				if ded.image:
					add_completed_thumbnail(ded.image, false)

	_update_questions_button_visibility()


func _clear_slots() -> void:
	"""Remove all slot and tray UI nodes."""
	for slot in _vignette_slots:
		if is_instance_valid(slot):
			slot.queue_free()
	_vignette_slots.clear()
	_vignette_panels.clear()
	_vignette_frames.clear()
	_vignette_images.clear()

	for tween in _vignette_tweens:
		if tween and tween.is_valid():
			tween.kill()
	_vignette_tweens.clear()

	for tween in _vignette_hover_tweens:
		if tween and tween.is_valid():
			tween.kill()
	_vignette_hover_tweens.clear()

	for thumb in _completed_thumbs:
		if is_instance_valid(thumb):
			thumb.queue_free()
	_completed_thumbs.clear()

	if _completed_tray and is_instance_valid(_completed_tray):
		_completed_tray.queue_free()
		_completed_tray = null


func _setup_slots() -> void:
	"""Create vignette slot nodes."""
	var fw := VIGNETTE_FRAME_WIDTH
	var slot_size := VIGNETTE_IMAGE_SIZE + fw * 2.0

	for i in _max_slots:
		# Clip container (fixed position, hides content when slid out)
		var slot := Control.new()
		slot.name = "VignetteSlot%d" % i
		slot.clip_contents = true
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.size = Vector2(slot_size, slot_size)
		_root.add_child(slot)
		_vignette_slots.append(slot)

		# Panel that slides in/out
		var panel := Control.new()
		panel.name = "Panel"
		panel.mouse_filter = Control.MOUSE_FILTER_PASS
		panel.size = Vector2(slot_size, slot_size)
		panel.position = Vector2(slot_size, 0)  # start hidden to the right
		slot.add_child(panel)
		_vignette_panels.append(panel)

		# Hover fade
		panel.mouse_entered.connect(_on_vignette_hover.bind(i, true))
		panel.mouse_exited.connect(_on_vignette_hover.bind(i, false))

		# White frame background
		var frame := ColorRect.new()
		frame.name = "Frame"
		frame.color = Color.WHITE
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.size = Vector2(slot_size, slot_size)
		panel.add_child(frame)
		_vignette_frames.append(frame)

		# Image inset by frame width
		var img := TextureRect.new()
		img.name = "VignetteImage"
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.position = Vector2(fw, fw)
		img.size = Vector2(VIGNETTE_IMAGE_SIZE, VIGNETTE_IMAGE_SIZE)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(img)
		_vignette_images.append(img)
		_vignette_tweens.append(null)
		_vignette_hover_tweens.append(null)

	_update_vignette_layout()


func _setup_completed_tray() -> void:
	"""Build the bottom-right tray for completed deduction thumbnails."""
	_completed_tray = Control.new()
	_completed_tray.name = "CompletedTray"
	_completed_tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_completed_tray.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_completed_tray)


func _update_vignette_layout() -> void:
	"""Position all vignette slots based on current viewport size."""
	if _vignette_slots.is_empty():
		return
	var viewport_size := _root.size
	if viewport_size == Vector2.ZERO:
		viewport_size = Vector2(get_viewport().size)
	var slot_size := VIGNETTE_IMAGE_SIZE + VIGNETTE_FRAME_WIDTH * 2.0
	var slot_x := viewport_size.x - VIGNETTE_MARGIN - slot_size
	for i in _max_slots:
		if i >= _vignette_slots.size():
			break
		var slot_y := VIGNETTE_MARGIN + i * (slot_size + VIGNETTE_GAP)
		_vignette_slots[i].position = Vector2(slot_x, slot_y)
		_vignette_slots[i].size = Vector2(slot_size, slot_size)


func _update_completed_tray_layout(animate_last: bool = false) -> void:
	"""Position all thumbnails horizontally at the bottom-right."""
	if not _completed_tray:
		return
	var viewport_size := _root.size
	if viewport_size == Vector2.ZERO:
		viewport_size = Vector2(get_viewport().size)
	var fw := COMPLETED_THUMB_FRAME
	var thumb_total := COMPLETED_THUMB_SIZE + fw * 2.0
	var count := _completed_thumbs.size()

	var total_width := count * thumb_total + maxf(0, count - 1) * COMPLETED_THUMB_GAP
	var start_x := viewport_size.x - COMPLETED_THUMB_MARGIN - total_width
	var target_y := viewport_size.y - COMPLETED_THUMB_MARGIN - thumb_total

	for i in count:
		var thumb: Control = _completed_thumbs[i]
		var target_pos := Vector2(start_x + i * (thumb_total + COMPLETED_THUMB_GAP), target_y)

		if animate_last and i == count - 1:
			thumb.position = Vector2(target_pos.x, viewport_size.y)
			var tw := _root.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(thumb, "position", target_pos, COMPLETED_THUMB_SLIDE_DURATION)
		else:
			thumb.position = target_pos


func _on_vignette_hover(index: int, hovered: bool) -> void:
	if index >= _vignette_hover_tweens.size():
		return
	if _vignette_hover_tweens[index]:
		_vignette_hover_tweens[index].kill()
	var panel := _vignette_panels[index]
	var target := VIGNETTE_HOVER_OPACITY if hovered else 1.0
	var tween := _root.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", target, VIGNETTE_HOVER_DURATION)
	_vignette_hover_tweens[index] = tween


func _on_viewport_resized() -> void:
	_update_vignette_layout()
	_update_completed_tray_layout()
	_update_questions_button_position()


# ─── Questions overlay ───────────────────────────────────────

func _setup_questions_overlay() -> void:
	"""Build the full-screen questions overlay (hidden by default)."""
	_questions_overlay = Control.new()
	_questions_overlay.name = "QuestionsOverlay"
	_questions_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_questions_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_questions_overlay.visible = false
	_root.add_child(_questions_overlay)

	# Dimmer background
	var dimmer := ColorRect.new()
	dimmer.name = "Dimmer"
	dimmer.color = Color(0, 0, 0, 0.5)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_questions_overlay.add_child(dimmer)

	# RichTextLabel for the question list — anchored to center 60% of viewport width
	_questions_label = RichTextLabel.new()
	_questions_label.name = "QuestionsLabel"
	_questions_label.bbcode_enabled = true
	_questions_label.fit_content = true
	_questions_label.scroll_active = false
	_questions_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_questions_label.add_theme_font_size_override("normal_font_size", QUESTIONS_LIST_FONT_SIZE)
	_questions_label.add_theme_color_override("default_color", Color.WHITE)
	# Horizontally centered 60% width, vertically centered via anchors
	_questions_label.anchor_left = 0.2
	_questions_label.anchor_right = 0.8
	_questions_label.anchor_top = 0.5
	_questions_label.anchor_bottom = 0.5
	_questions_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_questions_overlay.add_child(_questions_label)

	# Click anywhere on the overlay to dismiss
	_questions_overlay.gui_input.connect(_on_questions_overlay_input)


func _update_questions_button_position() -> void:
	"""Position the Questions button at the top-center of the screen."""
	if not _questions_button:
		return
	var viewport_size := _root.size
	if viewport_size == Vector2.ZERO:
		viewport_size = Vector2(get_viewport().size)
	# Wait one frame for the button to compute its size
	if _questions_button.size.x == 0:
		await _questions_button.resized
	var btn_x := (viewport_size.x - _questions_button.size.x) / 2.0
	_questions_button.position = Vector2(btn_x, QUESTIONS_BUTTON_MARGIN)


func _on_questions_button_pressed() -> void:
	"""Show the questions overlay with available deduction questions."""
	if _questions_overlay_active:
		return
	var questions := _collect_questions()
	if questions.is_empty():
		return
	_questions_label.text = "[center]" + "\n\n".join(questions) + "[/center]"
	_questions_overlay_active = true
	_questions_overlay.modulate.a = 0.0
	_questions_overlay.visible = true
	var tween := _root.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_questions_overlay, "modulate:a", 1.0, QUESTIONS_FADE_DURATION)


func _on_questions_overlay_input(event: InputEvent) -> void:
	"""Dismiss the questions overlay on click."""
	if not _questions_overlay_active:
		return
	if event is InputEventMouseButton and event.pressed:
		_dismiss_questions_overlay()
		get_viewport().set_input_as_handled()


func _dismiss_questions_overlay() -> void:
	"""Fade out the questions overlay."""
	var tween := _root.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(_questions_overlay, "modulate:a", 0.0, QUESTIONS_FADE_DURATION)
	tween.tween_callback(func():
		_questions_overlay.visible = false
		_questions_overlay_active = false
		_update_questions_button_visibility()
	)


func _update_questions_button_visibility() -> void:
	"""Hide the Questions button when there are no remaining questions."""
	if not _questions_button:
		return
	_questions_button.visible = not _collect_questions().is_empty()


func _collect_questions() -> Array[String]:
	"""Gather questions from available, non-completed deductions."""
	var result: Array[String] = []
	var inv_def := GameManager.get_active_investigation()
	if not inv_def:
		return result
	for ded in inv_def.deductions:
		if ded.question.is_empty():
			continue
		if GameManager.is_deduction_completed(ded.deduction_id):
			continue
		if not GameManager.is_deduction_available(ded.deduction_id):
			continue
		result.append(ded.question)
	return result
