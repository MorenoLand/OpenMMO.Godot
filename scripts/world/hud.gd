class_name OpenMMOHud
extends Control

signal follow_requested(party_index: int)
signal shop_buy_requested(item_id: int, quantity: int, exchange_type_index: int)
signal shop_sell_requested(item_entity_id: int, quantity: int)
signal shop_closed
signal wall_clock_confirmed(hour: int, minute: int)
signal menu_action_requested(action: String)

const PARTY_COUNT: int = 6
var location_label: Label
var money_label: Label
var time_label: Label
var party_box: VBoxContainer
var party_hp_bars: Array = []
var party_icons: Array = []
var party_hp_tweens: Dictionary = {}
var party_slots: Array = []
var party_context_menu: PopupMenu
var party_context_index: int = -1
var action_bar: HBoxContainer
var action_panel: PanelContainer
var hotbar_panel: PanelContainer
var hotkey_slots: Array = []
var hotkey_selected: int = -1
var bag_panel: PanelContainer
var menu_panel: PanelContainer
var bag_label: Label
var bag_tab_buttons: Array = []
var bag_category: String = "Items"
var current_content
var current_map_id: String = ""
var current_state: Dictionary = {}
var current_party: Array = []
var clock_elapsed: float = 0.0
var bag_open: bool = false
var menu_open: bool = false
var shop_panel: PanelContainer
var shop_money_label: Label
var shop_buy_button: Button
var shop_sell_button: Button
var shop_item_list: ItemList
var shop_detail_label: Label
var shop_quantity: SpinBox
var shop_confirm_button: Button
var shop_catalog: Dictionary = {}
var shop_mode: String = "buy"
var shop_open: bool = false
var clock_overlay: ColorRect
var clock_time_label: Label
var clock_period_label: Label
var clock_hour_hand: Line2D
var clock_minute_hand: Line2D
var clock_open: bool = false
var clock_hour: int = 10
var clock_minute: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_ui()
	_refresh()

func set_state(content, map_id: String, state: Dictionary = {}, party: Array = []) -> void:
	current_content = content
	current_map_id = map_id
	current_state = state
	current_party = party
	_refresh()

func _game_state() -> Node:
	return get_node_or_null("/root/GameState")

func _build_ui() -> void:
	var info_panel: PanelContainer = PanelContainer.new()
	info_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	info_panel.offset_left = 16.0
	info_panel.offset_top = 16.0
	info_panel.offset_right = 266.0
	info_panel.offset_bottom = 104.0
	info_panel.add_theme_stylebox_override("panel", _panel_style(Color("10151ed9"), Color("5f7185")))
	add_child(info_panel)
	var info_box: VBoxContainer = VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 1)
	info_panel.add_child(info_box)
	location_label = Label.new()
	location_label.add_theme_font_size_override("font_size", 16)
	info_box.add_child(location_label)
	money_label = Label.new()
	money_label.add_theme_font_size_override("font_size", 14)
	info_box.add_child(money_label)
	time_label = Label.new()
	time_label.add_theme_font_size_override("font_size", 14)
	info_box.add_child(time_label)
	party_box = VBoxContainer.new()
	party_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	party_box.offset_left = -68.0
	party_box.offset_top = 100.0
	party_box.offset_right = -16.0
	party_box.custom_minimum_size = Vector2(52.0, 0.0)
	party_box.add_theme_constant_override("separation", 3)
	party_box.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(party_box)
	var party_title: Label = Label.new()
	party_title.text = "PARTY"
	party_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	party_title.add_theme_font_size_override("font_size", 9)
	party_title.add_theme_color_override("font_color", Color("b8cbe0"))
	party_box.add_child(party_title)
	for index in range(PARTY_COUNT):
		var slot: PanelContainer = PanelContainer.new()
		slot.custom_minimum_size = Vector2(52.0, 52.0)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		var slot_style: StyleBoxFlat = _panel_style(Color("10151eb8"), Color("5f7185"))
		slot_style.content_margin_left = 0.0
		slot_style.content_margin_top = 0.0
		slot_style.content_margin_right = 0.0
		slot_style.content_margin_bottom = 0.0
		slot.add_theme_stylebox_override("panel", slot_style)
		var margin: MarginContainer = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 4)
		margin.add_theme_constant_override("margin_top", 4)
		margin.add_theme_constant_override("margin_right", 4)
		margin.add_theme_constant_override("margin_bottom", 4)
		slot.add_child(margin)
		var stack: VBoxContainer = VBoxContainer.new()
		stack.add_theme_constant_override("separation", 0)
		margin.add_child(stack)
		var icon: TextureRect = TextureRect.new()
		icon.custom_minimum_size = Vector2(44.0, 40.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(icon)
		var hp_bar: ProgressBar = ProgressBar.new()
		hp_bar.show_percentage = false
		hp_bar.custom_minimum_size = Vector2(44.0, 4.0)
		hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hp_bar.add_theme_stylebox_override("background", _panel_style(Color("26303d"), Color("26303d"), 2, 0))
		hp_bar.add_theme_stylebox_override("fill", _panel_style(Color("5ccf77"), Color("5ccf77"), 2, 0))
		stack.add_child(hp_bar)
		party_hp_bars.append(hp_bar)
		party_icons.append(icon)
		party_slots.append(slot)
		slot.gui_input.connect(_on_party_slot_gui_input.bind(index))
		party_box.add_child(slot)
	party_context_menu = PopupMenu.new()
	party_context_menu.add_item("Follow", 1)
	party_context_menu.add_item("Stop following", 2)
	party_context_menu.id_pressed.connect(_on_party_context_menu_pressed)
	add_child(party_context_menu)
	action_panel = PanelContainer.new()
	action_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	action_panel.offset_left = -286.0
	action_panel.offset_top = -64.0
	action_panel.offset_right = -16.0
	action_panel.offset_bottom = -16.0
	action_panel.z_index = 5
	action_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	action_panel.add_theme_stylebox_override("panel", _panel_style(Color("0b1420e8"), Color("5d7288")))
	add_child(action_panel)
	action_bar = HBoxContainer.new()
	action_bar.add_theme_constant_override("separation", 5)
	action_panel.add_child(action_bar)
	var bag_button: Button = _make_button("Bag")
	bag_button.custom_minimum_size = Vector2(78.0, 42.0)
	bag_button.pressed.connect(toggle_bag)
	action_bar.add_child(bag_button)
	var party_action_button: Button = _make_button("Party")
	party_action_button.custom_minimum_size = Vector2(78.0, 42.0)
	party_action_button.pressed.connect(_on_party_pressed)
	action_bar.add_child(party_action_button)
	var menu_button: Button = _make_button("Menu")
	menu_button.custom_minimum_size = Vector2(78.0, 42.0)
	menu_button.pressed.connect(toggle_menu)
	action_bar.add_child(menu_button)
	hotbar_panel = PanelContainer.new()
	hotbar_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hotbar_panel.offset_left = -224.0
	hotbar_panel.offset_top = 12.0
	hotbar_panel.offset_right = 224.0
	hotbar_panel.offset_bottom = 64.0
	hotbar_panel.z_index = 5
	hotbar_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	hotbar_panel.add_theme_stylebox_override("panel", _panel_style(Color("0b1420e8"), Color("5d7288")))
	add_child(hotbar_panel)
	var hotbar: HBoxContainer = HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 4)
	hotbar_panel.add_child(hotbar)
	for index in range(9):
		var hotkey_button: Button = _make_hotkey_button(index)
		hotkey_slots.append(hotkey_button)
		hotbar.add_child(hotkey_button)
	bag_panel = _make_popup_panel("Bag")
	bag_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bag_panel.offset_left = -300.0
	bag_panel.offset_top = -410.0
	bag_panel.offset_right = -16.0
	bag_panel.offset_bottom = -72.0
	add_child(bag_panel)
	var bag_box: VBoxContainer = bag_panel.get_child(0) as VBoxContainer
	var bag_tabs: HBoxContainer = HBoxContainer.new()
	bag_tabs.add_theme_constant_override("separation", 3)
	bag_box.add_child(bag_tabs)
	for category in ["Items", "Key", "Balls", "TMs", "Berries"]:
		var tab: Button = _make_button(category)
		tab.custom_minimum_size = Vector2(0.0, 30.0)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.add_theme_font_size_override("font_size", 11)
		tab.set_meta("bag_category", category)
		tab.pressed.connect(_select_bag_category.bind(category))
		bag_tab_buttons.append(tab)
		bag_tabs.add_child(tab)
	bag_label = Label.new()
	bag_label.custom_minimum_size = Vector2(260.0, 190.0)
	bag_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	bag_label.add_theme_font_size_override("font_size", 14)
	bag_label.text = "No items available."
	bag_box.add_child(bag_label)
	var bag_close: Button = _make_button("Close")
	bag_close.pressed.connect(toggle_bag)
	bag_box.add_child(bag_close)
	menu_panel = PanelContainer.new()
	menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	menu_panel.offset_left = -128.0
	menu_panel.offset_top = -172.0
	menu_panel.offset_right = 128.0
	menu_panel.offset_bottom = 172.0
	menu_panel.z_index = 20
	menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_panel.add_theme_stylebox_override("panel", _panel_style(Color("30383d"), Color("171c1f"), 4, 1))
	add_child(menu_panel)
	var menu_margin: MarginContainer = MarginContainer.new()
	menu_margin.add_theme_constant_override("margin_left", 14)
	menu_margin.add_theme_constant_override("margin_top", 14)
	menu_margin.add_theme_constant_override("margin_right", 14)
	menu_margin.add_theme_constant_override("margin_bottom", 14)
	menu_panel.add_child(menu_margin)
	var menu_box: VBoxContainer = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 7)
	menu_margin.add_child(menu_box)
	for entry in [{"label": "Return", "action": "return"}, {"label": "Settings", "action": "settings"}, {"label": "FAQ", "action": "faq"}, {"label": "Support Request", "action": "support"}, {"label": "Logout", "action": "logout"}, {"label": "Exit", "action": "exit"}]:
		var menu_action_button: Button = _make_escape_menu_button(str(entry.get("label", "")))
		menu_action_button.pressed.connect(_on_escape_menu_action.bind(str(entry.get("action", "return"))))
		menu_box.add_child(menu_action_button)
	shop_panel = _make_popup_panel("Mart")
	shop_panel.set_anchors_preset(Control.PRESET_CENTER)
	shop_panel.offset_left = -300.0
	shop_panel.offset_top = -225.0
	shop_panel.offset_right = 300.0
	shop_panel.offset_bottom = 225.0
	shop_panel.z_index = 20
	add_child(shop_panel)
	var shop_box: VBoxContainer = shop_panel.get_child(0) as VBoxContainer
	shop_money_label = Label.new()
	shop_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shop_box.add_child(shop_money_label)
	var shop_tabs: HBoxContainer = HBoxContainer.new()
	shop_tabs.add_theme_constant_override("separation", 4)
	shop_box.add_child(shop_tabs)
	shop_buy_button = _make_button("Buy")
	shop_buy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_buy_button.pressed.connect(_set_shop_mode.bind("buy"))
	shop_tabs.add_child(shop_buy_button)
	shop_sell_button = _make_button("Sell")
	shop_sell_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_sell_button.pressed.connect(_set_shop_mode.bind("sell"))
	shop_tabs.add_child(shop_sell_button)
	shop_item_list = ItemList.new()
	shop_item_list.custom_minimum_size = Vector2(568.0, 250.0)
	shop_item_list.select_mode = ItemList.SELECT_SINGLE
	shop_item_list.item_selected.connect(_on_shop_item_selected)
	shop_box.add_child(shop_item_list)
	shop_detail_label = Label.new()
	shop_detail_label.custom_minimum_size = Vector2(0.0, 28.0)
	shop_box.add_child(shop_detail_label)
	var shop_actions: HBoxContainer = HBoxContainer.new()
	shop_actions.add_theme_constant_override("separation", 6)
	shop_box.add_child(shop_actions)
	shop_quantity = SpinBox.new()
	shop_quantity.min_value = 1.0
	shop_quantity.max_value = 999.0
	shop_quantity.value = 1.0
	shop_quantity.custom_minimum_size = Vector2(120.0, 38.0)
	shop_quantity.value_changed.connect(_on_shop_quantity_changed)
	shop_actions.add_child(shop_quantity)
	shop_confirm_button = _make_button("Buy")
	shop_confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_confirm_button.pressed.connect(_confirm_shop_action)
	shop_actions.add_child(shop_confirm_button)
	var shop_close: Button = _make_button("Close")
	shop_close.pressed.connect(_close_shop)
	shop_actions.add_child(shop_close)
	_build_wall_clock()
	_refresh_panels()

func _build_wall_clock() -> void:
	clock_overlay = ColorRect.new()
	clock_overlay.color = Color(0.0, 0.0, 0.0, 0.72)
	clock_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clock_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	clock_overlay.visible = false
	clock_overlay.z_index = 30
	add_child(clock_overlay)
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -160.0
	panel.offset_top = -210.0
	panel.offset_right = 160.0
	panel.offset_bottom = 210.0
	panel.add_theme_stylebox_override("panel", _panel_style(Color("1b1a16f2"), Color("c9b48a"), 12, 2))
	clock_overlay.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title: Label = Label.new()
	title.text = "Set the clock"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("f4ead2"))
	box.add_child(title)
	var face_wrap: Control = Control.new()
	face_wrap.custom_minimum_size = Vector2(200.0, 200.0)
	face_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(face_wrap)
	var face: Panel = Panel.new()
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var face_style: StyleBoxFlat = StyleBoxFlat.new()
	face_style.bg_color = Color("e8d9b0")
	face_style.border_color = Color("6b542e")
	face_style.set_border_width_all(6)
	face_style.set_corner_radius_all(100)
	face.add_theme_stylebox_override("panel", face_style)
	face_wrap.add_child(face)
	clock_hour_hand = Line2D.new()
	clock_hour_hand.width = 5.0
	clock_hour_hand.default_color = Color("2b2418")
	face_wrap.add_child(clock_hour_hand)
	clock_minute_hand = Line2D.new()
	clock_minute_hand.width = 3.0
	clock_minute_hand.default_color = Color("5a3a18")
	face_wrap.add_child(clock_minute_hand)
	clock_time_label = Label.new()
	clock_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_time_label.add_theme_font_size_override("font_size", 28)
	clock_time_label.add_theme_color_override("font_color", Color("f4ead2"))
	box.add_child(clock_time_label)
	clock_period_label = Label.new()
	clock_period_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_period_label.add_theme_font_size_override("font_size", 16)
	clock_period_label.add_theme_color_override("font_color", Color("d2c093"))
	box.add_child(clock_period_label)
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for spec in [["-1h", -60], ["-10m", -10], ["+10m", 10], ["+1h", 60]]:
		var button: Button = _make_button(str(spec[0]))
		button.custom_minimum_size = Vector2(64.0, 36.0)
		button.pressed.connect(_adjust_wall_clock.bind(int(spec[1])))
		row.add_child(button)
	var set_button: Button = _make_button("Set the clock")
	set_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_button.pressed.connect(_confirm_wall_clock)
	box.add_child(set_button)

func show_wall_clock() -> void:
	clock_hour = 10
	clock_minute = 0
	var game_state: Node = _game_state()
	var game_clock_minutes: int = int(game_state.get("game_clock_minutes")) if game_state != null else -1
	if game_clock_minutes >= 0:
		clock_hour = int(game_clock_minutes / 60) % 24
		clock_minute = int(game_clock_minutes % 60)
		clock_minute = int(clock_minute / 10) * 10
	clock_open = true
	clock_overlay.visible = true
	_refresh_wall_clock()

func hide_wall_clock() -> void:
	clock_open = false
	if clock_overlay != null:
		clock_overlay.visible = false

func _adjust_wall_clock(delta_minutes: int) -> void:
	var total: int = posmod(clock_hour * 60 + clock_minute + delta_minutes, 24 * 60)
	clock_hour = int(total / 60)
	clock_minute = total % 60
	_refresh_wall_clock()

func _refresh_wall_clock() -> void:
	if clock_time_label == null:
		return
	var hour12: int = clock_hour % 12
	if hour12 == 0:
		hour12 = 12
	clock_time_label.text = "%d:%02d" % [hour12, clock_minute]
	clock_period_label.text = "AM" if clock_hour < 12 else "PM"
	var center: Vector2 = Vector2(100.0, 100.0)
	var minute_angle: float = deg_to_rad(-90.0 + clock_minute * 6.0)
	var hour_angle: float = deg_to_rad(-90.0 + (clock_hour % 12) * 30.0 + clock_minute * 0.5)
	clock_minute_hand.points = PackedVector2Array([center, center + Vector2(cos(minute_angle), sin(minute_angle)) * 78.0])
	clock_hour_hand.points = PackedVector2Array([center, center + Vector2(cos(hour_angle), sin(hour_angle)) * 50.0])

func _confirm_wall_clock() -> void:
	var game_state: Node = _game_state()
	if game_state != null:
		game_state.set("game_clock_minutes", clock_hour * 60 + clock_minute)
		game_state.set("game_clock_set_msec", Time.get_ticks_msec())
	hide_wall_clock()
	wall_clock_confirmed.emit(clock_hour, clock_minute)
	_refresh_time()

func handle_wall_clock_input(event: InputEventKey) -> bool:
	if not clock_open or not event.pressed or event.echo:
		return false
	match event.keycode:
		KEY_LEFT:
			_adjust_wall_clock(-10)
		KEY_RIGHT:
			_adjust_wall_clock(10)
		KEY_UP:
			_adjust_wall_clock(60)
		KEY_DOWN:
			_adjust_wall_clock(-60)
		KEY_ENTER, KEY_KP_ENTER, KEY_Z, KEY_SPACE:
			_confirm_wall_clock()
		KEY_ESCAPE:
			_confirm_wall_clock()
		_:
			return false
	return true

func _make_button(text_value: String) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(85.0, 38.0)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override("normal", _panel_style(Color("182231e8"), Color("5f7185")))
	button.add_theme_stylebox_override("hover", _panel_style(Color("26364ce8"), Color("82a8d3")))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("314b6be8"), Color("a7c8ed")))
	return button

func _make_escape_menu_button(text_value: String) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(226.0, 38.0)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override("normal", _panel_style(Color("343c41"), Color("1c2327"), 2, 1))
	button.add_theme_stylebox_override("hover", _panel_style(Color("465158"), Color("9db6c4"), 2, 1))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("56636b"), Color("c5d6de"), 2, 1))
	return button

func _select_bag_category(category: String) -> void:
	bag_category = category
	_refresh_bag()

func _make_hotkey_button(index: int) -> Button:
	var button: Button = _make_button("%d\n—" % (index + 1))
	button.custom_minimum_size = Vector2(44.0, 42.0)
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(_on_hotkey_pressed.bind(index))
	return button

func _on_hotkey_pressed(index: int) -> void:
	if index < 0 or index >= hotkey_slots.size():
		return
	hotkey_selected = index
	_refresh_hotbar()

func activate_hotkey(index: int) -> void:
	_on_hotkey_pressed(index)

func _refresh_hotbar() -> void:
	if hotkey_slots.is_empty():
		return
	var values: Variant = current_state.get("hotbar", current_state.get("hotkeys", []))
	if not values is Array:
		values = []
	for index in range(hotkey_slots.size()):
		var item_name: String = ""
		if index < (values as Array).size():
			var slot_value: Variant = (values as Array)[index]
			if slot_value is Dictionary:
				var slot: Dictionary = slot_value
				item_name = str(slot.get("name", slot.get("item_name", ""))).strip_edges()
			elif slot_value is String:
				item_name = str(slot_value).strip_edges()
		var display_name: String = item_name.left(5) if not item_name.is_empty() else "—"
		var button: Button = hotkey_slots[index] as Button
		button.text = "%d\n%s" % [index + 1, display_name]
		button.modulate = Color("9fc3ff") if index == hotkey_selected else Color.WHITE

func _make_popup_panel(title_value: String) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.z_index = 10
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _panel_style(Color("10151ef2"), Color("5f7185")))
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title: Label = Label.new()
	title.text = title_value
	title.add_theme_font_size_override("font_size", 17)
	box.add_child(title)
	return panel

func _panel_style(background: Color, border: Color, radius: int = 3, width: int = 1) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	return style

func _process(delta: float) -> void:
	clock_elapsed += delta
	if clock_elapsed >= 1.0:
		clock_elapsed = 0.0
		_refresh_time()

func toggle_bag() -> void:
	if shop_open:
		return
	bag_open = not bag_open
	if bag_open:
		menu_open = false
	_refresh_panels()

func toggle_menu() -> void:
	if shop_open:
		return
	menu_open = not menu_open
	if menu_open:
		bag_open = false
	_refresh_panels()
	if menu_open and menu_panel != null and menu_panel.get_child_count() > 0:
		var menu_margin: MarginContainer = menu_panel.get_child(0) as MarginContainer
		if menu_margin != null and menu_margin.get_child_count() > 0:
			var menu_box: VBoxContainer = menu_margin.get_child(0) as VBoxContainer
			if menu_box != null and menu_box.get_child_count() > 0:
				(menu_box.get_child(0) as Button).grab_focus()

func handle_escape() -> void:
	if shop_open:
		return
	if bag_open:
		toggle_bag()
	else:
		toggle_menu()

func _on_escape_menu_action(action: String) -> void:
	if action == "return":
		menu_open = false
		_refresh_panels()
		return
	menu_open = false
	_refresh_panels()
	menu_action_requested.emit(action)

func _on_party_pressed() -> void:
	menu_open = false
	if party_box != null:
		party_box.visible = true
	_refresh_panels()

func _refresh_panels() -> void:
	if bag_panel != null:
		bag_panel.visible = bag_open
	if menu_panel != null:
		menu_panel.visible = menu_open
	if shop_panel != null:
		shop_panel.visible = shop_open

func show_shop(catalog: Dictionary) -> void:
	shop_catalog = catalog.duplicate(true)
	shop_open = bool(catalog.get("open", false))
	if shop_open:
		bag_open = false
		menu_open = false
		shop_mode = "buy"
	_refresh_shop()
	_refresh_panels()

func _set_shop_mode(mode: String) -> void:
	shop_mode = mode
	_refresh_shop()

func _refresh_shop() -> void:
	if shop_item_list == null:
		return
	shop_money_label.text = "$%s" % _format_money(int(current_state.get("money", 0)))
	shop_buy_button.modulate = Color("9fc3ff") if shop_mode == "buy" else Color.WHITE
	shop_sell_button.modulate = Color("9fc3ff") if shop_mode == "sell" else Color.WHITE
	shop_item_list.clear()
	var items: Array = shop_catalog.get("items", []) if shop_mode == "buy" and shop_catalog.get("items", []) is Array else current_state.get("bag", []) if current_state.get("bag", []) is Array else []
	for item_value in items:
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		var quantity: int = int(item.get("quantity", 0))
		if shop_mode == "sell" and (quantity <= 0 or int(item.get("price", 0)) < 2):
			continue
		var item_name: String = str(item.get("name", "Item"))
		var price: int = int(item.get("price", 0)) if shop_mode == "buy" else int(item.get("price", 0)) / 2
		var text_value: String = "%s    $%s" % [item_name, _format_money(price)]
		if shop_mode == "sell":
			text_value = "%s  x%d    $%s" % [item_name, quantity, _format_money(price)]
		var index: int = shop_item_list.add_item(text_value)
		shop_item_list.set_item_metadata(index, item.duplicate(true))
	shop_detail_label.text = "Select an item."
	shop_quantity.value = 1.0
	shop_quantity.max_value = 1.0
	shop_confirm_button.text = "Buy" if shop_mode == "buy" else "Sell"
	shop_confirm_button.disabled = true

func _on_shop_item_selected(index: int) -> void:
	var item: Dictionary = shop_item_list.get_item_metadata(index) if shop_item_list.get_item_metadata(index) is Dictionary else {}
	if item.is_empty():
		return
	var available: int = int(item.get("stock", 0x7FFF)) if shop_mode == "buy" else int(item.get("quantity", 0))
	shop_quantity.max_value = maxi(1, mini(available, 999))
	shop_quantity.value = 1.0
	shop_confirm_button.disabled = false
	_update_shop_detail(item)

func _on_shop_quantity_changed(_value: float) -> void:
	var selected: PackedInt32Array = shop_item_list.get_selected_items()
	if selected.is_empty():
		return
	var item: Variant = shop_item_list.get_item_metadata(selected[0])
	if item is Dictionary:
		_update_shop_detail(item)

func _update_shop_detail(item: Dictionary) -> void:
	var unit_price: int = int(item.get("price", 0)) if shop_mode == "buy" else int(item.get("price", 0)) / 2
	var quantity: int = int(shop_quantity.value)
	shop_detail_label.text = "%s x%d — $%s" % [str(item.get("name", "Item")), quantity, _format_money(unit_price * quantity)]

func _confirm_shop_action() -> void:
	var selected: PackedInt32Array = shop_item_list.get_selected_items()
	if selected.is_empty():
		return
	var item: Variant = shop_item_list.get_item_metadata(selected[0])
	if not item is Dictionary:
		return
	var quantity: int = int(shop_quantity.value)
	if shop_mode == "buy":
		shop_buy_requested.emit(int((item as Dictionary).get("item_id", 0)), quantity, 0)
	else:
		shop_sell_requested.emit(int((item as Dictionary).get("object_id", 0)), quantity)
	shop_confirm_button.disabled = true

func _close_shop() -> void:
	shop_open = false
	shop_catalog.clear()
	_refresh_panels()
	shop_closed.emit()

func _refresh_bag() -> void:
	if bag_label == null:
		return
	for tab_value in bag_tab_buttons:
		var tab: Button = tab_value as Button
		tab.modulate = Color("9fc3ff") if str(tab.get_meta("bag_category", "")) == bag_category else Color.WHITE
	var items: Variant = current_state.get("bag", current_state.get("inventory", current_state.get("items", [])))
	var category_container: bool = false
	if items is Dictionary:
		var item_groups: Dictionary = items
		for category_key in _bag_category_keys():
			if item_groups.has(category_key):
				items = item_groups[category_key]
				category_container = true
				break
	var lines: Array[String] = []
	if items is Array:
		for item_value in items:
			if not item_value is Dictionary:
				continue
			var item: Dictionary = item_value
			if not _bag_item_matches_category(item, category_container):
				continue
			var item_name: String = _item_display_name(item, "Item")
			var quantity: int = int(item.get("quantity", item.get("count", 1)))
			lines.append("%s  x%d" % [item_name if not item_name.is_empty() else "Item", quantity])
	elif items is Dictionary:
		for item_key in items.keys():
			var item_value: Variant = items[item_key]
			if item_value is Dictionary:
				var item: Dictionary = item_value
				if not _bag_item_matches_category(item, category_container):
					continue
				var item_name: String = _item_display_name(item, str(item_key))
				var quantity: int = int(item.get("quantity", item.get("count", 1)))
				lines.append("%s  x%d" % [item_name if not item_name.is_empty() else str(item_key), quantity])
			elif bag_category == "Items":
				var item_id: int = int(item_key)
				var item_name: String = current_content.battle_item_info(item_id).get("name", str(item_key)) if current_content != null and item_id > 0 else str(item_key)
				lines.append("%s  x%d" % [item_name if not item_name.is_empty() else str(item_key), int(item_value)])
	bag_label.text = "\n".join(lines) if not lines.is_empty() else "No items available."

func _item_display_name(item: Dictionary, fallback: String) -> String:
	var item_name: String = str(item.get("name", item.get("item_name", ""))).strip_edges()
	var item_id: int = current_content.battle_item_id(item) if current_content != null else int(item.get("item_id", item.get("id", item.get("front_sprite_id", item.get("internal_id", 0)))))
	if current_content != null and item_id > 0:
		var resolved_name: String = str(current_content.battle_item_info(item_id).get("name", "")).strip_edges()
		if not resolved_name.is_empty() and resolved_name.to_lower() != "item":
			item_name = resolved_name
	if item_name.is_empty() or item_name.to_lower() == "item":
		return "Item #%d" % item_id if item_id > 0 else fallback
	return item_name

func _bag_category_keys() -> Array:
	match bag_category:
		"Key": return ["key", "key_items", "keyitems"]
		"Balls": return ["balls", "pokeballs", "poke_balls"]
		"TMs": return ["tms", "tm_hm", "tmhm"]
		"Berries": return ["berries", "berry"]
	return ["items", "item"]

func _bag_item_matches_category(item: Dictionary, category_container: bool) -> bool:
	if category_container:
		return true
	var raw_category: String = str(item.get("category", item.get("tab", ""))).strip_edges().to_lower()
	if raw_category.is_empty():
		return bag_category == "Items"
	match bag_category:
		"Key": return raw_category in ["key", "key_item", "key_items"]
		"Balls": return raw_category in ["ball", "balls", "pokeball", "pokeballs"]
		"TMs": return raw_category in ["tm", "tms", "hm", "tm_hm"]
		"Berries": return raw_category in ["berry", "berries"]
	return raw_category in ["item", "items", "medicine", "held"]

func _refresh() -> void:
	if location_label == null:
		return
	var map_name: String = current_map_id
	if current_content != null and not current_map_id.is_empty():
		var map_value: Dictionary = current_content.map_data(current_map_id)
		map_name = str(map_value.get("name", current_map_id))
	var channel: String = str(current_state.get("channel", current_state.get("channel_id", 1)))
	location_label.text = "%s  Ch. %s" % [map_name.to_upper(), channel]
	var money_value: int = int(current_state.get("money", current_state.get("currency", 0)))
	money_label.text = "$%s" % _format_money(money_value)
	_refresh_time()
	for index in range(party_slots.size()):
		var member: Variant = current_party[index] if index < current_party.size() else {}
		_refresh_party_slot(index, member as Dictionary if member is Dictionary else {})
	_refresh_bag()
	_refresh_hotbar()
	if shop_open:
		_refresh_shop()

func _refresh_time() -> void:
	if time_label == null:
		return
	var now: Dictionary = Time.get_datetime_dict_from_system()
	var weekdays: Array = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
	var weekday: String = str(weekdays[clampi(int(now.get("weekday", 0)), 0, weekdays.size() - 1)])
	var hour: int = int(now.get("hour", 0))
	var minute: int = int(now.get("minute", 0))
	var game_state: Node = _game_state()
	var game_clock_minutes: int = int(game_state.get("game_clock_minutes")) if game_state != null else -1
	if game_clock_minutes >= 0:
		var elapsed_min: int = int((Time.get_ticks_msec() - int(game_state.get("game_clock_set_msec"))) / 60000.0)
		var total: int = posmod(game_clock_minutes + elapsed_min, 24 * 60)
		hour = int(total / 60)
		minute = total % 60
	time_label.text = "%s, %02d:%02d" % [weekday, hour, minute]

func _on_party_slot_gui_input(event: InputEvent, party_index: int) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event: InputEventMouseButton = event
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return
	var member: Variant = current_party[party_index] if party_index >= 0 and party_index < current_party.size() else {}
	if not member is Dictionary or int((member as Dictionary).get("dex_id", (member as Dictionary).get("species_id", (member as Dictionary).get("species", 0)))) <= 0:
		return
	party_context_index = party_index
	party_context_menu.position = Vector2i(get_global_mouse_position())
	party_context_menu.popup()
	get_viewport().set_input_as_handled()

func _on_party_context_menu_pressed(menu_id: int) -> void:
	if party_context_index < 0:
		return
	if menu_id == 1:
		follow_requested.emit(party_context_index)
	elif menu_id == 2:
		follow_requested.emit(-1)
	party_context_index = -1

func _format_money(value: int) -> String:
	var negative: bool = value < 0
	var digits: String = str(absi(value))
	var formatted: String = ""
	while digits.length() > 3:
		formatted = "," + digits.substr(digits.length() - 3) + formatted
		digits = digits.substr(0, digits.length() - 3)
	formatted = digits + formatted
	return "-" + formatted if negative else formatted

func _refresh_party_slot(index: int, member: Dictionary) -> void:
	if index < 0 or index >= party_slots.size():
		return
	var slot: PanelContainer = party_slots[index] as PanelContainer
	var hp_bar: ProgressBar = party_hp_bars[index] as ProgressBar
	var icon: TextureRect = party_icons[index] as TextureRect
	var species_id: int = _party_species_id(member)
	if species_id <= 0:
		slot.tooltip_text = ""
		icon.texture = null
		icon.visible = false
		hp_bar.value = 0.0
		hp_bar.max_value = 1.0
		hp_bar.visible = false
		hp_bar.set_meta("initialized", false)
		return
	var name: String = _party_slot_name(member)
	var level: int = int(member.get("level", 0))
	var current_hp: int = int(member.get("current_hp", member.get("hp", 0)))
	var max_hp: int = int(member.get("max_hp", member.get("hp_max", 0)))
	if max_hp <= 0:
		max_hp = maxi(current_hp, 1)
	var target_hp: float = clampf(float(current_hp), 0.0, float(max_hp))
	slot.tooltip_text = "%s\nLv %d\n%d / %d HP" % [name, level, current_hp, max_hp]
	var sprite: Dictionary = current_content.battle_pokemon_sprite(species_id, false) if current_content != null else {}
	icon.texture = sprite.get("texture") as Texture2D
	icon.visible = icon.texture != null
	hp_bar.visible = true
	hp_bar.max_value = max_hp
	var fill_color: Color = Color("d94c5a") if target_hp * 5.0 <= max_hp else Color("e6bd5a") if target_hp * 2.0 <= max_hp else Color("5ccf77")
	hp_bar.add_theme_stylebox_override("fill", _panel_style(fill_color, fill_color, 3, 0))
	hp_bar.tooltip_text = slot.tooltip_text
	if not bool(hp_bar.get_meta("initialized", false)):
		hp_bar.value = target_hp
		hp_bar.set_meta("initialized", true)
	else:
		var previous_tween: Tween = party_hp_tweens.get(index) as Tween
		if previous_tween != null:
			previous_tween.kill()
		if absf(float(hp_bar.value) - target_hp) > 0.1:
			var tween: Tween = create_tween()
			party_hp_tweens[index] = tween
			tween.tween_property(hp_bar, "value", target_hp, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			hp_bar.value = target_hp

func _party_species_id(member: Dictionary) -> int:
	return int(member.get("dex_id", member.get("species_id", member.get("species", 0))))

func _party_slot_name(member: Dictionary) -> String:
	var species_id: int = _party_species_id(member)
	var nickname: String = str(member.get("nickname", "")).strip_edges()
	if nickname.is_empty() and species_id > 0 and current_content != null:
		nickname = current_content.battle_pokemon_name(species_id)
	return nickname if not nickname.is_empty() else "Pokemon"

func _party_slot_text(member: Dictionary) -> String:
	if _party_species_id(member) <= 0:
		return ""
	return "%s\nLv %d" % [_party_slot_name(member).left(12), int(member.get("level", 0))]
