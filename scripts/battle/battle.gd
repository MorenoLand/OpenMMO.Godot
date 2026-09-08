extends Control

signal exit_requested

var log_view: RichTextLabel
var state_label: Label
var action_box: VBoxContainer
var player_party_box: VBoxContainer
var opponent_party_box: VBoxContainer
var stage_root: Control
var flash_overlay: ColorRect
var close_button: Button
var opponent_name_label: Label
var opponent_level_label: Label
var opponent_hp_bar: ProgressBar
var opponent_hp_label: Label
var player_name_label: Label
var player_level_label: Label
var player_hp_bar: ProgressBar
var player_hp_label: Label
var player_xp_bar: ProgressBar
var opponent_sprite: TextureRect
var player_sprite: TextureRect
var effects_layer: Control
var party_status_box: HBoxContainer
var hp_tweens: Dictionary = {}
var move_hp_tweens: Array[Tween] = []
var move_tween: Tween
var move_animation_active: bool = false
var move_effects_pending: int = 0
var hp_tween_delay: float = 0.0
var battle_event_queue: Array[Dictionary] = []
var battle_event_busy: bool = false
var send_out_tweens: Array[Tween] = []
var release_glow_texture: Texture2D
var state: Dictionary = {}
var selection_mode: String = ""
var selection_index: int = 0
var selection_grid_columns: int = 2
var selection_buttons: Array[Button] = []
var input_locked: bool = true

func _ready() -> void:
	set_process_input(true)
	if not GameState.battle_event_received.is_connected(_on_battle_event):
		GameState.battle_event_received.connect(_on_battle_event)
	_build_ui()
	state = GameState.battle_state.duplicate(true)
	_render_state()
	_trigger_flash()

func _exit_tree() -> void:
	if GameState.battle_event_received.is_connected(_on_battle_event):
		GameState.battle_event_received.disconnect(_on_battle_event)
	battle_event_queue.clear()
	if move_tween != null:
		move_tween.kill()

func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var world_tint := ColorRect.new()
	world_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world_tint.color = Color(0.01, 0.025, 0.035, 0.64)
	world_tint.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(world_tint)
	var stage := Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(stage)
	var field := Panel.new()
	field.anchor_left = 0.055
	field.anchor_top = 0.09
	field.anchor_right = 0.945
	field.anchor_bottom = 0.94
	field.clip_contents = true
	field.mouse_filter = Control.MOUSE_FILTER_STOP
	field.add_theme_stylebox_override("panel", _panel_style(Color("071015"), Color("071015"), 0, 0))
	stage.add_child(field)
	stage_root = field
	var backdrop := TextureRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.texture = _make_battle_backdrop()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_root.add_child(backdrop)
	var field_shade := ColorRect.new()
	field_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	field_shade.color = Color(0.02, 0.035, 0.025, 0.06)
	field_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_root.add_child(field_shade)
	state_label = Label.new()
	state_label.visible = false
	stage_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_root.add_child(state_label)
	var opponent_card := _make_mon_card(true)
	opponent_card.anchor_left = 0.03
	opponent_card.anchor_top = 0.07
	opponent_card.anchor_right = 0.41
	opponent_card.anchor_bottom = 0.26
	stage_root.add_child(opponent_card)
	var player_card := _make_mon_card(false)
	player_card.anchor_left = 0.56
	player_card.anchor_top = 0.55
	player_card.anchor_right = 0.97
	player_card.anchor_bottom = 0.78
	stage_root.add_child(player_card)
	party_status_box = HBoxContainer.new()
	party_status_box.anchor_left = 0.78
	party_status_box.anchor_top = 0.79
	party_status_box.anchor_right = 0.97
	party_status_box.anchor_bottom = 0.86
	party_status_box.alignment = BoxContainer.ALIGNMENT_END
	party_status_box.add_theme_constant_override("separation", 3)
	party_status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	party_status_box.z_index = 4
	for _index in 6:
		var indicator := Label.new()
		indicator.text = "○"
		indicator.add_theme_font_size_override("font_size", 16)
		indicator.add_theme_color_override("font_color", Color("d4d9d4"))
		party_status_box.add_child(indicator)
	stage_root.add_child(party_status_box)
	opponent_sprite = _make_sprite()
	opponent_sprite.anchor_left = 0.58
	opponent_sprite.anchor_top = 0.20
	opponent_sprite.anchor_right = 0.96
	opponent_sprite.anchor_bottom = 0.60
	opponent_sprite.pivot_offset = Vector2(130.0, 100.0)
	opponent_sprite.z_index = 1
	stage_root.add_child(opponent_sprite)
	player_sprite = _make_sprite()
	player_sprite.anchor_left = 0.12
	player_sprite.anchor_top = 0.50
	player_sprite.anchor_right = 0.48
	player_sprite.anchor_bottom = 0.92
	player_sprite.pivot_offset = Vector2(150.0, 110.0)
	player_sprite.z_index = 1
	stage_root.add_child(player_sprite)
	effects_layer = Control.new()
	effects_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	effects_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effects_layer.z_index = 2
	stage_root.add_child(effects_layer)
	var log_panel := PanelContainer.new()
	log_panel.anchor_left = 0.0
	log_panel.anchor_top = 0.70
	log_panel.anchor_right = 1.0
	log_panel.anchor_bottom = 1.0
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_panel.z_index = 2
	log_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.055, 0.04, 0.78), Color(0.0, 0.0, 0.0, 0.0), 0, 0))
	stage_root.add_child(log_panel)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = false
	log_view.fit_content = false
	log_view.scroll_active = true
	log_view.scroll_following = true
	log_view.custom_minimum_size = Vector2(0.0, 88.0)
	log_view.add_theme_font_size_override("normal_font_size", 16)
	log_panel.add_child(log_view)
	log_view.scroll_following = true
	var action_panel := PanelContainer.new()
	action_panel.anchor_left = 0.55
	action_panel.anchor_top = 0.70
	action_panel.anchor_right = 0.99
	action_panel.anchor_bottom = 0.985
	action_panel.z_index = 3
	action_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), 0, 0))
	stage_root.add_child(action_panel)
	action_box = VBoxContainer.new()
	action_box.add_theme_constant_override("separation", 4)
	action_panel.add_child(action_box)
	close_button = _make_button("Return to world")
	close_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_button.offset_left = -184.0
	close_button.offset_top = 12.0
	close_button.offset_right = -12.0
	close_button.offset_bottom = 46.0
	close_button.pressed.connect(_return_to_world)
	close_button.disabled = true
	close_button.visible = false
	stage_root.add_child(close_button)
	flash_overlay = ColorRect.new()
	flash_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_overlay.color = Color(1.0, 1.0, 1.0, 0.0)
	flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_overlay.z_index = 20
	add_child(flash_overlay)

func _make_battle_backdrop() -> Texture2D:
	var width: int = 320
	var height: int = 180
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in range(78):
		var amount: float = float(y) / 77.0
		image.fill_rect(Rect2i(0, y, width, 1), Color("31bcea").lerp(Color("b9e9df"), amount))
	image.fill_rect(Rect2i(0, 78, width, 12), Color("6dbd6b"))
	for x in range(-8, width + 16, 16):
		_paint_ellipse(image, Vector2i(x + 8, 78 + int(x / 16) % 3), Vector2i(13, 11), Color("346b51"))
		_paint_ellipse(image, Vector2i(x + 8, 73 + int(x / 16) % 2), Vector2i(9, 10), Color("4d8760"))
	for y in range(90, height):
		var amount: float = float(y - 90) / float(height - 90)
		image.fill_rect(Rect2i(0, y, width, 1), Color("dce8ad").lerp(Color("769754"), amount))
	image.fill_rect(Rect2i(0, 88, width, 3), Color("4cae55"))
	_paint_ellipse(image, Vector2i(249, 102), Vector2i(62, 18), Color("174e2d"))
	_paint_ellipse(image, Vector2i(249, 99), Vector2i(58, 15), Color("278744"))
	_paint_ellipse(image, Vector2i(249, 98), Vector2i(47, 11), Color("5ec05b"))
	_paint_ellipse(image, Vector2i(249, 98), Vector2i(37, 8), Color("b5ad78"))
	_paint_ellipse(image, Vector2i(98, 177), Vector2i(96, 38), Color("133e27"))
	_paint_ellipse(image, Vector2i(98, 170), Vector2i(91, 32), Color("237c3b"))
	_paint_ellipse(image, Vector2i(98, 166), Vector2i(76, 26), Color("49af50"))
	_paint_ellipse(image, Vector2i(98, 164), Vector2i(59, 20), Color("a9a16e"))
	return ImageTexture.create_from_image(image)

func _paint_ellipse(image: Image, center: Vector2i, radii: Vector2i, color: Color) -> void:
	var left: int = maxi(0, center.x - radii.x)
	var top: int = maxi(0, center.y - radii.y)
	var right: int = mini(image.get_width() - 1, center.x + radii.x)
	var bottom: int = mini(image.get_height() - 1, center.y + radii.y)
	for y in range(top, bottom + 1):
		var normalized_y: float = float(y - center.y) / float(radii.y)
		for x in range(left, right + 1):
			var normalized_x: float = float(x - center.x) / float(radii.x)
			if normalized_x * normalized_x + normalized_y * normalized_y <= 1.0:
				image.set_pixel(x, y, color)

func _make_mon_card(opponent: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(Color(0.92, 0.94, 0.89, 0.94), Color("34454b"), 5, 2))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 7)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	margin.add_child(box)
	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color("26363b"))
	box.add_child(name_label)
	var level_label := Label.new()
	level_label.add_theme_font_size_override("font_size", 12)
	level_label.add_theme_color_override("font_color", Color("4c5d61"))
	box.add_child(level_label)
	var hp_bar := ProgressBar.new()
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(0.0, 12.0)
	hp_bar.add_theme_stylebox_override("background", _panel_style(Color("c2c9c1"), Color("57656a"), 4, 1))
	hp_bar.add_theme_stylebox_override("fill", _panel_style(Color("5ccf77") if not opponent else Color("e6bd5a"), Color("5ccf77") if not opponent else Color("e6bd5a"), 5, 0))
	box.add_child(hp_bar)
	var hp_label := Label.new()
	hp_label.add_theme_font_size_override("font_size", 11)
	hp_label.add_theme_color_override("font_color", Color("26363b"))
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(hp_label)
	if opponent:
		opponent_name_label = name_label
		opponent_level_label = level_label
		opponent_hp_bar = hp_bar
		opponent_hp_label = hp_label
	else:
		var xp_bar := ProgressBar.new()
		xp_bar.show_percentage = false
		xp_bar.custom_minimum_size = Vector2(0.0, 8.0)
		xp_bar.max_value = 1.0
		xp_bar.add_theme_stylebox_override("background", _panel_style(Color("c2c9c1"), Color("57656a"), 4, 1))
		xp_bar.add_theme_stylebox_override("fill", _panel_style(Color("3d8be0"), Color("3d8be0"), 4, 0))
		box.add_child(xp_bar)
		player_name_label = name_label
		player_level_label = level_label
		player_hp_bar = hp_bar
		player_hp_label = hp_label
		player_xp_bar = xp_bar
	return card

func _make_sprite() -> TextureRect:
	var sprite := TextureRect.new()
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sprite

func _panel_style(background: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style

func _make_button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("f2f4ed"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_color_override("font_pressed_color", Color("ffffff"))
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.12, 0.16, 0.18, 0.92), Color("73848a"), 3, 1))
	button.add_theme_stylebox_override("hover", _panel_style(Color(0.20, 0.26, 0.27, 0.96), Color("d3c25b"), 3, 2))
	button.add_theme_stylebox_override("focus", _panel_style(Color(0.20, 0.26, 0.27, 0.96), Color("d3c25b"), 3, 2))
	button.add_theme_stylebox_override("pressed", _panel_style(Color(0.27, 0.32, 0.31, 0.98), Color("eee1a0"), 3, 2))
	return button

func _return_to_world() -> void:
	if not bool(state.get("battle_complete", false)):
		return
	exit_requested.emit()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var key_code: Key = key_event.keycode
	var confirm_keys: Array[Key] = [KEY_A, KEY_F, KEY_E, KEY_Z, KEY_X, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]
	if bool(state.get("battle_complete", false)):
		if key_code in [KEY_ESCAPE, KEY_B, KEY_BACKSPACE] or key_code in confirm_keys:
			get_viewport().set_input_as_handled()
			_return_to_world()
		return
	if key_code in [KEY_ESCAPE, KEY_B, KEY_BACKSPACE]:
		if not selection_mode.is_empty() and not bool(state.get("force_switch", false)):
			get_viewport().set_input_as_handled()
			_cancel_selection()
		return
	if input_locked or not bool(state.get("can_act", false)):
		return
	if key_code in [KEY_LEFT]:
		get_viewport().set_input_as_handled()
		_move_selection_grid(-1, 0)
		return
	if key_code in [KEY_RIGHT, KEY_D]:
		get_viewport().set_input_as_handled()
		_move_selection_grid(1, 0)
		return
	if key_code in [KEY_UP, KEY_W]:
		get_viewport().set_input_as_handled()
		_move_selection_grid(0, -1)
		return
	if key_code in [KEY_DOWN, KEY_S]:
		get_viewport().set_input_as_handled()
		_move_selection_grid(0, 1)
		return
	if key_code in confirm_keys:
		get_viewport().set_input_as_handled()
		_activate_selection(selection_index)
		return
	if key_code >= KEY_1 and key_code <= KEY_4:
		get_viewport().set_input_as_handled()
		_activate_selection(int(key_code - KEY_1))

func _move_selection(delta: int) -> void:
	_move_selection_grid(delta, 0) if selection_grid_columns <= 1 else _move_selection_grid(0, delta)

func _move_selection_grid(dx: int, dy: int) -> void:
	var count: int = selection_buttons.size()
	if count == 0:
		return
	var cols: int = maxi(selection_grid_columns, 1)
	var rows: int = int((count + cols - 1) / cols)
	var index: int = clampi(selection_index, 0, count - 1)
	for _step in count:
		var row: int = int(index / cols)
		var col: int = index % cols
		if dx != 0:
			col = wrapi(col + dx, 0, cols)
			index = mini(row * cols + col, count - 1)
		else:
			row = wrapi(row + dy, 0, rows)
			index = mini(row * cols + col, count - 1)
		if not selection_buttons[index].disabled:
			selection_index = index
			selection_buttons[index].grab_focus()
			return

func _activate_selection(index: int) -> void:
	if index < 0 or index >= selection_buttons.size():
		return
	var button: Button = selection_buttons[index]
	if button.disabled:
		return
	button.pressed.emit()

func _register_selection_button(button: Button) -> void:
	button.focus_mode = Control.FOCUS_ALL
	var index: int = selection_buttons.size()
	selection_buttons.append(button)
	button.focus_entered.connect(_on_selection_focus_entered.bind(index))

func _on_selection_focus_entered(index: int) -> void:
	if index >= 0 and index < selection_buttons.size():
		selection_index = index

func _focus_selection() -> void:
	if selection_buttons.is_empty():
		return
	selection_index = clampi(selection_index, 0, selection_buttons.size() - 1)
	if selection_buttons[selection_index].disabled:
		_move_selection(1)
		return
	selection_buttons[selection_index].grab_focus()

func _waiting_for_name() -> String:
	var explicit_name: String = str(state.get("opponent_name", state.get("trainer_name", ""))).strip_edges()
	if not explicit_name.is_empty():
		return explicit_name
	if bool(state.get("trainer", false)):
		return "the opposing trainer"
	var party_value: Variant = state.get("opponent_party", [])
	var party: Array = party_value as Array if party_value is Array else []
	var opponent: Dictionary = _active_mon(party, int(state.get("opponent_active_slot", -1)))
	if not opponent.is_empty():
		return _battle_mon_name(opponent, true)
	return "the opponent"

func _waiting_text() -> String:
	return "Waiting for %s..." % _waiting_for_name()

func _render_state() -> void:
	if state.is_empty():
		state_label.text = "Waiting for server battle state..."
		_render_actions()
		return
	var opponent_party: Array = state.get("opponent_party", []) if state.get("opponent_party", []) is Array else []
	var player_party: Array = state.get("player_party", []) if state.get("player_party", []) is Array else []
	var opponent: Dictionary = _active_mon(opponent_party, int(state.get("opponent_active_slot", -1)))
	var player: Dictionary = _active_mon(player_party, int(state.get("active_slot", -1)))
	var opponent_name: String = _battle_mon_name(opponent, true)
	var player_name: String = _battle_mon_name(player, false)
	var phase: String = "Complete" if bool(state.get("battle_complete", false)) else "Active"
	var prompt: String = "Choose an action" if bool(state.get("can_act", false)) and not input_locked else _waiting_text()
	state_label.text = "%s  |  %s vs %s  |  %s" % [phase, opponent_name, player_name, prompt]
	_update_mon_card(opponent_name_label, opponent_level_label, opponent_hp_bar, opponent_hp_label, opponent, "opponent")
	_update_mon_card(player_name_label, player_level_label, player_hp_bar, player_hp_label, player, "player", player_xp_bar)
	_update_sprite(opponent_sprite, opponent, false)
	_update_sprite(player_sprite, player, true)
	_update_party_status(player_party)
	var battle_complete: bool = bool(state.get("battle_complete", false))
	close_button.disabled = not battle_complete
	close_button.visible = battle_complete
	_render_actions()

func _active_mon(party: Array, active_slot: int) -> Dictionary:
	for mon_value in party:
		if mon_value is Dictionary and int((mon_value as Dictionary).get("slot", -1)) == active_slot:
			return mon_value as Dictionary
	if active_slot >= 0 and active_slot < party.size() and party[active_slot] is Dictionary:
		return party[active_slot] as Dictionary
	return {}

func _update_mon_card(name_label: Label, level_label: Label, hp_bar: ProgressBar, hp_label: Label, mon: Dictionary, tween_key: String, xp_bar: ProgressBar = null) -> void:
	var level: int = int(mon.get("level", 0))
	level_label.text = "Lv %d" % level if level > 0 else ""
	var current_hp: int = int(mon.get("current_hp", mon.get("hp", 0)))
	var max_hp: int = int(mon.get("max_hp", mon.get("hp_max", 0)))
	if max_hp <= 0:
		max_hp = maxi(current_hp, 1)
	hp_bar.max_value = max_hp
	var target_hp: float = clampf(float(current_hp), 0.0, float(max_hp))
	var fill_color: Color = Color("d94c5a") if target_hp * 5.0 <= max_hp else Color("e6bd5a") if target_hp * 2.0 <= max_hp else Color("5ccf77")
	hp_bar.add_theme_stylebox_override("fill", _panel_style(fill_color, fill_color, 5, 0))
	if not bool(hp_bar.get_meta("initialized", false)):
		hp_bar.value = target_hp
		hp_bar.set_meta("initialized", true)
		hp_bar.set_meta("target_hp", target_hp)
	else:
		var previous_target: float = float(hp_bar.get_meta("target_hp", hp_bar.value))
		if not is_equal_approx(previous_target, target_hp):
			var previous_tween: Tween = hp_tweens.get(tween_key) as Tween
			if previous_tween != null:
				previous_tween.kill()
			hp_bar.set_meta("target_hp", target_hp)
			var tween: Tween = create_tween()
			hp_tweens[tween_key] = tween
			if move_animation_active:
				move_hp_tweens.append(tween)
				tween.finished.connect(_on_move_hp_tween_finished.bind(tween))
			if hp_tween_delay > 0.0:
				tween.tween_interval(hp_tween_delay)
			tween.tween_method(_set_hp_display.bind(hp_bar, hp_label, max_hp), float(hp_bar.value), target_hp, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		elif absf(float(hp_bar.value) - target_hp) <= 0.1:
			hp_bar.value = target_hp
	_set_hp_display(float(hp_bar.value), hp_bar, hp_label, max_hp)
	name_label.text = _battle_mon_name(mon, name_label == opponent_name_label)
	if xp_bar == null:
		return
	var species_id: int = int(mon.get("species", mon.get("species_id", mon.get("dex_id", 0))))
	var xp: int = int(mon.get("xp", mon.get("experience_points", -1)))
	var progress: Dictionary = GameState.content.battle_exp_progress(species_id, level, xp) if GameState.content != null and xp >= 0 and species_id > 0 else {}
	var ratio: float = float(progress.get("ratio", 0.0)) if bool(progress.get("ok", false)) else 0.0
	xp_bar.tooltip_text = "%d XP to next level" % int(progress.get("remaining", 0)) if bool(progress.get("ok", false)) and level < 100 else "Level 100"
	if not bool(xp_bar.get_meta("initialized", false)):
		xp_bar.value = ratio
		xp_bar.set_meta("initialized", true)
		xp_bar.set_meta("target_xp", ratio)
	else:
		var previous_ratio: float = float(xp_bar.get_meta("target_xp", xp_bar.value))
		if not is_equal_approx(previous_ratio, ratio):
			var previous_tween: Tween = hp_tweens.get("player_xp") as Tween
			if previous_tween != null:
				previous_tween.kill()
			xp_bar.set_meta("target_xp", ratio)
			var xp_tween: Tween = create_tween()
			hp_tweens["player_xp"] = xp_tween
			xp_tween.tween_property(xp_bar, "value", ratio, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			xp_bar.value = ratio

func _set_hp_display(value: float, hp_bar: ProgressBar, hp_label: Label, max_hp: int) -> void:
	var shown_hp: int = clampi(roundi(value), 0, max_hp)
	hp_bar.value = value
	hp_label.text = "%d / %d HP" % [shown_hp, max_hp]

func _on_move_hp_tween_finished(tween: Tween) -> void:
	move_hp_tweens.erase(tween)
	_try_finish_move_sequence()

func _update_sprite(sprite: TextureRect, mon: Dictionary, back: bool) -> void:
	var species_id: int = int(mon.get("species", mon.get("species_id", mon.get("dex_id", 0))))
	var previous_texture: Texture2D = sprite.texture
	sprite.texture = null
	if GameState.content == null or species_id <= 0:
		return
	var result: Dictionary = GameState.content.battle_pokemon_sprite(species_id, back)
	if bool(result.get("ok", false)):
		sprite.texture = result.get("texture") as Texture2D
	if previous_texture != sprite.texture:
		sprite.modulate = Color.WHITE

func _update_party_status(party: Array) -> void:
	if party_status_box == null:
		return
	for index in party_status_box.get_child_count():
		var indicator: Label = party_status_box.get_child(index) as Label
		if indicator == null:
			continue
		if index >= party.size() or not party[index] is Dictionary:
			indicator.text = "○"
			indicator.add_theme_color_override("font_color", Color("aab3ac"))
			continue
		var mon: Dictionary = party[index]
		var current_hp: int = int(mon.get("current_hp", mon.get("hp", 0)))
		indicator.text = "●" if current_hp > 0 else "×"
		indicator.add_theme_color_override("font_color", Color("d6c35c") if current_hp > 0 else Color("78817c"))

func _render_party(container: VBoxContainer, party_value: Variant, active_slot: int, opponent: bool) -> void:
	for child in container.get_children():
		child.queue_free()
	var heading := Label.new()
	heading.text = str(state.get("opponent_name", "Opponent") if opponent else state.get("player_name", "Player"))
	heading.add_theme_font_size_override("font_size", 20)
	container.add_child(heading)
	if not party_value is Array or (party_value as Array).is_empty():
		var empty_label := Label.new()
		empty_label.text = "No party data"
		container.add_child(empty_label)
		return
	for mon_value in party_value as Array:
		if not mon_value is Dictionary:
			continue
		var mon: Dictionary = mon_value
		var line := VBoxContainer.new()
		var label := Label.new()
		var slot: int = int(mon.get("slot", -1))
		var marker: String = "ACTIVE " if slot == active_slot else ""
		var fainted: bool = int(mon.get("current_hp", 0)) <= 0 or bool(mon.get("faint", false))
		var status: String = "FAINTED" if fainted else "Lv %d" % int(mon.get("level", 0))
		label.text = "%s%s  %s" % [marker, _battle_mon_name(mon, opponent), status]
		line.add_child(label)
		var hp := ProgressBar.new()
		hp.max_value = maxi(1, int(mon.get("max_hp", 0)))
		hp.value = clampi(int(mon.get("current_hp", 0)), 0, int(hp.max_value))
		hp.show_percentage = false
		hp.custom_minimum_size = Vector2(0, 12)
		line.add_child(hp)
		container.add_child(line)

func _battle_mon_name(mon: Dictionary, opponent: bool) -> String:
	var nickname_value: Variant = mon.get("nickname", "")
	var resolved_name: String = str(nickname_value).strip_edges() if nickname_value != null else ""
	if resolved_name.is_empty():
		resolved_name = str(mon.get("name", "")).strip_edges()
	if not resolved_name.is_empty():
		return resolved_name
	var resolved_species: int = int(mon.get("species", mon.get("species_id", mon.get("dex_id", 0))))
	if resolved_species > 0 and GameState.content != null:
		return GameState.content.battle_pokemon_name(resolved_species)
	if resolved_species > 0:
		return "POKEMON #%d" % resolved_species
	return "Wild Pokemon" if opponent else "Pokemon"

func _render_actions() -> void:
	if action_box == null:
		return
	selection_buttons.clear()
	selection_index = 0
	for child in action_box.get_children():
		child.queue_free()
	if bool(state.get("battle_complete", false)):
		var complete := Label.new()
		complete.text = "Battle complete."
		action_box.add_child(complete)
		return
	if input_locked or not bool(state.get("can_act", false)):
		var waiting := Label.new()
		waiting.text = _waiting_text()
		action_box.add_child(waiting)
		return
	if bool(state.get("force_switch", false)):
		selection_mode = "pokemon"
	if selection_mode == "fight":
		_render_move_selection()
	elif selection_mode == "pokemon":
		_render_pokemon_selection()
	elif selection_mode == "bag":
		_render_bag_selection()
	else:
		var buttons := GridContainer.new()
		buttons.columns = 2
		for entry in [["FIGHT", "Select your attack move.", "fight"], ["BAG", "Use an item.", "bag"], ["POKéMON", "Switch current Pokémon.", "pokemon"], ["RUN", "Escape from battle.", "run"]]:
			var button := _make_button("%s\n%s" % [str(entry[0]), str(entry[1])])
			button.custom_minimum_size = Vector2(178, 48)
			if str(entry[2]) == "fight":
				button.pressed.connect(_choose_fight)
			elif str(entry[2]) == "bag":
				button.pressed.connect(_choose_bag)
			elif str(entry[2]) == "pokemon":
				button.pressed.connect(_choose_pokemon)
			elif str(entry[2]) == "run":
				button.pressed.connect(_send_run)
			_register_selection_button(button)
			buttons.add_child(button)
		action_box.add_child(buttons)
		_focus_selection()

func _choose_fight() -> void:
	selection_mode = "fight"
	selection_index = 0
	_render_actions()

func _choose_bag() -> void:
	selection_mode = "bag"
	selection_index = 0
	_render_actions()

func _choose_pokemon() -> void:
	selection_mode = "pokemon"
	selection_index = 0
	_render_actions()

func _render_move_selection() -> void:
	var moves: Array = _active_moves()
	if moves.is_empty():
		var empty := Label.new()
		empty.text = "No revealed moves are available."
		action_box.add_child(empty)
		_add_cancel_button()
		return
	var grid := GridContainer.new()
	grid.columns = 2
	for move_value in moves:
		var move: Dictionary = move_value if move_value is Dictionary else {"id": int(move_value), "pp": -1}
		var move_id: int = int(move.get("id", 0))
		if move_id <= 0:
			continue
		var button := _make_button("")
		var move_info: Dictionary = GameState.content.battle_move_info(move_id) if GameState.content != null else {}
		var move_name: String = str(move_info.get("name", GameState.content.battle_move_name(move_id) if GameState.content != null else "MOVE %d" % move_id))
		var move_type: String = str(move_info.get("type_name", ""))
		var max_pp: int = int(move_info.get("pp", 0))
		var current_pp: int = int(move.get("pp", -1))
		if current_pp < 0:
			current_pp = max_pp
		var type_line: String = move_type if not move_type.is_empty() and move_type != "Unknown" else "Move"
		button.text = "%s\n%s    PP %d/%d" % [move_name, type_line, current_pp, max_pp]
		button.tooltip_text = "Type: %s | Power: %d | Accuracy: %d" % [type_line, int(move_info.get("power", 0)), int(move_info.get("accuracy", 0))]
		button.custom_minimum_size = Vector2(140, 44)
		button.disabled = max_pp > 0 and current_pp <= 0
		button.pressed.connect(_send_move.bind(move_id))
		_register_selection_button(button)
		grid.add_child(button)
	action_box.add_child(grid)
	_add_cancel_button()

func _render_pokemon_selection() -> void:
	var party_value: Variant = state.get("player_party", [])
	var grid := GridContainer.new()
	grid.columns = 2
	if party_value is Array:
		for mon_value in party_value as Array:
			if not mon_value is Dictionary:
				continue
			var mon: Dictionary = mon_value
			var slot: int = int(mon.get("slot", -1))
			if slot < 0 or slot == int(state.get("active_slot", -1)) or int(mon.get("current_hp", 0)) <= 0:
				continue
			var button := _make_button("")
			var current_hp: int = int(mon.get("current_hp", mon.get("hp", 0)))
			var max_hp: int = int(mon.get("max_hp", mon.get("hp_max", 0)))
			if max_hp <= 0:
				max_hp = maxi(current_hp, 1)
			button.text = "%s\nLv %d  %d / %d HP" % [_battle_mon_name(mon, false), int(mon.get("level", 0)), current_hp, max_hp]
			var species_id: int = int(mon.get("species", mon.get("species_id", mon.get("dex_id", 0))))
			if GameState.content != null and species_id > 0:
				var sprite: Dictionary = GameState.content.battle_pokemon_sprite(species_id, false)
				button.icon = sprite.get("texture") as Texture2D
			button.custom_minimum_size = Vector2(140, 50)
			button.pressed.connect(_send_switch.bind(slot))
			_register_selection_button(button)
			grid.add_child(button)
	if grid.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "No available Pokémon to switch to."
		action_box.add_child(empty)
	else:
		action_box.add_child(grid)
	if not bool(state.get("force_switch", false)):
		_add_cancel_button()
	else:
		_focus_selection()

func _render_bag_selection() -> void:
	var items: Array = _battle_bag()
	if items.is_empty():
		var empty := Label.new()
		empty.text = "Bag is empty."
		action_box.add_child(empty)
		_add_cancel_button()
		return
	var grid := GridContainer.new()
	grid.columns = 2
	for item_value in items:
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		var item_id: int = _battle_item_id(item)
		if item_id <= 0:
			continue
		var quantity: int = maxi(0, int(item.get("quantity", item.get("count", 1))))
		if quantity <= 0:
			continue
		var item_name: String = _battle_item_name(item, item_id)
		var button := _make_button("%s\nx%d" % [item_name, quantity])
		button.custom_minimum_size = Vector2(140, 48)
		button.pressed.connect(_send_item.bind(item_id, item_name))
		_register_selection_button(button)
		grid.add_child(button)
	if grid.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "Bag is empty."
		action_box.add_child(empty)
	else:
		action_box.add_child(grid)
	_add_cancel_button()

func _battle_bag() -> Array:
	var value: Variant = state.get("bag", null)
	if not value is Array and GameState.current_character.get("bag", []) is Array:
		value = GameState.current_character.get("bag", [])
	var items: Array = []
	if value is Array:
		items = (value as Array).duplicate(true)
	elif value is Dictionary:
		for group_value in (value as Dictionary).values():
			if group_value is Array:
				items.append_array(group_value as Array)
	return items

func _battle_item_id(item: Dictionary) -> int:
	return GameState.content.battle_item_id(item) if GameState.content != null else int(item.get("item_id", item.get("id", item.get("front_sprite_id", item.get("internal_id", 0)))))

func _battle_item_name(item: Dictionary, item_id: int) -> String:
	var item_name: String = str(item.get("name", item.get("item_name", ""))).strip_edges()
	if (item_name.is_empty() or item_name.to_lower() == "item") and item_id > 0 and GameState.content != null:
		var info: Dictionary = GameState.content.battle_item_info(item_id)
		item_name = str(info.get("name", "")).strip_edges()
	if item_name.is_empty() or item_name.to_lower() == "item":
		item_name = "Item #%d" % item_id
	return item_name

func _add_cancel_button() -> void:
	var cancel := _make_button("Back")
	cancel.pressed.connect(_cancel_selection)
	_register_selection_button(cancel)
	action_box.add_child(cancel)
	_focus_selection()

func _cancel_selection() -> void:
	selection_mode = ""
	selection_index = 0
	_render_actions()

func _active_moves() -> Array:
	var party_value: Variant = state.get("player_party", [])
	if not party_value is Array:
		return []
	var active_slot: int = int(state.get("active_slot", -1))
	for mon_value in party_value as Array:
		if mon_value is Dictionary and int((mon_value as Dictionary).get("slot", -1)) == active_slot:
			var mon: Dictionary = mon_value
			var moves_value: Variant = mon.get("moves", [])
			if moves_value is Array and not (moves_value as Array).is_empty():
				return (moves_value as Array).duplicate(true)
			var ids: Array = mon.get("move_ids", []) if mon.get("move_ids", []) is Array else []
			var pp: Array = mon.get("move_pp", []) if mon.get("move_pp", []) is Array else []
			var moves: Array = []
			for index in ids.size():
				moves.append({"id": int(ids[index]), "pp": int(pp[index]) if index < pp.size() else -1})
			return moves
	return []

func _send_move(move_id: int) -> void:
	_send_battle_action(0, move_id, GameState.content.battle_move_name(move_id) if GameState.content != null else "MOVE #%d" % move_id)

func _send_switch(slot: int) -> void:
	_send_battle_action(2, slot, "Switch to slot %d" % slot)

func _send_run() -> void:
	_send_battle_action(3, 0, "Run")

func _send_item(item_id: int, item_name: String) -> void:
	var player_party: Variant = state.get("player_party", [])
	var active_slot: int = int(state.get("active_slot", -1))
	var active: Dictionary = _active_mon(player_party as Array, active_slot) if player_party is Array else {}
	_send_battle_action(1, item_id, "Use %s" % item_name, int(active.get("entity_id", 0)))

func _send_battle_action(action: int, value: int, label: String, target_entity_id: int = 0) -> void:
	if input_locked or not bool(state.get("can_act", false)):
		return
	if GameState.send_battle_action(action, value, target_entity_id):
		input_locked = true
		selection_mode = ""
		_append_log("Sent: %s" % label)
		_render_actions()
	else:
		_append_log("Could not send: %s" % label)

func _append_log(message: String) -> void:
	if log_view == null:
		return
	log_view.append_text(message + "\n")
	log_view.scroll_following = true
	call_deferred("_scroll_log_to_bottom")

func _scroll_log_to_bottom() -> void:
	if log_view == null:
		return
	await get_tree().process_frame
	if log_view == null:
		return
	log_view.scroll_following = true
	var bar: VScrollBar = log_view.get_v_scroll_bar()
	bar.value = bar.max_value
	var last_line: int = log_view.get_line_count() - 1
	if last_line >= 0:
		log_view.scroll_to_line(last_line)

func _trigger_flash(color: Color = Color(1.0, 1.0, 1.0, 0.82)) -> void:
	if flash_overlay == null:
		return
	flash_overlay.visible = true
	flash_overlay.color = color
	var tween := create_tween()
	tween.tween_property(flash_overlay, "color", Color(color.r, color.g, color.b, 0.0), 0.22)
	tween.tween_callback(func() -> void:
		if flash_overlay != null:
			flash_overlay.visible = false
	)

func _sprite_for_entity(entity_id: int) -> TextureRect:
	if entity_id == 0:
		return null
	for party_key in ["player_party", "opponent_party"]:
		var party_value: Variant = state.get(party_key, [])
		if not party_value is Array:
			continue
		for mon_value in party_value as Array:
			if mon_value is Dictionary and int((mon_value as Dictionary).get("entity_id", 0)) == entity_id:
				return player_sprite if party_key == "player_party" else opponent_sprite
	return null

func _entity_in_party(entity_id: int, party_key: String) -> bool:
	if entity_id == 0:
		return false
	var party_value: Variant = state.get(party_key, [])
	if not party_value is Array:
		return false
	for mon_value in party_value as Array:
		if mon_value is Dictionary and int((mon_value as Dictionary).get("entity_id", 0)) == entity_id:
			return true
	return false

func _battle_entity_name(entity_id: int) -> String:
	for party_key in ["player_party", "opponent_party"]:
		var party_value: Variant = state.get(party_key, [])
		if not party_value is Array:
			continue
		for mon_value in party_value as Array:
			if mon_value is Dictionary and int((mon_value as Dictionary).get("entity_id", 0)) == entity_id:
				return _battle_mon_name(mon_value as Dictionary, party_key == "opponent_party")
	return "Pokemon"

func _animate_move(event: Dictionary, next_state: Dictionary) -> void:
	move_animation_active = true
	move_effects_pending = 0
	move_hp_tweens.clear()
	var source_entity: int = int(event.get("source_entity", 0))
	var attacker: TextureRect = _sprite_for_entity(source_entity)
	var target_entity: int = 0
	var targets: Variant = event.get("targets", [])
	if targets is Array:
		for target_value in targets as Array:
			if target_value is Dictionary:
				target_entity = int((target_value as Dictionary).get("entity_id", 0))
				if target_entity != 0:
					break
	var defender: TextureRect = _sprite_for_entity(target_entity)
	if attacker == null and defender != null:
		attacker = opponent_sprite if defender == player_sprite else player_sprite
	if attacker == null:
		attacker = player_sprite if _entity_in_party(source_entity, "player_party") else opponent_sprite
	if defender == null or defender == attacker:
		defender = opponent_sprite if attacker == player_sprite else player_sprite
	if attacker == null or defender == null:
		_finish_move_sequence.call_deferred()
		return
	attacker.modulate = Color.WHITE
	defender.modulate = Color.WHITE
	var base_position: Vector2 = attacker.position
	var direction: float = signf(defender.position.x - attacker.position.x)
	if is_zero_approx(direction):
		direction = 1.0 if attacker == player_sprite else -1.0
	var move_id: int = int(event.get("source_move", event.get("move_id", 0)))
	var move_info: Dictionary = GameState.content.battle_move_info(move_id) if GameState.content != null else {}
	if _is_attacker_motion_move(move_id, move_info):
		_animate_attacker_motion(attacker, base_position, direction, defender, next_state, event)
		return
	var contact: bool = (int(move_info.get("flags", 0)) & 1) != 0
	var damaging: bool = int(move_info.get("power", 0)) > 0
	var animation_plan: Dictionary = GameState.content.battle_move_animation_plan(move_id) if GameState.content != null else {"ok": false}
	var duration: float = float(animation_plan.get("duration_frames", 48)) / 60.0
	var hit_delay: float = float(animation_plan.get("hit_frame", 18)) / 60.0
	move_tween = create_tween()
	if contact:
		move_tween.tween_property(attacker, "position", base_position + Vector2(72.0 * direction, -4.0), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		move_tween.tween_interval(0.08)
	move_tween.tween_callback(_spawn_move_effect.bind(attacker, defender, animation_plan))
	move_tween.tween_interval(maxf(0.0, hit_delay))
	move_tween.tween_callback(_apply_move_hit_state.bind(next_state, event))
	if damaging:
		move_tween.tween_callback(_blink_sprite.bind(defender))
	move_tween.tween_interval(maxf(0.52, duration - hit_delay))
	if contact:
		move_tween.tween_property(attacker, "position", base_position, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	move_tween.tween_callback(_finish_move_animation.bind(attacker, base_position, defender, event))
	move_tween.tween_callback(_finish_move_sequence)

func _is_attacker_motion_move(move_id: int, move_info: Dictionary) -> bool:
	var normalized_name: String = str(move_info.get("name", "")).replace(" ", "").replace("_", "").to_upper()
	return move_id == 39 or normalized_name == "TAILWHIP"

func _animate_attacker_motion(attacker: TextureRect, base_position: Vector2, direction: float, defender: TextureRect, next_state: Dictionary, event: Dictionary) -> void:
	var offsets: Array[Vector2] = [Vector2(10.0 * direction, -3.0), Vector2(-8.0 * direction, -6.0), Vector2(-12.0 * direction, 1.0), Vector2(6.0 * direction, 5.0), Vector2(10.0 * direction, -3.0), Vector2(-8.0 * direction, -6.0), Vector2(-12.0 * direction, 1.0), Vector2(6.0 * direction, 5.0), Vector2.ZERO]
	move_tween = create_tween()
	for offset in offsets:
		move_tween.tween_property(attacker, "position", base_position + offset, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	move_tween.tween_callback(_apply_move_hit_state.bind(next_state, event))
	move_tween.tween_callback(_finish_move_animation.bind(attacker, base_position, defender, event))
	move_tween.tween_callback(_finish_move_sequence)

func _apply_move_hit_state(next_state: Dictionary, event: Dictionary) -> void:
	if not next_state.is_empty():
		state = next_state.duplicate(true)
	_apply_move_hp_events(event)
	hp_tween_delay = 0.0
	_render_state()

func _apply_move_hp_events(event: Dictionary) -> void:
	var source_entity: int = int(event.get("source_entity", 0))
	var targets: Variant = event.get("targets", [])
	if not targets is Array:
		return
	for target_value in targets as Array:
		if not target_value is Dictionary:
			continue
		var target: Dictionary = target_value
		var target_entity: int = int(target.get("entity_id", 0))
		for event_value in target.get("events", []):
			if not event_value is Dictionary or not (event_value as Dictionary).has("current_hp"):
				continue
			var current_hp: int = int((event_value as Dictionary).get("current_hp", 0))
			if not _set_battle_entity_hp(target_entity, current_hp):
				var target_party: String = "opponent_party" if _entity_in_party(source_entity, "player_party") else "player_party"
				_set_active_battle_hp(target_party, current_hp)

func _set_battle_entity_hp(entity_id: int, current_hp: int) -> bool:
	if entity_id == 0:
		return false
	for party_key in ["player_party", "opponent_party"]:
		var party_value: Variant = state.get(party_key, [])
		if not party_value is Array:
			continue
		var party: Array = (party_value as Array).duplicate(true)
		for index in range(party.size()):
			if not party[index] is Dictionary or int((party[index] as Dictionary).get("entity_id", 0)) != entity_id:
				continue
			var mon: Dictionary = (party[index] as Dictionary).duplicate(true)
			mon["current_hp"] = current_hp
			mon["faint"] = current_hp <= 0
			party[index] = mon
			state[party_key] = party
			return true
	return false

func _set_active_battle_hp(party_key: String, current_hp: int) -> void:
	var party_value: Variant = state.get(party_key, [])
	if not party_value is Array:
		return
	var active_key: String = "active_slot" if party_key == "player_party" else "opponent_active_slot"
	var active_slot: int = int(state.get(active_key, -1))
	var party: Array = (party_value as Array).duplicate(true)
	for index in range(party.size()):
		if not party[index] is Dictionary or int((party[index] as Dictionary).get("slot", -1)) != active_slot:
			continue
		var mon: Dictionary = (party[index] as Dictionary).duplicate(true)
		mon["current_hp"] = current_hp
		mon["faint"] = current_hp <= 0
		party[index] = mon
		state[party_key] = party
		return

func _blink_sprite(sprite: TextureRect) -> void:
	if sprite == null:
		return
	var tween: Tween = create_tween()
	tween.tween_property(sprite, "modulate", Color(1.0, 0.45, 0.45, 1.0), 0.05)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.08)

func _finish_move_animation(attacker: TextureRect, base_position: Vector2, defender: TextureRect, event: Dictionary) -> void:
	if attacker != null:
		attacker.position = base_position
	var targets: Variant = event.get("targets", [])
	if not targets is Array or defender == null:
		return
	for target_value in targets as Array:
		if not target_value is Dictionary:
			continue
		for event_value in (target_value as Dictionary).get("events", []):
			if event_value is Dictionary and bool((event_value as Dictionary).get("faint", false)):
				var fade: Tween = create_tween()
				fade.tween_property(defender, "modulate", Color(1.0, 1.0, 1.0, 0.25), 0.28)
				fade.parallel().tween_property(defender, "position", defender.position + Vector2(0.0, 18.0), 0.28)
				return

func _spawn_move_effect(attacker: TextureRect, target: TextureRect, plan: Dictionary) -> void:
	if attacker == null or target == null or effects_layer == null or not bool(plan.get("ok", false)) or GameState.content == null:
		return
	for spawn_value in plan.get("spawns", []):
		if not spawn_value is Dictionary:
			continue
		var spawn: Dictionary = spawn_value
		var sheet: Dictionary = GameState.content.battle_animation_sheet(int(spawn.get("tag", 0)))
		if not bool(sheet.get("ok", false)):
			continue
		move_effects_pending += 1
		var delay: float = float(spawn.get("delay", 0)) / 60.0
		var tween: Tween = create_tween()
		if delay > 0.0:
			tween.tween_interval(delay)
		tween.tween_callback(_create_battle_effect.bind(attacker, target, spawn, sheet))

func _create_battle_effect(attacker: TextureRect, target: TextureRect, spawn: Dictionary, sheet: Dictionary) -> void:
	if effects_layer == null:
		_finish_battle_effect(null)
		return
	var frames: Array = sheet.get("frames", [])
	if frames.is_empty():
		_finish_battle_effect(null)
		return
	var effect := TextureRect.new()
	effect.texture = frames[0] as Texture2D
	effect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	effect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	effect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var display_scale: float = 2.4
	effect.size = Vector2(float(sheet.get("width", 16)), float(sheet.get("height", 16))) * display_scale
	effect.pivot_offset = effect.size * 0.5
	effects_layer.add_child(effect)
	var attacker_center: Vector2 = attacker.position + attacker.size * 0.5
	var target_center: Vector2 = target.position + target.size * 0.5
	var offset: Vector2 = (spawn.get("offset", Vector2.ZERO) as Vector2) * display_scale
	var kind: String = str(spawn.get("kind", "impact"))
	var destination: Vector2 = target_center + offset - effect.size * 0.5
	var lifetime: float = maxf(0.24, float(frames.size()) * 0.06)
	if kind == "aura":
		destination = attacker_center + offset - effect.size * 0.5
	elif kind == "rain":
		destination.y -= 48.0
	effect.position = attacker_center - effect.size * 0.5 if kind == "travel" else destination
	var frame_tween: Tween = create_tween()
	frame_tween.tween_method(_set_effect_frame.bind(effect, frames), 0.0, float(frames.size()), lifetime)
	var motion: Tween = create_tween()
	if kind == "travel":
		motion.tween_property(effect, "position", destination, lifetime * 0.72).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	elif kind == "rain":
		motion.tween_property(effect, "position", destination + Vector2(0.0, 72.0), lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	elif kind == "aura":
		motion.tween_property(effect, "position", destination + Vector2(0.0, -42.0), lifetime).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		effect.scale = Vector2(0.65, 0.65)
		motion.tween_property(effect, "scale", Vector2(1.2, 1.2), lifetime * 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	motion.parallel().tween_property(effect, "modulate", Color(1.0, 1.0, 1.0, 0.0), lifetime).set_delay(lifetime * 0.55)
	motion.tween_callback(_finish_battle_effect.bind(effect))

func _finish_battle_effect(effect: TextureRect) -> void:
	if effect != null and is_instance_valid(effect):
		effect.queue_free()
	move_effects_pending = maxi(0, move_effects_pending - 1)
	_try_finish_move_sequence()

func _set_effect_frame(value: float, effect: TextureRect, frames: Array) -> void:
	if effect == null or not is_instance_valid(effect) or frames.is_empty():
		return
	var index: int = clampi(floori(value), 0, frames.size() - 1)
	effect.texture = frames[index] as Texture2D

func _reset_battle_sprite_visuals() -> void:
	if move_tween != null:
		move_tween.kill()
		move_tween = null
	if player_sprite != null:
		player_sprite.modulate = Color.WHITE
		player_sprite.scale = Vector2.ONE
		player_sprite.visible = true
	if opponent_sprite != null:
		opponent_sprite.modulate = Color.WHITE
		opponent_sprite.scale = Vector2.ONE
		opponent_sprite.visible = true
	for tween in send_out_tweens:
		if tween != null:
			tween.kill()
	send_out_tweens.clear()

func _animate_send_out(event: Dictionary) -> void:
	var side: int = int(event.get("side", 0))
	var sprite: TextureRect = player_sprite if side == 0 else opponent_sprite
	if sprite == null or sprite.texture == null or effects_layer == null:
		_finish_move_event.call_deferred()
		return
	var ball_result: Dictionary = GameState.content.battle_pokeball_frames(0) if GameState.content != null else {}
	var frames: Array = ball_result.get("frames", []) if bool(ball_result.get("ok", false)) else []
	var ball := TextureRect.new()
	ball.texture = frames[0] as Texture2D if not frames.is_empty() else null
	ball.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ball.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ball.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ball.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ball.size = Vector2(48.0, 48.0)
	ball.pivot_offset = ball.size * 0.5
	effects_layer.add_child(ball)
	var target: Vector2 = sprite.position + sprite.size * 0.5
	var start: Vector2 = Vector2(stage_root.size.x * (0.05 if side == 0 else 0.95), stage_root.size.y * (0.77 if side == 0 else 0.27))
	sprite.visible = false
	sprite.scale = Vector2(0.08, 0.08)
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tween: Tween = create_tween()
	send_out_tweens.append(tween)
	tween.tween_method(_set_ball_arc.bind(ball, start, target, frames, side), 0.0, 1.0, 0.42).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(_release_battler.bind(sprite, ball, target, frames))
	tween.tween_interval(0.38)
	tween.tween_callback(_finish_send_out.bind(sprite, ball, tween))

func _set_ball_arc(value: float, ball: TextureRect, start: Vector2, target: Vector2, frames: Array, side: int) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	var center: Vector2 = start.lerp(target, value)
	center.y -= sin(value * PI) * 92.0
	ball.position = center - ball.size * 0.5
	ball.rotation = value * TAU * 2.0 * (1.0 if side == 0 else -1.0)
	if not frames.is_empty():
		ball.texture = frames[clampi(floori(value * 2.0), 0, mini(frames.size() - 1, 1))] as Texture2D

func _release_battler(sprite: TextureRect, ball: TextureRect, target: Vector2, frames: Array) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	if ball != null and is_instance_valid(ball):
		if not frames.is_empty():
			ball.texture = frames[frames.size() - 1] as Texture2D
		var ball_fade: Tween = create_tween()
		ball_fade.tween_property(ball, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.18)
	var glow := TextureRect.new()
	glow.texture = _release_glow()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.size = Vector2(104.0, 104.0)
	glow.position = target - glow.size * 0.5
	glow.pivot_offset = glow.size * 0.5
	glow.scale = Vector2(0.35, 0.35)
	effects_layer.add_child(glow)
	var glow_tween: Tween = create_tween()
	glow_tween.tween_property(glow, "scale", Vector2(1.35, 1.35), 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	glow_tween.parallel().tween_property(glow, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.32)
	glow_tween.tween_callback(glow.queue_free)
	sprite.pivot_offset = sprite.size * 0.5
	sprite.visible = true
	var emerge: Tween = create_tween()
	emerge.tween_property(sprite, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	emerge.parallel().tween_property(sprite, "modulate", Color.WHITE, 0.24)

func _finish_send_out(sprite: TextureRect, ball: TextureRect, tween: Tween) -> void:
	if sprite != null and is_instance_valid(sprite):
		sprite.visible = true
		sprite.scale = Vector2.ONE
		sprite.modulate = Color.WHITE
	if ball != null and is_instance_valid(ball):
		ball.queue_free()
	send_out_tweens.erase(tween)
	_finish_move_event()

func _release_glow() -> Texture2D:
	if release_glow_texture != null:
		return release_glow_texture
	var image: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var distance: float = Vector2(x - 15.5, y - 15.5).length() / 16.0
			image.set_pixel(x, y, Color(1.0, 1.0, 0.86, clampf(1.0 - distance, 0.0, 1.0)))
	release_glow_texture = ImageTexture.create_from_image(image)
	return release_glow_texture

func _on_battle_event(value: Dictionary) -> void:
	battle_event_queue.append(value.duplicate(true))
	_process_battle_event_queue()

func _process_battle_event_queue() -> void:
	if battle_event_busy:
		return
	while not battle_event_queue.is_empty():
		var value: Dictionary = battle_event_queue.pop_front()
		battle_event_busy = str(value.get("type", "update")) in ["move_event", "switch_in"]
		_apply_battle_event(value)
		if battle_event_busy:
			return

func _finish_move_event() -> void:
	move_tween = null
	battle_event_busy = false
	_process_battle_event_queue()

func _finish_move_sequence() -> void:
	move_tween = null
	move_animation_active = false
	_try_finish_move_sequence()

func _try_finish_move_sequence() -> void:
	if move_animation_active or move_effects_pending > 0 or not move_hp_tweens.is_empty():
		return
	_finish_move_event()

func _apply_battle_event(value: Dictionary) -> void:
	var event_type: String = str(value.get("type", "update"))
	var event_state: Variant = value.get("state", null)
	var move_event: Dictionary = {}
	var move_state: Dictionary = {}
	var switch_event: Dictionary = {}
	var resolved_state: Dictionary = GameState.battle_state.duplicate(true)
	if event_state is Dictionary:
		resolved_state = (event_state as Dictionary).duplicate(true)
	if event_type == "move_event":
		move_state = resolved_state
	else:
		state = resolved_state
	match event_type:
		"field_state":
			input_locked = true
			_reset_battle_sprite_visuals()
			_append_log("A battle started.")
			_trigger_flash()
		"queued_event":
			input_locked = not bool(value.get("event", {}).get("prompt", false))
			if not input_locked:
				_append_log("Choose your next action.")
		"move_event":
			input_locked = true
			var event_value: Variant = value.get("event", {})
			move_event = event_value as Dictionary if event_value is Dictionary else {}
			var move_id: int = int(move_event.get("source_move", move_event.get("move_id", 0)))
			var animation_plan: Dictionary = GameState.content.battle_move_animation_plan(move_id) if move_id > 0 and GameState.content != null else {}
			hp_tween_delay = float(animation_plan.get("hit_frame", 18)) / 60.0
			var move_name: String = GameState.content.battle_move_name(move_id) if move_id > 0 and GameState.content != null else "Move"
			_append_log("%s used %s!" % [_battle_entity_name(int(move_event.get("source_entity", 0))), move_name])
			_trigger_flash(Color(1.0, 0.86, 0.58, 0.32))
		"switch_in":
			input_locked = true
			_reset_battle_sprite_visuals()
			var switch_value: Variant = value.get("event", {})
			switch_event = switch_value as Dictionary if switch_value is Dictionary else {}
		"battle_end":
			input_locked = true
			selection_mode = ""
			_append_log("Battle complete.")
		"start_scene":
			_reset_battle_sprite_visuals()
			_append_log("Battle scene initialized.")
			_trigger_flash(Color(1.0, 1.0, 1.0, 0.72))
	if move_event.is_empty():
		_render_state()
	hp_tween_delay = 0.0
	if not move_event.is_empty():
		_animate_move(move_event, move_state)
	elif not switch_event.is_empty():
		_animate_send_out(switch_event)
	elif battle_event_busy:
		_finish_move_event.call_deferred()
