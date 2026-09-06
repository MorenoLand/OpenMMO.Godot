extends Control

signal authenticated
signal local_preview_requested

var provider: OpenMMOContentProvider
var username_input: LineEdit
var password_input: LineEdit
var remember_input: CheckButton
var key_dialog: FileDialog
var submit_button: Button
var rom_button: Button
var preview_button: Button
var content_status_label: Label
var status_label: Label
var settings_window: Window
var settings_server_input: LineEdit
var settings_custom_key_toggle: CheckButton
var settings_key_input: LineEdit
var settings_key_button: Button
var settings_status_label: Label
var busy := false
var saved_username: String = ""
var saved_password: String = ""
var saved_token: String = ""

func _ready() -> void:
	provider = OpenMMOContentProvider.new()
	add_child(provider)
	provider.content_loaded.connect(_on_content_loaded)
	provider.content_failed.connect(_on_content_failed)
	_build_ui()
	_load_saved_credentials()
	call_deferred("_initialize_content")

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("0b111b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	move_child(background, 0)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "LoginCard"
	panel.custom_minimum_size = Vector2(480, 0)
	var panel_style: StyleBoxFlat = _box_style(Color("151d29"), Color("29374b"), 14, 1)
	panel_style.shadow_color = Color("00000070")
	panel_style.shadow_size = 18
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 13)
	margin.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	box.add_child(header)
	var heading_box := VBoxContainer.new()
	heading_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_box.add_theme_constant_override("separation", 2)
	header.add_child(heading_box)
	var title := Label.new()
	title.text = "OpenMMOGo"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("f4f7fb"))
	heading_box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Sign in to the OpenMMO network"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color("91a0b5"))
	heading_box.add_child(subtitle)
	var settings_button := Button.new()
	settings_button.name = "ConnectionSettingsButton"
	settings_button.text = "Settings"
	settings_button.tooltip_text = "Connection settings"
	settings_button.pressed.connect(_open_settings)
	_style_button(settings_button)
	header.add_child(settings_button)
	var fields_spacer := Control.new()
	fields_spacer.custom_minimum_size = Vector2(0, 4)
	box.add_child(fields_spacer)
	username_input = LineEdit.new()
	username_input.name = "Username"
	username_input.placeholder_text = "Username"
	username_input.text_submitted.connect(_on_text_submitted)
	_style_line_edit(username_input)
	box.add_child(username_input)
	password_input = LineEdit.new()
	password_input.name = "Password"
	password_input.placeholder_text = "Password"
	password_input.secret = true
	password_input.text_submitted.connect(_on_text_submitted)
	_style_line_edit(password_input)
	box.add_child(password_input)
	remember_input = CheckButton.new()
	remember_input.name = "RememberMe"
	remember_input.text = "Remember me"
	remember_input.tooltip_text = "Remember this username and password on this device."
	remember_input.add_theme_color_override("font_color", Color("c4cedb"))
	box.add_child(remember_input)
	submit_button = Button.new()
	submit_button.name = "SignIn"
	submit_button.text = "Sign in"
	submit_button.custom_minimum_size = Vector2(0, 48)
	submit_button.pressed.connect(_submit)
	_style_button(submit_button, true)
	box.add_child(submit_button)
	var separator := HSeparator.new()
	separator.add_theme_color_override("separator", Color("2a384b"))
	box.add_child(separator)
	var content_row := HBoxContainer.new()
	content_row.add_theme_constant_override("separation", 10)
	box.add_child(content_row)
	content_status_label = Label.new()
	content_status_label.name = "ContentStatus"
	content_status_label.text = "No ROMs selected"
	content_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content_status_label.add_theme_color_override("font_color", Color("aebbd0"))
	content_row.add_child(content_status_label)
	rom_button = Button.new()
	rom_button.name = "ChooseRom"
	rom_button.text = "Client Management"
	rom_button.pressed.connect(_choose_rom)
	_style_button(rom_button)
	content_row.add_child(rom_button)
	preview_button = Button.new()
	preview_button.name = "LocalPreview"
	preview_button.text = "Test ROM locally"
	preview_button.disabled = true
	preview_button.pressed.connect(_test_rom_locally)
	_style_button(preview_button)
	box.add_child(preview_button)
	status_label = Label.new()
	status_label.name = "Status"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(0, 34)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(status_label)
	key_dialog = FileDialog.new()
	key_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	key_dialog.access = FileDialog.ACCESS_FILESYSTEM
	key_dialog.use_native_dialog = true
	key_dialog.filters = PackedStringArray(["*.pem ; PEM public keys"])
	key_dialog.file_selected.connect(_on_key_selected)
	add_child(key_dialog)
	settings_window = _build_settings_window()

func _build_settings_window() -> Window:
	var window := Window.new()
	window.name = "ConnectionSettings"
	window.title = "Connection settings"
	window.size = Vector2i(560, 430)
	window.min_size = Vector2i(500, 390)
	window.transient = true
	window.exclusive = true
	window.close_requested.connect(window.hide)
	add_child(window)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _box_style(Color("111923"), Color("29374b"), 0, 0))
	window.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var heading := Label.new()
	heading.text = "Connection settings"
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Color("f4f7fb"))
	box.add_child(heading)
	var description := Label.new()
	description.text = "Configure the OpenMMO login server. The bundled server key is used unless you choose an override."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", Color("91a0b5"))
	box.add_child(description)
	var server_label := Label.new()
	server_label.text = "Login server"
	server_label.add_theme_color_override("font_color", Color("c4cedb"))
	box.add_child(server_label)
	settings_server_input = LineEdit.new()
	settings_server_input.name = "LoginServer"
	settings_server_input.placeholder_text = "host:port"
	settings_server_input.text_submitted.connect(_on_settings_submitted)
	_style_line_edit(settings_server_input)
	box.add_child(settings_server_input)
	settings_custom_key_toggle = CheckButton.new()
	settings_custom_key_toggle.name = "UseCustomKey"
	settings_custom_key_toggle.text = "Use a custom server public key"
	settings_custom_key_toggle.toggled.connect(_on_custom_key_toggled)
	settings_custom_key_toggle.add_theme_color_override("font_color", Color("c4cedb"))
	box.add_child(settings_custom_key_toggle)
	var key_row := HBoxContainer.new()
	key_row.add_theme_constant_override("separation", 8)
	box.add_child(key_row)
	settings_key_input = LineEdit.new()
	settings_key_input.name = "CustomKeyPath"
	settings_key_input.placeholder_text = "Bundled server key is active"
	settings_key_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_key_input.text_submitted.connect(_on_settings_submitted)
	_style_line_edit(settings_key_input)
	key_row.add_child(settings_key_input)
	settings_key_button = Button.new()
	settings_key_button.text = "Browse"
	settings_key_button.pressed.connect(_choose_key)
	_style_button(settings_key_button)
	key_row.add_child(settings_key_button)
	settings_status_label = Label.new()
	settings_status_label.custom_minimum_size = Vector2(0, 28)
	settings_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_status_label.add_theme_color_override("font_color", Color("ff9a9a"))
	box.add_child(settings_status_label)
	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_END
	action_row.add_theme_constant_override("separation", 8)
	box.add_child(action_row)
	var cancel_button := Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(window.hide)
	_style_button(cancel_button)
	action_row.add_child(cancel_button)
	var save_button := Button.new()
	save_button.name = "SaveConnectionSettings"
	save_button.text = "Save"
	save_button.pressed.connect(_save_connection_settings)
	_style_button(save_button, true)
	action_row.add_child(save_button)
	_on_custom_key_toggled(false)
	window.hide()
	return window

func _box_style(background: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	style.content_margin_left = 14.0
	style.content_margin_top = 10.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 10.0
	return style

func _style_line_edit(input: LineEdit) -> void:
	input.custom_minimum_size = Vector2(0, 46)
	input.add_theme_stylebox_override("normal", _box_style(Color("0e1520"), Color("29374b"), 8, 1))
	input.add_theme_stylebox_override("focus", _box_style(Color("101a28"), Color("668cff"), 8, 2))
	input.add_theme_stylebox_override("read_only", _box_style(Color("101620"), Color("222e3e"), 8, 1))
	input.add_theme_color_override("font_color", Color("eef3f9"))
	input.add_theme_color_override("font_placeholder_color", Color("718096"))

func _style_button(button: Button, accent: bool = false) -> void:
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 40.0)
	var normal_color := Color("567cff") if accent else Color("202c3c")
	var hover_color := Color("668cff") if accent else Color("2a394d")
	var pressed_color := Color("4569e5") if accent else Color("182331")
	button.add_theme_stylebox_override("normal", _box_style(normal_color, normal_color, 8, 0))
	button.add_theme_stylebox_override("hover", _box_style(hover_color, hover_color, 8, 0))
	button.add_theme_stylebox_override("pressed", _box_style(pressed_color, pressed_color, 8, 0))
	button.add_theme_stylebox_override("disabled", _box_style(Color("18212d"), Color("18212d"), 8, 0))
	button.add_theme_color_override("font_color", Color("ffffff"))
	button.add_theme_color_override("font_disabled_color", Color("657286"))

func _load_saved_credentials() -> void:
	var saved: Dictionary = OpenMMOAuthStore.load_saved()
	if saved.is_empty():
		return
	username_input.text = str(saved.get("username", ""))
	password_input.text = str(saved.get("password", ""))
	saved_username = username_input.text
	saved_password = password_input.text
	saved_token = str(saved.get("token", ""))
	remember_input.button_pressed = true

func _initialize_content() -> void:
	if GameState.has_content():
		_refresh_content_status()
		return
	if not provider.restore_saved_rom():
		provider.choose(self)

func _choose_key() -> void:
	settings_custom_key_toggle.set_pressed_no_signal(true)
	_on_custom_key_toggled(true)
	key_dialog.popup_centered_ratio(0.75)

func _on_key_selected(path: String) -> void:
	settings_key_input.text = path

func _open_settings() -> void:
	settings_server_input.text = GameState.endpoint_text()
	var custom_key_path: String = GameState.public_key_override()
	settings_custom_key_toggle.set_pressed_no_signal(not custom_key_path.is_empty())
	settings_key_input.text = custom_key_path
	_on_custom_key_toggled(not custom_key_path.is_empty())
	settings_status_label.text = ""
	settings_window.popup_centered()

func _on_custom_key_toggled(enabled: bool) -> void:
	if settings_key_input == null or settings_key_button == null:
		return
	settings_key_input.editable = enabled
	settings_key_button.disabled = not enabled

func _on_settings_submitted(_value: String) -> void:
	_save_connection_settings()

func _save_connection_settings() -> void:
	var custom_key_path: String = settings_key_input.text.strip_edges() if settings_custom_key_toggle.button_pressed else ""
	var configured: Dictionary = GameState.configure_server(settings_server_input.text, custom_key_path)
	if not bool(configured.get("ok", false)):
		settings_status_label.text = str(configured.get("error", "Invalid connection settings"))
		return
	var settings: Dictionary = OpenMMOStorage.read_json(OpenMMOStorage.SETTINGS_FILE)
	settings["login_host"] = GameState.login_host
	settings["login_port"] = GameState.login_port
	if custom_key_path.is_empty():
		settings.erase("root_public_key_path")
	else:
		settings["root_public_key_path"] = custom_key_path
	if not OpenMMOStorage.write_json(OpenMMOStorage.SETTINGS_FILE, settings):
		settings_status_label.text = "Could not save connection settings"
		return
	settings_window.hide()
	_set_status("Connection settings saved.")

func _choose_rom() -> void:
	provider.choose(self)

func _on_content_loaded(content: OpenMMOContent) -> void:
	var result: Dictionary = GameState.use_content(content)
	if result.ok:
		_refresh_content_status()
		_set_status("")
	else:
		_set_status(str(result.error), true)

func _on_content_failed(message: String) -> void:
	_refresh_content_status()
	_set_status(message, true)

func _refresh_content_status() -> void:
	var ready: PackedStringArray = GameState.content_regions_ready()
	rom_button.text = "Client Management"
	if ready.is_empty():
		content_status_label.text = "No ROMs selected"
		content_status_label.add_theme_color_override("font_color", Color("aebbd0"))
		preview_button.disabled = true
		return
	content_status_label.text = "%s ready" % " / ".join(ready)
	content_status_label.add_theme_color_override("font_color", Color("89d6a3"))
	preview_button.disabled = false

func _test_rom_locally() -> void:
	if not GameState.has_content():
		_set_status("Select a compatible ROM first.", true)
		provider.choose(self)
		return
	local_preview_requested.emit()
func _on_text_submitted(_text: String) -> void:
	_submit()

func _submit() -> void:
	if busy:
		return
	var username: String = username_input.text.strip_edges()
	var password: String = password_input.text
	var token: String = saved_token if remember_input.button_pressed and username == saved_username and password == saved_password else ""
	if username.is_empty() or (password.is_empty() and token.is_empty()):
		_set_status("Username and password are required.", true)
		return
	if not GameState.has_content():
		_set_status("Select at least one ROM (Kanto and/or Hoenn) before signing in.", true)
		provider.choose(self)
		return
	var configured: Dictionary = GameState.configure_server(GameState.endpoint_text(), GameState.public_key_override())
	if not configured.ok:
		_set_status(str(configured.error), true)
		return
	busy = true
	submit_button.disabled = true
	_set_status("Authenticating…")
	var result: Dictionary = await GameState.login(username, password, remember_input.button_pressed, token)
	if not result.ok:
		_finish_submit(str(result.error), true)
		return
	if remember_input.button_pressed:
		OpenMMOAuthStore.save(username, password, str(result.get("remember_token", "")))
		saved_username = username
		saved_password = password
		saved_token = str(result.get("remember_token", ""))
	else:
		OpenMMOAuthStore.clear()
	_set_status("Opening game connection…")
	result = await GameState.connect_game()
	if not result.ok:
		_finish_submit(str(result.error), true)
		return
	busy = false
	submit_button.disabled = false
	authenticated.emit()

func _finish_submit(message: String, is_error: bool) -> void:
	busy = false
	submit_button.disabled = false
	_set_status(message, is_error)

func _set_status(value: String, is_error := false) -> void:
	if status_label == null:
		return
	status_label.text = value
	status_label.modulate = Color("ff9a9a") if is_error else Color("b8c7d9")
