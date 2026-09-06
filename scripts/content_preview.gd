extends Control

signal exit_requested

var content: OpenMMOContent
var selected_map_id: String = ""
var map_title: Label
var map_details: Label
var map_status: Label
var map_view: OpenMMOMapPreviewCanvas
var play_view: OpenMMOMapPlayCanvas
var hud: OpenMMOHud
var map_selector: OptionButton
var play_button: Button
var preview_button: Button
var dialogue_overlay: OpenMMODialogue
var audio: OpenMMOAudio
var preview_shell: Control
var animation_tick: int = 0
var animation_elapsed: float = 0.0
var playing: bool = false
var preparing_play: bool = false

func _ready() -> void:
	if content == null:
		var rom_path: String = OS.get_environment("OPENMMOGO_ROM")
		if not rom_path.is_empty():
			var local_result: Dictionary = OpenMMOContent.from_rom_path(rom_path)
			if bool(local_result.get("ok", false)):
				content = local_result.get("content") as OpenMMOContent
	_build_ui()
	if content == null:
		return
	var maps: Array = content.manifest.get("maps", [])
	if not maps.is_empty() and maps[0] is Dictionary:
		_select_map(str(maps[0].get("id", "")))

func _process(delta: float) -> void:
	if content == null or selected_map_id.is_empty():
		return
	animation_elapsed += delta
	if animation_elapsed < 0.125:
		return
	animation_elapsed = 0.0
	animation_tick += 1
	if playing:
		play_view.set_animation_tick(animation_tick)
	else:
		_render_selected_map()

func _build_ui() -> void:
	preview_shell = Control.new()
	preview_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(preview_shell)
	var background: ColorRect = ColorRect.new()
	background.color = Color("101721")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_shell.add_child(background)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 22)
	preview_shell.add_child(margin)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title: Label = Label.new()
	title.text = "ROM-backed map preview"
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	var subtitle: Label = Label.new()
	subtitle.text = "Rendered directly from the selected GBA ROM; no account or server connection is used."
	subtitle.modulate = Color("b8c7d9")
	box.add_child(subtitle)
	var metadata: Label = Label.new()
	metadata.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	metadata.text = _metadata_text()
	metadata.modulate = Color("d7e0eb")
	box.add_child(metadata)
	var map_controls: HBoxContainer = HBoxContainer.new()
	map_controls.add_theme_constant_override("separation", 8)
	var maps: Array = content.manifest.get("maps", []) if content != null else []
	map_selector = OptionButton.new()
	map_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_selector.item_selected.connect(_on_map_selected)
	for map_value in maps:
		if not map_value is Dictionary:
			continue
		var map_dictionary: Dictionary = map_value
		map_selector.add_item(str(map_dictionary.get("name", map_dictionary.get("id", "Map"))))
		map_selector.set_item_metadata(map_selector.item_count - 1, str(map_dictionary.get("id", "")))
	map_controls.add_child(map_selector)
	preview_button = Button.new()
	preview_button.text = "Preview"
	preview_button.pressed.connect(_on_preview_pressed)
	map_controls.add_child(preview_button)
	play_button = Button.new()
	play_button.text = "Play selected map"
	play_button.pressed.connect(_on_play_pressed)
	map_controls.add_child(play_button)
	box.add_child(map_controls)
	map_title = Label.new()
	map_title.add_theme_font_size_override("font_size", 23)
	box.add_child(map_title)
	map_details = Label.new()
	map_details.modulate = Color("b8c7d9")
	box.add_child(map_details)
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(panel)
	map_view = OpenMMOMapPreviewCanvas.new()
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.custom_minimum_size = Vector2(0, 260)
	panel.add_child(map_view)
	play_view = OpenMMOMapPlayCanvas.new()
	play_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	play_view.visible = false
	play_view.set_content(content)
	play_view.location_changed.connect(_on_play_location_changed)
	play_view.back_requested.connect(_on_preview_pressed)
	play_view.interaction_requested.connect(_on_interaction_requested)
	play_view.sound_requested.connect(_on_sound_requested)
	add_child(play_view)
	play_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	play_view.z_index = 100
	audio = OpenMMOAudio.new()
	add_child(audio)
	hud = OpenMMOHud.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.visible = false
	play_view.add_child(hud)
	_build_dialogue_overlay()
	map_status = Label.new()
	map_status.modulate = Color("b8c7d9")
	box.add_child(map_status)

func _metadata_text() -> String:
	if content == null:
		return "No local ROM is loaded."
	var source: Dictionary = content.manifest.get("source", {})
	var header: Dictionary = content.rom_header
	return "%s %s  •  %s  •  %s  •  %s\nROM fingerprint: %s  •  Content ID: %s" % [str(source.get("game", "Unknown")), str(source.get("revision", "")), str(header.get("title", "Unknown")), str(header.get("game_code", "Unknown")), str(header.get("maker_code", "Unknown")), content.rom_sha1, content.content_id()]

func _select_map(map_id: String) -> void:
	if content == null:
		return
	var map_value: Dictionary = content.map_data(map_id)
	if map_value.is_empty():
		return
	selected_map_id = map_id
	animation_tick = 0
	animation_elapsed = 0.0
	if map_selector != null:
		for item_index in range(map_selector.item_count):
			if str(map_selector.get_item_metadata(item_index)) == map_id:
				map_selector.select(item_index)
				break
	_render_selected_map()

func _on_map_selected(item_index: int) -> void:
	if map_selector == null:
		return
	_select_map(str(map_selector.get_item_metadata(item_index)))

func _on_play_pressed() -> void:
	if content == null or selected_map_id.is_empty() or preparing_play:
		return
	preparing_play = true
	play_button.disabled = true
	map_status.text = "Preparing the complete map and animation set..."
	await get_tree().process_frame
	var prepared: Dictionary = content.prepare_map(selected_map_id)
	preparing_play = false
	play_button.disabled = false
	if not bool(prepared.get("ok", false)):
		map_status.text = str(prepared.get("error", "Map preparation failed"))
		return
	_set_playing(true)
	play_view.set_map(prepared.get("texture", prepared.get("background_texture")) as Texture2D, int(prepared.get("width", 0)), int(prepared.get("height", 0)), prepared.get("objects", []), selected_map_id, prepared.get("foreground_texture") as Texture2D)
	if hud != null:
		hud.set_state(content, selected_map_id)
	audio.play_map_music(content, selected_map_id)

func _on_preview_pressed() -> void:
	_set_playing(false)
	_render_selected_map()

func _on_back_pressed() -> void:
	exit_requested.emit()

func _build_dialogue_overlay() -> void:
	dialogue_overlay = OpenMMODialogue.new()
	dialogue_overlay.action_requested.connect(_on_dialogue_action)
	play_view.add_child(dialogue_overlay)

func _on_interaction_requested(dialogue: Dictionary) -> void:
	if dialogue_overlay == null or dialogue.is_empty() or dialogue_overlay.is_open():
		return
	var pages: Array = dialogue.get("pages", [])
	if pages.is_empty():
		pages = [str(dialogue.get("text", ""))]
	dialogue_overlay.show_pages(pages, true, play_view.dialogue_anchor_screen(dialogue))
	play_view.set_dialogue_active(true)
	audio.play_effect("dialogue")

func _on_dialogue_action() -> void:
	audio.play_effect("dialogue")
	if dialogue_overlay != null and dialogue_overlay.handle_action() and not dialogue_overlay.is_open():
		play_view.set_dialogue_active(false)

func _on_sound_requested(effect: String) -> void:
	audio.play_effect(effect)

func _set_playing(value: bool) -> void:
	playing = value
	preview_shell.visible = not value
	play_view.visible = value
	if hud != null:
		hud.visible = value
	play_view.set_input_enabled(value)
	if dialogue_overlay != null:
		dialogue_overlay.close_dialogue()
	play_view.set_dialogue_active(false)

func _on_play_location_changed(map_id: String, _x: int, _y: int) -> void:
	selected_map_id = map_id
	if playing:
		audio.play_map_music(content, map_id)
	if playing and hud != null:
		hud.set_state(content, map_id)
	if not playing:
		_render_selected_map()

func _render_selected_map() -> void:
	if content == null or selected_map_id.is_empty():
		return
	var map_value: Dictionary = content.map_data(selected_map_id)
	map_title.text = str(map_value.get("name", selected_map_id))
	map_details.text = "Loading ROM tiles..."
	map_status.text = ""
	var result: Dictionary = content.render_map(selected_map_id, animation_tick)
	if not bool(result.get("ok", false)):
		map_details.text = "%d × %d map cells" % [int(map_value.get("width", 0)), int(map_value.get("height", 0))]
		map_status.text = str(result.get("error", "Map rendering failed"))
		return
	var texture: Texture2D = result.get("texture") as Texture2D
	map_view.set_map(texture, int(result.get("width", 0)), int(result.get("height", 0)), result.get("objects", []))
	map_details.text = "%d × %d map cells  •  actual 16×16 metatiles  •  %d ROM object events" % [int(result.get("width", 0)), int(result.get("height", 0)), (result.get("objects", []) as Array).size()]
	map_status.text = "Use Play selected map to walk the ROM map; collision, ledges, warps, and map connections are active."
