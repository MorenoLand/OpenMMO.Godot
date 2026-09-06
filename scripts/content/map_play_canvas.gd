class_name OpenMMOMapPlayCanvas
extends Control

signal location_changed(map_id: String, x: int, y: int)
signal back_requested
signal interaction_requested(dialogue: Dictionary)
signal sound_requested(effect: String)

const TILE_PIXELS: float = 16.0
const CAMERA_MAX_CELLS_X: int = 30
const CAMERA_MAX_CELLS_Y: int = 20
const MAX_TILE_SCALE: float = 4.0
const REFERENCE_VIEWPORT_SIZE: Vector2 = Vector2(1280.0, 720.0)
const NORMAL_STEP_DURATION: float = 0.17
const PLAYER_WALK_ANIMATION_RATE: float = 0.9
const ANIMATION_FRAME_INTERVAL: float = 0.125
const DOOR_ANIMATION_DURATION: float = 16.0 / 60.0
const DOOR_TRAVERSAL_DURATION: float = 44.0 / 60.0
const DOOR_FRAME_COUNT: int = 4
const AUTHORITATIVE_PROBE_INTERVAL: float = 0.2

var content
var map_id: String = ""
var map_texture: Texture2D
var foreground_texture: Texture2D
var map_pixel_size: Vector2 = Vector2.ZERO
var objects: Array = []
var regions: Array = []
var region_origins: Dictionary = {}
var world_bounds: Rect2 = Rect2()
var player_position: Vector2i = Vector2i.ZERO
var player_elevation: int = 3
var player_texture: Texture2D
var player_texture_key: String = ""
var animation_tick: int = 0
var animation_elapsed: float = 0.0
var movement_active: bool = false
var movement_scripted: bool = false
var movement_scripted_action: int = -1
var movement_animation_active: bool = false
var movement_unvalidated: bool = false
var movement_start: Vector2 = Vector2.ZERO
var movement_target: Vector2 = Vector2.ZERO
var movement_jump: bool = false
var exclaim_timer: float = 0.0
var movement_stair: bool = false
var movement_stair_behavior: int = 0
var movement_door: bool = false
var movement_door_position: Vector2i = Vector2i.ZERO
var door_progress: float = 0.0
var movement_elapsed: float = 0.0
var movement_duration: float = 0.14
var pending_map_id: String = ""
var pending_position: Vector2i = Vector2i.ZERO
var pending_elevation: int = 3
var pending_warp: Dictionary = {}
var warp_cooldown: float = 0.0
var has_spawn: bool = false
var input_enabled: bool = false
var player_facing: int = 1
var held_direction: int = 0
var local_entity_id: int = 0
var player_visible: bool = true
var scripted_movement_queue: Array = []
var pending_scripted_movements: Dictionary = {}
var movement_retry_elapsed: float = 0.0
var authoritative_probe_pending: bool = false
var authoritative_probe_elapsed: float = 0.0
var world_entities: Array = []
var authoritative_state: bool = false
var transition_active: bool = false
var dialogue_active: bool = false
var following_party_index: int = -1
var follower_texture: Texture2D
var follower_frames: Array = []
var follower_species_id: int = 0
var follower_texture_key: String = ""
var follower_width: float = 0.0
var follower_height: float = 0.0
var follower_position: Vector2 = Vector2.ZERO
var follower_initialized: bool = false
var follower_facing: int = 1
var follower_movement_active: bool = false
var follower_movement_start: Vector2 = Vector2.ZERO
var follower_movement_target: Vector2 = Vector2.ZERO
var follower_movement_elapsed: float = 0.0
var follower_step_queue: Array[Vector2] = []
var follower_owner_step_key: String = ""
var resize_redraw_pending: bool = false
var connected_preload_generation: int = 0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	resized.connect(_on_resized)
	queue_redraw()

func _on_resized() -> void:
	if resize_redraw_pending:
		return
	resize_redraw_pending = true
	call_deferred("_finish_resize")

func _finish_resize() -> void:
	resize_redraw_pending = false
	if is_inside_tree():
		queue_redraw()

func set_content(value) -> void:
	content = value
	player_texture = null
	player_texture_key = ""
	foreground_texture = null
	follower_texture = null
	follower_frames.clear()
	follower_texture_key = ""
	if not map_id.is_empty():
		_set_spawn()
	_refresh_object_textures()
	queue_redraw()

func set_input_enabled(value: bool) -> void:
	input_enabled = value
	if value:
		call_deferred("_restore_input_focus")
	else:
		_reset_movement_state(true)
		authoritative_probe_pending = false
		authoritative_probe_elapsed = 0.0

func set_transition_active(value: bool) -> void:
	if transition_active == value:
		return
	transition_active = value
	if value:
		_reset_movement_state(true)
		if authoritative_state:
			has_spawn = false
	else:
		if input_enabled:
			call_deferred("_restore_input_focus")

func _restore_input_focus() -> void:
	if input_enabled and is_inside_tree():
		grab_focus()

func _text_input_has_focus() -> bool:
	var focus_owner: Control = get_viewport().gui_get_focus_owner() as Control
	return focus_owner is LineEdit or focus_owner is TextEdit

func set_dialogue_active(value: bool) -> void:
	dialogue_active = value
	if value:
		held_direction = 0
		movement_retry_elapsed = 0.0
	else:
		_restore_interaction_facing()

func set_following_party_index(index: int) -> void:
	following_party_index = index
	follower_initialized = false
	follower_texture = null
	follower_frames.clear()
	follower_species_id = 0
	follower_texture_key = ""
	follower_width = 0.0
	follower_height = 0.0
	follower_movement_active = false
	follower_movement_elapsed = 0.0
	follower_step_queue.clear()
	follower_owner_step_key = ""
	if index >= 0:
		_update_follower_texture()
	queue_redraw()

func _update_follower_texture() -> void:
	if following_party_index < 0 or content == null:
		return
	var party_value: Variant = GameState.current_character.get("party", [])
	if not party_value is Array or following_party_index >= (party_value as Array).size():
		follower_texture = null
		follower_frames.clear()
		follower_species_id = 0
		return
	var member_value: Variant = (party_value as Array)[following_party_index]
	if not member_value is Dictionary:
		return
	var species_id: int = int((member_value as Dictionary).get("dex_id", (member_value as Dictionary).get("species_id", (member_value as Dictionary).get("species", 0))))
	if species_id <= 0:
		follower_texture = null
		follower_frames.clear()
		follower_species_id = 0
		follower_texture_key = ""
		follower_width = 0.0
		follower_height = 0.0
		return
	var member: Dictionary = member_value as Dictionary
	var gender: int = int(member.get("gender", -1))
	var shiny: bool = bool(member.get("shiny", member.get("is_shiny", false)))
	var form: int = int(member.get("form", member.get("forme", member.get("form_id", 0))))
	var texture_key: String = "%d:%d:%d:%d" % [species_id, gender, int(shiny), form]
	if texture_key == follower_texture_key:
		return
	follower_texture_key = texture_key
	var sprite: Dictionary = content.follower_pokemon_sprite(species_id, gender, shiny, form)
	var frames_value: Variant = sprite.get("frames", [])
	follower_frames = (frames_value as Array).duplicate() if frames_value is Array else []
	follower_texture = follower_frames[0] as Texture2D if not follower_frames.is_empty() else sprite.get("texture") as Texture2D
	follower_species_id = species_id if follower_texture != null else 0
	follower_width = float(sprite.get("width", 0)) if follower_texture != null else 0.0
	follower_height = float(sprite.get("height", 0)) if follower_texture != null else 0.0

func _update_follower(delta: float) -> void:
	if following_party_index < 0 or not has_spawn or content == null:
		return
	_update_follower_texture()
	if follower_texture == null:
		return
	var player_world: Vector2 = _movement_world_position()
	var player_direction: Vector2 = _direction_vector(player_facing)
	if player_direction == Vector2.ZERO:
		player_direction = Vector2.UP
	if not follower_initialized or follower_position.distance_to(player_world) > 3.0:
		follower_position = (_world_position(map_id, movement_start) if movement_active else player_world) - player_direction
		follower_initialized = true
		follower_facing = player_facing
		follower_movement_active = false
		follower_step_queue.clear()
		follower_owner_step_key = ""
	if movement_active:
		var owner_start: Vector2 = _world_position(map_id, movement_start)
		var owner_target: Vector2 = _world_position(pending_map_id, pending_position) if region_origins.has(pending_map_id) else owner_start + _direction_vector(player_facing)
		var step_key: String = "%s:%.3f:%.3f:%.3f:%.3f" % [map_id, owner_start.x, owner_start.y, owner_target.x, owner_target.y]
		if step_key != follower_owner_step_key:
			follower_owner_step_key = step_key
			if follower_step_queue.is_empty() or follower_step_queue.back().distance_to(owner_start) > 0.01:
				follower_step_queue.append(owner_start)
	if not follower_movement_active and not follower_step_queue.is_empty():
		follower_movement_start = follower_position
		follower_movement_target = follower_step_queue.pop_front()
		var travel: Vector2 = follower_movement_target - follower_movement_start
		if travel.length() > 2.5:
			follower_position = follower_movement_target
		else:
			follower_facing = 4 if absf(travel.x) > absf(travel.y) and travel.x > 0.0 else 3 if absf(travel.x) > absf(travel.y) else 1 if travel.y > 0.0 else 2
			follower_movement_elapsed = 0.0
			follower_movement_active = travel.length() > 0.01
	if follower_movement_active:
		follower_movement_elapsed = minf(follower_movement_elapsed + delta, NORMAL_STEP_DURATION)
		var progress: float = follower_movement_elapsed / NORMAL_STEP_DURATION
		follower_position = follower_movement_start.lerp(follower_movement_target, progress)
		_set_follower_frame(1 if progress >= 0.5 else 0)
		if follower_movement_elapsed >= NORMAL_STEP_DURATION:
			follower_position = follower_movement_target
			follower_movement_active = false
			_set_follower_frame(0)
	else:
		_set_follower_frame(0)

func _set_follower_frame(gait_frame: int) -> void:
	if follower_frames.size() < 8:
		return
	var direction_offset: int = 0 if follower_facing == 1 else 2 if follower_facing == 2 else 4 if follower_facing == 3 else 6
	follower_texture = follower_frames[direction_offset + clampi(gait_frame, 0, 1)] as Texture2D

func set_local_entity_id(value: int) -> void:
	local_entity_id = value

func set_authoritative_state(value: bool) -> void:
	authoritative_state = value
	objects = objects_for_mode(objects)
	held_direction = 0
	authoritative_probe_pending = false
	authoritative_probe_elapsed = 0.0
	movement_unvalidated = false

func objects_for_mode(values: Variant) -> Array:
	if not values is Array:
		return []
	var source: Array = values as Array
	if not authoritative_state:
		return source
	var filtered: Array = []
	for value in source:
		if value is Dictionary and str((value as Dictionary).get("kind", "")) == "object":
			continue
		filtered.append(value)
	return filtered

func _reset_movement_state(clear_direction: bool = false) -> void:
	movement_active = false
	movement_scripted = false
	movement_scripted_action = -1
	movement_animation_active = false
	scripted_movement_queue.clear()
	movement_unvalidated = false
	movement_start = Vector2.ZERO
	movement_target = Vector2.ZERO
	movement_jump = false
	movement_stair = false
	movement_stair_behavior = 0
	movement_door = false
	movement_door_position = Vector2i.ZERO
	door_progress = 0.0
	movement_elapsed = 0.0
	pending_map_id = ""
	pending_position = player_position
	pending_elevation = player_elevation
	pending_warp = {}
	authoritative_probe_pending = false
	authoritative_probe_elapsed = 0.0
	movement_retry_elapsed = 0.0
	if clear_direction:
		held_direction = 0

func set_animation_tick(value: int) -> void:
	animation_tick = value
	queue_redraw()

func request_move(direction_name: String) -> bool:
	var direction: int = 0
	match direction_name.to_lower():
		"down":
			direction = 1
		"up":
			direction = 2
		"left":
			direction = 3
		"right":
			direction = 4
	if direction == 0:
		return false
	return _request_move(direction)

func set_map(texture: Texture2D, map_width: int, map_height: int, map_objects: Array, selected_map_id: String = "", map_foreground_texture: Texture2D = null) -> void:
	var changed: bool = not selected_map_id.is_empty() and map_id != selected_map_id
	var visible_objects: Array = objects_for_mode(map_objects)
	if not selected_map_id.is_empty():
		map_id = selected_map_id
	regions = [{"map_id": map_id, "origin": Vector2i.ZERO, "width": map_width, "height": map_height, "render_origin": Vector2i.ZERO, "render_width": map_width, "render_height": map_height, "background_texture": texture, "foreground_texture": map_foreground_texture, "objects": visible_objects, "ready": true}]
	region_origins = {map_id: Vector2i.ZERO}
	_rebuild_world_bounds()
	map_texture = texture
	foreground_texture = map_foreground_texture
	map_pixel_size = Vector2(map_width * 16, map_height * 16)
	objects = visible_objects
	if changed or not has_spawn:
		if authoritative_state:
			has_spawn = false
			player_visible = true
			movement_active = false
			movement_unvalidated = false
			pending_map_id = ""
			pending_warp = {}
		else:
			_set_spawn()
	_refresh_object_textures()
	if animation_tick > 0:
		set_animation_tick(animation_tick)
	_update_player_texture()
	queue_redraw()

func set_world(world_value: Dictionary, selected_map_id: String = "") -> void:
	var previous_map_id: String = map_id
	regions = world_value.get("regions", []) if world_value.get("regions", []) is Array else []
	region_origins = {}
	for region_value in regions:
		if region_value is Dictionary:
			var region: Dictionary = region_value
			var region_id: String = str(region.get("map_id", ""))
			if not region_id.is_empty():
				region_origins[region_id] = region.get("origin", Vector2i.ZERO)
	_rebuild_world_bounds()
	var next_map_id: String = selected_map_id
	if next_map_id.is_empty():
		next_map_id = str(world_value.get("root_map_id", map_id))
	if next_map_id.is_empty() or not region_origins.has(next_map_id):
		return
	map_id = next_map_id
	_set_active_region(map_id)
	var changed: bool = previous_map_id != map_id
	if changed:
		_reset_movement_state(true)
		player_visible = true
		if authoritative_state:
			has_spawn = false
		elif not has_spawn:
			_set_spawn()
	elif not has_spawn and not authoritative_state:
		_set_spawn()
	_refresh_object_textures()
	if animation_tick > 0:
		set_animation_tick(animation_tick)
	_update_player_texture()
	queue_redraw()

func set_active_map(selected_map_id: String) -> bool:
	if selected_map_id.is_empty() or not region_origins.has(selected_map_id):
		return false
	if not _ensure_region_rendered(selected_map_id):
		return false
	var changed: bool = map_id != selected_map_id
	map_id = selected_map_id
	if changed:
		_reset_movement_state(true)
		player_visible = true
		if authoritative_state:
			has_spawn = false
	_set_active_region(map_id)
	_update_player_texture()
	queue_redraw()
	return true

func is_map_rendered(selected_map_id: String = "") -> bool:
	var candidate_map_id: String = selected_map_id if not selected_map_id.is_empty() else map_id
	if candidate_map_id.is_empty():
		return false
	for region_value in regions:
		if not region_value is Dictionary:
			continue
		var region: Dictionary = region_value
		if str(region.get("map_id", "")) == candidate_map_id and bool(region.get("ready", false)) and region.get("background_texture") is Texture2D:
			return true
	return false

func _ensure_region_rendered(selected_map_id: String) -> bool:
	if content == null:
		return false
	for region_index in range(regions.size()):
		if not regions[region_index] is Dictionary:
			continue
		var region: Dictionary = regions[region_index]
		if str(region.get("map_id", "")) != selected_map_id:
			continue
		if bool(region.get("ready", false)) and region.get("background_texture") is Texture2D:
			return true
		if authoritative_state:
			return false
		var server_map: Dictionary = content._server_map_for_local_map(selected_map_id, GameState.server_maps)
		var prepared: Dictionary = content.prepare_server_map(selected_map_id, server_map, GameState.server_maps, false) if content._is_server_custom_map(server_map) else content.prepare_map(selected_map_id, false)
		if not bool(prepared.get("ok", false)):
			return false
		region["background_texture"] = prepared.get("background_texture", prepared.get("texture"))
		region["foreground_texture"] = prepared.get("foreground_texture")
		region["render_origin"] = Vector2i(region.get("origin", Vector2i.ZERO)) + Vector2i(prepared.get("render_origin", Vector2i.ZERO))
		region["render_width"] = int(prepared.get("render_width", region.get("width", 0)))
		region["render_height"] = int(prepared.get("render_height", region.get("height", 0)))
		region["objects"] = objects_for_mode(prepared.get("objects", []))
		region["warps"] = prepared.get("warps", [])
		region["connections"] = prepared.get("connections", region.get("connections", []))
		region["animated_background_tiles"] = prepared.get("animated_background_tiles", [])
		region["animated_foreground_tiles"] = prepared.get("animated_foreground_tiles", [])
		region["ready"] = true
		regions[region_index] = region
		_refresh_object_list(region.get("objects", []))
		_rebuild_world_bounds()
		return true
	return false

func refresh_world_bounds() -> void:
	_rebuild_world_bounds()
	queue_redraw()

func _set_active_region(selected_map_id: String) -> void:
	for region_value in regions:
		if not region_value is Dictionary:
			continue
		var region: Dictionary = region_value
		if str(region.get("map_id", "")) != selected_map_id:
			continue
		map_texture = region.get("background_texture") as Texture2D
		foreground_texture = region.get("foreground_texture") as Texture2D
		map_pixel_size = Vector2(int(region.get("width", 0)) * TILE_PIXELS, int(region.get("height", 0)) * TILE_PIXELS)
		objects = objects_for_mode(region.get("objects", []))
		return

func _rebuild_world_bounds() -> void:
	if regions.is_empty():
		world_bounds = Rect2()
		return
	var has_bounds: bool = false
	var minimum: Vector2i = Vector2i.ZERO
	var maximum: Vector2i = Vector2i.ZERO
	for region_value in regions:
		if not region_value is Dictionary:
			continue
		var region: Dictionary = region_value
		if not bool(region.get("ready", false)) or bool(region.get("corner_filler", false)):
			continue
		var origin: Vector2i = _region_render_origin(str(region.get("map_id", "")))
		var extent: Vector2i = origin + Vector2i(int(region.get("render_width", region.get("width", 0))), int(region.get("render_height", region.get("height", 0))))
		if not has_bounds:
			minimum = origin
			maximum = extent
			has_bounds = true
		else:
			minimum.x = mini(minimum.x, origin.x)
			minimum.y = mini(minimum.y, origin.y)
			maximum.x = maxi(maximum.x, extent.x)
			maximum.y = maxi(maximum.y, extent.y)
	if has_bounds:
		world_bounds = Rect2(Vector2(minimum) * TILE_PIXELS, Vector2(maximum - minimum) * TILE_PIXELS)

func _region_origin(selected_map_id: String) -> Vector2i:
	var value: Variant = region_origins.get(selected_map_id, Vector2i.ZERO)
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(value)
	return Vector2i.ZERO

func _region_render_origin(selected_map_id: String) -> Vector2i:
	for region_value in regions:
		if not region_value is Dictionary:
			continue
		var region: Dictionary = region_value
		if str(region.get("map_id", "")) != selected_map_id:
			continue
		var value: Variant = region.get("render_origin", region.get("origin", Vector2i.ZERO))
		if value is Vector2i:
			return value
		if value is Vector2:
			return Vector2i(value)
		break
	return _region_origin(selected_map_id)

func _world_position(selected_map_id: String, local_position: Vector2) -> Vector2:
	return Vector2(_region_origin(selected_map_id)) + local_position

func _movement_world_position() -> Vector2:
	if not movement_active:
		return _world_position(map_id, Vector2(player_position))
	var start_world: Vector2 = _world_position(map_id, movement_start)
	var target_world: Vector2
	if region_origins.has(pending_map_id):
		target_world = _world_position(pending_map_id, pending_position)
	else:
		target_world = start_world + _direction_vector(player_facing)
	var progress: float = clampf(movement_elapsed / movement_duration, 0.0, 1.0)
	if movement_door:
		progress = clampf((progress - 16.0 / 44.0) / (12.0 / 44.0), 0.0, 1.0)
	return start_world.lerp(target_world, progress)

func _door_frame_index() -> int:
	var tick: int = clampi(floori(door_progress * 44.0), 0, 43)
	if tick < 16:
		return clampi(tick / 4, 0, DOOR_FRAME_COUNT - 1)
	if tick < 28:
		return DOOR_FRAME_COUNT - 1
	return clampi(DOOR_FRAME_COUNT - 1 - (tick - 28) / 4, 0, DOOR_FRAME_COUNT - 1)

func _camera_origin(world_position: Vector2, camera_world_size: Vector2) -> Vector2:
	var camera_center: Vector2 = (world_position + Vector2(0.5, 0.5)) * TILE_PIXELS
	var camera_origin: Vector2 = camera_center - camera_world_size * 0.5
	if world_bounds.size.x > 0.0:
		if world_bounds.size.x <= camera_world_size.x:
			camera_origin.x = world_bounds.position.x - (camera_world_size.x - world_bounds.size.x) * 0.5
		else:
			camera_origin.x = clampf(camera_origin.x, world_bounds.position.x, world_bounds.end.x - camera_world_size.x)
	if world_bounds.size.y > 0.0:
		if world_bounds.size.y <= camera_world_size.y:
			camera_origin.y = world_bounds.position.y - (camera_world_size.y - world_bounds.size.y) * 0.5
		else:
			camera_origin.y = clampf(camera_origin.y, world_bounds.position.y, world_bounds.end.y - camera_world_size.y)
	return Vector2(roundf(camera_origin.x), roundf(camera_origin.y))

func set_player_state(x: int, y: int, elevation: int = 3, facing: int = 1) -> void:
	var next_position: Vector2i = Vector2i(x, y)
	if authoritative_state:
		authoritative_probe_pending = false
		authoritative_probe_elapsed = 0.0
	if authoritative_state:
		_reset_movement_state()
		player_position = next_position
		player_elevation = elevation
		player_facing = facing
		has_spawn = true
		_update_player_texture()
		queue_redraw()
		return
	player_position = next_position
	player_elevation = elevation
	player_facing = facing
	movement_start = Vector2(player_position)
	movement_target = movement_start
	movement_active = false
	movement_unvalidated = false
	has_spawn = true
	_update_player_texture()
	queue_redraw()

func apply_server_position(x: int, y: int, elevation: int = 3, facing: int = 1) -> void:
	var next_position: Vector2i = Vector2i(x, y)
	if authoritative_state:
		authoritative_probe_pending = false
		authoritative_probe_elapsed = 0.0
		if movement_scripted:
			if pending_map_id == map_id and next_position == pending_position:
				movement_unvalidated = false
				player_elevation = elevation
				player_facing = facing
				_update_player_texture()
				queue_redraw()
				return
			if next_position == player_position:
				player_elevation = elevation
				player_facing = facing
				has_spawn = true
				_update_player_texture()
				queue_redraw()
				return
			return
		if movement_active and next_position == player_position:
			_reset_movement_state()
			authoritative_probe_pending = true
			authoritative_probe_elapsed = 0.0
			player_elevation = elevation
			player_facing = facing
			has_spawn = true
			_update_player_texture()
			queue_redraw()
			return
		if movement_active and pending_map_id == map_id and next_position == pending_position:
			movement_unvalidated = false
			player_elevation = elevation
			player_facing = facing
			_update_player_texture()
			queue_redraw()
			return
		if next_position == player_position:
			player_elevation = elevation
			player_facing = facing
			has_spawn = true
			_update_player_texture()
			queue_redraw()
			return
	set_player_state(x, y, elevation, facing)

func apply_server_facing(facing: int) -> void:
	if authoritative_state:
		authoritative_probe_pending = false
		authoritative_probe_elapsed = 0.0
	player_facing = facing
	_update_player_texture()
	queue_redraw()

func _direction_between(from: Vector2i, to: Vector2i) -> int:
	if to.y > from.y:
		return 1
	if to.y < from.y:
		return 2
	if to.x < from.x:
		return 3
	if to.x > from.x:
		return 4
	return player_facing

func _direction_vector(direction: int) -> Vector2:
	match direction:
		1:
			return Vector2.DOWN
		2:
			return Vector2.UP
		3:
			return Vector2.LEFT
		4:
			return Vector2.RIGHT
	return Vector2.ZERO

func set_world_entities(values: Array, local_character_id: int) -> void:
	var previous_entities: Dictionary = {}
	for old_value in world_entities:
		if not old_value is Dictionary:
			continue
		var old_entity: Dictionary = old_value
		var old_key: String = str(old_entity.get("entity_key", old_entity.get("entity_id", 0)))
		previous_entities[old_key] = old_entity
	world_entities = []
	if content == null:
		return
	for value in values:
		if not value is Dictionary:
			continue
		var entity: Dictionary = value
		var entity_map_id: String = str(entity.get("map_id", ""))
		if int(entity.get("character_id", 0)) == local_character_id or not region_origins.has(entity_map_id):
			continue
		var is_npc: bool = bool(entity.get("npc", false))
		var graphics_id: int = int(entity.get("resolved_graphics_id", entity.get("graphics_id", entity.get("graphic_id", entity.get("sprite_id", 19))))) if is_npc else 19
		var sprite_region_id: int = int(entity.get("sprite_region_id", 1))
		var facing: int = int(entity.get("facing", 1))
		var entity_id: int = int(entity.get("entity_id", entity.get("character_id", entity.get("user_id", 0))))
		var entity_key: String = "%s:%s" % [str(entity_id), entity_map_id]
		var previous_value: Variant = previous_entities.get(entity_key, {})
		var previous: Dictionary = previous_value as Dictionary if previous_value is Dictionary else {}
		var incoming_position: Vector2i = Vector2i(int(entity.get("x", 0)), int(entity.get("y", 0)))
		var previous_position: Vector2i = Vector2i(int(previous.get("x", incoming_position.x)), int(previous.get("y", incoming_position.y)))
		var previous_active: bool = bool(previous.get("movement_active", false))
		var previous_scripted: bool = bool(previous.get("movement_scripted", false))
		var retain_script_position: bool = (previous_active or previous_scripted) and incoming_position != previous_position
		var clear_script_position: bool = previous_scripted and not previous_active and incoming_position == previous_position
		var resolved_x: int = previous_position.x if retain_script_position else incoming_position.x
		var resolved_y: int = previous_position.y if retain_script_position else incoming_position.y
		var script_busy: bool = previous_scripted and not clear_script_position
		var resolved_facing: int = int(previous.get("facing", facing)) if previous_active or script_busy else facing
		var texture: Texture2D = previous.get("texture") as Texture2D
		if texture == null or int(previous.get("graphics_id", -1)) != graphics_id or int(previous.get("facing", -1)) != resolved_facing:
			var sprite: Dictionary = content.render_facing_object_sprite(graphics_id, resolved_facing, false, 0)
			texture = sprite.get("texture") as Texture2D
		if texture == null and not is_npc:
			continue
		var stored_entity: Dictionary = {"entity_key": entity_key, "entity_id": entity_id, "npc": is_npc, "map_id": entity_map_id, "texture": texture, "width": texture.get_width() if texture != null else 0, "height": texture.get_height() if texture != null else 0, "x": resolved_x, "y": resolved_y, "elevation": int(entity.get("elevation", 3)), "facing": resolved_facing, "default_facing": int(entity.get("facing", 1)), "graphics_id": graphics_id, "sprite_region_id": sprite_region_id, "blocks_movement": bool(entity.get("blocks_movement", is_npc)), "visible": true, "movement_scripted": script_busy, "movement_active": false, "movement_start": Vector2.ZERO, "movement_target": Vector2.ZERO, "movement_elapsed": 0.0, "movement_duration": 0.0, "movement_action": -1, "movement_animation": false, "movement_frame": -1, "movement_queue": []}
		stored_entity["battle"] = bool(entity.get("battle", false))
		for dynamic_key in ["visible", "movement_scripted", "movement_active", "movement_start", "movement_target", "movement_elapsed", "movement_duration", "movement_action", "movement_animation", "movement_frame", "movement_queue"]:
			if previous.has(dynamic_key):
				stored_entity[dynamic_key] = previous.get(dynamic_key)
		stored_entity["movement_scripted"] = script_busy
		world_entities.append(stored_entity)
		var pending_value: Variant = pending_scripted_movements.get(str(entity_id), [])
		if pending_value is Array and not (pending_value as Array).is_empty():
			stored_entity["movement_scripted"] = true
			stored_entity["movement_queue"] = (pending_value as Array).duplicate()
			pending_scripted_movements.erase(str(entity_id))
			var stored_index: int = world_entities.size() - 1
			if not bool(stored_entity.get("movement_active", false)):
				_start_world_entity_movement(stored_index)
	queue_redraw()

func queue_scripted_movement(entity_id: int, steps: Variant, _running: bool = false) -> void:
	var actions: Array = []
	if steps is PackedByteArray:
		for step in steps:
			actions.append(int(step))
	elif steps is Array:
		for step_value in steps:
			actions.append(int(step_value))
	if actions.is_empty():
		return
	var resolved_local_id: int = local_entity_id
	if resolved_local_id <= 0:
		resolved_local_id = int(GameState.current_character.get("id", 0))
	if entity_id == resolved_local_id:
		scripted_movement_queue.append_array(actions)
		if not movement_active:
			_start_next_scripted_movement()
		return
	var entity_index: int = _world_entity_index(entity_id)
	if entity_index < 0:
		var pending: Array = pending_scripted_movements.get(str(entity_id), [])
		pending.append_array(actions)
		pending_scripted_movements[str(entity_id)] = pending
		return
	var entity: Dictionary = (world_entities[entity_index] as Dictionary).duplicate()
	entity["movement_scripted"] = true
	var movement_queue: Array = entity.get("movement_queue", []).duplicate()
	movement_queue.append_array(actions)
	entity["movement_queue"] = movement_queue
	world_entities[entity_index] = entity
	if not bool(entity.get("movement_active", false)):
		_start_world_entity_movement(entity_index)
	queue_redraw()

func _world_entity_index(entity_id: int) -> int:
	for index in world_entities.size():
		if world_entities[index] is Dictionary and int((world_entities[index] as Dictionary).get("entity_id", 0)) == entity_id:
			return index
	return -1

func _scripted_step_info(action: int) -> Dictionary:
	match action:
		0x00:
			return {"direction": 1, "walk": false, "animate": false, "duration": 0.12}
		0x01:
			return {"direction": 2, "walk": false, "animate": false, "duration": 0.12}
		0x02:
			return {"direction": 3, "walk": false, "animate": false, "duration": 0.12}
		0x03:
			return {"direction": 4, "walk": false, "animate": false, "duration": 0.12}
		0x10:
			return {"direction": 1, "walk": true, "animate": true, "duration": 0.25}
		0x11:
			return {"direction": 2, "walk": true, "animate": true, "duration": 0.25}
		0x12:
			return {"direction": 3, "walk": true, "animate": true, "duration": 0.25}
		0x13:
			return {"direction": 4, "walk": true, "animate": true, "duration": 0.25}
		0x1B:
			return {"direction": 0, "walk": false, "animate": false, "duration": 8.0 / 60.0}
		0x1C:
			return {"direction": 0, "walk": false, "animate": false, "duration": 16.0 / 60.0}
		0x1D:
			return {"direction": 1, "walk": true, "animate": true, "duration": 0.13}
		0x1E:
			return {"direction": 2, "walk": true, "animate": true, "duration": 0.13}
		0x1F:
			return {"direction": 3, "walk": true, "animate": true, "duration": 0.13}
		0x20:
			return {"direction": 4, "walk": true, "animate": true, "duration": 0.13}
		0x21:
			return {"direction": 1, "walk": false, "animate": true, "duration": 0.13}
		0x22:
			return {"direction": 2, "walk": false, "animate": true, "duration": 0.13}
		0x23:
			return {"direction": 3, "walk": false, "animate": true, "duration": 0.13}
		0x24:
			return {"direction": 4, "walk": false, "animate": true, "duration": 0.13}
		0x4A:
			return {"direction": 1, "walk": true, "animate": true, "duration": 0.5, "tiles": 2, "jump": true}
		0x4B:
			return {"direction": 2, "walk": true, "animate": true, "duration": 0.5, "tiles": 2, "jump": true}
		0x4C:
			return {"direction": 3, "walk": true, "animate": true, "duration": 0.5, "tiles": 2, "jump": true}
		0x4D:
			return {"direction": 4, "walk": true, "animate": true, "duration": 0.5, "tiles": 2, "jump": true}
		0x60:
			return {"direction": 0, "walk": false, "animate": false, "duration": 0.01, "visible": false}
		0x70:
			return {"direction": 0, "walk": false, "animate": false, "duration": 0.5, "exclaim": true}
	return {}

func _start_next_scripted_movement() -> void:
	while not scripted_movement_queue.is_empty():
		var action: int = int(scripted_movement_queue.pop_front())
		var info: Dictionary = _scripted_step_info(action)
		if info.is_empty():
			continue
		var direction: int = int(info.get("direction", 0))
		if direction > 0:
			player_facing = direction
		movement_scripted = true
		movement_scripted_action = action
		movement_animation_active = bool(info.get("animate", false))
		movement_start = Vector2(player_position)
		var tiles: int = maxi(int(info.get("tiles", 1)), 1)
		movement_target = movement_start + _direction_vector(direction) * tiles if bool(info.get("walk", false)) else movement_start
		pending_map_id = map_id
		pending_position = Vector2i(int(round(movement_target.x)), int(round(movement_target.y)))
		pending_elevation = player_elevation
		pending_warp = {}
		movement_jump = bool(info.get("jump", false))
		exclaim_timer = float(info.get("exclaim", false)) * float(info.get("duration", 0.5))
		movement_stair = false
		movement_stair_behavior = 0
		movement_door = false
		movement_elapsed = 0.0
		movement_duration = maxf(float(info.get("duration", NORMAL_STEP_DURATION)), 0.01)
		if bool(info.get("visible", true)) == false:
			player_visible = false
		if bool(info.get("walk", false)):
			sound_requested.emit("step")
		movement_active = true
		_update_player_texture()
		queue_redraw()
		return
	movement_scripted = false
	movement_animation_active = false
	movement_active = false

func _start_world_entity_movement(index: int) -> void:
	if index < 0 or index >= world_entities.size() or not world_entities[index] is Dictionary:
		return
	var entity: Dictionary = (world_entities[index] as Dictionary).duplicate()
	var movement_queue: Array = entity.get("movement_queue", []).duplicate()
	while not movement_queue.is_empty():
		var action: int = int(movement_queue.pop_front())
		var info: Dictionary = _scripted_step_info(action)
		if info.is_empty():
			continue
		var direction: int = int(info.get("direction", 0))
		var start: Vector2 = Vector2(int(entity.get("x", 0)), int(entity.get("y", 0)))
		entity["movement_queue"] = movement_queue
		entity["movement_active"] = true
		entity["movement_start"] = start
		entity["movement_target"] = start + _direction_vector(direction) if bool(info.get("walk", false)) else start
		entity["movement_elapsed"] = 0.0
		entity["movement_duration"] = maxf(float(info.get("duration", NORMAL_STEP_DURATION)), 0.01)
		entity["movement_action"] = action
		entity["movement_animation"] = bool(info.get("animate", false))
		entity["movement_frame"] = -1
		if direction > 0:
			entity["facing"] = direction
		if info.has("visible"):
			entity["visible"] = bool(info.get("visible", true))
		_update_world_entity_texture(entity)
		world_entities[index] = entity
		return
	entity["movement_queue"] = movement_queue
	entity["movement_active"] = false
	entity["movement_action"] = -1
	entity["movement_animation"] = false
	_update_world_entity_texture(entity)
	world_entities[index] = entity

func _update_world_entity_texture(entity: Dictionary) -> void:
	if content == null:
		return
	var moving: bool = bool(entity.get("movement_animation", false))
	var frame_step: int = 0
	if moving and float(entity.get("movement_duration", 0.0)) > 0.0:
		frame_step = int(floorf(clampf(float(entity.get("movement_elapsed", 0.0)) / float(entity.get("movement_duration", 1.0)), 0.0, 0.999) * 4.0))
	var movement_frame: int = frame_step if moving else -1
	if int(entity.get("movement_frame", -2)) == movement_frame:
		return
	var sprite: Dictionary = content.render_facing_object_sprite(int(entity.get("graphics_id", 19)), int(entity.get("facing", 1)), moving, frame_step)
	if bool(sprite.get("ok", false)):
		entity["texture"] = sprite.get("texture")
		entity["width"] = int(sprite.get("width", 0))
		entity["height"] = int(sprite.get("height", 0))
		entity["movement_frame"] = movement_frame

func _process_world_entity_movements(delta: float) -> void:
	var redraw_needed: bool = false
	for index in world_entities.size():
		if not world_entities[index] is Dictionary:
			continue
		var entity: Dictionary = (world_entities[index] as Dictionary).duplicate()
		if not bool(entity.get("movement_active", false)):
			continue
		redraw_needed = true
		var elapsed: float = float(entity.get("movement_elapsed", 0.0)) + delta
		var duration: float = maxf(float(entity.get("movement_duration", NORMAL_STEP_DURATION)), 0.01)
		if elapsed >= duration:
			var target: Vector2 = entity.get("movement_target", Vector2(int(entity.get("x", 0)), int(entity.get("y", 0))))
			entity["x"] = int(round(target.x))
			entity["y"] = int(round(target.y))
			entity["movement_elapsed"] = duration
			entity["movement_active"] = false
			entity["movement_action"] = -1
			entity["movement_animation"] = false
			_update_world_entity_texture(entity)
			world_entities[index] = entity
			if not (entity.get("movement_queue", []) as Array).is_empty():
				_start_world_entity_movement(index)
		else:
			entity["movement_elapsed"] = elapsed
			_update_world_entity_texture(entity)
			world_entities[index] = entity
	if redraw_needed:
		queue_redraw()

func _apply_map(result: Dictionary, reset_spawn: bool) -> void:
	map_texture = result.get("texture", result.get("background_texture")) as Texture2D
	foreground_texture = result.get("foreground_texture") as Texture2D
	map_pixel_size = Vector2(int(result.get("width", 0)) * 16, int(result.get("height", 0)) * 16)
	objects = objects_for_mode(result.get("objects", []))
	regions = [{"map_id": map_id, "origin": Vector2i.ZERO, "width": int(result.get("width", 0)), "height": int(result.get("height", 0)), "background_texture": map_texture, "foreground_texture": foreground_texture, "objects": objects, "ready": true}]
	region_origins = {map_id: Vector2i.ZERO}
	_rebuild_world_bounds()
	_refresh_object_textures()
	if reset_spawn:
		_set_spawn()

func _set_spawn() -> void:
	if content == null or map_id.is_empty():
		return
	var spawn: Dictionary = content.default_spawn(map_id)
	if not bool(spawn.get("ok", false)):
		has_spawn = false
		return
	player_position = Vector2i(int(spawn.get("x", 0)), int(spawn.get("y", 0)))
	player_elevation = int(spawn.get("elevation", 3))
	player_facing = 1
	player_visible = true
	has_spawn = true
	movement_active = false
	movement_unvalidated = false
	movement_stair = false
	movement_stair_behavior = 0
	movement_door = false
	door_progress = 0.0
	pending_warp = {}
	warp_cooldown = 0.0

func _input(event: InputEvent) -> void:
	if not input_enabled or not visible or transition_active:
		return
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if _text_input_has_focus():
		held_direction = 0
		movement_retry_elapsed = 0.0
		return
	if key_event.keycode == KEY_ESCAPE and key_event.pressed and not key_event.echo:
		get_viewport().set_input_as_handled()
		back_requested.emit()
		return
	if key_event.keycode in [KEY_F, KEY_E, KEY_Z, KEY_X] and key_event.pressed and not key_event.echo:
		if dialogue_active:
			return
		get_viewport().set_input_as_handled()
		interact()
		return
	if dialogue_active:
		return
	var direction: int = _key_direction(key_event)
	if direction == 0:
		return
	if not key_event.pressed:
		if held_direction == direction:
			held_direction = 0
		return
	if key_event.echo:
		return
	held_direction = direction
	get_viewport().set_input_as_handled()
	if not movement_active:
		movement_retry_elapsed = 0.0

func interact() -> void:
	if content == null or map_id.is_empty() or dialogue_active:
		return
	var target_position: Vector2i = player_position + Vector2i(_direction_vector(player_facing))
	var target_positions: Array = [target_position, target_position + Vector2i(_direction_vector(player_facing))]
	for target_value in target_positions:
		var npc_target: Vector2i = target_value
		for index in world_entities.size():
			var entity_value: Variant = world_entities[index]
			if not entity_value is Dictionary:
				continue
			var entity: Dictionary = entity_value
			if not bool(entity.get("npc", false)) or str(entity.get("map_id", "")) != map_id or int(entity.get("x", -1)) != npc_target.x or int(entity.get("y", -1)) != npc_target.y:
				continue
			if authoritative_state:
				if not GameState.send_face_direction(_direction_name(player_facing)):
					return
				if not GameState.send_entity_interact(int(entity.get("entity_id", 0)), 0):
					return
			_face_world_entity(index, player_facing)
			return
	if authoritative_state:
		if not GameState.send_face_direction(_direction_name(player_facing)):
			return
		GameState.send_tile_interact()
		return
	var interaction: Dictionary = content.interaction_at(map_id, player_position.x, player_position.y, player_facing, player_elevation, objects)
	if bool(interaction.get("ok", false)):
		_face_interaction_object(interaction.get("object", {}))
		interaction_requested.emit(interaction)

func _key_direction(event: InputEventKey) -> int:
	match event.keycode:
		KEY_DOWN, KEY_S:
			return 1
		KEY_UP, KEY_W:
			return 2
		KEY_LEFT, KEY_A:
			return 3
		KEY_RIGHT, KEY_D:
			return 4
	return 0

func _physical_direction() -> int:
	if not input_enabled or not visible or transition_active or dialogue_active:
		return 0
	var direction: int = 0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		direction = 2
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		direction = 1
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		direction = 3
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		direction = 4
	return direction

func _movement_objects() -> Array:
	var result: Array = []
	for object_value in objects:
		if object_value is Dictionary and authoritative_state and str((object_value as Dictionary).get("kind", "")) == "object":
			continue
		result.append(object_value)
	return result

func _movement_destination_occupied(objects_to_check: Array, destination: Vector2i) -> bool:
	for object_value in objects_to_check:
		if not object_value is Dictionary:
			continue
		var object: Dictionary = object_value
		if bool(object.get("blocks_movement", true)) and int(object.get("x", -1)) == destination.x and int(object.get("y", -1)) == destination.y:
			return true
	return false

func _request_move(direction: int) -> bool:
	if transition_active or (authoritative_state and GameState.map_transition_pending) or content == null or map_id.is_empty() or not has_spawn:
		return false
	if authoritative_state and movement_active:
		return false
	player_facing = direction
	_update_player_texture()
	queue_redraw()
	var occupied: Array = _movement_objects()
	for entity_value in world_entities:
		if not entity_value is Dictionary:
			continue
		var entity: Dictionary = entity_value
		if bool(entity.get("npc", false)) and bool(entity.get("blocks_movement", true)) and str(entity.get("map_id", "")) == map_id:
			occupied.append({"x": int(entity.get("x", -1)), "y": int(entity.get("y", -1)), "elevation": int(entity.get("elevation", player_elevation)), "collision": 1, "blocks_movement": true})
	var destination: Vector2i = player_position + Vector2i(_direction_vector(direction))
	if _movement_destination_occupied(occupied, destination):
		return false
	var result: Dictionary = content.movement_result(map_id, player_position.x, player_position.y, direction, player_elevation, occupied)
	if authoritative_state:
		if not bool(result.get("ok", false)):
			var local_error: String = str(result.get("error", ""))
			if local_error == "water" or local_error == "ledge" or local_error == "jump landing is blocked":
				return false
			var predicted_position := player_position + Vector2i(_direction_vector(direction))
			var movement_map: Dictionary = content.map_data(map_id)
			var cache_value: Variant = content.get("map_cache")
			if movement_map.is_empty() and cache_value is Dictionary:
				var cached_map: Variant = (cache_value as Dictionary).get(map_id, {})
				if cached_map is Dictionary and bool(cached_map.get("ok", false)):
					movement_map = {"width": int(cached_map.get("width", 0)), "height": int(cached_map.get("height", 0))}
			var can_predict_same_map := not movement_map.is_empty() and predicted_position.x >= 0 and predicted_position.y >= 0 and predicted_position.x < int(movement_map.get("width", 0)) and predicted_position.y < int(movement_map.get("height", 0))
			if not can_predict_same_map:
				if authoritative_probe_pending:
					return false
				if not GameState.send_input(_direction_name(direction), player_position.x, player_position.y):
					return false
				authoritative_probe_pending = true
				authoritative_probe_elapsed = 0.0
				return true
			if not GameState.send_input(_direction_name(direction), player_position.x, player_position.y):
				return false
			pending_map_id = map_id
			pending_position = predicted_position
			pending_elevation = player_elevation
			pending_warp = {}
			movement_start = Vector2(player_position)
			movement_target = Vector2(predicted_position)
			movement_jump = false
			movement_stair = false
			movement_stair_behavior = 0
			movement_door = false
			movement_elapsed = 0.0
			movement_duration = NORMAL_STEP_DURATION
			movement_active = true
			movement_animation_active = true
			movement_unvalidated = true
			sound_requested.emit("step")
			queue_redraw()
			return true
		if not GameState.send_input(_direction_name(direction), player_position.x, player_position.y):
			return false
		movement_unvalidated = false
		var destination_map_id: String = str(result.get("map_id", map_id))
		var map_transition: bool = destination_map_id != map_id
		var result_warp: Dictionary = result.get("warp", {}) if result.get("warp", {}) is Dictionary else {}
		var server_traversal: bool = bool(result.get("stair", false)) or bool(result.get("door", false)) or not result_warp.is_empty() or map_transition
		pending_map_id = destination_map_id
		pending_position = Vector2i(int(result.get("x", player_position.x)), int(result.get("y", player_position.y))) if map_transition else player_position + Vector2i(_direction_vector(direction)) if server_traversal else Vector2i(int(result.get("x", player_position.x)), int(result.get("y", player_position.y)))
		pending_elevation = int(result.get("elevation", player_elevation)) if map_transition else player_elevation if server_traversal else int(result.get("elevation", player_elevation))
		movement_stair = false if server_traversal else bool(result.get("stair", false))
		movement_stair_behavior = 0 if server_traversal else int(result.get("stair_behavior", 0))
		movement_door = bool(result.get("door", false)) and not movement_stair
		movement_door_position = player_position + Vector2i(_direction_vector(direction)) if movement_door else Vector2i.ZERO
		pending_warp = result_warp
		movement_start = Vector2(player_position)
		movement_target = Vector2(pending_position)
		movement_jump = bool(result.get("jump", false)) and not server_traversal
		movement_elapsed = 0.0
		movement_duration = 0.24 if movement_stair else DOOR_TRAVERSAL_DURATION if movement_door else 0.32 if movement_jump else NORMAL_STEP_DURATION
		door_progress = 0.0
		movement_active = true
		movement_animation_active = true
		sound_requested.emit("ledge" if movement_jump else "door" if movement_door else "step")
		queue_redraw()
		return true
	elif not bool(result.get("ok", false)):
		return false
	pending_map_id = str(result.get("map_id", map_id))
	pending_position = Vector2i(int(result.get("x", player_position.x)), int(result.get("y", player_position.y)))
	pending_elevation = int(result.get("elevation", player_elevation))
	movement_stair = bool(result.get("stair", false))
	movement_stair_behavior = int(result.get("stair_behavior", 0))
	movement_door = bool(result.get("door", false)) and not movement_stair
	movement_door_position = player_position + Vector2i(_direction_vector(direction)) if movement_door else Vector2i.ZERO
	pending_warp = result.get("warp", {}) if result.get("warp", {}) is Dictionary else {}
	movement_start = Vector2(player_position)
	movement_target = movement_start + _direction_vector(direction) if pending_map_id != map_id else Vector2(pending_position)
	movement_jump = bool(result.get("jump", false))
	movement_elapsed = 0.0
	movement_duration = 0.24 if movement_stair else DOOR_TRAVERSAL_DURATION if movement_door else 0.32 if movement_jump else NORMAL_STEP_DURATION
	door_progress = 0.0
	movement_active = true
	movement_animation_active = true
	sound_requested.emit("ledge" if movement_jump else "door" if movement_door else "step")
	queue_redraw()
	return true

func _process(delta: float) -> void:
	if transition_active:
		held_direction = 0
		return
	_process_world_entity_movements(delta)
	_update_follower(delta)
	if _text_input_has_focus():
		held_direction = 0
		movement_retry_elapsed = 0.0
	else:
		held_direction = _physical_direction()
	if authoritative_probe_pending:
		authoritative_probe_elapsed += delta
		if authoritative_probe_elapsed >= AUTHORITATIVE_PROBE_INTERVAL:
			authoritative_probe_pending = false
			authoritative_probe_elapsed = 0.0
	if warp_cooldown > 0.0:
		warp_cooldown = maxf(warp_cooldown - delta, 0.0)
	animation_elapsed += delta
	if animation_elapsed >= ANIMATION_FRAME_INTERVAL:
		animation_elapsed = fmod(animation_elapsed, ANIMATION_FRAME_INTERVAL)
		animation_tick += 1
		queue_redraw()
	if not movement_active:
		if not scripted_movement_queue.is_empty():
			_start_next_scripted_movement()
			return
		if held_direction != 0 and not authoritative_probe_pending:
			movement_retry_elapsed += delta
			if movement_retry_elapsed >= 0.05:
				movement_retry_elapsed = 0.0
				_request_move(held_direction)
		else:
			movement_retry_elapsed = 0.0
		return
	movement_elapsed += delta
	if movement_door and movement_duration > 0.0:
		door_progress = clampf(movement_elapsed / movement_duration, 0.0, 1.0)
	_update_player_texture()
	if movement_elapsed < movement_duration:
		queue_redraw()
		return
	var completed_map_id: String = pending_map_id
	var completed_position: Vector2i = pending_position
	var completed_elevation: int = pending_elevation
	var completed_warp: Dictionary = pending_warp
	var completed_scripted: bool = movement_scripted
	movement_active = false
	movement_scripted = false
	movement_animation_active = false
	movement_unvalidated = false
	movement_stair = false
	movement_stair_behavior = 0
	movement_door = false
	movement_door_position = Vector2i.ZERO
	door_progress = 0.0
	pending_warp = {}
	player_position = completed_position
	player_elevation = completed_elevation
	if completed_scripted:
		if not scripted_movement_queue.is_empty():
			_start_next_scripted_movement()
		else:
			movement_scripted_action = -1
		_update_player_texture()
		queue_redraw()
		return
	if authoritative_state:
		if completed_map_id != map_id:
			set_active_map(completed_map_id)
		_update_player_texture()
		location_changed.emit(map_id, player_position.x, player_position.y)
		queue_redraw()
		if held_direction != 0 and completed_map_id == map_id:
			movement_retry_elapsed = 0.0
			_request_move(held_direction)
		return
	if completed_map_id != map_id:
		if not set_active_map(completed_map_id):
			_load_map(completed_map_id)
	else:
		_update_player_texture()
	var warp: Dictionary = completed_warp
	if bool(warp.get("ok", false)) and warp_cooldown <= 0.0:
		map_id = str(warp.get("map_id", map_id))
		player_position = Vector2i(int(warp.get("x", player_position.x)), int(warp.get("y", player_position.y)))
		player_elevation = int(warp.get("elevation", player_elevation))
		_load_map(map_id, false)
		warp_cooldown = 0.35
	location_changed.emit(map_id, player_position.x, player_position.y)
	queue_redraw()
	if held_direction != 0 and not movement_active:
		movement_retry_elapsed = 0.0
		_request_move(held_direction)

func _load_map(next_map_id: String, reset_spawn: bool = false) -> void:
	if content == null or next_map_id.is_empty():
		return
	connected_preload_generation += 1
	var generation: int = connected_preload_generation
	var connected_world: Dictionary = content.prepare_connected_world(next_map_id, 96, 0, GameState.server_maps)
	if bool(connected_world.get("ok", false)):
		set_world(connected_world, next_map_id)
		if reset_spawn and not authoritative_state:
			_set_spawn()
		call_deferred("_preload_connected_regions", connected_world, next_map_id, generation)
		return
	var changed: bool = map_id != next_map_id
	map_id = next_map_id
	if changed:
		_reset_movement_state(true)
		if authoritative_state:
			has_spawn = false
	var server_map: Dictionary = content._server_map_for_local_map(map_id, GameState.server_maps)
	var result: Dictionary = content.prepare_server_map(map_id, server_map, GameState.server_maps) if content._is_server_custom_map(server_map) else content.prepare_map(map_id)
	if not bool(result.get("ok", false)):
		return
	_apply_map(result, reset_spawn)
	if animation_tick > 0:
		set_animation_tick(animation_tick)
	if not reset_spawn:
		has_spawn = true
	_refresh_object_textures()
	_update_player_texture()

func _preload_connected_regions(world_value: Dictionary, root_map_id: String, generation: int) -> void:
	var world_regions: Array = world_value.get("regions", [])
	for region_value in world_regions:
		if generation != connected_preload_generation or map_id != root_map_id or not is_inside_tree() or not region_value is Dictionary:
			return
		var region: Dictionary = region_value
		var region_id: String = str(region.get("map_id", ""))
		if region_id.is_empty() or region_id == root_map_id or bool(region.get("ready", false)):
			continue
		await get_tree().process_frame
		if generation != connected_preload_generation or map_id != root_map_id:
			return
		var server_map: Dictionary = content._server_map_for_local_map(region_id, GameState.server_maps)
		var prepared: Dictionary = content.prepare_server_map(region_id, server_map, GameState.server_maps, false) if content._is_server_custom_map(server_map) else content.prepare_map(region_id, false)
		if not bool(prepared.get("ok", false)):
			continue
		region["background_texture"] = prepared.get("background_texture")
		region["foreground_texture"] = prepared.get("foreground_texture")
		region["objects"] = prepared.get("objects", [])
		region["warps"] = prepared.get("warps", [])
		region["animated_background_tiles"] = prepared.get("animated_background_tiles", [])
		region["animated_foreground_tiles"] = prepared.get("animated_foreground_tiles", [])
		region["ready"] = true
		_rebuild_world_bounds()
		queue_redraw()

func _refresh_object_textures() -> void:
	if content == null:
		return
	for region_value in regions:
		if region_value is Dictionary:
			_refresh_object_list(region_value.get("objects", []))
	if regions.is_empty():
		_refresh_object_list(objects)

func _refresh_object_list(values: Array) -> void:
	if content == null:
		return
	for object_value in objects_for_mode(values):
		if not object_value is Dictionary or not bool(object_value.get("render", true)):
			continue
		var object: Dictionary = object_value
		var sprite: Dictionary = content.render_facing_object_sprite(int(object.get("graphics_id", -1)), int(object.get("facing", object.get("default_facing", 1))), false, 0)
		if bool(sprite.get("ok", false)):
			object["texture"] = sprite.get("texture")
			object["width"] = int(sprite.get("width", 0))
			object["height"] = int(sprite.get("height", 0))

func _update_player_texture() -> void:
	if content == null:
		return
	var frame_step: int = 0
	if movement_active and movement_duration > 0.0:
		frame_step = int(floorf(clampf(movement_elapsed / movement_duration, 0.0, 0.999) * 4.0 * PLAYER_WALK_ANIMATION_RATE))
	var movement_key: int = 1 if movement_active and movement_animation_active else 0
	var texture_key: String = "%d:%d:%d" % [player_facing, movement_key, frame_step]
	if player_texture != null and player_texture_key == texture_key:
		return
	var sprite_content = content
	var sprite: Dictionary = sprite_content.render_facing_object_sprite(19, player_facing, movement_animation_active and movement_active, frame_step)
	if not bool(sprite.get("ok", false)) or sprite.get("texture") == null:
		var kanto = GameState.content_for_region("kanto")
		if kanto != null and kanto != sprite_content:
			sprite = kanto.render_facing_object_sprite(19, player_facing, movement_animation_active and movement_active, frame_step)
	player_texture = sprite.get("texture") as Texture2D
	player_texture_key = texture_key if player_texture != null else ""

func inspect_at_screen(screen_position: Vector2) -> Dictionary:
	if regions.is_empty() or size.x <= 0.0 or size.y <= 0.0:
		return {"ok": false}
	var tile_scale: float = _tile_scale()
	var camera_world_size: Vector2 = size / tile_scale
	var world_player: Vector2 = _movement_world_position()
	var camera_origin: Vector2 = _camera_origin(world_player, camera_world_size)
	var destination_position: Vector2 = (size - camera_world_size * tile_scale) * 0.5
	var world_pixels: Vector2 = (screen_position - destination_position) / tile_scale + camera_origin
	var world_tile: Vector2i = Vector2i(floori(world_pixels.x / TILE_PIXELS), floori(world_pixels.y / TILE_PIXELS))
	var hit_map_id: String = ""
	var local_tile: Vector2i = world_tile
	for region_value in regions:
		if not region_value is Dictionary:
			continue
		var region: Dictionary = region_value
		var origin: Vector2i = region.get("origin", Vector2i.ZERO)
		var width: int = int(region.get("width", 0))
		var height: int = int(region.get("height", 0))
		if width <= 0 or height <= 0:
			continue
		if world_tile.x < origin.x or world_tile.y < origin.y or world_tile.x >= origin.x + width or world_tile.y >= origin.y + height:
			continue
		hit_map_id = str(region.get("map_id", ""))
		local_tile = world_tile - origin
		break
	if hit_map_id.is_empty():
		return {"ok": true, "world_tile": world_tile, "map_id": "", "local_tile": Vector2i.ZERO}
	var cell: Dictionary = {}
	var warp: Dictionary = {}
	var door_ok: bool = false
	if content != null:
		cell = content.map_cell(hit_map_id, local_tile.x, local_tile.y)
		warp = content.warp_at(hit_map_id, local_tile.x, local_tile.y, player_elevation)
		door_ok = bool(content.door_animation_frame(hit_map_id, local_tile.x, local_tile.y, 1).get("ok", false))
	var hit_objects: Array = []
	for object_value in objects:
		if not object_value is Dictionary:
			continue
		var object: Dictionary = object_value
		var object_map: String = str(object.get("map_id", hit_map_id))
		if object_map != hit_map_id and not str(object.get("map_id", "")).is_empty():
			continue
		if int(object.get("x", -1)) != local_tile.x or int(object.get("y", -1)) != local_tile.y:
			continue
		hit_objects.append({"kind": str(object.get("kind", "object")), "local_id": int(object.get("local_id", -1)), "graphics_id": int(object.get("graphics_id", -1)), "script_offset": int(object.get("script_offset", -1)), "dialogue_id": str(object.get("dialogue_id", "")), "movement_type": int(object.get("movement_type", -1)), "elevation": int(object.get("elevation", -1))})
	for entity_value in world_entities:
		if not entity_value is Dictionary:
			continue
		var entity: Dictionary = entity_value
		if int(entity.get("x", -1)) != local_tile.x or int(entity.get("y", -1)) != local_tile.y:
			continue
		hit_objects.append({"kind": "npc" if bool(entity.get("npc", false)) else "entity", "entity_id": int(entity.get("entity_id", -1)), "graphics_id": int(entity.get("graphics_id", -1)), "facing": int(entity.get("facing", -1))})
	return {"ok": true, "world_tile": world_tile, "map_id": hit_map_id, "local_tile": local_tile, "cell": cell, "warp": warp, "door_graphics": door_ok, "animated_door_behavior": content._is_animated_door_behavior(int(cell.get("behavior", -1))) if content != null else false, "hits": hit_objects}

func _tile_scale() -> float:
	var maximum_camera_size: Vector2 = Vector2(CAMERA_MAX_CELLS_X * TILE_PIXELS, CAMERA_MAX_CELLS_Y * TILE_PIXELS)
	var reference_scale: float = minf(maxf(ceilf(maxf(REFERENCE_VIEWPORT_SIZE.x / maximum_camera_size.x, REFERENCE_VIEWPORT_SIZE.y / maximum_camera_size.y)), 1.0), MAX_TILE_SCALE)
	var viewport_scale: float = maxf(ceilf(maxf(size.x / maximum_camera_size.x, size.y / maximum_camera_size.y)), 1.0)
	return minf(reference_scale, viewport_scale)

func dialogue_anchor_screen(dialogue: Dictionary) -> Vector2:
	if regions.is_empty() or not has_spawn:
		return size * 0.5
	var tile_scale: float = _tile_scale()
	var camera_world_size: Vector2 = size / tile_scale
	var world_player: Vector2 = _movement_world_position()
	var camera_origin: Vector2 = _camera_origin(world_player, camera_world_size)
	var object: Dictionary = dialogue.get("object", {})
	var object_map_id: String = str(object.get("map_id", map_id))
	var object_position: Vector2 = _world_position(object_map_id, Vector2(int(object.get("x", player_position.x)), int(object.get("y", player_position.y))))
	var object_x: float = (object_position.x + 0.5) * TILE_PIXELS
	var object_y: float = (object_position.y + 1.0) * TILE_PIXELS
	var object_height: float = float(int(object.get("height", 16)))
	var destination_position: Vector2 = (size - camera_world_size * tile_scale) * 0.5
	return destination_position + Vector2((object_x - camera_origin.x) * tile_scale, (object_y - object_height - camera_origin.y) * tile_scale)

func dialogue_actor_sprite(entity_id: int) -> Dictionary:
	if entity_id <= 0 or content == null:
		return {}
	for entity_value in world_entities:
		if not entity_value is Dictionary:
			continue
		var entity: Dictionary = entity_value
		if int(entity.get("entity_id", 0)) != entity_id or not bool(entity.get("npc", false)):
			continue
		var texture: Texture2D = entity.get("texture") as Texture2D
		if texture == null:
			var sprite: Dictionary = content.render_facing_object_sprite(int(entity.get("graphics_id", 19)), int(entity.get("facing", 1)), false, 0)
			texture = sprite.get("texture") as Texture2D
			if texture != null:
				return {"texture": texture, "width": int(sprite.get("width", texture.get_width())), "height": int(sprite.get("height", texture.get_height()))}
		if texture != null:
			return {"texture": texture, "width": int(entity.get("width", texture.get_width())), "height": int(entity.get("height", texture.get_height()))}
	return {}

func _face_interaction_object(object_value: Variant) -> void:
	if not object_value is Dictionary:
		return
	var object: Dictionary = object_value
	if not bool(object.get("render", true)) or int(object.get("graphics_id", -1)) < 0:
		return
	var object_direction: int = _opposite_direction(player_facing)
	object["facing"] = object_direction
	var sprite: Dictionary = content.render_facing_object_sprite(int(object.get("graphics_id", -1)), object_direction, false, 0)
	if bool(sprite.get("ok", false)):
		object["texture"] = sprite.get("texture")
		object["width"] = int(sprite.get("width", 0))
		object["height"] = int(sprite.get("height", 0))
	queue_redraw()

func _restore_interaction_facing() -> void:
	for object_value in objects:
		if not object_value is Dictionary:
			continue
		var object: Dictionary = object_value
		var default_facing: int = int(object.get("default_facing", object.get("facing", 1)))
		if int(object.get("facing", default_facing)) != default_facing:
			object["facing"] = default_facing
	_refresh_object_textures()
	queue_redraw()

func restore_interaction_facing() -> void:
	_restore_interaction_facing()
	for index in world_entities.size():
		var entity_value: Variant = world_entities[index]
		if not entity_value is Dictionary:
			continue
		var entity: Dictionary = (entity_value as Dictionary).duplicate()
		if not bool(entity.get("npc", false)):
			continue
		if bool(entity.get("movement_active", false)):
			continue
		var facing: int = int(entity.get("default_facing", 1))
		entity["facing"] = facing
		var sprite: Dictionary = content.render_facing_object_sprite(int(entity.get("graphics_id", 19)), facing, false, 0)
		if bool(sprite.get("ok", false)):
			entity["texture"] = sprite.get("texture")
			entity["width"] = int(sprite.get("width", 0))
			entity["height"] = int(sprite.get("height", 0))
		world_entities[index] = entity
	queue_redraw()

func _face_world_entity(index: int, player_direction: int) -> void:
	if index < 0 or index >= world_entities.size() or content == null:
		return
	var entity_value: Variant = world_entities[index]
	if not entity_value is Dictionary:
		return
	var entity: Dictionary = (entity_value as Dictionary).duplicate()
	var facing: int = _opposite_direction(player_direction)
	entity["facing"] = facing
	var sprite: Dictionary = content.render_facing_object_sprite(int(entity.get("graphics_id", 19)), facing, false, 0)
	if bool(sprite.get("ok", false)):
		entity["texture"] = sprite.get("texture")
		entity["width"] = int(sprite.get("width", 0))
		entity["height"] = int(sprite.get("height", 0))
	world_entities[index] = entity
	queue_redraw()

func _opposite_direction(direction: int) -> int:
	match direction:
		1:
			return 2
		2:
			return 1
		3:
			return 4
		4:
			return 3
	return 1

func _direction_name(direction: int) -> String:
	match direction:
		1:
			return "down"
		2:
			return "up"
		3:
			return "left"
		4:
			return "right"
	return ""

func _world_entity_render_position(entity: Dictionary) -> Vector2:
	var position: Vector2 = Vector2(int(entity.get("x", 0)), int(entity.get("y", 0)))
	if bool(entity.get("movement_active", false)):
		var duration: float = maxf(float(entity.get("movement_duration", NORMAL_STEP_DURATION)), 0.01)
		var progress: float = clampf(float(entity.get("movement_elapsed", 0.0)) / duration, 0.0, 1.0)
		position = (entity.get("movement_start", position) as Vector2).lerp(entity.get("movement_target", position) as Vector2, progress)
	return position

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK, true)
	if regions.is_empty():
		return
	var tile_scale: float = _tile_scale()
	var camera_world_size: Vector2 = size / tile_scale
	var world_player: Vector2 = _movement_world_position()
	if not has_spawn:
		world_player = Vector2(_region_origin(map_id)) * TILE_PIXELS + map_pixel_size * 0.5
	if movement_active and movement_jump:
		world_player.y -= sin(clampf(movement_elapsed / movement_duration, 0.0, 1.0) * PI) * 0.75
	var camera_origin: Vector2 = _camera_origin(world_player, camera_world_size)
	var destination_size: Vector2 = camera_world_size * tile_scale
	var destination_position: Vector2 = (size - destination_size) * 0.5
	var drawables: Array = []
	var camera_rect: Rect2 = Rect2(camera_origin, camera_world_size)
	for region_value in regions:
		if not region_value is Dictionary:
			continue
		var region: Dictionary = region_value
		if not bool(region.get("ready", false)):
			continue
		var region_id: String = str(region.get("map_id", ""))
		var region_origin: Vector2 = Vector2(_region_render_origin(region_id)) * TILE_PIXELS
		var region_size: Vector2 = Vector2(int(region.get("render_width", region.get("width", 0))), int(region.get("render_height", region.get("height", 0)))) * TILE_PIXELS
		var region_rect: Rect2 = Rect2(region_origin, region_size)
		var visible_region: Rect2 = region_rect.intersection(camera_rect)
		if visible_region.size.x > 0.0 and visible_region.size.y > 0.0:
			var background: Texture2D = region.get("background_texture") as Texture2D
			if background != null:
				var background_destination: Rect2 = Rect2(destination_position + (visible_region.position - camera_origin) * tile_scale, visible_region.size * tile_scale)
				var background_source: Rect2 = Rect2(visible_region.position - region_origin, visible_region.size)
				draw_texture_rect_region(background, background_destination, background_source, Color.WHITE, false, true)
			for tile_value in region.get("animated_background_tiles", []):
				if not tile_value is Dictionary:
					continue
				var animated_tile: Dictionary = tile_value
				var tile_world_position: Vector2 = region_origin + Vector2(int(animated_tile.get("x", 0)), int(animated_tile.get("y", 0)))
				var tile_rect: Rect2 = Rect2(tile_world_position, Vector2(16.0, 16.0))
				if not tile_rect.intersects(camera_rect):
					continue
				var animated_texture: Texture2D = content.animated_metatile_texture(region_id, animated_tile, animation_tick, false)
				if animated_texture == null:
					continue
				draw_texture_rect(animated_texture, Rect2(destination_position + (tile_world_position - camera_origin) * tile_scale, Vector2(16.0, 16.0) * tile_scale), false)
			var foreground: Texture2D = region.get("foreground_texture") as Texture2D
			if foreground != null:
				var first_row: int = maxi(0, floori((camera_rect.position.y - region_origin.y) / TILE_PIXELS) - 1)
				var last_row: int = mini(int(region.get("render_height", region.get("height", 0))) - 1, ceili((camera_rect.end.y - region_origin.y) / TILE_PIXELS) + 1)
				for row_index in range(first_row, last_row + 1):
					var row_rect: Rect2 = Rect2(region_origin + Vector2(0.0, row_index * TILE_PIXELS), Vector2(region_size.x, TILE_PIXELS))
					var visible_row: Rect2 = row_rect.intersection(camera_rect)
					if visible_row.size.x > 0.0 and visible_row.size.y > 0.0:
						drawables.append({"kind": "foreground", "map_id": region_id, "texture": foreground, "rect": visible_row, "sort_y": float(_region_render_origin(region_id).y + row_index + 1), "sort_order": 2})
			for tile_value in region.get("animated_foreground_tiles", []):
				if not tile_value is Dictionary:
					continue
				var animated_tile: Dictionary = tile_value
				var tile_world_position: Vector2 = region_origin + Vector2(int(animated_tile.get("x", 0)), int(animated_tile.get("y", 0)))
				var tile_rect: Rect2 = Rect2(tile_world_position, Vector2(16.0, 16.0))
				if not tile_rect.intersects(camera_rect):
					continue
				var animated_texture: Texture2D = content.animated_metatile_texture(region_id, animated_tile, animation_tick, true)
				if animated_texture == null:
					continue
				drawables.append({"kind": "animated_tile", "texture": animated_texture, "world_position": tile_world_position, "sort_y": float(_region_render_origin(region_id).y + floori(float(int(animated_tile.get("y", 0))) / TILE_PIXELS) + 1), "sort_order": 3})
			for object_value in region.get("objects", []):
				if not object_value is Dictionary:
					continue
				var object: Dictionary = object_value
				if authoritative_state and str(object.get("kind", "")) == "object":
					continue
				if not bool(object.get("render", true)):
					continue
				var texture: Texture2D = object.get("texture") as Texture2D
				if texture == null:
					continue
				var sprite_size: Vector2 = Vector2(int(object.get("width", 0)), int(object.get("height", 0)))
				if sprite_size.x <= 0.0 or sprite_size.y <= 0.0:
					continue
				var object_world: Vector2 = _world_position(region_id, Vector2(int(object.get("x", 0)), int(object.get("y", 0))))
				var object_rect: Rect2 = Rect2(Vector2((object_world.x + 0.5) * TILE_PIXELS - sprite_size.x * 0.5, (object_world.y + 1.0) * TILE_PIXELS - sprite_size.y), sprite_size)
				if not object_rect.grow(TILE_PIXELS).intersects(camera_rect):
					continue
				var furniture: bool = bool(object.get("inanimate", false)) or (int(object.get("height", 0)) <= 16 and int(object.get("width", 0)) >= 32)
				drawables.append({"kind": "sprite", "texture": texture, "width": sprite_size.x, "height": sprite_size.y, "world_anchor": Vector2((object_world.x + 0.5) * TILE_PIXELS, (object_world.y + 1.0) * TILE_PIXELS), "sort_y": object_world.y + 1.0, "sort_order": -1 if furniture else 0})
	for entity_value in world_entities:
		if not entity_value is Dictionary:
			continue
		var entity: Dictionary = entity_value
		if not bool(entity.get("visible", true)):
			continue
		var entity_texture: Texture2D = entity.get("texture") as Texture2D
		var entity_map_id: String = str(entity.get("map_id", ""))
		var entity_world: Vector2 = _world_position(entity_map_id, _world_entity_render_position(entity))
		if bool(entity.get("battle", false)):
			drawables.append({"kind": "battle_marker", "world_position": Vector2((entity_world.x + 0.5) * TILE_PIXELS, entity_world.y * TILE_PIXELS - 3.0), "sort_y": entity_world.y + 0.1, "sort_order": 3})
		if entity_texture == null:
			continue
		var entity_furniture: bool = bool(entity.get("inanimate", false)) or int(entity.get("graphics_id", -1)) == 93 or (float(entity.get("height", 0)) <= 16.0 and float(entity.get("width", 0)) >= 32.0)
		drawables.append({"kind": "sprite", "texture": entity_texture, "width": float(entity.get("width", 0)), "height": float(entity.get("height", 0)), "world_anchor": Vector2((entity_world.x + 0.5) * TILE_PIXELS, (entity_world.y + 1.0) * TILE_PIXELS), "sort_y": entity_world.y + 1.0, "sort_order": -1 if entity_furniture else 0})
	if follower_texture != null and following_party_index >= 0 and follower_initialized:
		drawables.append({"kind": "sprite", "texture": follower_texture, "width": follower_width, "height": follower_height, "world_anchor": (follower_position + Vector2(0.5, 1.0)) * TILE_PIXELS, "sort_y": follower_position.y + 1.0, "sort_order": 0})
	if player_texture != null and player_visible:
		var player_size: Vector2 = Vector2(player_texture.get_width(), player_texture.get_height())
		var player_anchor: Vector2 = (world_player + Vector2(0.5, 1.0)) * TILE_PIXELS
		drawables.append({"kind": "sprite", "texture": player_texture, "width": player_size.x, "height": player_size.y, "world_anchor": player_anchor, "sort_y": world_player.y + 1.0, "sort_order": 1})
	if movement_active and movement_door and content != null:
		var door_frame: Dictionary = content.door_animation_frame(map_id, movement_door_position.x, movement_door_position.y, _door_frame_index())
		var door_texture: Texture2D = door_frame.get("texture") as Texture2D
		if door_texture != null:
			var door_world: Vector2 = _world_position(map_id, Vector2(movement_door_position))
			drawables.append({"kind": "door", "texture": door_texture, "width": float(door_texture.get_width()), "height": float(door_texture.get_height()), "world_anchor": Vector2((door_world.x + 0.5) * TILE_PIXELS, (door_world.y + 1.0) * TILE_PIXELS), "sort_y": door_world.y + 1.0, "sort_order": 3})
	drawables.sort_custom(_sort_drawables)
	for drawable_value in drawables:
		var drawable: Dictionary = drawable_value
		if str(drawable.get("kind", "sprite")) == "foreground":
			var foreground_rect: Rect2 = drawable.get("rect", Rect2())
			var foreground_texture_value: Texture2D = drawable.get("texture") as Texture2D
			var foreground_destination: Rect2 = Rect2(destination_position + (foreground_rect.position - camera_origin) * tile_scale, foreground_rect.size * tile_scale)
			var foreground_origin: Vector2 = Vector2(_region_render_origin(str(drawable.get("map_id", "")))) * TILE_PIXELS
			draw_texture_rect_region(foreground_texture_value, foreground_destination, Rect2(foreground_rect.position - foreground_origin, foreground_rect.size), Color.WHITE, false, true)
			continue
		if str(drawable.get("kind", "sprite")) == "animated_tile":
			var animated_drawable_texture: Texture2D = drawable.get("texture") as Texture2D
			var animated_world_position: Vector2 = drawable.get("world_position", Vector2.ZERO)
			draw_texture_rect(animated_drawable_texture, Rect2(destination_position + (animated_world_position - camera_origin) * tile_scale, Vector2(16.0, 16.0) * tile_scale), false)
			continue
		if str(drawable.get("kind", "sprite")) == "battle_marker":
			var marker_world_position: Vector2 = drawable.get("world_position", Vector2.ZERO)
			var marker_position: Vector2 = destination_position + (marker_world_position - camera_origin) * tile_scale
			var marker_radius: float = maxf(4.0 * tile_scale, 3.0)
			draw_circle(marker_position, marker_radius, Color("f5f7fb"))
			draw_arc(marker_position, marker_radius - 0.5, PI, TAU, 16, Color("e45763"), maxf(tile_scale, 1.0), true)
			draw_line(marker_position + Vector2(-marker_radius, 0.0), marker_position + Vector2(marker_radius, 0.0), Color("202633"), maxf(tile_scale, 1.0), true)
			draw_circle(marker_position, marker_radius * 0.28, Color("202633"))
			draw_circle(marker_position, marker_radius * 0.13, Color("f5f7fb"))
			continue
		var drawable_texture: Texture2D = drawable.get("texture") as Texture2D
		var drawable_size: Vector2 = Vector2(float(drawable.get("width", 0.0)), float(drawable.get("height", 0.0)))
		var drawable_anchor: Vector2 = drawable.get("world_anchor", Vector2.ZERO)
		var drawable_position: Vector2 = destination_position + (drawable_anchor - camera_origin) * tile_scale - Vector2(drawable_size.x * tile_scale * 0.5, drawable_size.y * tile_scale)
		draw_texture_rect(drawable_texture, Rect2(drawable_position, drawable_size * tile_scale), false)

func _sort_drawables(left: Dictionary, right: Dictionary) -> bool:
	var left_y: float = float(left.get("sort_y", 0.0))
	var right_y: float = float(right.get("sort_y", 0.0))
	if not is_equal_approx(left_y, right_y):
		return left_y < right_y
	return int(left.get("sort_order", 0)) < int(right.get("sort_order", 0))
