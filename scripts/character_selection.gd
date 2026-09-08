extends Control

signal character_selected
signal logout_requested

var card_grid: GridContainer
var status_label: Label
var character_cards: Array[PanelContainer] = []
var selecting: bool = false
var warmed_map_ids: Dictionary = {}
var warming_map_ids: Dictionary = {}
var selected_character_id: int = 0
var last_click_character_id: int = 0
var last_click_msec: int = 0
const DOUBLE_CLICK_WINDOW_MSEC: int = 400

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process_unhandled_input(true)
	GameState.characters_changed.connect(_on_characters_changed)
	GameState.connection_error.connect(_on_connection_error)
	_build_ui()
	_on_characters_changed(GameState.characters)

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("0b111b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 0)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("151d29"), Color("334760"), 14, 1))
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	var title := Label.new()
	title.text = "Character Selection"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("f4f7fb"))
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Choose a character to enter the world."
	subtitle.add_theme_color_override("font_color", Color("aebbd0"))
	box.add_child(subtitle)
	var separator := HSeparator.new()
	separator.add_theme_color_override("separator", Color("2a384b"))
	box.add_child(separator)
	card_grid = GridContainer.new()
	card_grid.columns = 2
	card_grid.add_theme_constant_override("h_separation", 12)
	card_grid.add_theme_constant_override("v_separation", 12)
	card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(card_grid)
	status_label = Label.new()
	status_label.custom_minimum_size = Vector2(0, 30)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("b8c7d9"))
	box.add_child(status_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	actions.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(actions)
	var new_button := Button.new()
	new_button.text = "NEW CHARACTER"
	new_button.tooltip_text = "Character creation is not exposed by the current OpenMMO server protocol."
	new_button.disabled = true
	_style_button(new_button)
	actions.add_child(new_button)
	var delete_button := Button.new()
	delete_button.text = "DELETE CHARACTER"
	delete_button.tooltip_text = "Character deletion is not exposed by the current OpenMMO server protocol."
	delete_button.disabled = true
	_style_button(delete_button)
	actions.add_child(delete_button)
	var logout_button := Button.new()
	logout_button.text = "LOGOUT"
	logout_button.pressed.connect(_logout)
	_style_button(logout_button, true)
	actions.add_child(logout_button)

func _on_characters_changed(value: Array) -> void:
	if card_grid == null:
		return
	for child in card_grid.get_children():
		child.queue_free()
	character_cards.clear()
	selected_character_id = 0
	last_click_character_id = 0
	last_click_msec = 0
	if value.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No characters are available on this account."
		empty_label.add_theme_color_override("font_color", Color("aebbd0"))
		card_grid.add_child(empty_label)
		status_label.text = "This server does not currently expose character creation."
		return
	status_label.text = "Select a character to continue."
	for character_value in value:
		if character_value is Dictionary:
			_add_character_card(character_value as Dictionary)
	call_deferred("_warm_character_maps", value.duplicate())

func _warm_character_maps(values: Array) -> void:
	if not GameState.has_content():
		return
	for character_value in values:
		if not character_value is Dictionary:
			continue
		var character: Dictionary = character_value
		var bank_id: int = int(character.get("bank_id", -1))
		var map_num: int = int(character.get("map_id", -1))
		var region_id: int = int(character.get("region_id", character.get("region", -1)))
		var region_content: OpenMMOContent = GameState.content_for_location(bank_id, map_num, region_id)
		var map_id: String = GameState.map_id_for_location(bank_id, map_num, region_id)
		if region_content == null or map_id.is_empty() or warmed_map_ids.has(map_id) or warming_map_ids.has(map_id):
			continue
		warming_map_ids[map_id] = true
		await get_tree().process_frame
		if not is_inside_tree() or selecting or not GameState.has_content():
			warming_map_ids.erase(map_id)
			return
		region_content = GameState.content_for_location(bank_id, map_num, region_id)
		if region_content == null:
			warming_map_ids.erase(map_id)
			continue
		var worker: OpenMMOContent = region_content.create_map_cache_worker()
		var task_id: int = WorkerThreadPool.add_task(worker.build_detached_map_cache.bind(map_id), false, "Warm map %s" % map_id)
		var prepared: Dictionary = await _finish_map_warm(worker, task_id)
		warming_map_ids.erase(map_id)
		if not bool(prepared.get("ok", false)):
			continue
		region_content.install_detached_map_cache(map_id, prepared)
		warmed_map_ids[map_id] = true
		_set_map_ready(map_id)

func _finish_map_warm(worker: OpenMMOContent, task_id: int) -> Dictionary:
	if task_id < 0:
		return {}
	while not WorkerThreadPool.is_task_completed(task_id):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task_id)
	return worker.detached_map_cache_result if worker != null else {}

func _add_character_card(character: Dictionary) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(316, 250)
	card.add_theme_stylebox_override("panel", _panel_style(Color("1b2635"), Color("405873"), 10, 1))
	card_grid.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	box.add_child(top)
	var avatar := TextureRect.new()
	avatar.custom_minimum_size = Vector2(92, 116)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	avatar.texture = _character_texture()
	top.add_child(avatar)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 4)
	top.add_child(details)
	var name_label := Label.new()
	name_label.text = str(character.get("name", "Character"))
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color("f4f7fb"))
	details.add_child(name_label)
	var location_label := Label.new()
	location_label.text = _location_text(character)
	location_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	location_label.add_theme_color_override("font_color", Color("aebbd0"))
	details.add_child(location_label)
	var money_label := Label.new()
	money_label.text = "$%s" % _format_money(int(character.get("money", 0)))
	money_label.add_theme_color_override("font_color", Color("89d6a3"))
	details.add_child(money_label)
	var guild_name := str(character.get("guild_name", ""))
	if not guild_name.is_empty():
		var guild_label := Label.new()
		guild_label.text = guild_name
		guild_label.add_theme_color_override("font_color", Color("d8b4ff"))
		details.add_child(guild_label)
	var party_title := Label.new()
	party_title.text = "PARTY"
	party_title.add_theme_font_size_override("font_size", 12)
	party_title.add_theme_color_override("font_color", Color("91a0b5"))
	box.add_child(party_title)
	var party_box := HBoxContainer.new()
	party_box.add_theme_constant_override("separation", 5)
	box.add_child(party_box)
	var party: Array = character.get("party", [])
	for index in range(6):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(42, 52)
		slot.add_theme_stylebox_override("panel", _panel_style(Color("101923"), Color("334760"), 5, 1))
		var slot_box := VBoxContainer.new()
		slot_box.alignment = BoxContainer.ALIGNMENT_CENTER
		slot_box.add_theme_constant_override("separation", 0)
		slot.add_child(slot_box)
		var member: Dictionary = party[index] as Dictionary if index < party.size() and party[index] is Dictionary else {}
		var slot_icon := TextureRect.new()
		slot_icon.custom_minimum_size = Vector2(36, 36)
		slot_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		slot_icon.texture = _party_icon_texture(member)
		slot_icon.visible = slot_icon.texture != null
		slot_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_box.add_child(slot_icon)
		var slot_label := Label.new()
		slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot_label.add_theme_font_size_override("font_size", 9)
		slot_label.text = "Lv %d" % int(member.get("level", 0)) if not member.is_empty() else ""
		slot_label.tooltip_text = _party_slot_text(member) if not member.is_empty() else ""
		slot_box.add_child(slot_label)
		slot.tooltip_text = _party_slot_text(member) if not member.is_empty() else ""
		party_box.add_child(slot)
	var local_map_id: String = GameState.map_id_for_location(int(character.get("bank_id", -1)), int(character.get("map_id", -1)), int(character.get("region_id", character.get("region", -1)))) if GameState.has_content() else ""
	var character_id: int = int(character.get("id", 0))
	card.set_meta("character_id", character_id)
	card.set_meta("map_id", local_map_id)
	card.set_meta("available", _character_location_available(character))
	card.set_meta("ready", bool(card.get_meta("available", false)))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if bool(card.get_meta("available", false)) and bool(card.get_meta("ready", false)) else Control.CURSOR_ARROW
	card.gui_input.connect(_on_character_card_gui_input.bind(card, character_id))
	character_cards.append(card)
	_refresh_card_style(card)

func _on_character_card_gui_input(event: InputEvent, card: PanelContainer, character_id: int) -> void:
	if selecting or not bool(card.get_meta("available", false)) or not bool(card.get_meta("ready", false)):
		return
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event == null or mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	var now: int = Time.get_ticks_msec()
	var double_click: bool = last_click_character_id == character_id and now - last_click_msec <= DOUBLE_CLICK_WINDOW_MSEC
	selected_character_id = character_id
	last_click_character_id = character_id
	last_click_msec = now
	status_label.text = "Opening character..." if double_click else "Character selected. Double-click to enter the world."
	for candidate in character_cards:
		_refresh_card_style(candidate)
	card.accept_event()
	if double_click:
		_select_character(character_id)

func _refresh_card_style(card: PanelContainer) -> void:
	var available: bool = bool(card.get_meta("available", false)) and bool(card.get_meta("ready", false))
	var selected: bool = int(card.get_meta("character_id", 0)) == selected_character_id
	var fill: Color = Color("243653") if selected else Color("1b2635")
	var border: Color = Color("6b8fff") if selected else Color("405873")
	if not available:
		fill = Color("101722")
		border = Color("1d2938")
	card.add_theme_stylebox_override("panel", _panel_style(fill, border, 10, 1))

func _set_map_ready(map_id: String) -> void:
	for card in character_cards:
		if str(card.get_meta("map_id", "")) == map_id:
			card.set_meta("ready", true)
			_refresh_card_style(card)

func _character_location_available(character: Dictionary) -> bool:
	if not GameState.has_content():
		return false
	var bank_id: int = int(character.get("bank_id", -1))
	var map_num: int = int(character.get("map_id", -1))
	var region_id: int = int(character.get("region_id", character.get("region", -1)))
	var local_map_id: String = GameState.map_id_for_location(bank_id, map_num, region_id)
	if local_map_id.is_empty():
		return false
	return not GameState.map_data_for_location(bank_id, map_num, region_id).is_empty()

func _character_texture() -> Texture2D:
	if not GameState.has_content() or GameState.content == null:
		return null
	var sprite: Dictionary = GameState.content.render_facing_object_sprite(19, 1, false, 0)
	return sprite.get("texture") as Texture2D

func _location_text(character: Dictionary) -> String:
	if not GameState.has_content():
		return "Unknown area"
	var bank_id: int = int(character.get("bank_id", -1))
	var map_num: int = int(character.get("map_id", -1))
	var region_id: int = int(character.get("region_id", character.get("region", -1)))
	var local_id: String = GameState.map_id_for_location(bank_id, map_num, region_id)
	if local_id.is_empty():
		return "Unknown area"
	var map_value: Dictionary = GameState.map_data_for_location(bank_id, map_num, region_id)
	var name: String = str(map_value.get("name", local_id)).strip_edges()
	if name.is_empty():
		return local_id
	return name

func _party_slot_text(member: Dictionary) -> String:
	var species_id: int = int(member.get("dex_id", member.get("species_id", member.get("species", 0))))
	var nickname: String = str(member.get("nickname", "")).strip_edges()
	if nickname.is_empty() and species_id > 0 and GameState.content != null:
		nickname = GameState.content.battle_pokemon_name(species_id)
	if nickname.is_empty():
		nickname = "Pokemon"
	return "%s\nLv %d" % [nickname.left(10), int(member.get("level", 0))]

func _party_icon_texture(member: Dictionary) -> Texture2D:
	var species_id: int = int(member.get("dex_id", member.get("species_id", member.get("species", 0))))
	if species_id <= 0 or GameState.content == null:
		return null
	var sprite: Dictionary = GameState.content.battle_pokemon_sprite(species_id, false)
	return sprite.get("texture") as Texture2D

func _select_character(character_id: int) -> void:
	if selecting:
		return
	if not GameState.select_character(character_id):
		status_label.text = "The character could not be selected."
		status_label.modulate = Color("ff9a9a")
		return
	selecting = true
	for card in character_cards:
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.modulate = Color("b8c7d9")
	status_label.text = "Entering the world…"
	character_selected.emit()

func _logout() -> void:
	GameState.disconnect_game()
	GameState.current_character.clear()
	selecting = false
	logout_requested.emit()

func _on_connection_error(message: String) -> void:
	selecting = false
	for card in character_cards:
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		_refresh_card_style(card)
	if status_label != null:
		status_label.modulate = Color("ff9a9a")
		status_label.text = message

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_logout()
	elif key_event.keycode == KEY_ENTER:
		var character_id: int = selected_character_id
		if character_id == 0 and character_cards.size() == 1:
			var only_card: PanelContainer = character_cards[0]
			if bool(only_card.get_meta("available", false)) and bool(only_card.get_meta("ready", false)):
				character_id = int(only_card.get_meta("character_id", 0))
		if character_id != 0:
			get_viewport().set_input_as_handled()
			_select_character(character_id)

func _panel_style(background: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10.0
	style.content_margin_top = 8.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 8.0
	return style

func _style_button(button: Button, accent: bool = false) -> void:
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 40.0)
	var normal_color := Color("567cff") if accent else Color("202c3c")
	var hover_color := Color("668cff") if accent else Color("2a394d")
	var pressed_color := Color("4569e5") if accent else Color("182331")
	button.add_theme_stylebox_override("normal", _panel_style(normal_color, normal_color, 8, 0))
	button.add_theme_stylebox_override("hover", _panel_style(hover_color, hover_color, 8, 0))
	button.add_theme_stylebox_override("pressed", _panel_style(pressed_color, pressed_color, 8, 0))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("18212d"), Color("18212d"), 8, 0))
	button.add_theme_color_override("font_color", Color("ffffff"))
	button.add_theme_color_override("font_disabled_color", Color("657286"))

func _format_money(value: int) -> String:
	var negative := value < 0
	var digits := str(absi(value))
	var formatted := ""
	while digits.length() > 3:
		formatted = "," + digits.substr(digits.length() - 3) + formatted
		digits = digits.substr(0, digits.length() - 3)
	formatted = digits + formatted
	return "-" + formatted if negative else formatted
