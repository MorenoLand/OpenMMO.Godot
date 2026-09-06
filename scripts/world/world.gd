extends Control

signal battle_requested

const MAP_VIEW_SCRIPT = preload("res://scripts/content/map_play_canvas.gd")
const HUD_SCRIPT = preload("res://scripts/world/hud.gd")
const DIALOGUE_SCRIPT = preload("res://scripts/dialogue.gd")
const AUDIO_SCRIPT = preload("res://scripts/world/audio.gd")
const CHAT_SCRIPT = preload("res://scripts/world/chat.gd")
const CONNECTED_WORLD_PRELOAD_DEPTH: int = 2
const CONNECTED_WORLD_MAX_MAPS: int = 24

var title_label: Label
var status_label: Label
var chat_box
var snapshot: Dictionary = {}
var entities: Dictionary = {}
var selected_character_id := 0
var map_view
var hud
var dialogue_overlay
var audio
var transition_overlay: ColorRect
var transition_tween: Tween
var debug_panel: PanelContainer
var debug_label: Label
var debug_dragging: bool = false
var debug_drag_offset: Vector2 = Vector2.ZERO
var transition_reveal_pending: bool = false
var transition_map_ready: bool = false
var transition_screen_ready: bool = false
var animation_tick: int = 0
var animation_elapsed: float = 0.0
var held_input: String = ""
var held_input_elapsed: float = 0.0
var map_has_animation: bool = false
var server_dialogue_active: bool = false
var server_dialogue_sequence: int = 0
var server_dialogue_action_type: int = -1
var server_dialogue_detail: PackedByteArray = PackedByteArray()
var dialogue_string_vars: Dictionary = {}
var trainer_battle_dialogue_pending: bool = false
var connected_world_generation: int = 0
var removed_npc_entities: Dictionary = {}
var npc_entity_maps: Dictionary = {}
var story_objects_by_map: Dictionary = {}
var map_prepare_jobs: Dictionary = {}
var map_preload_queue: Array[String] = []
var map_preload_queued: Dictionary = {}
var map_preload_active: bool = false
var ignore_stale_entity_removals: bool = false

func _ready() -> void:
	set_process_input(true)
	set_process_unhandled_input(true)
	selected_character_id = int(GameState.current_character.get("id", 0))
	GameState.map_load_received.connect(_on_map_load)
	GameState.render_screen_changed.connect(_on_render_screen)
	GameState.world_snapshot_received.connect(_on_world_snapshot)
	GameState.entity_update_received.connect(_on_entity_update)
	GameState.chat_received.connect(_on_chat)
	GameState.connection_error.connect(_on_connection_error)
	GameState.dialog_action_received.connect(_on_dialog_action_received)
	GameState.dialog_state_received.connect(_on_dialog_state_received)
	GameState.battle_event_received.connect(_on_battle_event)
	GameState.character_state_changed.connect(_on_character_state_changed)
	GameState.story_state_changed.connect(_on_story_state_changed)
	GameState.story_state_resynced.connect(_on_story_state_resynced)
	GameState.shop_catalog_received.connect(_on_shop_catalog)
	_build_ui()
	if not GameState.pending_map_load.is_empty():
		call_deferred("_consume_pending_map_load")
	queue_redraw()

func _build_ui() -> void:
	map_view = MAP_VIEW_SCRIPT.new()
	map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_view.set_content(GameState.content)
	map_view.set_authoritative_state(true)
	map_view.set_local_entity_id(selected_character_id)
	map_view.interaction_requested.connect(_on_interaction_requested)
	map_view.sound_requested.connect(_on_sound_requested)
	map_view.location_changed.connect(_on_local_location_changed)
	add_child(map_view)
	map_view.set_input_enabled(true)
	audio = AUDIO_SCRIPT.new()
	add_child(audio)
	hud = HUD_SCRIPT.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.follow_requested.connect(_on_follow_requested)
	hud.shop_buy_requested.connect(_on_shop_buy_requested)
	hud.shop_sell_requested.connect(_on_shop_sell_requested)
	hud.shop_closed.connect(_on_shop_closed)
	add_child(hud)
	chat_box = CHAT_SCRIPT.new()
	chat_box.message_submitted.connect(_send_chat)
	add_child(chat_box)
	dialogue_overlay = DIALOGUE_SCRIPT.new()
	dialogue_overlay.action_requested.connect(_on_dialogue_action)
	dialogue_overlay.choice_requested.connect(_on_dialogue_choice)
	add_child(dialogue_overlay)
	title_label = Label.new()
	title_label.position = Vector2(24, 18)
	title_label.add_theme_font_size_override("font_size", 22)
	add_child(title_label)
	title_label.visible = false
	status_label = Label.new()
	status_label.position = Vector2(24, 47)
	add_child(status_label)
	status_label.visible = false
	transition_overlay = ColorRect.new()
	transition_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transition_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition_overlay.visible = false
	add_child(transition_overlay)
	_build_debug_panel()
	resized.connect(_layout_ui)
	_layout_ui()

func _layout_ui() -> void:
	map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chat_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_box.offset_left = 24
	chat_box.offset_top = -214
	chat_box.offset_right = 444
	chat_box.offset_bottom = -24
	_clamp_debug_panel_position()

func _build_debug_panel() -> void:
	debug_panel = PanelContainer.new()
	debug_panel.name = "DebugPanel"
	debug_panel.position = Vector2(24.0, 120.0)
	debug_panel.custom_minimum_size = Vector2(420.0, 0.0)
	debug_panel.z_index = 1000
	debug_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color("10151ef2")
	panel_style.border_color = Color("5f7185")
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(3)
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_top = 8.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_bottom = 8.0
	debug_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(debug_panel)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	debug_panel.add_child(content)
	var title_bar: HBoxContainer = HBoxContainer.new()
	title_bar.custom_minimum_size = Vector2(0.0, 28.0)
	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	title_bar.gui_input.connect(_on_debug_title_input)
	content.add_child(title_bar)
	var title: Label = Label.new()
	title.text = "DEBUG  Ctrl+Shift+;"
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title)
	var close_button: Button = Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(28.0, 28.0)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(_toggle_debug_panel)
	title_bar.add_child(close_button)
	debug_label = Label.new()
	debug_label.add_theme_font_size_override("font_size", 13)
	debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(debug_label)
	debug_panel.visible = false

func _clamp_debug_panel_position() -> void:
	if debug_panel == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var max_position := Vector2(maxf(viewport_size.x - debug_panel.size.x, 0.0), maxf(viewport_size.y - debug_panel.size.y, 0.0))
	debug_panel.position = Vector2(clampf(debug_panel.position.x, 0.0, max_position.x), clampf(debug_panel.position.y, 0.0, max_position.y))

func _toggle_debug_panel() -> void:
	if debug_panel == null:
		return
	debug_panel.visible = not debug_panel.visible
	if debug_panel.visible:
		_update_debug_panel(0.0)

func _update_debug_panel(delta: float) -> void:
	if debug_label == null:
		return
	var map_id: String = "-"
	var position_text: String = "-"
	var elevation: int = -1
	var facing: int = -1
	var movement_status: String = "idle"
	var target_text: String = "-"
	var transition_status: String = "no"
	var spawn_status: String = "no"
	var input_status: String = "off"
	if map_view != null:
		map_id = str(map_view.map_id)
		position_text = "%d, %d" % [map_view.player_position.x, map_view.player_position.y]
		elevation = int(map_view.player_elevation)
		facing = int(map_view.player_facing)
		if bool(map_view.movement_active):
			movement_status = "active"
			target_text = "%d, %d" % [map_view.movement_target.x, map_view.movement_target.y]
		transition_status = "yes" if bool(map_view.transition_active) or transition_reveal_pending else "no"
		spawn_status = "yes" if bool(map_view.has_spawn) else "no"
		input_status = "on" if bool(map_view.input_enabled) else "off"
	var server_location: String = "%s/%s" % [str(GameState.current_character.get("bank_id", "-")), str(GameState.current_character.get("map_id", "-"))]
	var viewport_size: Vector2 = get_viewport_rect().size
	var hover_text: String = _debug_hover_text()
	debug_label.text = "FPS: %d\nFrame: %.1f ms\nMap: %s\nServer bank/map: %s\nPosition: %s\nElevation: %d  Facing: %d\nMovement: %s\nTarget: %s\nTransition: %s\nSpawn ready: %s\nInput: %s\nHeld: %s\nEntities: %d\nViewport: %d x %d\n--- hover ---\n%s" % [Engine.get_frames_per_second(), delta * 1000.0, map_id, server_location, position_text, elevation, facing, movement_status, target_text, transition_status, spawn_status, input_status, held_input if not held_input.is_empty() else "-", entities.size(), int(viewport_size.x), int(viewport_size.y), hover_text]


func _debug_hover_text() -> String:
	if map_view == null or not map_view.has_method("inspect_at_screen"):
		return "(no inspect)"
	var local_mouse: Vector2 = map_view.get_local_mouse_position()
	if local_mouse.x < 0.0 or local_mouse.y < 0.0 or local_mouse.x > map_view.size.x or local_mouse.y > map_view.size.y:
		return "outside map view"
	var info: Dictionary = map_view.inspect_at_screen(local_mouse)
	if not bool(info.get("ok", false)):
		return "n/a"
	var hit_map: String = str(info.get("map_id", ""))
	if hit_map.is_empty():
		return "world %s (no map)" % str(info.get("world_tile", Vector2i.ZERO))
	var local_tile: Vector2i = info.get("local_tile", Vector2i.ZERO)
	var cell: Dictionary = info.get("cell", {})
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s @ %d,%d" % [hit_map, local_tile.x, local_tile.y])
	lines.append("metatile %d  behavior 0x%02X" % [int(cell.get("metatile_id", -1)), int(cell.get("behavior", -1))])
	lines.append("collision %d  elev %d  layer %d" % [int(cell.get("collision", -1)), int(cell.get("elevation", -1)), int(cell.get("layer_type", -1))])
	var warp: Dictionary = info.get("warp", {})
	if bool(warp.get("ok", false)):
		lines.append("warp -> %s (%s,%s) id %s" % [str(warp.get("map_id", "?")), str(warp.get("x", "?")), str(warp.get("y", "?")), str(warp.get("warp_id", "?"))])
	else:
		lines.append("warp: none")
	lines.append("door gfx: %s  anim-door bhv: %s" % ["yes" if bool(info.get("door_graphics", false)) else "no", "yes" if bool(info.get("animated_door_behavior", false)) else "no"])
	var hits: Array = info.get("hits", [])
	if hits.is_empty():
		lines.append("obj/npc: none")
	else:
		for hit_value in hits:
			if not hit_value is Dictionary:
				continue
			var hit: Dictionary = hit_value
			var kind: String = str(hit.get("kind", "?"))
			if kind == "object" or kind == "sign":
				lines.append("%s local=%d gfx=%d script=0x%X" % [kind, int(hit.get("local_id", -1)), int(hit.get("graphics_id", -1)), int(hit.get("script_offset", -1))])
				var dialogue_id: String = str(hit.get("dialogue_id", ""))
				if not dialogue_id.is_empty():
					lines.append("  dialogue %s" % dialogue_id)
			else:
				lines.append("%s id=%s gfx=%s" % [kind, str(hit.get("entity_id", hit.get("local_id", "?"))), str(hit.get("graphics_id", "?"))])
	return "\n".join(lines)

func _on_debug_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button_event: InputEventMouseButton = event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT:
			debug_dragging = button_event.pressed
			if debug_dragging:
				debug_drag_offset = debug_panel.position - get_global_mouse_position()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and debug_dragging:
		var pointer_position: Vector2 = get_global_mouse_position() + debug_drag_offset
		var viewport_size: Vector2 = get_viewport_rect().size
		var max_position := Vector2(maxf(viewport_size.x - debug_panel.size.x, 0.0), maxf(viewport_size.y - debug_panel.size.y, 0.0))
		debug_panel.position = Vector2(clampf(pointer_position.x, 0.0, max_position.x), clampf(pointer_position.y, 0.0, max_position.y))
		get_viewport().set_input_as_handled()

func _consume_pending_map_load() -> void:
	if not GameState.pending_map_load.is_empty():
		_on_map_load(GameState.pending_map_load)

func _on_world_snapshot(value: Dictionary) -> void:
	snapshot = value
	entities.clear()
	for player_value in value.get("players", []):
		if player_value is Dictionary:
			var player: Dictionary = player_value
			entities[str(player.get("user_id", 0))] = player
	title_label.text = "Map: %s" % str(snapshot.get("map_id", "unknown"))
	status_label.text = "Authoritative movement active. Arrow keys or WASD move one tile."
	if hud != null:
		var party: Array = []
		var snapshot_party: Variant = snapshot.get("party", [])
		if snapshot_party is Array:
			party = snapshot_party
		if party.is_empty():
			var selected_party: Variant = GameState.current_character.get("party", [])
			if selected_party is Array:
				party = selected_party
		snapshot["party"] = party
		snapshot["money"] = int(GameState.current_character.get("money", 0))
		snapshot["bag"] = GameState.current_character.get("bag", [])
		hud.set_state(GameState.content, str(snapshot.get("map_id", "")), snapshot, party)
	await _load_map_texture(str(snapshot.get("map_id", "")))
	_sync_map_entities()

func _on_map_load(value: Dictionary) -> void:
	if dialogue_overlay != null and dialogue_overlay.is_open():
		dialogue_overlay.close_dialogue()
		map_view.set_dialogue_active(false)
	server_dialogue_active = false
	if map_view != null and GameState.content != null:
		map_view.set_content(GameState.content)
	var map_id: String = str(value.get("local_map_id", ""))
	if map_id.is_empty():
		status_label.text = "OpenMMO did not provide a renderable map"
		_force_reveal_screen_transition()
		return
	await _wait_for_door_traversal()
	var overlay_wait: int = 0
	while transition_reveal_pending and transition_overlay != null and not transition_overlay.visible and overlay_wait < 60:
		await get_tree().process_frame
		overlay_wait += 1
	snapshot = {"map_id": map_id, "server_map": value, "party": GameState.current_character.get("party", []), "money": int(GameState.current_character.get("money", 0)), "bag": GameState.current_character.get("bag", []), "players": []}
	_retain_server_entities_for_map(map_id)
	if hud != null:
		hud.set_state(GameState.content, map_id, snapshot, snapshot.party)
	if not await _load_map_texture(map_id, int(value.get("width", 0)), int(value.get("height", 0))):
		_force_reveal_screen_transition()
		return
	_apply_local_spawn_for_map(map_id)
	map_view.set_input_enabled(true)
	_sync_map_entities()
	GameState.call_deferred("complete_map_load", str(value.get("key", "")))
	transition_map_ready = true
	_try_reveal_screen_transition()
	ignore_stale_entity_removals = false

func _load_map_texture(map_id: String, expected_width: int = 0, expected_height: int = 0) -> bool:
	if GameState.content == null or map_id.is_empty():
		return false
	if map_view != null and map_view.map_id == map_id and map_view.is_map_rendered(map_id):
		return true
	connected_world_generation += 1
	var generation: int = connected_world_generation
	var server_map: Dictionary = GameState.content._server_map_for_local_map(map_id, GameState.server_maps)
	if not GameState.content._is_server_custom_map(server_map):
		var cached_map: Dictionary = await _ensure_rom_map_prepared(map_id)
		if not bool(cached_map.get("ok", false)):
			status_label.text = "Map renderer: %s" % str(cached_map.get("error", "map rendering failed"))
			return false
	var result: Dictionary = GameState.content.prepare_server_map(map_id, server_map, GameState.server_maps, false) if GameState.content._is_server_custom_map(server_map) else GameState.content.prepare_map(map_id, false)
	if not bool(result.get("ok", false)):
		status_label.text = "Map renderer: %s" % str(result.get("error", "map rendering failed"))
		return false
	if expected_width > 0 and expected_height > 0 and (int(result.get("width", 0)) != expected_width or int(result.get("height", 0)) != expected_height):
		status_label.text = "The local ROM map dimensions do not match the OpenMMO map"
	map_has_animation = false
	map_has_animation = not (result.get("animated_background_tiles", []) as Array).is_empty() or not (result.get("animated_foreground_tiles", []) as Array).is_empty()
	_cache_story_objects(map_id, result.get("objects", []))
	var root_region: Dictionary = {"map_id": map_id, "origin": Vector2i.ZERO, "width": int(result.get("width", 0)), "height": int(result.get("height", 0)), "render_origin": Vector2i(result.get("render_origin", Vector2i.ZERO)), "render_width": int(result.get("render_width", result.get("width", 0))), "render_height": int(result.get("render_height", result.get("height", 0))), "background_texture": result.get("background_texture"), "foreground_texture": result.get("foreground_texture"), "objects": map_view.objects_for_mode(result.get("objects", [])), "warps": result.get("warps", []), "connections": result.get("connections", []), "animated_background_tiles": result.get("animated_background_tiles", []), "animated_foreground_tiles": result.get("animated_foreground_tiles", []), "music_id": int(result.get("music_id", 0)), "map_type": int(result.get("map_type", 0)), "ready": true}
	var root_world: Dictionary = {"ok": true, "root_map_id": map_id, "regions": [root_region], "map_origins": {map_id: Vector2i.ZERO}}
	map_view.set_world(root_world, map_id)
	audio.play_map_music(GameState.content, map_id)
	_queue_warp_map_preloads(result.get("warps", []))
	call_deferred("_expand_connected_world", map_id, generation)
	return true

func _start_rom_map_prepare(map_id: String) -> void:
	if map_id.is_empty() or map_prepare_jobs.has(map_id) or GameState.content == null or GameState.content.has_prepared_map(map_id):
		return
	var worker: OpenMMOContent = GameState.content.create_map_cache_worker()
	var task_id: int = WorkerThreadPool.add_task(worker.build_detached_map_cache.bind(map_id), false, "Prepare map %s" % map_id)
	map_prepare_jobs[map_id] = {"worker": worker, "task_id": task_id, "joined": false, "result": {}}

func _ensure_rom_map_prepared(map_id: String) -> Dictionary:
	if GameState.content.has_prepared_map(map_id):
		return GameState.content.map_cache.get(map_id, {})
	_start_rom_map_prepare(map_id)
	var job_value: Variant = map_prepare_jobs.get(map_id, {})
	if not job_value is Dictionary or (job_value as Dictionary).is_empty():
		return {"ok": false, "error": "could not start map preparation"}
	var job: Dictionary = job_value as Dictionary
	var task_id: int = int(job.get("task_id", -1))
	while task_id >= 0 and not WorkerThreadPool.is_task_completed(task_id):
		await get_tree().process_frame
	if not bool(job.get("joined", false)):
		job["joined"] = true
		WorkerThreadPool.wait_for_task_completion(task_id)
		var worker: OpenMMOContent = job.get("worker") as OpenMMOContent
		var result: Dictionary = worker.detached_map_cache_result if worker != null else {"ok": false, "error": "map preparation worker failed"}
		job["result"] = result
		GameState.content.install_detached_map_cache(map_id, result)
		map_prepare_jobs.erase(map_id)
		return result
	while (job.get("result", {}) as Dictionary).is_empty():
		await get_tree().process_frame
	return job.get("result", {}) as Dictionary

func _queue_warp_map_preloads(warps: Variant) -> void:
	if not warps is Array or GameState.content == null:
		return
	for warp_value in warps as Array:
		if not warp_value is Dictionary:
			continue
		var target_map_id: String = str((warp_value as Dictionary).get("map_id", ""))
		if target_map_id.is_empty() or map_preload_queued.has(target_map_id) or GameState.content.has_prepared_map(target_map_id):
			continue
		map_preload_queue.append(target_map_id)
		map_preload_queued[target_map_id] = true
	if not map_preload_active and not map_preload_queue.is_empty():
		call_deferred("_drain_map_preload_queue")

func _drain_map_preload_queue() -> void:
	if map_preload_active:
		return
	map_preload_active = true
	while not map_preload_queue.is_empty():
		var target_map_id: String = map_preload_queue.pop_front()
		await get_tree().process_frame
		if GameState.content == null:
			map_preload_queued.erase(target_map_id)
			continue
		var server_map: Dictionary = GameState.content._server_map_for_local_map(target_map_id, GameState.server_maps)
		if GameState.content._is_server_custom_map(server_map):
			GameState.content.prepare_server_map(target_map_id, server_map, GameState.server_maps, false)
		else:
			var cached_map: Dictionary = await _ensure_rom_map_prepared(target_map_id)
			if bool(cached_map.get("ok", false)):
				await get_tree().process_frame
				GameState.content.prepare_map(target_map_id, false)
		map_preload_queued.erase(target_map_id)
	map_preload_active = false

func _expand_connected_world(root_map_id: String, generation: int) -> void:
	await get_tree().process_frame
	while transition_overlay != null and transition_overlay.visible:
		await get_tree().process_frame
	if generation != connected_world_generation or map_view == null or map_view.map_id != root_map_id:
		return
	var connected_world: Dictionary = GameState.content.prepare_connected_world(root_map_id, CONNECTED_WORLD_MAX_MAPS, 0, GameState.server_maps, CONNECTED_WORLD_PRELOAD_DEPTH)
	if not bool(connected_world.get("ok", false)) or generation != connected_world_generation:
		return
	map_view.set_world(connected_world, root_map_id)
	call_deferred("_preload_connected_regions", connected_world, root_map_id, generation)

func _preload_connected_regions(world_value: Dictionary, root_map_id: String, generation: int) -> void:
	var regions: Array = world_value.get("regions", [])
	for region_value in regions:
		if generation != connected_world_generation or not region_value is Dictionary:
			return
		var region: Dictionary = region_value
		var region_id: String = str(region.get("map_id", ""))
		if region_id.is_empty() or region_id == root_map_id or bool(region.get("ready", false)) or int(region.get("depth", 1)) > CONNECTED_WORLD_PRELOAD_DEPTH:
			continue
		await get_tree().process_frame
		if generation != connected_world_generation:
			return
		var server_map: Dictionary = GameState.content._server_map_for_local_map(region_id, GameState.server_maps)
		if not GameState.content._is_server_custom_map(server_map):
			var cached_map: Dictionary = await _ensure_rom_map_prepared(region_id)
			if not bool(cached_map.get("ok", false)):
				continue
		var prepared: Dictionary = GameState.content.prepare_server_map(region_id, server_map, GameState.server_maps, false) if GameState.content._is_server_custom_map(server_map) else GameState.content.prepare_map(region_id, false)
		if not bool(prepared.get("ok", false)):
			continue
		region["background_texture"] = prepared.get("background_texture")
		region["foreground_texture"] = prepared.get("foreground_texture")
		region["render_origin"] = Vector2i(region.get("origin", Vector2i.ZERO)) + Vector2i(prepared.get("render_origin", Vector2i.ZERO))
		region["render_width"] = int(prepared.get("render_width", region.get("width", 0)))
		region["render_height"] = int(prepared.get("render_height", region.get("height", 0)))
		_cache_story_objects(region_id, prepared.get("objects", []))
		region["objects"] = map_view.objects_for_mode(prepared.get("objects", []))
		region["warps"] = prepared.get("warps", [])
		region["animated_background_tiles"] = prepared.get("animated_background_tiles", [])
		region["animated_foreground_tiles"] = prepared.get("animated_foreground_tiles", [])
		region["ready"] = true
		if map_view != null:
			map_view.refresh_world_bounds()
		_sync_map_entities()

func _on_entity_update(value: Dictionary) -> void:
	if value.has("scripted_movement"):
		var scripted_value: Variant = value.get("scripted_movement")
		if scripted_value is Dictionary and map_view != null:
			var scripted: Dictionary = scripted_value as Dictionary
			map_view.queue_scripted_movement(int(scripted.get("entity_id", 0)), scripted.get("steps", PackedByteArray()), bool(scripted.get("running", false)))
		return
	if value.has("remove_entity_id"):
		var removed_entity_id: int = int(value.get("remove_entity_id", 0))
		var removed_key: String = str(removed_entity_id)
		var removed_map_id: String = str(npc_entity_maps.get(removed_key, ""))
		if removed_map_id.is_empty():
			for stored_key in entities:
				var stored_value: Variant = entities[stored_key]
				if stored_value is Dictionary and int((stored_value as Dictionary).get("entity_id", (stored_value as Dictionary).get("character_id", 0))) == removed_entity_id:
					removed_map_id = str((stored_value as Dictionary).get("map_id", ""))
					break
		if not removed_map_id.is_empty() and not ignore_stale_entity_removals:
			var removed_for_map: Dictionary = removed_npc_entities.get(removed_map_id, {}).duplicate()
			removed_for_map[removed_key] = true
			removed_npc_entities[removed_map_id] = removed_for_map
		var remove_keys: Array = []
		for key in entities:
			var stored_value: Variant = entities[key]
			if stored_value is Dictionary and int((stored_value as Dictionary).get("entity_id", (stored_value as Dictionary).get("character_id", 0))) == removed_entity_id:
				remove_keys.append(key)
		for key in remove_keys:
			entities.erase(key)
		_sync_map_entities()
		return
	var player: Variant = value.get("player")
	if player is Dictionary:
		var entity: Dictionary = player
		var key := str(entity.get("entity_id", entity.get("character_id", entity.get("user_id", 0))))
		if bool(entity.get("npc", false)):
			var entity_map_id: String = str(entity.get("map_id", ""))
			entity["story_cutscene_spawn"] = bool(value.get("spawn", false)) and not bool(value.get("map_load_spawn", false))
			npc_entity_maps[key] = entity_map_id
			var removed_for_map: Dictionary = removed_npc_entities.get(entity_map_id, {}).duplicate()
			if bool(value.get("spawn", false)) and removed_for_map.has(key):
				if bool(value.get("map_load_spawn", false)):
					return
				removed_for_map.erase(key)
				removed_npc_entities[entity_map_id] = removed_for_map
		var is_local: bool = bool(value.get("local", false)) or int(entity.get("character_id", 0)) == selected_character_id
		var merged: Dictionary = {}
		var existing: Variant = entities.get(key, {})
		if existing is Dictionary:
			merged = (existing as Dictionary).duplicate(true)
		merged.merge(entity, true)
		entities[key] = merged
		if is_local and map_view != null:
			var entity_map_id: String = str(entity.get("map_id", ""))
			if not entity_map_id.is_empty() and entity_map_id != map_view.map_id:
				if not map_view.set_active_map(entity_map_id):
					await _load_map_texture(entity_map_id)
				snapshot["map_id"] = entity_map_id
				if title_label != null:
					title_label.text = "Map: %s" % entity_map_id
			if entity.has("x") and entity.has("y"):
				var local_elevation: int = map_view.player_elevation
				map_view.apply_server_position(int(entity.get("x", map_view.player_position.x)), int(entity.get("y", map_view.player_position.y)), int(entity.get("elevation", local_elevation)), int(entity.get("facing", map_view.player_facing)))
			elif entity.has("facing"):
				map_view.apply_server_facing(int(entity.get("facing", map_view.player_facing)))
		_sync_map_entities()

func _on_local_location_changed(next_map_id: String, x: int, y: int) -> void:
	var facing: int = map_view.player_facing if map_view != null else int(GameState.current_character.get("facing", 1))
	var elevation: int = map_view.player_elevation if map_view != null else int(GameState.current_character.get("elevation", 3))
	var updated: bool = false
	for key in entities:
		var value: Variant = entities[key]
		if not value is Dictionary:
			continue
		var entity: Dictionary = value
		if int(entity.get("character_id", 0)) != selected_character_id:
			continue
		entity = entity.duplicate(true)
		entity["x"] = x
		entity["y"] = y
		entity["map_id"] = next_map_id
		entity["elevation"] = elevation
		entity["facing"] = facing
		entities[key] = entity
		updated = true
	if not updated:
		entities[str(selected_character_id)] = {"entity_id": selected_character_id, "character_id": selected_character_id, "map_id": next_map_id, "x": x, "y": y, "elevation": elevation, "facing": facing}
	GameState.current_character["x"] = x
	GameState.current_character["y"] = y
	GameState.current_character["facing"] = facing
	if map_view != null:
		map_view.set_player_state(x, y, elevation, facing)

func _on_render_screen(visible: bool) -> void:
	if not visible:
		transition_reveal_pending = true
		transition_map_ready = false
		transition_screen_ready = false
		await _wait_for_door_traversal()
		if map_view != null:
			map_view.set_transition_active(true)
			map_view.set_input_enabled(false)
		_cover_screen_transition()
		# If map prepare stalls (common on Hoenn indoor after truck), do not stay black forever.
		await get_tree().create_timer(2.5).timeout
		if transition_reveal_pending:
			_force_reveal_screen_transition()
		return
	if transition_reveal_pending:
		transition_screen_ready = true
		_try_reveal_screen_transition()
		return
	if transition_overlay != null:
		transition_overlay.visible = false
	if map_view != null:
		map_view.visible = true
		map_view.set_transition_active(false)
		map_view.set_input_enabled(true)
	if hud != null:
		hud.visible = true

func _wait_for_door_traversal() -> void:
	var frames: int = 0
	while map_view != null and bool(map_view.get("movement_active")) and bool(map_view.get("movement_door")) and frames < 45:
		await get_tree().process_frame
		frames += 1
	if frames >= 45 and map_view != null:
		map_view._reset_movement_state()

func _try_reveal_screen_transition() -> void:
	if not transition_reveal_pending or not transition_map_ready or not transition_screen_ready:
		return
	_reveal_screen_transition()
	if map_view != null:
		map_view.set_transition_active(false)
		map_view.set_input_enabled(true)

func _force_reveal_screen_transition() -> void:
	# Escape hatch for indoor Hoenn warps that never get map/screen ready.
	if not transition_reveal_pending:
		return
	transition_map_ready = true
	transition_screen_ready = true
	_try_reveal_screen_transition()

func _cover_screen_transition() -> void:
	if transition_overlay == null:
		return
	if transition_tween != null:
		transition_tween.kill()
	transition_overlay.visible = true
	transition_overlay.color = Color(0.0, 0.0, 0.0, 1.0)
	if map_view != null:
		map_view.visible = false
	if hud != null:
		hud.visible = false

func _reveal_screen_transition() -> void:
	transition_reveal_pending = false
	transition_map_ready = false
	transition_screen_ready = false
	if map_view != null:
		map_view.visible = true
	if hud != null:
		hud.visible = true
	if transition_overlay == null:
		return
	if transition_tween != null:
		transition_tween.kill()
	transition_overlay.visible = true
	transition_overlay.color = Color(0.0, 0.0, 0.0, 1.0)
	transition_tween = create_tween()
	transition_tween.tween_property(transition_overlay, "color", Color(0.0, 0.0, 0.0, 0.0), 0.12)
	transition_tween.tween_callback(func() -> void:
		if transition_overlay != null:
			transition_overlay.visible = false
	)

func _sync_map_entities() -> void:
	if map_view == null:
		return
	var players: Array = []
	for key in entities:
		var entity: Dictionary = (entities[key] as Dictionary).duplicate()
		if _story_hides_entity(entity):
			continue
		var entity_id: int = int(entity.get("entity_id", entity.get("character_id", entity.get("user_id", 0))))
		entity["battle"] = bool(GameState.battle_presence.get(str(entity_id), false))
		players.append(entity)
	map_view.set_world_entities(players, selected_character_id)

func _on_battle_event(value: Dictionary) -> void:
	match str(value.get("type", "")):
		"field_state":
			var battle_value: Variant = value.get("state", {})
			trainer_battle_dialogue_pending = bool((battle_value as Dictionary).get("trainer", false)) if battle_value is Dictionary else false
		"presence":
			_sync_map_entities()

func _on_follow_requested(party_index: int) -> void:
	if map_view != null:
		map_view.set_following_party_index(party_index)

func _on_character_state_changed(value: Dictionary) -> void:
	for key in ["money", "bag", "party"]:
		if value.has(key):
			snapshot[key] = value[key]
	if hud != null:
		var party: Array = value.get("party", []) if value.get("party", []) is Array else []
		hud.set_state(GameState.content, str(snapshot.get("map_id", "")), snapshot, party)

func _on_story_state_changed(_value: Dictionary) -> void:
	_sync_map_entities()

func _on_story_state_resynced(_value: Dictionary) -> void:
	removed_npc_entities.clear()
	npc_entity_maps.clear()
	ignore_stale_entity_removals = true
	_sync_map_entities()

func _on_shop_catalog(catalog: Dictionary) -> void:
	if dialogue_overlay != null and dialogue_overlay.is_open():
		dialogue_overlay.close_dialogue()
	if map_view != null:
		map_view.set_dialogue_active(bool(catalog.get("open", false)))
		map_view.set_input_enabled(not bool(catalog.get("open", false)))
	if hud != null:
		hud.show_shop(catalog)

func _on_shop_buy_requested(item_id: int, quantity: int, exchange_type_index: int) -> void:
	GameState.send_shop_buy(item_id, quantity, exchange_type_index)

func _on_shop_sell_requested(item_entity_id: int, quantity: int) -> void:
	GameState.send_shop_sell(item_entity_id, quantity)

func _on_shop_closed() -> void:
	if map_view != null:
		map_view.set_dialogue_active(false)
		map_view.set_input_enabled(true)

func set_battle_overlay_active(value: bool) -> void:
	if map_view != null:
		map_view.set_input_enabled(not value)

func _retain_server_entities_for_map(target_map_id: String) -> void:
	var retained: Dictionary = {}
	for key in entities:
		var value: Variant = entities[key]
		if not value is Dictionary:
			continue
		var entity: Dictionary = value
		var is_local: bool = int(entity.get("character_id", 0)) == selected_character_id or int(entity.get("entity_id", 0)) == selected_character_id
		if is_local:
			entity["map_id"] = target_map_id
			retained[key] = entity
		elif str(entity.get("map_id", "")) == target_map_id:
			retained[key] = entity
	entities = retained

func _apply_local_spawn_for_map(map_id: String) -> void:
	if map_view == null or GameState.content == null or map_id.is_empty():
		return
	var map_value: Dictionary = GameState.content.map_data(map_id)
	var width: int = int(map_value.get("width", 0))
	var height: int = int(map_value.get("height", 0))
	var x: int = int(GameState.current_character.get("x", -1))
	var y: int = int(GameState.current_character.get("y", -1))
	if width > 0 and height > 0 and (x < 0 or y < 0 or x >= width or y >= height):
		var spawn: Dictionary = GameState.content.default_spawn(map_id)
		if bool(spawn.get("ok", false)):
			x = int(spawn.get("x", 0))
			y = int(spawn.get("y", 0))
		else:
			x = int(width / 2)
			y = int(height / 2)
	var facing: int = int(GameState.current_character.get("facing", map_view.player_facing))
	var elevation: int = int(GameState.current_character.get("elevation", map_view.player_elevation))
	map_view.set_player_state(x, y, elevation, facing)
	GameState.current_character["x"] = x
	GameState.current_character["y"] = y
	GameState.current_character["map_id"] = map_id

func _cache_story_objects(map_id: String, values: Variant) -> void:
	if map_id.is_empty() or not values is Array:
		return
	var entries: Array = []
	for value in values as Array:
		if not value is Dictionary:
			continue
		var object: Dictionary = value
		var hide_flag_id: int = int(object.get("hide_flag_id", 0))
		if str(object.get("kind", "")) != "object" or hide_flag_id <= 0:
			continue
		entries.append({"x": int(object.get("x", 0)), "y": int(object.get("y", 0)), "hide_flag_id": hide_flag_id})
	story_objects_by_map[map_id] = entries

func _story_hides_entity(entity: Dictionary) -> bool:
	if not bool(entity.get("npc", false)) or bool(entity.get("story_cutscene_spawn", false)):
		return false
	var map_id: String = str(entity.get("map_id", ""))
	var objects_value: Variant = story_objects_by_map.get(map_id, [])
	if not objects_value is Array:
		return false
	var region_id: int = int(entity.get("region_id", GameState.story_region_id))
	var entity_x: int = int(entity.get("x", -1))
	var entity_y: int = int(entity.get("y", -1))
	for object_value in objects_value as Array:
		if not object_value is Dictionary:
			continue
		var object: Dictionary = object_value
		if int(object.get("x", -2)) != entity_x or int(object.get("y", -2)) != entity_y:
			continue
		var hide_flag_id: int = int(object.get("hide_flag_id", 0))
		if GameState.is_story_flag_set(region_id, hide_flag_id) or _oaks_lab_scene_hides(map_id, region_id, hide_flag_id):
			return true
	return false

func _oaks_lab_scene_hides(map_id: String, region_id: int, hide_flag_id: int) -> bool:
	if not _is_oaks_lab_map(map_id):
		return false
	var scene: int = GameState.story_variable(region_id, 0x55, -1)
	if scene < 0:
		return false
	if hide_flag_id >= 40 and hide_flag_id <= 42:
		return scene >= 3
	return hide_flag_id == 45 and scene >= 4

func _is_oaks_lab_map(map_id: String) -> bool:
	var normalized: String = map_id.to_lower().replace("_", "").replace("-", "")
	if normalized.contains("palletoakslab") or normalized.contains("pallettownprofessoroakslab"):
		return true
	if GameState.content == null:
		return false
	var map_value: Dictionary = GameState.content.map_data(map_id)
	var map_name: String = str(map_value.get("name", "")).to_lower().replace("_", "").replace("-", "")
	return map_name.contains("pallettown") and map_name.contains("oak") and map_name.contains("lab")

func _process(delta: float) -> void:
	if debug_panel != null and debug_panel.visible:
		_update_debug_panel(delta)

func _on_chat(value: Dictionary) -> void:
	if chat_box != null:
		chat_box.add_message(value)

func _send_chat(text: String, channel: String = "Normal") -> void:
	var trimmed := text.strip_edges()
	if not trimmed.is_empty() and GameState.send_chat(trimmed, channel):
		chat_box.clear_input()

func _on_connection_error(message: String) -> void:
	status_label.text = message

func _on_interaction_requested(dialogue: Dictionary) -> void:
	if dialogue_overlay == null or dialogue.is_empty() or dialogue_overlay.is_open():
		return
	var pages: Array = dialogue.get("pages", [])
	if pages.is_empty():
		pages = [str(dialogue.get("text", ""))]
	pages = _resolve_dialogue_pages(pages)
	var choices: Array = dialogue.get("choices", [])
	# Bottom message box (FR/PokeMMO style); actor-anchored panels were huge and clipped short pages.
	var dialogue_anchor: Vector2 = Vector2(-1.0, -1.0)
	if choices.is_empty():
		dialogue_overlay.show_pages(pages, false, dialogue_anchor)
	else:
		dialogue_overlay.show_choice(pages, choices, false, dialogue_anchor)
	map_view.set_dialogue_active(true)
	audio.play_effect("dialogue")

func _on_dialog_action_received(action: Dictionary) -> void:
	if dialogue_overlay == null or map_view == null:
		return
	var action_type: int = int(action.get("action_type", -1))
	if action_type == 0x64:
		server_dialogue_active = false
		server_dialogue_action_type = -1
		server_dialogue_detail = PackedByteArray()
		trainer_battle_dialogue_pending = false
		dialogue_overlay.close_dialogue()
		map_view.set_dialogue_active(false)
		map_view.restore_interaction_facing()
		return
	server_dialogue_action_type = action_type
	server_dialogue_detail = action.get("detail", PackedByteArray()) if action.get("detail", PackedByteArray()) is PackedByteArray else PackedByteArray()
	_update_dialogue_string_vars(action)
	var text_id: int = int(action.get("text_id", 0))
	var pages: Array = _streamed_dialogue_pages(action.get("detail", PackedByteArray()))
	if pages.is_empty() and text_id != 0:
		var rom_content: OpenMMOContent = GameState.content_for_text_id(text_id)
		var dialogue: Dictionary = rom_content.dialogue_for_text_id(text_id) if rom_content != null else {}
		pages = dialogue.get("pages", []) if not dialogue.is_empty() else []
		if bool(dialogue.get("stub", false)):
			var tag: int = (text_id >> 24) & 0xFF
			var game: String = str(rom_content.source_profile.get("game", "ROM")) if rom_content != null else ""
			if tag == 0x10 and game != "Emerald":
				pages = ["Hoenn story text uses Emerald ROM offsets. Select Pokemon Emerald for readable dialogue (got %s)." % game]
	if pages.is_empty() and text_id != 0:
		var tag2: int = (text_id >> 24) & 0xFF
		if tag2 == 0x10 and GameState.content_for_region("hoenn") == null:
			pages = ["Hoenn dialogue 0x%08X needs a loaded Hoenn ROM (Emerald preferred)." % text_id]
		else:
			pages = ["Dialogue text 0x%08X is unavailable in the selected ROM." % text_id]
	var preview_species: int = _dialogue_preview_species(action, pages)
	pages = _resolve_dialogue_pages(pages)
	var actor: Dictionary = {}
	var entity_id: int = int(action.get("entity_id", -1))
	var entity_value: Variant = entities.get(str(entity_id), {})
	if entity_value is Dictionary:
		actor = (entity_value as Dictionary).duplicate()
	if actor.is_empty():
		actor = {"map_id": map_view.map_id, "x": map_view.player_position.x, "y": map_view.player_position.y, "elevation": map_view.player_elevation}
	server_dialogue_active = true
	server_dialogue_sequence = int(action.get("flags", 0)) & 0xFF
	map_view.set_dialogue_active(true)
	# Keep the classic bottom textbox; actor anchoring left a tall empty panel over the map.
	var anchor: Vector2 = Vector2(-1.0, -1.0)
	var choices: Array = _server_dialogue_choices(action_type, server_dialogue_detail)
	if choices.is_empty():
		dialogue_overlay.show_pages(pages, false, anchor)
	else:
		dialogue_overlay.show_choice(pages, choices, false, anchor)
	dialogue_overlay.set_pokemon_preview(preview_species)
	if preview_species <= 0 and trainer_battle_dialogue_pending:
		var actor_sprite: Dictionary = map_view.dialogue_actor_sprite(entity_id)
		dialogue_overlay.set_actor_preview(actor_sprite.get("texture") as Texture2D)
	audio.play_effect("dialogue")

func _dialogue_preview_species(action: Dictionary, pages: Array) -> int:
	var args_value: Variant = action.get("message_args", [])
	if args_value is Array:
		for arg_value in args_value as Array:
			if not arg_value is Dictionary:
				continue
			var arg: Dictionary = arg_value
			if str(arg.get("tag", "")) == "pokemon_species":
				return int(arg.get("species_id", 0))
	if int(action.get("action_type", -1)) != 0x05:
		return 0
	for species_id in [1, 4, 7]:
		var species_name: String = _pokemon_choice_name(species_id).to_upper()
		if species_name.is_empty():
			continue
		for page_value in pages:
			if str(page_value).to_upper().contains(species_name):
				return species_id
	return 0

func _server_dialogue_choices(action_type: int, detail_value: Variant) -> Array:
	if action_type == 0x05:
		return [{"label": "Yes", "value": 1}, {"label": "No", "value": 0}]
	if action_type != 0x23 or not detail_value is PackedByteArray:
		return []
	var detail: PackedByteArray = detail_value
	var count: int = int(detail[0]) if not detail.is_empty() else 0
	var choices: Array = []
	for index in mini(count, 6):
		var offset: int = 1 + index * 2
		if offset + 1 >= detail.size():
			break
		var species_id: int = int(detail[offset]) | (int(detail[offset + 1]) << 8)
		choices.append({"label": _pokemon_choice_name(species_id), "value": index + 1})
	if choices.is_empty():
		for index in 3:
			choices.append({"label": "POKEMON %d" % (index + 1), "value": index + 1})
	return choices

func _pokemon_choice_name(species_id: int) -> String:
	if GameState.content != null and species_id > 0:
		return GameState.content.battle_pokemon_name(species_id)
	return "POKEMON #%d" % species_id

func _resolve_dialogue_pages(pages: Array) -> Array:
	var values: Dictionary = _dialogue_placeholder_values()
	var regex: RegEx = RegEx.new()
	regex.compile("\\{(0x[0-9A-Fa-f]{2}|[0-9A-Fa-f]{2}|[A-Za-z0-9_]+)\\}")
	var resolved: Array = []
	# Cap pathological Hoenn floods only; never truncate real Kanto pages mid-sentence.
	var page_limit: int = mini(pages.size(), 64)
	for page_index in page_limit:
		var page: String = str(pages[page_index])
		var matches: Array[RegExMatch] = regex.search_all(page)
		if matches.is_empty():
			if _dialogue_page_is_placeholder_spam(page):
				continue
			resolved.append(page)
			continue
		var output: String = ""
		var cursor: int = 0
		for match in matches:
			output += page.substr(cursor, match.get_start() - cursor)
			var key: String = str(match.get_string(1)).to_upper().trim_prefix("0X")
			if values.has(key):
				output += str(values[key])
			else:
				# Keep unknown braces (do not delete mid-sentence fragments).
				output += match.get_string(0)
			cursor = match.get_end()
		output += page.substr(cursor)
		if _dialogue_page_is_placeholder_spam(output):
			continue
		resolved.append(output)
	if resolved.is_empty() and not pages.is_empty():
		resolved.append("...")
	return resolved

func _dialogue_page_is_placeholder_spam(page: String) -> bool:
	# Drop Hoenn placeholder / decode-garbage floods; never filter ordinary Kanto dialogue.
	var upper: String = page.to_upper()
	var team_hits: int = upper.count("MAGMA") + upper.count("AQUA") + upper.count("MAXIE") + upper.count("ARCHIE")
	if team_hits >= 6 and page.count("{") + team_hits >= 8:
		return true
	var question_marks: int = page.count("?")
	if question_marks >= 8 and question_marks * 2 >= page.length():
		return true
	if page.count("\n") >= 80:
		return true
	return false

func _dialogue_placeholder_values() -> Dictionary:
	var character_name: String = str(GameState.current_character.get("name", ""))
	var region_name: String = "Kanto"
	var version_name: String = "FireRed"
	if GameState.content != null:
		var profile_value: Variant = GameState.content.get("source_profile")
		if profile_value is Dictionary:
			var profile: Dictionary = profile_value
			region_name = str(profile.get("region", region_name))
			var source_game: String = str(profile.get("game", profile.get("name", ""))).strip_edges()
			if not source_game.is_empty():
				version_name = source_game
	var vars: Dictionary = {}
	var character_vars: Variant = GameState.current_character.get("string_vars", {})
	if character_vars is Dictionary:
		vars.merge(character_vars)
	vars.merge(dialogue_string_vars)
	var party: Variant = GameState.current_character.get("party", [])
	var party_names: Array = []
	if party is Array:
		for pokemon in party:
			party_names.append(_dialogue_pokemon_name(pokemon))
	var string_1: String = str(vars.get("02", vars.get("STRING_VAR_1", "")))
	var string_2: String = str(vars.get("03", vars.get("STRING_VAR_2", "")))
	var string_3: String = str(vars.get("04", vars.get("STRING_VAR_3", "")))
	if string_1.is_empty() and party_names.size() > 0:
		string_1 = str(party_names[0])
	if string_2.is_empty() and party_names.size() > 1:
		string_2 = str(party_names[1])
	if string_3.is_empty() and party_names.size() > 2:
		string_3 = str(party_names[2])
	if string_1.is_empty():
		string_1 = "POKEMON"
	var rival_name: String = str(GameState.current_character.get("rival_name", "")).strip_edges()
	if rival_name.is_empty():
		rival_name = "RED" if int(GameState.current_character.get("rival_sex", 0)) == 1 else "GREEN"
	var values: Dictionary = {"00": str(vars.get("00", "")), "01": character_name, "02": string_1, "03": string_2, "04": string_3, "05": "KUN", "06": rival_name, "07": version_name, "08": "MAGMA", "09": "AQUA", "0A": "MAXIE", "0B": "ARCHIE", "0C": "GROUDON", "0D": "KYOGRE", "PLAYER": character_name, "PLAYER_NAME": character_name, "STRING_VAR_1": string_1, "STRING_VAR_2": string_2, "STRING_VAR_3": string_3, "STR_VAR_1": string_1, "STR_VAR_2": string_2, "STR_VAR_3": string_3, "RIVAL": rival_name, "RIVAL_NAME": rival_name, "REGION": region_name, "KUN": "KUN", "CHAN": "CHAN", "VERSION": version_name, "DYNAMIC": "", "CONTROL": ""}
	return values

func _dialogue_pokemon_name(value: Variant) -> String:
	if not value is Dictionary:
		return "POKEMON"
	var pokemon: Dictionary = value
	var nickname: String = str(pokemon.get("nickname", "")).strip_edges()
	if not nickname.is_empty():
		return nickname
	return _pokemon_choice_name(int(pokemon.get("dex_id", pokemon.get("species", 0))))

func _update_dialogue_string_vars(action: Dictionary) -> void:
	var args_value: Variant = action.get("message_args", [])
	if not args_value is Array:
		return
	for arg_value in args_value:
		if not arg_value is Dictionary:
			continue
		var arg: Dictionary = arg_value
		if str(arg.get("tag", "")) != "pokemon_species":
			continue
		var variable: int = int(arg.get("string_variable", 2))
		var value: String = _pokemon_choice_name(int(arg.get("species_id", 0)))
		dialogue_string_vars["%02X" % variable] = value
		dialogue_string_vars["STRING_VAR_%d" % maxi(variable - 1, 1)] = value

func _streamed_dialogue_pages(detail_value: Variant) -> Array:
	if not detail_value is PackedByteArray:
		return []
	var detail: PackedByteArray = detail_value
	var marker: PackedByteArray = PackedByteArray([0x4F, 0x4D, 0x54, 0x58, 0x54, 0x00])
	if detail.size() <= marker.size():
		return []
	for index in marker.size():
		if detail[index] != marker[index]:
			return []
	var pages: Array = []
	for page in detail.slice(marker.size()).get_string_from_utf8().split("\f"):
		if not str(page).is_empty():
			pages.append(page)
	return pages

func _on_dialog_state_received(open: bool) -> void:
	server_dialogue_active = open
	map_view.set_dialogue_active(open)
	if not open:
		dialogue_overlay.close_dialogue()
		map_view.restore_interaction_facing()

func _on_dialogue_action() -> void:
	audio.play_effect("dialogue")
	if server_dialogue_active:
		if dialogue_overlay != null and dialogue_overlay.is_open():
			var choice_commit: bool = dialogue_overlay.is_choice_open() and dialogue_overlay.text_complete()
			dialogue_overlay.handle_action()
			# Advance local pages / finish typing; choice emits choice_requested for the response path.
			if dialogue_overlay.is_open() or choice_commit:
				return
		GameState.send_dialogue_action_response(server_dialogue_sequence, 0)
		map_view.restore_interaction_facing()
		return
	if dialogue_overlay != null and dialogue_overlay.handle_action() and not dialogue_overlay.is_open():
		map_view.set_dialogue_active(false)
		map_view.restore_interaction_facing()

func _on_dialogue_choice(value: int) -> void:
	audio.play_effect("dialogue")
	if server_dialogue_active:
		if server_dialogue_action_type == 0x23 and value > 0:
			for choice_value in _server_dialogue_choices(server_dialogue_action_type, server_dialogue_detail):
				if not choice_value is Dictionary or int((choice_value as Dictionary).get("value", 0)) != value:
					continue
				var selected_name: String = str((choice_value as Dictionary).get("label", "POKEMON"))
				dialogue_string_vars["02"] = selected_name
				dialogue_string_vars["STRING_VAR_1"] = selected_name
				break
		if GameState.send_dialogue_action_response(server_dialogue_sequence, value):
			if dialogue_overlay != null:
				dialogue_overlay.close_dialogue()
			map_view.restore_interaction_facing()
		return
	if dialogue_overlay != null:
		dialogue_overlay.close_dialogue()
	map_view.set_dialogue_active(false)
	map_view.restore_interaction_facing()

func _on_sound_requested(effect: String) -> void:
	audio.play_effect(effect)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if key_event.keycode == KEY_F3 and key_event.pressed and not key_event.echo:
		_toggle_debug_panel()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_B and key_event.pressed and not key_event.echo:
		if hud != null:
			hud.toggle_bag()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_M and key_event.pressed and not key_event.echo:
		if hud != null:
			hud.toggle_menu()
		get_viewport().set_input_as_handled()
		return
	var hotkey_slot: int = _hotkey_slot_for_key(key_event.keycode)
	if hotkey_slot >= 0 and key_event.pressed and not key_event.echo:
		if hud != null:
			hud.activate_hotkey(hotkey_slot)
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode in [KEY_F, KEY_E, KEY_Z, KEY_X] and key_event.pressed and not key_event.echo:
		get_viewport().set_input_as_handled()
		if dialogue_overlay == null or not dialogue_overlay.is_open():
			map_view.interact()
		return
	if key_event.pressed and not key_event.echo and chat_box != null and not chat_box.input_focused() and key_event.keycode in [KEY_ENTER, KEY_T, KEY_SLASH]:
		chat_box.focus_input("/" if key_event.keycode == KEY_SLASH else "")
		get_viewport().set_input_as_handled()
		return
	if dialogue_overlay != null and dialogue_overlay.is_open():
		return
	return

func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	var is_semicolon: bool = key_event.keycode == KEY_SEMICOLON or key_event.physical_keycode == KEY_SEMICOLON
	if is_semicolon and key_event.ctrl_pressed and key_event.shift_pressed and key_event.pressed and not key_event.echo:
		_toggle_debug_panel()
		get_viewport().set_input_as_handled()

func _hotkey_slot_for_key(keycode: int) -> int:
	match keycode:
		KEY_1: return 0
		KEY_2: return 1
		KEY_3: return 2
		KEY_4: return 3
		KEY_5: return 4
		KEY_6: return 5
		KEY_7: return 6
		KEY_8: return 7
		KEY_9: return 8
	return -1
