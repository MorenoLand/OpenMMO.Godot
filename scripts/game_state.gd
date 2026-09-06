extends Node

const DEFAULT_ROOT_PUBLIC_KEY_PATH: String = "res://config/openmmo/game.public.pem"

signal characters_changed(characters: Array)
signal world_snapshot_received(snapshot: Dictionary)
signal entity_update_received(update: Dictionary)
signal chat_received(message: Dictionary)
signal battle_event_received(event: Dictionary)
signal character_state_changed(state: Dictionary)
signal shop_catalog_received(catalog: Dictionary)
signal map_load_received(map_load: Dictionary)
signal dialog_action_received(action: Dictionary)
signal dialog_state_received(open: bool)
signal render_screen_changed(visible: bool)
signal connection_error(message: String)
signal login_completed(result: Dictionary)
signal game_connection_completed(result: Dictionary)
signal story_state_changed(state: Dictionary)
signal story_state_resynced(state: Dictionary)

const SESSION_SCRIPT = preload("res://scripts/net/session.gd")
const LOGIN_PROTOCOL_SCRIPT = preload("res://scripts/net/login_protocol.gd")
const GAME_PROTOCOL_SCRIPT = preload("res://scripts/net/game_protocol.gd")
const FLOW_TIMEOUT_MSEC: int = 15000

var login_session: Node
var game_session: Node
var content: OpenMMOContent
var contents: Dictionary = {}
var user: Dictionary = {}
var characters: Array = []
var current_snapshot: Dictionary = {}
var current_character: Dictionary = {}
var login_host: String = "127.0.0.1"
var login_port: int = 2106
var root_public_key_path: String = DEFAULT_ROOT_PUBLIC_KEY_PATH
var custom_root_public_key_path: String = ""
var login_flow: String = "idle"
var game_flow: String = "idle"
var flow_deadline_msec: int = 0
var game_access: Dictionary = {}
var hardware_id: PackedByteArray = PackedByteArray()
var server_maps: Dictionary = {}
var pending_map_load: Dictionary = {}
var awaiting_local_entity: bool = false
var map_transition_pending: bool = false
var map_load_spawn_window: bool = false
var active_map_key: String = ""
var story_region_id: int = -1
var game_clock_minutes: int = -1
var game_clock_set_msec: int = 0
var story_flags: Dictionary = {}
var story_variables: Dictionary = {}
var world_flag_groups: Array = []
var world_flags: Dictionary = {}
var battle_state: Dictionary = {}
var battle_in_progress: bool = false
var battle_presence: Dictionary = {}
var active_shop: Dictionary = {}

func _ready() -> void:
	login_session = SESSION_SCRIPT.new()
	login_session.name = "LoginSession"
	add_child(login_session)
	game_session = SESSION_SCRIPT.new()
	game_session.name = "GameSession"
	add_child(game_session)
	login_session.established.connect(_on_login_established)
	login_session.packet_received.connect(_on_login_packet)
	login_session.failed.connect(_on_login_failed)
	game_session.established.connect(_on_game_established)
	game_session.packet_received.connect(_on_game_packet)
	game_session.failed.connect(_on_game_failed)
	var settings: Dictionary = OpenMMOStorage.read_json(OpenMMOStorage.SETTINGS_FILE)
	login_host = str(settings.get("login_host", ProjectSettings.get_setting("openmmo/login_host", "127.0.0.1")))
	login_port = int(settings.get("login_port", ProjectSettings.get_setting("openmmo/login_port", 2106)))
	custom_root_public_key_path = str(settings.get("root_public_key_path", "")).strip_edges()
	if not custom_root_public_key_path.is_empty() and FileAccess.file_exists(custom_root_public_key_path):
		root_public_key_path = custom_root_public_key_path
	else:
		custom_root_public_key_path = ""
		root_public_key_path = str(ProjectSettings.get_setting("openmmo/root_public_key_path", DEFAULT_ROOT_PUBLIC_KEY_PATH))
	hardware_id = _load_hardware_id(settings)
	set_process(true)

func _process(_delta: float) -> void:
	if flow_deadline_msec <= 0 or Time.get_ticks_msec() < flow_deadline_msec:
		return
	if login_flow != "idle":
		_finish_login({"ok": false, "error": "OpenMMO login timed out"})
	elif game_flow != "idle":
		_finish_game_connection({"ok": false, "error": "OpenMMO game connection timed out"})

func configure_server(endpoint: String, public_key_path: String) -> Dictionary:
	var parsed: Dictionary = _parse_endpoint(endpoint, 2106)
	if not parsed.ok:
		return parsed
	var custom_key_path: String = public_key_path.strip_edges()
	var key_path: String = DEFAULT_ROOT_PUBLIC_KEY_PATH if custom_key_path.is_empty() else custom_key_path
	if not FileAccess.file_exists(key_path):
		return {"ok": false, "error": "The bundled OpenMMO server key is missing" if custom_key_path.is_empty() else "The custom OpenMMO server key could not be found"}
	login_host = str(parsed.host)
	login_port = int(parsed.port)
	root_public_key_path = key_path
	custom_root_public_key_path = custom_key_path
	return {"ok": true}

func endpoint_text() -> String:
	return "%s:%d" % [login_host, login_port]

func public_key_override() -> String:
	return custom_root_public_key_path

func use_content(value: OpenMMOContent) -> Dictionary:
	if value == null:
		return {"ok": false, "error": "content is missing"}
	var region: String = str(value.source_profile.get("region", "")).strip_edges().to_lower()
	if region.is_empty():
		region = "kanto"
	contents[region] = value
	content = _preferred_content()
	return {"ok": true}

func has_content() -> bool:
	return content != null or not contents.is_empty()

func all_contents() -> Array:
	var values: Array = []
	for key in ["kanto", "hoenn"]:
		if contents.has(key) and contents[key] != null:
			values.append(contents[key])
	for key in contents.keys():
		if str(key) in ["kanto", "hoenn"]:
			continue
		if contents[key] != null:
			values.append(contents[key])
	return values

func content_regions_ready() -> PackedStringArray:
	var ready: PackedStringArray = PackedStringArray()
	for key in ["kanto", "hoenn"]:
		if contents.has(key) and contents[key] != null:
			ready.append(str(key).capitalize())
	return ready

func content_for_region(region: String) -> OpenMMOContent:
	var key: String = region.strip_edges().to_lower()
	if contents.has(key):
		return contents[key] as OpenMMOContent
	return null

func content_for_location(bank_id: int, map_id: int) -> OpenMMOContent:
	var best: OpenMMOContent = null
	var best_score: int = -1
	for content_value in all_contents():
		var score: int = _location_content_score(content_value, bank_id, map_id)
		if score > best_score:
			best_score = score
			best = content_value
	if best != null:
		return best
	return content

func map_id_for_location(bank_id: int, map_id: int) -> String:
	var chosen: OpenMMOContent = content_for_location(bank_id, map_id)
	if chosen == null:
		return ""
	var local_bank: int = _local_bank_for_content(chosen, bank_id)
	return chosen.map_id_for_location(local_bank, map_id)

func map_data_for_location(bank_id: int, map_id: int) -> Dictionary:
	var chosen: OpenMMOContent = content_for_location(bank_id, map_id)
	if chosen == null:
		return {}
	var local_bank: int = _local_bank_for_content(chosen, bank_id)
	var local_id: String = chosen.map_id_for_location(local_bank, map_id)
	if local_id.is_empty():
		return {}
	return chosen.map_data(local_id)

func content_for_text_id(text_id: int) -> OpenMMOContent:
	# 0x10xxxxxx = Emerald file-offset tag (OpenMMO-Client gba_text.h); never decode on Kanto.
	var tag: int = (text_id >> 24) & 0xFF
	if tag == 0x10:
		var hoenn: OpenMMOContent = content_for_region("hoenn")
		if hoenn != null:
			return hoenn
		# Do not fall back to Kanto — Emerald offsets on FireRed yield garbage/stubs.
		return null
	if content != null:
		return content
	return _preferred_content()

func activate_content_for_location(bank_id: int, map_id: int) -> OpenMMOContent:

	var chosen: OpenMMOContent = content_for_location(bank_id, map_id)
	if chosen != null:
		content = chosen
	return content

func _preferred_content() -> OpenMMOContent:
	if contents.has("kanto") and contents["kanto"] != null:
		return contents["kanto"] as OpenMMOContent
	if contents.has("hoenn") and contents["hoenn"] != null:
		return contents["hoenn"] as OpenMMOContent
	for value in contents.values():
		if value != null:
			return value as OpenMMOContent
	return content

func _local_bank_for_content(value: OpenMMOContent, bank_id: int) -> int:
	if value == null:
		return bank_id
	var region: String = str(value.source_profile.get("region", "")).strip_edges().to_lower()
	# OpenMMO server tags Hoenn banks with +50 (see OpenMMO-Client GbaTables.serverBankOffset).
	if region == "hoenn" and bank_id >= 50:
		return bank_id - 50
	return bank_id

func _location_content_score(value: OpenMMOContent, bank_id: int, map_id: int) -> int:
	if value == null or bank_id < 0 or map_id < 0:
		return -1
	var region: String = str(value.source_profile.get("region", "")).strip_edges().to_lower()
	var local_bank: int = _local_bank_for_content(value, bank_id)
	var local_id: String = value.map_id_for_location(local_bank, map_id)
	if local_id.is_empty():
		return -1
	var map_value: Dictionary = value.map_data(local_id)
	if map_value.is_empty():
		return -1
	var name: String = str(map_value.get("name", "")).strip_edges()
	var score: int = 1
	if not name.is_empty() and name != "Unlisted area" and not name.begins_with("rom-map-"):
		score += 10
	if not local_id.begins_with("rom-map-"):
		score += 5
	if region == "hoenn" and bank_id >= 50:
		score += 8
	if region == "kanto" and bank_id < 50:
		score += 8
	return score

func is_story_flag_set(region_id: int, flag_id: int) -> bool:
	var region_value: Variant = story_flags.get(str(region_id), {})
	if not region_value is Dictionary:
		return false
	return bool((region_value as Dictionary).get(str(flag_id & 0xFFFF), false))

func story_variable(region_id: int, variable_key: int, default_value: int = 0) -> int:
	var region_value: Variant = story_variables.get(str(region_id), {})
	if not region_value is Dictionary:
		return default_value
	return int((region_value as Dictionary).get(str(variable_key & 0xFF), default_value))

func _story_state_snapshot() -> Dictionary:
	return {"region_id": story_region_id, "flags": story_flags.duplicate(true), "variables": story_variables.duplicate(true)}

func _clear_story_state() -> void:
	story_region_id = -1
	story_flags.clear()
	story_variables.clear()
	world_flag_groups.clear()
	world_flags.clear()
	if not current_character.is_empty():
		current_character.erase("story_flags")
		current_character.erase("story_variables")

func login(username: String, password: String, stay_logged_in: bool = false, saved_token: String = "") -> Dictionary:
	if login_flow != "idle" or game_flow != "idle":
		return {"ok": false, "error": "another connection is already in progress"}
	if root_public_key_path.is_empty() or not FileAccess.file_exists(root_public_key_path):
		return {"ok": false, "error": "The OpenMMO server key is unavailable; restore the bundled key or choose a custom key in Settings"}
	var token: String = saved_token.strip_edges()
	user = {"username": username, "password": password, "stay_logged_in": stay_logged_in, "saved_key": token, "login_method": "token" if not token.is_empty() else "password"}
	game_access.clear()
	login_flow = "connecting"
	flow_deadline_msec = Time.get_ticks_msec() + FLOW_TIMEOUT_MSEC
	var error: Error = login_session.connect_openmmo(login_host, login_port, root_public_key_path)
	if error != OK:
		login_flow = "idle"
		flow_deadline_msec = 0
		return {"ok": false, "error": "could not connect to OpenMMO login server (%s)" % error_string(error)}
	var result: Dictionary = await login_completed
	if bool(result.get("ok", false)):
		result["remember_token"] = str(user.get("saved_key", ""))
	return result

func connect_game() -> Dictionary:
	if game_access.is_empty():
		return {"ok": false, "error": "OpenMMO login did not provide a game server"}
	if game_flow != "idle":
		return {"ok": false, "error": "game connection is already in progress"}
	var endpoint: Dictionary = _game_endpoint(game_access)
	if not endpoint.ok:
		return endpoint
	game_flow = "connecting"
	flow_deadline_msec = Time.get_ticks_msec() + FLOW_TIMEOUT_MSEC
	var error: Error = game_session.connect_openmmo(str(endpoint.host), int(endpoint.port), root_public_key_path, true)
	if error != OK:
		game_flow = "idle"
		flow_deadline_msec = 0
		return {"ok": false, "error": "could not connect to OpenMMO game server (%s)" % error_string(error)}
	var result: Dictionary = await game_connection_completed
	return result

func list_characters() -> Dictionary:
	if not game_session.send_packet(GAME_PROTOCOL_SCRIPT.REQUEST_CHARACTERS, GAME_PROTOCOL_SCRIPT.encode_request_characters()):
		return {"ok": false, "error": "game connection is not ready"}
	return {"ok": true, "data": characters}

func create_character(_name: String) -> Dictionary:
	return {"ok": false, "error": "OpenMMO character creation is not wired yet"}

func select_character(character_id: int) -> bool:
	for character_value in characters:
		if character_value is Dictionary and int(character_value.get("id", 0)) == character_id:
			current_character = (character_value as Dictionary).duplicate(true)
			if current_character.get("bag", []) is Array:
				current_character["bag"] = _normalise_bag(current_character.get("bag", []))
			activate_content_for_location(int(current_character.get("bank_id", -1)), int(current_character.get("map_id", -1)))
			break
	active_map_key = ""
	pending_map_load.clear()
	map_load_spawn_window = false
	_clear_story_state()
	awaiting_local_entity = false
	map_transition_pending = false
	battle_state.clear()
	battle_in_progress = false
	battle_presence.clear()
	return game_session.send_packet(GAME_PROTOCOL_SCRIPT.SELECT_CHARACTER, GAME_PROTOCOL_SCRIPT.encode_select_character(character_id))

func complete_map_load(load_key: String) -> bool:
	if pending_map_load.is_empty() or str(pending_map_load.get("key", "")) != load_key:
		return false
	var map_load: Dictionary = pending_map_load.duplicate(true)
	var reload_local_player: bool = bool(map_load.get("delete_cache", false)) and bool(map_load.get("reload_player", false))
	if not reload_local_player:
		pending_map_load.clear()
		return true
	awaiting_local_entity = true
	if not game_session.send_packet(GAME_PROTOCOL_SCRIPT.MAP_LOADED_ACK, GAME_PROTOCOL_SCRIPT.encode_map_loaded_ack()):
		awaiting_local_entity = false
		return false
	if not game_session.send_packet(GAME_PROTOCOL_SCRIPT.REQUEST_PLAYER, GAME_PROTOCOL_SCRIPT.encode_request_player()):
		awaiting_local_entity = false
		return false
	pending_map_load.clear()
	return true

func send_input(direction: String, source_x: int = -1, source_y: int = -1, running: bool = false) -> bool:
	var x: int = source_x if source_x >= 0 else int(current_character.get("x", -1))
	var y: int = source_y if source_y >= 0 else int(current_character.get("y", -1))
	if x < 0 or y < 0:
		return false
	var payload: PackedByteArray = GAME_PROTOCOL_SCRIPT.encode_movement(x, y, direction, running)
	return not payload.is_empty() and game_session.send_packet(GAME_PROTOCOL_SCRIPT.MOVEMENT, payload)

func send_face_direction(direction: String) -> bool:
	var payload: PackedByteArray = GAME_PROTOCOL_SCRIPT.encode_face_direction(direction)
	return not payload.is_empty() and game_session.send_packet(GAME_PROTOCOL_SCRIPT.FACE_DIRECTION, payload)

func send_entity_interact(entity_id: int, token: int = 0) -> bool:
	return game_session.send_packet(GAME_PROTOCOL_SCRIPT.ENTITY_INTERACT, GAME_PROTOCOL_SCRIPT.encode_entity_interact(entity_id, token))

func send_tile_interact() -> bool:
	return game_session.send_packet(GAME_PROTOCOL_SCRIPT.TILE_INTERACT, GAME_PROTOCOL_SCRIPT.encode_tile_interact())

func send_dialogue_action_response(dialogue_id: int, value: int = 0) -> bool:
	return game_session.send_packet(GAME_PROTOCOL_SCRIPT.DIALOG_ACTION, GAME_PROTOCOL_SCRIPT.encode_dialog_action_response(dialogue_id, value))

func send_chat(text: String, channel: String = "Normal") -> bool:
	if channel != "Normal":
		return false
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return false
	if trimmed.begins_with("/"):
		var command_payload: PackedByteArray = GAME_PROTOCOL_SCRIPT.encode_chat_send(4, "", trimmed)
		return not command_payload.is_empty() and game_session.send_packet(GAME_PROTOCOL_SCRIPT.CHAT_SEND, command_payload)
	var payload: PackedByteArray = GAME_PROTOCOL_SCRIPT.encode_chat_message(trimmed, 0, 0)
	return not payload.is_empty() and game_session.send_packet(GAME_PROTOCOL_SCRIPT.CHAT_MESSAGE, payload)

func send_battle_action(action: int, move_or_item_id: int = 0, target_entity_id: int = 0, extra_flag: int = 0, slot_ref: int = 0) -> bool:
	var payload: PackedByteArray = GAME_PROTOCOL_SCRIPT.encode_battle_action_select(action, move_or_item_id, target_entity_id, extra_flag, slot_ref)
	return not payload.is_empty() and game_session.send_packet(GAME_PROTOCOL_SCRIPT.BATTLE_ACTION_SELECT, payload)

func send_shop_buy(item_id: int, quantity: int, exchange_type_index: int = 0) -> bool:
	var payload: PackedByteArray = GAME_PROTOCOL_SCRIPT.encode_shop_buy(item_id, quantity, exchange_type_index)
	return not payload.is_empty() and game_session.send_packet(GAME_PROTOCOL_SCRIPT.SHOP_BUY, payload)

func send_shop_sell(item_entity_id: int, quantity: int) -> bool:
	var payload: PackedByteArray = GAME_PROTOCOL_SCRIPT.encode_shop_sell(item_entity_id, quantity)
	return not payload.is_empty() and game_session.send_packet(GAME_PROTOCOL_SCRIPT.SHOP_SELL, payload)

func disconnect_game() -> void:
	pending_map_load.clear()
	server_maps.clear()
	awaiting_local_entity = false
	map_transition_pending = false
	map_load_spawn_window = false
	_clear_story_state()
	battle_state.clear()
	battle_in_progress = false
	battle_presence.clear()
	active_shop.clear()
	game_session.close()

func _on_login_established() -> void:
	if login_flow != "connecting":
		return
	login_flow = "response"
	var saved_token: PackedByteArray = Marshalls.base64_to_raw(str(user.get("saved_key", "")))
	var payload: PackedByteArray = LOGIN_PROTOCOL_SCRIPT.encode_token_login(str(user.get("username", "")), saved_token, hardware_id, _os_ordinal()) if user.get("login_method", "password") == "token" and not saved_token.is_empty() else LOGIN_PROTOCOL_SCRIPT.encode_password_login(str(user.get("username", "")), str(user.get("password", "")), bool(user.get("stay_logged_in", false)), hardware_id, _os_ordinal())
	if payload.is_empty() or not login_session.send_packet(LOGIN_PROTOCOL_SCRIPT.LOGIN_REQUEST, payload):
		_finish_login({"ok": false, "error": "OpenMMO login request could not be sent"})

func _on_login_packet(opcode: int, payload: PackedByteArray) -> void:
	if login_flow == "response" and opcode == LOGIN_PROTOCOL_SCRIPT.LOGIN_RESPONSE:
		var response: Dictionary = LOGIN_PROTOCOL_SCRIPT.decode_login_response(payload)
		if not response.ok or not bool(response.get("authenticated", false)):
			if int(response.get("state", -1)) == 30 and user.get("login_method", "password") == "token" and not str(user.get("password", "")).is_empty():
				user["login_method"] = "password"
				var password_payload: PackedByteArray = LOGIN_PROTOCOL_SCRIPT.encode_password_login(str(user.get("username", "")), str(user.get("password", "")), bool(user.get("stay_logged_in", false)), hardware_id, _os_ordinal())
				if not password_payload.is_empty() and login_session.send_packet(LOGIN_PROTOCOL_SCRIPT.LOGIN_REQUEST, password_payload):
					return
			_finish_login({"ok": false, "error": str(response.get("message", "OpenMMO login failed"))})
			return
		login_flow = "server_list"
		if not login_session.send_packet(LOGIN_PROTOCOL_SCRIPT.REQUEST_SERVER_LIST, LOGIN_PROTOCOL_SCRIPT.encode_server_list_request()):
			_finish_login({"ok": false, "error": "OpenMMO server-list request could not be sent"})
	elif login_flow == "server_list" and opcode == LOGIN_PROTOCOL_SCRIPT.GAME_SERVER_LIST:
		var response: Dictionary = LOGIN_PROTOCOL_SCRIPT.decode_server_list(payload)
		if not response.ok:
			_finish_login({"ok": false, "error": "OpenMMO server list is malformed"})
			return
		var server_id: int = -1
		for server in response.servers:
			if bool(server.get("joinable", false)):
				server_id = int(server.get("id", -1))
				break
		if server_id < 0:
			_finish_login({"ok": false, "error": "no joinable OpenMMO game server is available"})
			return
		login_flow = "nodes"
		if not login_session.send_packet(LOGIN_PROTOCOL_SCRIPT.JOIN_GAME_SERVER, LOGIN_PROTOCOL_SCRIPT.encode_join_server(server_id)):
			_finish_login({"ok": false, "error": "OpenMMO game-server request could not be sent"})
	elif login_flow == "nodes" and opcode == LOGIN_PROTOCOL_SCRIPT.GAME_SERVER_NODES:
		var response: Dictionary = LOGIN_PROTOCOL_SCRIPT.decode_game_server_nodes(payload)
		if not response.ok or int(response.get("state", -1)) != 0:
			_finish_login({"ok": false, "error": str(response.get("message", "OpenMMO game-server handoff failed"))})
			return
		game_access = response
		_finish_login({"ok": true, "data": response})
	elif opcode == LOGIN_PROTOCOL_SCRIPT.SENT_CREDENTIALS:
		var credentials: Dictionary = LOGIN_PROTOCOL_SCRIPT.decode_sent_credentials(payload)
		if credentials.ok:
			user["saved_key"] = credentials.key

func _on_game_established() -> void:
	if game_flow != "connecting":
		return
	game_flow = "join"
	var session_token: PackedByteArray = game_access.get("session_token", PackedByteArray())
	var payload: PackedByteArray = GAME_PROTOCOL_SCRIPT.encode_join(int(game_access.get("user_id", 0)), session_token, hardware_id)
	if payload.is_empty() or not game_session.send_packet(GAME_PROTOCOL_SCRIPT.JOIN, payload):
		_finish_game_connection({"ok": false, "error": "OpenMMO game join could not be sent"})

func _on_game_packet(opcode: int, payload: PackedByteArray) -> void:
	if game_flow == "join" and opcode == GAME_PROTOCOL_SCRIPT.JOIN:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_join_response(payload)
		if not response.ok or not bool(response.get("can_join", false)):
			_finish_game_connection({"ok": false, "error": str(response.get("error", "OpenMMO game join failed"))})
			return
		user["playtime"] = int(response.get("playtime", 0))
		user["reward_points"] = int(response.get("reward_points", 0))
		user["balance"] = int(response.get("balance", 0))
		game_flow = "characters"
		if not game_session.send_packet(GAME_PROTOCOL_SCRIPT.REQUEST_CHARACTERS, GAME_PROTOCOL_SCRIPT.encode_request_characters()):
			_finish_game_connection({"ok": false, "error": "OpenMMO character-list request could not be sent"})
	elif opcode == GAME_PROTOCOL_SCRIPT.ENTITY_PRESENCE:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_entity_presence(payload)
		if not response.ok:
			connection_error.emit(str(response.get("error", "OpenMMO entity presence packet is malformed")))
			return
		var presence: Dictionary = response.presence
		battle_presence[str(int(presence.get("entity_id", 0)))] = int(presence.get("status", 0)) != 0
		if int(presence.get("entity_id", 0)) == int(current_character.get("id", 0)):
			battle_in_progress = int(presence.get("status", 0)) != 0
			battle_state["in_progress"] = battle_in_progress
		battle_event_received.emit({"type": "presence", "presence": presence, "in_progress": battle_in_progress})
	elif opcode == GAME_PROTOCOL_SCRIPT.REQUEST_CHARACTERS:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_characters(payload)
		if response.ok:
			characters = response.characters
			characters_changed.emit(characters)
			if game_flow == "characters":
				_finish_game_connection({"ok": true, "data": {"characters": characters}})
		else:
			var message: String = str(response.get("error", "OpenMMO character list is malformed"))
			if game_flow == "characters":
				_finish_game_connection({"ok": false, "error": message})
			else:
				connection_error.emit(message)
	elif opcode == GAME_PROTOCOL_SCRIPT.WORLD_FLAG_TABLE_RESET:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_world_flag_table_reset(payload)
		if response.ok:
			world_flag_groups = response.get("groups", [])
			world_flags.clear()
		else:
			connection_error.emit(str(response.get("error", "OpenMMO world flag table packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.WORLD_FLAG_SET:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_world_flag_set(payload)
		if response.ok:
			_apply_world_flag_set(response)
		else:
			connection_error.emit(str(response.get("error", "OpenMMO world flag packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.STORY_FLAG_UPDATE:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_story_flag_update(payload)
		if response.ok:
			_apply_story_flag_update(response)
		else:
			connection_error.emit(str(response.get("error", "OpenMMO story flag packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.LOCAL_PLAYER_STATE:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_local_player_state(payload)
		if response.ok:
			_apply_local_player_state(response.get("state", {}))
		else:
			connection_error.emit(str(response.get("error", "OpenMMO local player state packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.CHAT_MESSAGE:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_chat_message(payload)
		if response.ok:
			chat_received.emit(response.message)
		else:
			connection_error.emit(str(response.get("error", "OpenMMO chat message is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.SERVER_NOTICE:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_server_notice(payload)
		if response.ok:
			var notice: Dictionary = response.notice
			notice["channel"] = "Local"
			notice["system"] = true
			chat_received.emit(notice)
		else:
			connection_error.emit(str(response.get("error", "OpenMMO server notice is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.LOCAL_CHARACTER_DELTA:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_local_character_delta(payload)
		if response.ok:
			_apply_character_updates(response.updates)
		else:
			connection_error.emit(str(response.get("error", "OpenMMO local character delta packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.POKEMON_STORAGE:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_pokemon_storage(payload)
		if response.ok:
			_apply_pokemon_storage(response)
		else:
			connection_error.emit(str(response.get("error", "OpenMMO Pokemon storage packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.SHOP_CATALOG:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_shop_catalog(payload)
		if not response.ok:
			connection_error.emit(str(response.get("error", "OpenMMO shop catalog packet is malformed")))
			return
		var items: Array = []
		for item_value in response.get("items", []):
			if not item_value is Dictionary:
				continue
			var item: Dictionary = (item_value as Dictionary).duplicate(true)
			if content != null:
				item.merge(content.battle_item_info(int(item.get("item_id", 0))))
			items.append(item)
		response["items"] = items
		active_shop = response.duplicate(true) if bool(response.get("open", false)) else {}
		shop_catalog_received.emit(response)
	elif opcode == GAME_PROTOCOL_SCRIPT.BATTLE_SIDE_PARTY:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_battle_side_party(payload)
		if response.ok:
			_apply_bag_snapshot(response)
		else:
			connection_error.emit(str(response.get("error", "OpenMMO bag snapshot packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.BATTLE_SIDE_ADD_POKEMON:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_battle_side_add_pokemon(payload)
		if response.ok:
			_apply_bag_stack(response)
		else:
			connection_error.emit(str(response.get("error", "OpenMMO bag update packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.BATTLE_SIDE:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_battle_side(payload)
		if response.ok:
			battle_state["player_side"] = int(response.get("side", 0))
			battle_event_received.emit({"type": "side", "side": int(response.get("side", 0))})
		else:
			connection_error.emit(str(response.get("error", "OpenMMO battle-side packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.BATTLE_FIELD_STATE:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_battle_field_state(payload)
		if not response.ok:
			connection_error.emit(str(response.get("error", "OpenMMO battle field state is malformed")))
			return
		battle_state = (response.state as Dictionary).duplicate(true)
		battle_state["in_progress"] = true
		battle_state["can_act"] = false
		battle_state["force_switch"] = false
		battle_in_progress = true
		_hydrate_battle_party_xp()
		_sync_current_party_from_battle()
		battle_event_received.emit({"type": "field_state", "state": battle_state})
	elif opcode == GAME_PROTOCOL_SCRIPT.BATTLE_BULK_STATE:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_battle_bulk_state(payload)
		if not response.ok:
			connection_error.emit(str(response.get("error", "OpenMMO battle bulk state is malformed")))
			return
		battle_state["phase"] = int(response.get("phase", 0))
		battle_state["prize_money"] = int(response.get("prize_money", 0))
		battle_state["value_b"] = int(response.get("value_b", 0))
		battle_state["battle_flag"] = int(response.get("flag", 0))
		battle_state["in_progress"] = false
		battle_state["can_act"] = false
		battle_state["battle_complete"] = true
		battle_in_progress = false
		_sync_current_party_from_battle()
		game_session.send_packet(GAME_PROTOCOL_SCRIPT.MAP_LOADED_ACK, GAME_PROTOCOL_SCRIPT.encode_map_loaded_ack())
		battle_event_received.emit({"type": "battle_end", "state": battle_state.duplicate(true)})
	elif opcode == GAME_PROTOCOL_SCRIPT.BATTLE_QUEUED_EVENT:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_battle_queued_event(payload)
		if response.ok:
			battle_state["can_act"] = bool(response.get("prompt", false))
			battle_state["prompt_value"] = int(response.get("value", 0))
			battle_event_received.emit({"type": "queued_event", "event": response, "state": battle_state})
		else:
			connection_error.emit(str(response.get("error", "OpenMMO battle queued event is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.BATTLE_MOVE_EVENT:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_battle_move_event(payload)
		if response.ok:
			_apply_battle_move_event(response)
			battle_event_received.emit({"type": "move_event", "event": response, "state": battle_state})
		else:
			connection_error.emit(str(response.get("error", "OpenMMO battle move event is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.BATTLE_SLOT_EVENT:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_battle_slot_event(payload)
		if response.ok:
			battle_event_received.emit({"type": "slot_event", "event": response})
		else:
			connection_error.emit(str(response.get("error", "OpenMMO battle slot event is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.BATTLE_SWITCH_IN:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_battle_switch_in(payload)
		if response.ok:
			_apply_battle_switch_event(response)
			battle_event_received.emit({"type": "switch_in", "event": response, "state": battle_state})
		else:
			connection_error.emit(str(response.get("error", "OpenMMO battle switch-in packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.BATTLE_SLOT_FLAG:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_battle_slot_flag(payload)
		if response.ok:
			battle_state["force_switch"] = bool(response.get("flag", false)) and not bool(response.get("immediate", false))
			if bool(response.get("immediate", false)):
				battle_state["can_act"] = bool(response.get("flag", false))
			battle_event_received.emit({"type": "slot_flag", "event": response, "state": battle_state})
		else:
			connection_error.emit(str(response.get("error", "OpenMMO battle slot flag event is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.BATTLE_LIST_EVENT:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_battle_list_event(payload)
		if response.ok:
			battle_event_received.emit({"type": "list_event", "event": response.event})
		else:
			connection_error.emit(str(response.get("error", "OpenMMO battle list event is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.BATTLE_STAT_COUNTERS:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_battle_stat_counters(payload)
		if response.ok:
			battle_event_received.emit({"type": "stat_counters", "event": response})
		else:
			connection_error.emit(str(response.get("error", "OpenMMO battle stat counters are malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.BATTLE_START_SCENE:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_battle_start_scene(payload)
		if response.ok:
			battle_state["start_scene"] = response
			battle_event_received.emit({"type": "start_scene", "event": response})
		else:
			connection_error.emit(str(response.get("error", "OpenMMO battle start scene is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.BATTLE_ENTITY_DELTA:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_battle_entity_delta(payload)
		if response.ok:
			_apply_battle_entity_delta(response)
			battle_event_received.emit({"type": "entity_delta", "event": response, "state": battle_state})
		else:
			connection_error.emit(str(response.get("error", "OpenMMO battle entity delta is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.ENTITY_MOVE_PP:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_entity_move_pp(payload)
		if response.ok:
			_apply_battle_move_pp(response)
			battle_event_received.emit({"type": "move_pp", "event": response, "state": battle_state})
		else:
			connection_error.emit(str(response.get("error", "OpenMMO move PP packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.ENTITY_LEAVE:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_entity_leave(payload)
		if response.ok:
			entity_update_received.emit({"remove_entity_id": int(response.entity.get("entity_id", 0))})
		else:
			connection_error.emit(str(response.get("error", "OpenMMO entity-leave packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.MAP_TRANSITION:
		map_transition_pending = true
		pending_map_load.clear()
		map_load_spawn_window = false
		awaiting_local_entity = false
		render_screen_changed.emit(false)
	elif opcode == GAME_PROTOCOL_SCRIPT.LOAD_MAP:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_load_map(payload)
		if not response.ok:
			connection_error.emit(str(response.get("error", "OpenMMO map packet is malformed")))
			return
		if not has_content():
			connection_error.emit("Select a local ROM before entering the OpenMMO world")
			return
		var bank_id: int = int(response.get("bank_id", -1))
		var map_id: int = int(response.get("map_id", -1))
		activate_content_for_location(bank_id, map_id)
		var local_map_id: String = map_id_for_location(bank_id, map_id)
		var custom_map_value: Variant = response.get("custom_map_gzip", PackedByteArray())
		var has_custom_map: bool = custom_map_value is PackedByteArray and not (custom_map_value as PackedByteArray).is_empty()
		if has_custom_map:
			local_map_id = "server-map-%s" % str(response.get("key", ""))
		elif local_map_id.is_empty() or map_data_for_location(bank_id, map_id).is_empty():
			connection_error.emit("No loaded ROM contains OpenMMO map %d/%d" % [bank_id, map_id])
			# Clear covered warp fade so indoor Hoenn failures are not a permanent black screen.
			render_screen_changed.emit(true)
			return
		response["local_map_id"] = local_map_id
		server_maps[str(response.key)] = response
		var switch_current: bool = bool(response.get("delete_cache", false)) or active_map_key.is_empty()
		if not switch_current:
			return
		map_transition_pending = false
		active_map_key = str(response.get("key", ""))
		pending_map_load = response
		map_load_spawn_window = true
		map_load_received.emit(response)
	elif opcode == GAME_PROTOCOL_SCRIPT.NPC_SPAWN:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_npc_spawn(payload)
		if not response.ok:
			connection_error.emit(str(response.get("error", "OpenMMO NPC spawn packet is malformed")))
			return
		var npc: Dictionary = response.entity
		npc["map_id"] = map_id_for_location(int(npc.get("bank_id", -1)), int(npc.get("wire_map_id", -1))) if has_content() else ""
		entity_update_received.emit({"player": npc, "local": false, "spawn": true, "map_load_spawn": map_load_spawn_window})
	elif opcode == GAME_PROTOCOL_SCRIPT.NPC_UPDATE:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_npc_update(payload)
		if response.ok:
			_emit_entity_update(response.entity)
		else:
			connection_error.emit(str(response.get("error", "OpenMMO NPC update packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.NPC_ANIMATION:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_npc_animation(payload)
		if response.ok:
			_emit_entity_update(response.entity)
		else:
			connection_error.emit(str(response.get("error", "OpenMMO NPC animation packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.ENTITY_MOVE_SEQUENCE:
		var movement_sequence: Dictionary = GAME_PROTOCOL_SCRIPT.decode_entity_move_sequence(payload)
		if movement_sequence.ok:
			entity_update_received.emit({"scripted_movement": movement_sequence})
		else:
			connection_error.emit(str(movement_sequence.get("error", "OpenMMO scripted movement packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.DIALOG_ACTION:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_dialog_action(payload)
		if response.ok:
			dialog_action_received.emit(response.action)
		else:
			connection_error.emit(str(response.get("error", "OpenMMO dialog action packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.DIALOG_STATE:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_dialog_state(payload)
		if response.ok:
			dialog_state_received.emit(bool(response.open))
		else:
			connection_error.emit(str(response.get("error", "OpenMMO dialog state packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.REQUEST_PLAYER:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_load_entity(payload)
		if not response.ok:
			connection_error.emit(str(response.get("error", "OpenMMO entity packet is malformed")))
			return
		var player: Dictionary = response.entity
		player["map_id"] = map_id_for_location(int(player.get("bank_id", -1)), int(player.get("wire_map_id", -1))) if has_content() else ""
		player["character_id"] = int(player.get("entity_id", 0))
		var is_local: bool = awaiting_local_entity
		var current_character_id: int = int(current_character.get("id", 0))
		if current_character_id > 0:
			is_local = int(player.get("entity_id", 0)) == current_character_id
		if is_local:
			awaiting_local_entity = false
			player["user_id"] = int(current_character.get("user_id", 0))
			current_character["x"] = int(player.get("x", 0))
			current_character["y"] = int(player.get("y", 0))
			current_character["region_id"] = int(player.get("region_id", 0))
			current_character["bank_id"] = int(player.get("bank_id", 0))
			current_character["map_id"] = int(player.get("wire_map_id", 0))
		entity_update_received.emit({"player": player, "local": is_local})
	elif opcode == GAME_PROTOCOL_SCRIPT.ENTITY_MOVE_GBA:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_gba_entity_move(payload)
		if response.ok:
			_emit_entity_update(response.entity)
		else:
			connection_error.emit(str(response.get("error", "OpenMMO GBA movement packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.ENTITY_MOVE_NDS:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_entity_move(payload)
		if response.ok:
			_emit_entity_update(response.entity)
		else:
			connection_error.emit(str(response.get("error", "OpenMMO movement packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.ENTITY_FACE_TURN:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_entity_face_turn(payload)
		if response.ok:
			_emit_entity_update(response.entity)
		else:
			connection_error.emit(str(response.get("error", "OpenMMO face-turn packet is malformed")))
	elif opcode == GAME_PROTOCOL_SCRIPT.RENDER_SCREEN:
		var response: Dictionary = GAME_PROTOCOL_SCRIPT.decode_render_screen(payload)
		if response.ok:
			if bool(response.visible):
				map_load_spawn_window = false
			render_screen_changed.emit(bool(response.visible))
		else:
			connection_error.emit(str(response.error))

func _emit_entity_update(entity: Dictionary) -> void:
	var entity_id: int = int(entity.get("entity_id", 0))
	entity["character_id"] = entity_id
	if has_content() and entity.has("bank_id") and entity.has("wire_map_id"):
		entity["map_id"] = map_id_for_location(int(entity.get("bank_id", -1)), int(entity.get("wire_map_id", -1)))
	if entity_id == int(current_character.get("id", 0)):
		for key in ["x", "y", "facing", "bank_id", "wire_map_id", "map_id"]:
			if entity.has(key):
				current_character[key] = entity[key]
	entity_update_received.emit({"player": entity, "local": entity_id == int(current_character.get("id", 0))})

func _apply_world_flag_set(update: Dictionary) -> void:
	var group_key: String = str(int(update.get("group", 0)) & 0xFF)
	var group_value: Variant = world_flags.get(group_key, {})
	var group: Dictionary = group_value.duplicate(true) if group_value is Dictionary else {}
	group[str(int(update.get("index", 0)) & 0xFFFF)] = int(update.get("value", 0))
	world_flags[group_key] = group

func _apply_story_flag_update(update: Dictionary) -> void:
	var region_id: int = int(update.get("region_id", -1))
	var region_key: String = str(region_id)
	var region_value: Variant = story_flags.get(region_key, {})
	var flags: Dictionary = region_value.duplicate(true) if region_value is Dictionary else {}
	var flag_key: String = str(int(update.get("flag_id", 0)) & 0xFFFF)
	if bool(update.get("enabled", false)):
		flags[flag_key] = true
	else:
		flags.erase(flag_key)
	if flags.is_empty():
		story_flags.erase(region_key)
	else:
		story_flags[region_key] = flags
	story_region_id = region_id
	current_character["story_flags"] = story_flags.duplicate(true)
	story_state_changed.emit(_story_state_snapshot())

func _apply_local_player_state(state: Dictionary) -> void:
	story_region_id = int(state.get("region", -1))
	story_flags.clear()
	story_variables.clear()
	var variables: Dictionary = {}
	var variable_values: Variant = state.get("variables", [])
	if variable_values is Array:
		for value in variable_values as Array:
			if value is Dictionary:
				var variable: Dictionary = value
				variables[str(int(variable.get("key", 0)) & 0xFF)] = int(variable.get("value", 0))
	if story_region_id >= 0:
		story_variables[str(story_region_id)] = variables
	for key in ["region", "map_id", "move_speed", "x", "y", "z", "money", "gender", "skin_tone", "hair_color", "playtime", "flags", "party_dex", "party_forms", "pokedex_seen", "pokedex_caught", "badges"]:
		if state.has(key):
			current_character[key] = state[key]
	current_character["story_flags"] = story_flags.duplicate(true)
	current_character["story_variables"] = story_variables.duplicate(true)
	_update_character_list_entry()
	var story_snapshot: Dictionary = _story_state_snapshot()
	story_state_changed.emit(story_snapshot)
	story_state_resynced.emit(story_snapshot)
	character_state_changed.emit(current_character.duplicate(true))

func _apply_character_updates(updates: Dictionary) -> void:
	for key in updates:
		current_character[key] = _normalise_bag(updates[key]) if key == "bag" and updates[key] is Array else updates[key]
	_update_character_list_entry()
	character_state_changed.emit(current_character.duplicate(true))

func _apply_pokemon_storage(packet: Dictionary) -> void:
	if int(packet.get("container", -1)) != GAME_PROTOCOL_SCRIPT.POKEMON_CONTAINER_PARTY:
		return
	if bool(packet.get("delete", false)):
		current_character["party"] = []
		_update_character_list_entry()
		character_state_changed.emit(current_character.duplicate(true))
		return
	var incoming_value: Variant = packet.get("pokemon", [])
	if not incoming_value is Array:
		return
	var previous_value: Variant = current_character.get("party", [])
	var previous_party: Array = previous_value as Array if previous_value is Array else []
	var battle_value: Variant = battle_state.get("player_party", [])
	var battle_party: Array = battle_value as Array if battle_value is Array else []
	var party: Array = []
	for entry_value in incoming_value as Array:
		if not entry_value is Dictionary:
			continue
		var pokemon: Dictionary = (entry_value as Dictionary).duplicate(true)
		var current_hp: int = int(pokemon.get("hp", pokemon.get("current_hp", 0)))
		pokemon["current_hp"] = current_hp
		var previous_index: int = _party_member_index(previous_party, pokemon)
		if previous_index >= 0:
			var previous: Dictionary = previous_party[previous_index]
			if int(previous.get("max_hp", 0)) > 0:
				pokemon["max_hp"] = int(previous.get("max_hp", 0))
		var battle_index: int = _party_member_index(battle_party, pokemon)
		if battle_index >= 0:
			var battle_mon: Dictionary = battle_party[battle_index]
			if int(battle_mon.get("max_hp", 0)) > 0:
				pokemon["max_hp"] = int(battle_mon.get("max_hp", 0))
		pokemon["faint_flag"] = 1 if current_hp <= 0 else 0
		party.append(pokemon)
	current_character["party"] = party
	if battle_in_progress:
		_hydrate_battle_party_xp()
		battle_event_received.emit({"type": "party_xp", "state": battle_state})
	_update_character_list_entry()
	character_state_changed.emit(current_character.duplicate(true))

func _apply_bag_snapshot(packet: Dictionary) -> void:
	if int(packet.get("side", -1)) != 1:
		return
	var entries: Array = packet.get("entries", []) if packet.get("entries", []) is Array else []
	var bag: Array = [] if bool(packet.get("replace", false)) else _current_bag()
	for entry_value in entries:
		if not entry_value is Dictionary:
			continue
		var stack: Dictionary = _bag_stack_from_entry(entry_value as Dictionary)
		if stack.is_empty():
			return
		_merge_bag_stack(bag, stack)
	current_character["bag"] = bag
	_update_character_list_entry()
	character_state_changed.emit(current_character.duplicate(true))

func _apply_bag_stack(packet: Dictionary) -> void:
	if int(packet.get("side", -1)) != 1 or not packet.get("entry", {}) is Dictionary:
		return
	var stack: Dictionary = _bag_stack_from_entry(packet.entry)
	if stack.is_empty():
		return
	var bag: Array = _current_bag()
	_merge_bag_stack(bag, stack)
	current_character["bag"] = bag
	_update_character_list_entry()
	character_state_changed.emit(current_character.duplicate(true))

func _bag_stack_from_entry(entry: Dictionary) -> Dictionary:
	var object_id: int = int(entry.get("entity_id", 0))
	var item_id: int = content.battle_item_id(entry) if content != null else _bag_item_id_from_value(entry)
	if (object_id & 0xFFFF) != 0x5000 or item_id <= 0:
		return {}
	var stack: Dictionary = content.battle_item_info(item_id).duplicate(true) if content != null else {"item_id": item_id, "internal_id": item_id, "name": "", "category": "items", "price": 0}
	stack["object_id"] = object_id
	stack["quantity"] = maxi(0, int(entry.get("back_sprite_id", 0)))
	return stack

func _current_bag() -> Array:
	var value: Variant = current_character.get("bag", [])
	return _normalise_bag(value) if value is Array else []

func _normalise_bag(value: Variant) -> Array:
	if not value is Array:
		return []
	var bag: Array = (value as Array).duplicate(true)
	for index in bag.size():
		if bag[index] is Dictionary:
			bag[index] = _normalise_bag_entry(bag[index] as Dictionary)
	return bag

func _normalise_bag_entry(entry: Dictionary) -> Dictionary:
	var item: Dictionary = entry.duplicate(true)
	var item_id: int = content.battle_item_id(item) if content != null else _bag_item_id_from_value(item)
	if item_id <= 0:
		return item
	item["item_id"] = item_id
	if content != null:
		var info: Dictionary = content.battle_item_info(item_id)
		for key in ["internal_id", "name", "price", "pocket", "category"]:
			if info.has(key):
				item[key] = info[key]
	return item

func _bag_item_id_from_value(value: Variant) -> int:
	if not value is Dictionary:
		return int(value)
	var item: Dictionary = value
	for key in ["item_id", "front_sprite_id", "id", "internal_id"]:
		var candidate: int = int(item.get(key, 0))
		if candidate > 0:
			return candidate
	var object_id: int = int(item.get("object_id", item.get("entity_id", 0)))
	return object_id >> 16 if (object_id & 0xFFFF) == 0x5000 else 0

func _merge_bag_stack(bag: Array, stack: Dictionary) -> void:
	var item_id: int = int(stack.get("item_id", 0))
	for index in bag.size():
		if not bag[index] is Dictionary or int((bag[index] as Dictionary).get("item_id", 0)) != item_id:
			continue
		if int(stack.get("quantity", 0)) <= 0:
			bag.remove_at(index)
		else:
			bag[index] = stack
		return
	if int(stack.get("quantity", 0)) > 0:
		bag.append(stack)

func _update_character_list_entry() -> void:
	var character_id: int = int(current_character.get("id", 0))
	for index in characters.size():
		if characters[index] is Dictionary and int((characters[index] as Dictionary).get("id", 0)) == character_id:
			characters[index] = current_character.duplicate(true)
			return

func _party_member_index(party: Array, target: Dictionary) -> int:
	var target_id: int = int(target.get("id", target.get("entity_id", 0)))
	if target_id > 0:
		for index in party.size():
			var value: Variant = party[index]
			if value is Dictionary and int((value as Dictionary).get("id", (value as Dictionary).get("entity_id", 0))) == target_id:
				return index
	var target_slot: int = int(target.get("container_slot", -1))
	if target_slot < 0:
		target_slot = int(target.get("party_index", -1))
	if target_slot < 0:
		target_slot = int(target.get("slot", -1))
	if target_slot < 0:
		return -1
	for index in party.size():
		var value: Variant = party[index]
		if not value is Dictionary:
			continue
		var member: Dictionary = value
		var member_slot: int = int(member.get("container_slot", -1))
		if member_slot < 0:
			member_slot = int(member.get("party_index", -1))
		if member_slot < 0:
			member_slot = int(member.get("slot", -1))
		if member_slot == target_slot:
			return index
	return target_slot if target_slot < party.size() else -1

func _hydrate_battle_party_xp() -> void:
	var party_value: Variant = current_character.get("party", [])
	var battle_value: Variant = battle_state.get("player_party", [])
	if not party_value is Array or not battle_value is Array:
		return
	var party: Array = party_value
	var battle_party: Array = (battle_value as Array).duplicate(true)
	var changed: bool = false
	for index in battle_party.size():
		if not battle_party[index] is Dictionary:
			continue
		var battle_mon: Dictionary = battle_party[index]
		var member_index: int = _party_member_index(party, battle_mon)
		if member_index < 0:
			continue
		var member: Dictionary = party[member_index]
		if not battle_mon.has("xp") and member.has("xp"):
			battle_mon["xp"] = int(member.get("xp", 0))
			changed = true
		if int(battle_mon.get("level", 0)) <= 0 and int(member.get("level", 0)) > 0:
			battle_mon["level"] = int(member.get("level", 0))
			changed = true
		if int(battle_mon.get("species", battle_mon.get("dex_id", 0))) <= 0 and int(member.get("dex_id", 0)) > 0:
			battle_mon["dex_id"] = int(member.get("dex_id", 0))
			changed = true
		battle_party[index] = battle_mon
	if changed:
		battle_state["player_party"] = battle_party

func _sync_current_party_from_battle() -> void:
	var battle_value: Variant = battle_state.get("player_party", [])
	var current_value: Variant = current_character.get("party", [])
	if not battle_value is Array or not current_value is Array:
		return
	var battle_party: Array = battle_value
	var party: Array = (current_value as Array).duplicate(true)
	var changed: bool = false
	for battle_member_value in battle_party:
		if not battle_member_value is Dictionary:
			continue
		var battle_mon: Dictionary = battle_member_value
		var index: int = _party_member_index(party, battle_mon)
		if index < 0:
			continue
		var member: Dictionary = party[index]
		var current_hp: int = int(battle_mon.get("current_hp", battle_mon.get("hp", 0)))
		if int(member.get("current_hp", member.get("hp", -1))) != current_hp:
			member["current_hp"] = current_hp
			changed = true
		if int(member.get("hp", -1)) != current_hp:
			member["hp"] = current_hp
			changed = true
		var max_hp: int = int(battle_mon.get("max_hp", 0))
		if max_hp > 0 and int(member.get("max_hp", 0)) != max_hp:
			member["max_hp"] = max_hp
			changed = true
		if battle_mon.has("xp") and int(member.get("xp", -1)) != int(battle_mon.get("xp", 0)):
			member["xp"] = int(battle_mon.get("xp", 0))
			changed = true
		if battle_mon.has("level") and int(member.get("level", -1)) != int(battle_mon.get("level", 0)):
			member["level"] = int(battle_mon.get("level", 0))
			changed = true
		var faint_flag: int = 1 if current_hp <= 0 else 0
		if int(member.get("faint_flag", -1)) != faint_flag:
			member["faint_flag"] = faint_flag
			changed = true
		party[index] = member
	if not changed:
		return
	current_character["party"] = party
	_update_character_list_entry()
	character_state_changed.emit(current_character.duplicate(true))

func _apply_battle_move_event(event: Dictionary) -> void:
	for target_value in event.get("targets", []):
		if not target_value is Dictionary:
			continue
		var target: Dictionary = target_value
		var entity_id: int = int(target.get("entity_id", 0))
		for event_value in target.get("events", []):
			if not event_value is Dictionary:
				continue
			var nested: Dictionary = event_value
			var updates: Dictionary = {}
			if nested.has("current_hp"):
				updates["current_hp"] = int(nested.get("current_hp", 0))
			if nested.has("faint"):
				updates["faint_flag"] = 1 if bool(nested.get("faint", false)) else 0
			if not updates.is_empty():
				_apply_battle_entity_updates(entity_id, updates)

func _apply_battle_switch_event(event: Dictionary) -> void:
	var side: int = int(event.get("side", 0))
	var active: Dictionary = event.get("active", {}) if event.get("active", {}) is Dictionary else {}
	var slot: int = int(active.get("slot", event.get("new_slot", 0)))
	var party_key: String = "player_party" if side == 0 else "opponent_party"
	var party_value: Variant = battle_state.get(party_key, [])
	if party_value is Array:
		var party: Array = (party_value as Array).duplicate(true)
		var new_mon: Dictionary = event.get("mon", {}) if event.get("mon", {}) is Dictionary else {}
		if not new_mon.is_empty():
			for index in party.size():
				if not party[index] is Dictionary or int((party[index] as Dictionary).get("slot", -1)) != int(event.get("new_slot", -2)):
					continue
				party[index] = new_mon.duplicate(true)
				break
			battle_state[party_key] = party
	if side == 0:
		battle_state["active_slot"] = slot
	else:
		battle_state["opponent_active_slot"] = slot
	battle_state["force_switch"] = false
	_sync_current_party_from_battle()

func _apply_battle_entity_delta(event: Dictionary) -> void:
	_apply_battle_entity_updates(int(event.get("entity_id", 0)), event.get("updates", {}) if event.get("updates", {}) is Dictionary else {})

func _apply_battle_move_pp(event: Dictionary) -> void:
	var entity_id: int = int(event.get("entity_id", 0))
	var move_slot: int = int(event.get("move_slot", -1))
	if entity_id == 0 or move_slot < 0 or move_slot >= 4:
		return
	for party_key in ["player_party", "opponent_party"]:
		var party_value: Variant = battle_state.get(party_key, [])
		if not party_value is Array:
			continue
		var party: Array = (party_value as Array).duplicate(true)
		for index in party.size():
			if not party[index] is Dictionary:
				continue
			var mon: Dictionary = party[index]
			if int(mon.get("entity_id", 0)) != entity_id:
				continue
			var move_pp: Array = mon.get("move_pp", []).duplicate() if mon.get("move_pp", []) is Array else []
			while move_pp.size() < 4:
				move_pp.append(-1)
			move_pp[move_slot] = maxi(0, int(event.get("pp", 0)))
			mon["move_pp"] = move_pp
			var moves: Array = mon.get("moves", []).duplicate(true) if mon.get("moves", []) is Array else []
			if move_slot < moves.size() and moves[move_slot] is Dictionary:
				var move: Dictionary = moves[move_slot]
				move["pp"] = move_pp[move_slot]
				moves[move_slot] = move
				mon["moves"] = moves
			party[index] = mon
			battle_state[party_key] = party
			_sync_current_party_from_battle()
			return

func _apply_battle_entity_updates(entity_id: int, updates: Dictionary) -> void:
	for party_key in ["player_party", "opponent_party"]:
		var party_value: Variant = battle_state.get(party_key, [])
		if not party_value is Array:
			continue
		var party: Array = (party_value as Array).duplicate(true)
		for index in party.size():
			if not party[index] is Dictionary:
				continue
			var mon: Dictionary = party[index]
			if entity_id != 0 and int(mon.get("entity_id", 0)) != entity_id:
				continue
			for key in ["current_hp", "species", "level", "gender", "faint_flag"]:
				if updates.has(key):
					mon[key] = updates[key]
			if updates.has("experience_points"):
				mon["xp"] = int(updates.get("experience_points", 0))
			if updates.has("experience_level"):
				mon["level"] = int(updates.get("experience_level", mon.get("level", 0)))
			if updates.has("moves"):
				var moves: Array = updates.get("moves", []) if updates.get("moves", []) is Array else []
				var move_ids: Array = []
				var move_pp: Array = []
				for move_value in moves:
					if move_value is Dictionary:
						move_ids.append(int((move_value as Dictionary).get("id", 0)))
						move_pp.append(int((move_value as Dictionary).get("pp", 0)))
				mon["moves"] = moves.duplicate(true)
				mon["move_ids"] = move_ids
				mon["move_pp"] = move_pp
			party[index] = mon
			battle_state[party_key] = party
			break
	_sync_current_party_from_battle()

func _on_login_failed(message: String) -> void:
	if login_flow != "idle":
		_finish_login({"ok": false, "error": message})

func _on_game_failed(message: String) -> void:
	if game_flow != "idle":
		_finish_game_connection({"ok": false, "error": message})
	else:
		connection_error.emit(message)

func _finish_login(result: Dictionary) -> void:
	login_flow = "idle"
	flow_deadline_msec = 0
	login_session.close()
	login_completed.emit(result)

func _finish_game_connection(result: Dictionary) -> void:
	game_flow = "idle"
	flow_deadline_msec = 0
	game_connection_completed.emit(result)

func _game_endpoint(access: Dictionary) -> Dictionary:
	var local_address: String = str(access.get("local_address", ""))
	var local_hostname: String = str(access.get("local_hostname", ""))
	var port: int = int(access.get("port", 0))
	if _is_loopback(login_host):
		var host: String = local_address
		if host.is_empty() or host == "0.0.0.0":
			host = local_hostname if not local_hostname.is_empty() else login_host
		if port > 0:
			return {"ok": true, "host": host, "port": port}
	for node in access.get("nodes", []):
		var host: String = str(node.get("ipv4", ""))
		if not host.is_empty() and int(node.get("port", 0)) > 0:
			return {"ok": true, "host": host, "port": int(node.get("port", 0))}
	return {"ok": false, "error": "OpenMMO did not provide a usable game-server endpoint"}

func _parse_endpoint(value: String, default_port: int) -> Dictionary:
	var text: String = value.strip_edges().trim_prefix("tcp://")
	if text.is_empty():
		return {"ok": false, "error": "Enter an OpenMMO login server"}
	var host: String = text
	var port: int = default_port
	if text.begins_with("["):
		var close_index: int = text.find("]")
		if close_index < 0:
			return {"ok": false, "error": "OpenMMO login endpoint is invalid"}
		host = text.substr(1, close_index - 1)
		if close_index + 1 < text.length():
			if text[close_index + 1] != ":":
				return {"ok": false, "error": "OpenMMO login endpoint is invalid"}
			port = text.substr(close_index + 2).to_int()
	elif text.count(":") == 1:
		var separator: int = text.rfind(":")
		host = text.left(separator)
		port = text.substr(separator + 1).to_int()
	if host.is_empty() or port <= 0 or port > 65535:
		return {"ok": false, "error": "OpenMMO login endpoint is invalid"}
	return {"ok": true, "host": host, "port": port}

func _load_hardware_id(settings: Dictionary) -> PackedByteArray:
	var encoded: String = str(settings.get("hardware_id", ""))
	var value: PackedByteArray = _decode_hex(encoded)
	if value.size() == 16:
		return value
	value = Crypto.new().generate_random_bytes(16)
	settings["hardware_id"] = value.hex_encode()
	OpenMMOStorage.write_json(OpenMMOStorage.SETTINGS_FILE, settings)
	return value

func _decode_hex(value: String) -> PackedByteArray:
	if value.length() % 2 != 0:
		return PackedByteArray()
	var output: PackedByteArray = PackedByteArray()
	for index in range(0, value.length(), 2):
		var byte_text: String = value.substr(index, 2)
		if not byte_text.is_valid_hex_number(false):
			return PackedByteArray()
		output.append(byte_text.hex_to_int())
	return output

func _os_ordinal() -> int:
	match OS.get_name():
		"Windows": return 0
		"Linux": return 1
		"macOS": return 2
		"iOS": return 3
		"Android": return 4
	return 0xFF

func _is_loopback(host: String) -> bool:
	return host.to_lower() in ["127.0.0.1", "localhost", "::1"]
