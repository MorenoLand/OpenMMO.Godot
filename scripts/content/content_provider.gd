class_name OpenMMOContentProvider
extends Node

const REGION_OPTIONS: Array = [
	{"region": "Unova", "title": "Black/White ROM", "enabled": false, "description": "Unavailable until Unova content is implemented."},
	{"region": "Kanto", "title": "FireRed/LeafGreen ROM", "enabled": true, "description": "Accepts a compatible FireRed or LeafGreen base ROM, including graphics patches that preserve the source map layout."},
	{"region": "Hoenn", "title": "Ruby/Sapphire/Emerald ROM", "enabled": true, "description": "Accepts a compatible Ruby, Sapphire, or Emerald .gba ROM. Map layout rendering uses the ROM gMapGroups table; content stays local and is never uploaded."},
	{"region": "Sinnoh", "title": "Platinum ROM", "enabled": false, "description": "Unavailable until Sinnoh content is implemented."},
	{"region": "Followers", "title": "HeartGold/SoulSilver extracted source", "enabled": true, "mode": "followers", "description": "Optional desktop source for authentic directional follower sprites. Select the pokeheartgold source root or its extracted mmodel folder; Johto map content remains unavailable."}
]
signal content_loaded(content: OpenMMOContent)
signal content_failed(message: String)

var manager: Window
var _web_callback: Variant
var _native_dialog_open: bool = false
var _pending_option: Dictionary = {}

func choose(parent: Node) -> void:
	if is_instance_valid(manager):
		manager.popup_centered()
		return
	manager = Window.new()
	manager.title = "Client Management"
	manager.size = Vector2i(680, 520)
	manager.min_size = Vector2i(560, 420)
	manager.close_requested.connect(_close_manager)
	manager.tree_exiting.connect(_on_manager_exiting)
	parent.add_child(manager)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	manager.add_child(margin)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var heading: Label = Label.new()
	heading.text = "Local game content"
	heading.add_theme_font_size_override("font_size", 24)
	box.add_child(heading)
	var description: Label = Label.new()
	description.text = "Select a supported region ROM. Other regions will unlock as their content is implemented."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)
	for option_value in REGION_OPTIONS:
		var option: Dictionary = option_value
		var row: HBoxContainer = HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 44)
		var label: Label = Label.new()
		label.text = "%s — %s" % [str(option.get("region", "")), str(option.get("title", ""))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.tooltip_text = str(option.get("description", ""))
		if not bool(option.get("enabled", false)):
			label.modulate = Color("7f8794")
		row.add_child(label)
		var state: Label = Label.new()
		state.text = "Optional" if str(option.get("mode", "rom")) == "followers" else "Available" if bool(option.get("enabled", false)) else "Coming later"
		state.custom_minimum_size = Vector2(110, 0)
		state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		state.modulate = Color("b8c7d9") if bool(option.get("enabled", false)) else Color("6c7480")
		row.add_child(state)
		var select_button: Button = Button.new()
		select_button.text = "Select Folder" if str(option.get("mode", "rom")) == "followers" else "Select File"
		select_button.disabled = not bool(option.get("enabled", false))
		select_button.pressed.connect(_select_region.bind(option))
		row.add_child(select_button)
		var info_button: Button = Button.new()
		info_button.text = "Info"
		info_button.pressed.connect(_show_region_info.bind(option))
		row.add_child(info_button)
		box.add_child(row)
	var note: Label = Label.new()
	note.text = "Kanto accepts FireRed/LeafGreen .gba ROMs. Hoenn accepts Ruby/Sapphire/Emerald .gba ROMs. The optional follower source reads extracted HGSS models in place. Content stays local and is never uploaded."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color("b8c7d9")
	box.add_child(note)
	var close_button: Button = Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(_close_manager)
	box.add_child(close_button)
	manager.popup_centered()

func _select_region(option: Dictionary) -> void:
	if not bool(option.get("enabled", false)):
		return
	_pending_option = option.duplicate(true)
	if is_instance_valid(manager):
		manager.hide()
	if str(option.get("mode", "rom")) == "followers" and OS.has_feature("web"):
		content_failed.emit("extracted follower folders are available on desktop builds")
		return
	if OS.has_feature("web"):
		_choose_web()
		return
	if _native_dialog_open:
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		content_failed.emit("native file selection is unavailable on this platform")
		return
	_native_dialog_open = true
	var folder_mode: bool = str(option.get("mode", "rom")) == "followers"
	var dialog_mode: int = DisplayServer.FILE_DIALOG_MODE_OPEN_DIR if folder_mode else DisplayServer.FILE_DIALOG_MODE_OPEN_FILE
	var filters: PackedStringArray = PackedStringArray() if folder_mode else PackedStringArray(["*.gba;Game Boy Advance ROM;application/octet-stream"])
	var dialog_error: int = DisplayServer.file_dialog_show("Select %s" % str(option.get("title", "ROM")), "", "", false, dialog_mode, filters, _on_native_file_selected)
	if dialog_error != OK:
		_native_dialog_open = false
		content_failed.emit("could not open the native file picker")

func _show_region_info(option: Dictionary) -> void:
	if not is_instance_valid(manager):
		return
	var info: AcceptDialog = AcceptDialog.new()
	info.title = "%s — %s" % [str(option.get("region", "")), str(option.get("title", ""))]
	info.dialog_text = str(option.get("description", ""))
	manager.add_child(info)
	info.popup_centered()

func _close_manager() -> void:
	if is_instance_valid(manager):
		manager.queue_free()

func _on_manager_exiting() -> void:
	manager = null

func _on_native_file_selected(status: bool, selected_paths: PackedStringArray, _filter_index: int) -> void:
	_native_dialog_open = false
	var mode: String = str(_pending_option.get("mode", "rom"))
	if not status or selected_paths.is_empty():
		_pending_option = {}
		content_failed.emit("no follower folder was selected" if mode == "followers" else "no ROM was selected")
		return
	if mode == "followers":
		_pending_option = {}
		_on_follower_source_selected(selected_paths[0])
	else:
		_on_rom_selected(selected_paths[0])
		_pending_option = {}

func _on_rom_selected(path: String) -> void:
	var extension: String = path.get_extension().to_lower()
	if extension != "gba":
		content_failed.emit("unsupported file; select a .gba ROM")
		return
	var expected_region: String = str(_pending_option.get("region", "")).strip_edges()
	var result: Dictionary = OpenMMOContent.from_rom_path(path)
	if bool(result.get("ok", false)):
		var content: OpenMMOContent = result.get("content") as OpenMMOContent
		var actual_region: String = str(content.source_profile.get("region", "")).strip_edges()
		if not expected_region.is_empty() and not actual_region.is_empty() and expected_region.to_lower() != actual_region.to_lower():
			content_failed.emit("That ROM is %s content; pick a %s ROM for this row." % [actual_region, expected_region])
			if is_instance_valid(manager):
				manager.popup_centered()
			return
		_attach_saved_follower_source(content)
		_save_rom_path(path, actual_region if not actual_region.is_empty() else expected_region)
		_close_manager()
		content_loaded.emit(content)
	else:
		content_failed.emit(str(result.get("error", "could not load content")))
		if is_instance_valid(manager):
			manager.popup_centered()

func restore_saved_rom() -> bool:
	var roms: Dictionary = OpenMMOStorage.read_json(OpenMMOStorage.SETTINGS_FILE).get("roms", {})
	if not roms is Dictionary:
		_clear_saved_rom()
		return false
	var path: String = ""
	var region_key: String = ""
	for key in ["hoenn", "kanto"]:
		var candidate: String = str(roms.get(key, ""))
		if not candidate.is_empty():
			path = candidate
			region_key = key
			break
	if path.is_empty():
		return false
	if not FileAccess.file_exists(path):
		_clear_saved_rom_key(region_key)
		content_failed.emit("The saved %s ROM was moved or removed; select it again." % region_key.capitalize())
		return false
	var result: Dictionary = OpenMMOContent.from_rom_path(path)
	if bool(result.get("ok", false)):
		var content: OpenMMOContent = result.get("content") as OpenMMOContent
		_attach_saved_follower_source(content)
		content_loaded.emit(content)
		return true
	content_failed.emit("The saved %s ROM is still selected but could not be decoded: %s" % [region_key.capitalize(), str(result.get("error", "unknown content error"))])
	return false

func _save_rom_path(path: String, region: String = "") -> void:
	var settings: Dictionary = OpenMMOStorage.read_json(OpenMMOStorage.SETTINGS_FILE)
	var roms: Dictionary = settings.get("roms", {})
	var key: String = region.strip_edges().to_lower()
	if key.is_empty():
		key = "kanto"
	for wipe in ["kanto", "hoenn"]:
		if wipe != key:
			roms.erase(wipe)
	roms[key] = path
	settings["roms"] = roms
	OpenMMOStorage.write_json(OpenMMOStorage.SETTINGS_FILE, settings)

func _on_follower_source_selected(path: String) -> void:
	var resolved_path: String = OpenMMOContent.resolve_follower_source_path(path)
	if resolved_path.is_empty():
		content_failed.emit("The selected folder does not contain extracted HeartGold/SoulSilver follower models")
		if is_instance_valid(manager):
			manager.popup_centered()
		return
	_save_follower_source_path(resolved_path)
	if GameState.content != null:
		var attached: Dictionary = GameState.content.set_follower_source(resolved_path)
		if not bool(attached.get("ok", false)):
			content_failed.emit(str(attached.get("error", "could not load follower sprites")))
			return
		_close_manager()
		content_loaded.emit(GameState.content)
	elif is_instance_valid(manager):
		manager.popup_centered()

func _attach_saved_follower_source(content: OpenMMOContent) -> void:
	if content == null:
		return
	var roms: Dictionary = OpenMMOStorage.read_json(OpenMMOStorage.SETTINGS_FILE).get("roms", {})
	var path: String = str(roms.get("johto_follower_source", ""))
	if path.is_empty():
		return
	if not bool(content.set_follower_source(path).get("ok", false)):
		_clear_saved_follower_source()

func _save_follower_source_path(path: String) -> void:
	var settings: Dictionary = OpenMMOStorage.read_json(OpenMMOStorage.SETTINGS_FILE)
	var roms: Dictionary = settings.get("roms", {})
	roms["johto_follower_source"] = path
	settings["roms"] = roms
	OpenMMOStorage.write_json(OpenMMOStorage.SETTINGS_FILE, settings)

func _clear_saved_follower_source() -> void:
	var settings: Dictionary = OpenMMOStorage.read_json(OpenMMOStorage.SETTINGS_FILE)
	var roms: Dictionary = settings.get("roms", {})
	roms.erase("johto_follower_source")
	settings["roms"] = roms
	OpenMMOStorage.write_json(OpenMMOStorage.SETTINGS_FILE, settings)

func _clear_saved_rom() -> void:
	_clear_saved_rom_key("kanto")
	_clear_saved_rom_key("hoenn")

func _clear_saved_rom_key(key: String) -> void:
	var settings: Dictionary = OpenMMOStorage.read_json(OpenMMOStorage.SETTINGS_FILE)
	var roms: Dictionary = settings.get("roms", {})
	roms.erase(key)
	settings["roms"] = roms
	OpenMMOStorage.write_json(OpenMMOStorage.SETTINGS_FILE, settings)

func _choose_web() -> void:
	_web_callback = JavaScriptBridge.create_callback(_on_web_file)
	var window := JavaScriptBridge.get_interface("window")
	window.openmmogo_content_callback = _web_callback
	JavaScriptBridge.eval("""
(function() {
  const input = document.createElement('input');
  input.type = 'file';
	input.accept = '.gba,application/octet-stream';
  input.onchange = function() {
    const file = input.files && input.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = function() {
      const bytes = new Uint8Array(reader.result);
      let binary = '';
      const chunk = 0x8000;
      for (let i = 0; i < bytes.length; i += chunk) binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
      window.openmmogo_content_callback(file.name, btoa(binary));
    };
    reader.onerror = function() { window.openmmogo_content_callback('', ''); };
    reader.readAsArrayBuffer(file);
  };
  input.click();
})();
""")

func _on_web_file(args: Array) -> void:
	if args.size() < 2 or str(args[0]).is_empty() or str(args[1]).is_empty():
		content_failed.emit("no ROM was selected")
		return
	var filename: String = str(args[0])
	var extension: String = filename.get_extension().to_lower()
	if extension != "gba":
		content_failed.emit("unsupported file; select a .gba ROM")
		return
	var data: PackedByteArray = Marshalls.base64_to_raw(str(args[1]))
	var path: String = OpenMMOStorage.session_rom_path()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		content_failed.emit("could not store the selected content locally")
		return
	file.store_buffer(data)
	file.close()
	_on_rom_selected(path)
