extends Node

var current_screen: Node
var battle_screen_active: bool = false
var battle_screen: Control

func _ready() -> void:
	GameState.battle_event_received.connect(_on_battle_event)
	GameState.dialog_action_received.connect(_on_dialog_action_received)
	GameState.map_load_received.connect(_on_map_load_during_battle)
	_show_auth()

func _replace_screen(scene: PackedScene) -> Node:
	if is_instance_valid(current_screen):
		current_screen.queue_free()
	current_screen = scene.instantiate()
	add_child(current_screen)
	return current_screen

func _show_auth() -> void:
	_close_battle()
	battle_screen_active = false
	var screen = _replace_screen(preload("res://scenes/auth.tscn"))
	screen.authenticated.connect(_show_character_selection)
	screen.local_preview_requested.connect(_show_local_preview)

func _show_character_selection() -> void:
	_close_battle()
	battle_screen_active = false
	var screen = _replace_screen(preload("res://scenes/character_selection.tscn"))
	screen.character_selected.connect(_show_world)
	screen.logout_requested.connect(_show_auth)

func _show_world() -> void:
	_close_battle()
	battle_screen_active = false
	var screen = _replace_screen(preload("res://scenes/world.tscn"))
	screen.battle_requested.connect(_show_battle)

func _show_battle() -> void:
	if battle_screen_active:
		return
	battle_screen_active = true
	if is_instance_valid(current_screen) and current_screen.has_method("set_battle_overlay_active"):
		current_screen.set_battle_overlay_active(true)
	battle_screen = preload("res://scenes/battle.tscn").instantiate()
	battle_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle_screen.z_index = 100
	if is_instance_valid(current_screen):
		current_screen.add_child(battle_screen)
	else:
		add_child(battle_screen)
	battle_screen.exit_requested.connect(_close_battle)

func _close_battle() -> void:
	if is_instance_valid(battle_screen):
		battle_screen.hide()
		battle_screen.queue_free()
	battle_screen = null
	if is_instance_valid(current_screen) and current_screen.has_method("set_battle_overlay_active"):
		current_screen.set_battle_overlay_active(false)
	battle_screen_active = false

func _on_battle_event(event: Dictionary) -> void:
	if str(event.get("type", "")) == "field_state" and not battle_screen_active:
		_show_battle()

func _on_dialog_action_received(_action: Dictionary) -> void:
	if not battle_screen_active or not is_instance_valid(battle_screen):
		return
	if not GameState.battle_in_progress and bool(GameState.battle_state.get("battle_complete", false)):
		_close_battle()

func _on_map_load_during_battle(_map_load: Dictionary) -> void:
	if battle_screen_active and not GameState.battle_in_progress:
		_close_battle()

func _show_local_preview() -> void:
	_close_battle()
	if is_instance_valid(current_screen):
		current_screen.queue_free()
	var screen = preload("res://scenes/content_preview.tscn").instantiate()
	screen.content = GameState.content
	current_screen = screen
	add_child(current_screen)
	screen.exit_requested.connect(_show_auth)
