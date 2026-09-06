class_name OpenMMODialogue
extends PanelContainer

signal action_requested
signal choice_requested(value: int)
signal closed

const TYPE_INTERVAL: float = 1.0 / 30.0
const PANEL_HEIGHT: float = 164.0
const PANEL_WIDTH: float = 430.0
var text_label: Label
var arrow_label: Label
var choice_box: VBoxContainer
var choice_labels: Array = []
var current_text: String = ""
var pages: Array = []
var choice_options: Array = []
var page_index: int = 0
var choice_index: int = 0
var visible_count: int = 0
var type_elapsed: float = 0.0
var open_state: bool = false
var ignore_next_action: bool = false
var screen_anchor: Vector2 = Vector2(-1.0, -1.0)
var actor_anchored: bool = false
var layout_in_progress: bool = false
var choice_active: bool = false
var pokemon_preview: TextureRect
var pokemon_preview_species_id: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_top = -170.0
	offset_bottom = -28.0
	resized.connect(_layout_panel)
	_layout_panel()
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(margin)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(box)
	text_label = Label.new()
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.clip_text = false
	text_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text_label.add_theme_font_size_override("font_size", 20)
	text_label.custom_minimum_size = Vector2(0, 112)
	box.add_child(text_label)
	choice_box = VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 0)
	choice_box.visible = false
	box.add_child(choice_box)
	var arrow_row: HBoxContainer = HBoxContainer.new()
	arrow_row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(arrow_row)
	arrow_label = Label.new()
	arrow_label.text = "▼"
	arrow_label.add_theme_font_size_override("font_size", 16)
	arrow_row.add_child(arrow_label)
	visible = false
	set_process(false)
	var preview_parent: Node = get_parent()
	if preview_parent != null:
		pokemon_preview = TextureRect.new()
		pokemon_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pokemon_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pokemon_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pokemon_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pokemon_preview.z_index = z_index + 1
		pokemon_preview.visible = false
		preview_parent.add_child(pokemon_preview)
	resized.connect(_position_pokemon_preview)

func _exit_tree() -> void:
	if is_instance_valid(pokemon_preview):
		pokemon_preview.queue_free()

func _panel_height() -> float:
	if not choice_active:
		return PANEL_HEIGHT
	return maxf(PANEL_HEIGHT, PANEL_HEIGHT - 32.0 + choice_options.size() * 28.0)

func _layout_panel() -> void:
	if layout_in_progress:
		return
	layout_in_progress = true
	var viewport_size: Vector2 = get_viewport_rect().size
	var viewport_width: float = viewport_size.x
	var viewport_height: float = viewport_size.y
	var panel_height: float = _panel_height()
	# Actor anchors are opt-in; if the bubble would cover the upper half, fall back to bottom box.
	var use_actor_anchor: bool = actor_anchored and screen_anchor.x >= 0.0 and screen_anchor.y >= viewport_height * 0.45
	if use_actor_anchor:
		var panel_width: float = minf(PANEL_WIDTH, maxf(viewport_width - 24.0, 240.0))
		var left: float = clampf(screen_anchor.x - panel_width * 0.5, 12.0, maxf(viewport_width - panel_width - 12.0, 12.0))
		var top: float = screen_anchor.y - panel_height - 12.0
		var safe_top: float = 88.0
		var safe_bottom: float = 88.0
		var max_top: float = maxf(safe_top, viewport_height - panel_height - safe_bottom)
		if top < safe_top:
			top = minf(screen_anchor.y + 12.0, maxf(viewport_height - panel_height - 12.0, 12.0))
		top = clampf(top, safe_top, max_top)
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		offset_left = left
		offset_top = top
		offset_right = left + panel_width
		offset_bottom = top + panel_height
	else:
		var bottom_panel_width: float = minf(PANEL_WIDTH, maxf(viewport_width - 24.0, 240.0))
		set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		offset_left = -bottom_panel_width * 0.5
		offset_right = bottom_panel_width * 0.5
		offset_top = -panel_height - 88.0
		offset_bottom = -88.0
	layout_in_progress = false
	_position_pokemon_preview()

func set_pokemon_preview(species_id: int) -> void:
	pokemon_preview_species_id = species_id
	if pokemon_preview == null:
		return
	pokemon_preview.texture = null
	if species_id > 0 and GameState.content != null:
		var result: Dictionary = GameState.content.battle_pokemon_sprite(species_id, false)
		if bool(result.get("ok", false)):
			pokemon_preview.texture = result.get("texture") as Texture2D
	pokemon_preview.visible = open_state and pokemon_preview.texture != null
	_position_pokemon_preview()

func set_actor_preview(texture: Texture2D) -> void:
	pokemon_preview_species_id = 0
	if pokemon_preview == null:
		return
	pokemon_preview.texture = texture
	pokemon_preview.visible = open_state and texture != null
	_position_pokemon_preview()

func clear_pokemon_preview() -> void:
	pokemon_preview_species_id = 0
	if pokemon_preview != null:
		pokemon_preview.texture = null
		pokemon_preview.visible = false

func _position_pokemon_preview() -> void:
	if pokemon_preview == null or not open_state or pokemon_preview.texture == null:
		if pokemon_preview != null:
			pokemon_preview.visible = false
		return
	var preview_size: Vector2 = Vector2(128.0, 128.0)
	var viewport_size: Vector2 = get_viewport_rect().size
	var panel_rect: Rect2 = get_global_rect()
	var left: float = panel_rect.position.x + (panel_rect.size.x - preview_size.x) * 0.5
	var top: float = panel_rect.position.y - preview_size.y - 6.0
	left = clampf(left, 8.0, maxf(viewport_size.x - preview_size.x - 8.0, 8.0))
	top = clampf(top, 8.0, maxf(viewport_size.y - preview_size.y - 8.0, 8.0))
	pokemon_preview.size = preview_size
	pokemon_preview.global_position = Vector2(left, top)
	pokemon_preview.visible = true

func show_text(value: String, suppress_action: bool = false) -> void:
	show_pages([value], suppress_action)

func show_pages(values: Array, suppress_action: bool = false, anchor: Vector2 = Vector2(-1.0, -1.0)) -> void:
	clear_pokemon_preview()
	_clear_choices()
	pages = []
	for value in values:
		var page: String = str(value)
		if not page.is_empty():
			pages.append(page)
	page_index = 0
	current_text = str(pages[0]) if not pages.is_empty() else ""
	visible_count = 0
	type_elapsed = 0.0
	open_state = not pages.is_empty()
	ignore_next_action = suppress_action and open_state
	screen_anchor = anchor
	actor_anchored = anchor.x >= 0.0 and anchor.y >= 0.0
	visible = open_state
	set_process(open_state)
	_layout_panel()
	_render()

func show_choice(values: Array, options: Array, suppress_action: bool = false, anchor: Vector2 = Vector2(-1.0, -1.0)) -> void:
	show_pages(values, suppress_action, anchor)
	for index in options.size():
		var option_value: Variant = options[index]
		var option: Dictionary = option_value if option_value is Dictionary else {"label": str(option_value), "value": index}
		choice_options.append({"label": str(option.get("label", "")), "value": int(option.get("value", index))})
		var label: Label = Label.new()
		label.add_theme_font_size_override("font_size", 18)
		label.custom_minimum_size = Vector2(0, 26)
		choice_box.add_child(label)
		choice_labels.append(label)
	choice_index = 0
	choice_active = false
	if choice_box != null:
		choice_box.visible = false
	_layout_panel()
	_render()

func is_open() -> bool:
	return open_state

func text_complete() -> bool:
	return open_state and visible_count >= current_text.length()

func is_choice_open() -> bool:
	return open_state and choice_active

func _choice_prompt_ready() -> bool:
	return open_state and not choice_options.is_empty() and page_index + 1 >= pages.size() and visible_count >= current_text.length()

func handle_action() -> bool:
	if not open_state:
		return false
	if visible_count < current_text.length():
		visible_count = current_text.length()
		_render()
		return true
	if page_index + 1 < pages.size():
		page_index += 1
		current_text = str(pages[page_index])
		visible_count = 0
		type_elapsed = 0.0
		set_process(true)
		_render()
		return true
	if choice_active:
		choice_requested.emit(int(choice_options[choice_index].get("value", choice_index)))
		return true
	close_dialogue()
	return true

func close_dialogue() -> void:
	if not open_state:
		return
	open_state = false
	visible = false
	set_process(false)
	_clear_choices()
	clear_pokemon_preview()
	closed.emit()

func _process(delta: float) -> void:
	if visible_count >= current_text.length():
		set_process(false)
		_render()
		return
	type_elapsed += delta
	while type_elapsed >= TYPE_INTERVAL and visible_count < current_text.length():
		type_elapsed -= TYPE_INTERVAL
		visible_count += 1
	_render()

func _input(event: InputEvent) -> void:
	if not open_state or not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if choice_active and key_event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		get_viewport().set_input_as_handled()
		if visible_count < current_text.length():
			visible_count = current_text.length()
		else:
			var delta: int = -1 if key_event.keycode in [KEY_UP, KEY_LEFT] else 1
			choice_index = wrapi(choice_index + delta, 0, choice_options.size())
		_render()
		return
	if key_event.keycode not in [KEY_F, KEY_E, KEY_Z, KEY_X, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		return
	get_viewport().set_input_as_handled()
	if ignore_next_action:
		ignore_next_action = false
		return
	if choice_active:
		handle_action()
	else:
		action_requested.emit()

func _clear_choices() -> void:
	choice_active = false
	choice_options.clear()
	choice_labels.clear()
	choice_index = 0
	if choice_box != null:
		for child in choice_box.get_children():
			child.queue_free()
		choice_box.visible = false
	if text_label != null:
		text_label.custom_minimum_size = Vector2(0, 112)

func _render() -> void:
	if text_label == null:
		return
	text_label.text = current_text
	text_label.visible_characters = visible_count
	var prompt: bool = _choice_prompt_ready()
	if prompt != choice_active:
		choice_active = prompt
		if choice_box != null:
			choice_box.visible = prompt
		text_label.custom_minimum_size = Vector2(0, 88 if prompt else 112)
		_layout_panel()
	for index in choice_labels.size():
		var label: Label = choice_labels[index]
		var option: Dictionary = choice_options[index]
		label.text = ("▶ " if index == choice_index else "  ") + str(option.get("label", ""))
		label.modulate = Color(1.0, 0.92, 0.5) if index == choice_index else Color.WHITE
	if arrow_label != null:
		arrow_label.visible = open_state and visible_count >= current_text.length() and not prompt
