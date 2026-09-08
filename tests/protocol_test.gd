extends SceneTree

const SESSION_SCRIPT: GDScript = preload("res://scripts/net/session.gd")
const GAME_STATE_SCRIPT: GDScript = preload("res://scripts/game_state.gd")

func _init() -> void:
	if SESSION_SCRIPT == null:
		push_error("OpenMMO session script did not load")
		quit(1)
		return
	if not _test_codec():
		quit(1)
		return
	if not _test_aes_ctr():
		quit(1)
		return
	if not _test_p256():
		quit(1)
		return
	if not _test_login_codec():
		quit(1)
		return
	if not _test_game_codec():
		quit(1)
		return
	if not _test_battle_hp_event():
		quit(1)
		return
	quit(0)

func _test_codec() -> bool:
	var payload: PackedByteArray = PackedByteArray()
	OpenMMOCodec.append_u8(payload, 0x11)
	OpenMMOCodec.append_u16_le(payload, 0xCAFE)
	OpenMMOCodec.append_s32_le(payload, -1234567)
	OpenMMOCodec.append_bool(payload, true)
	OpenMMOCodec.append_utf16_le_null(payload, "OpenMMO Ω")
	var reader: OpenMMOCodec.Reader = OpenMMOCodec.Reader.new(payload)
	if reader.read_u8() != 0x11 or reader.read_u16_le() != 0xCAFE or reader.read_s32_le() != -1234567 or not reader.read_bool() or reader.read_utf16_le_null() != "OpenMMO Ω" or reader.failed or reader.remaining() != 0:
		push_error("OpenMMO byte codec roundtrip failed")
		return false
	var framed: PackedByteArray = OpenMMOCodec.frame(PackedByteArray([0xAA, 0xBB, 0xCC]))
	if framed.size() != 5 or framed.decode_u16(0) != 5:
		push_error("OpenMMO inclusive frame length is incorrect")
		return false
	return true

func _test_aes_ctr() -> bool:
	var key: PackedByteArray = _hex("2b7e151628aed2a6abf7158809cf4f3c")
	var counter: PackedByteArray = _hex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
	var plaintext: PackedByteArray = _hex("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51")
	var expected: PackedByteArray = _hex("874d6191b620e3261bef6864990db6ce9806f66b7970fdff8617187bb9fffdff")
	var stream: OpenMMOAESCTR = OpenMMOAESCTR.new()
	if stream.start(key, counter) != OK:
		push_error("OpenMMO AES-CTR could not start")
		return false
	var output: PackedByteArray = stream.update(plaintext.slice(0, 7))
	output.append_array(stream.update(plaintext.slice(7)))
	stream.finish()
	if output != expected:
		push_error("OpenMMO AES-CTR does not match the NIST vector")
		return false
	return true

func _test_p256() -> bool:
	var curve: OpenMMOP256 = OpenMMOP256.new()
	var generator: PackedByteArray = curve.generator_bytes()
	var doubled: Dictionary = curve.scalar_multiply_for_test("02", generator)
	if not bool(doubled.get("ok", false)):
		push_error(str(doubled.get("error", "P-256 multiplication failed")))
		return false
	var expected: PackedByteArray = _hex("047cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc4766997807775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1")
	if doubled.get("point") as PackedByteArray != expected:
		push_error("OpenMMO P-256 scalar multiplication does not match 2G")
		return false
	return true

func _test_login_codec() -> bool:
	var encoded: PackedByteArray = OpenMMOLoginProtocol.encode_password_login("test", "test", true, PackedByteArray([1, 2, 3]), 0)
	var reader: OpenMMOCodec.Reader = OpenMMOCodec.Reader.new(encoded)
	if reader.read_utf16_le_null() != "test" or not reader.read_bool() or reader.read_u8_bytes() != PackedByteArray([1, 2, 3]) or reader.read_u8() != 0 or reader.read_utf16_le_null() != "a94a8fe5ccb19ba61c4c0873d391e987982fbbd3" or not reader.read_bool() or reader.read_utf16_le_null() != "en" or reader.read_s32_le() != 0 or reader.read_s32_le() != 0 or reader.read_u8() != 0 or not reader.read_u8_bytes().is_empty() or reader.failed or reader.remaining() != 0:
		push_error("OpenMMO password login packet does not match the server codec")
		return false
	var response: PackedByteArray = PackedByteArray([0])
	OpenMMOCodec.append_utf16_le_null(response, "")
	var decoded: Dictionary = OpenMMOLoginProtocol.decode_login_response(response)
	if not bool(decoded.get("ok", false)) or not bool(decoded.get("authenticated", false)):
		push_error("OpenMMO authenticated login response did not decode")
		return false
	return true

func _test_game_codec() -> bool:
	var join: PackedByteArray = OpenMMOGameProtocol.encode_join(17, PackedByteArray([1, 2, 3, 4]), PackedByteArray([9, 8, 7, 6, 5, 4, 3, 2]))
	var reader: OpenMMOCodec.Reader = OpenMMOCodec.Reader.new(join)
	if reader.read_u8() != 0 or reader.read_s32_le() != 17 or reader.read_u8_bytes() != PackedByteArray([1, 2, 3, 4]) or reader.read_bytes(6) != PackedByteArray([9, 8, 7, 6, 5, 4]) or reader.read_s32_le() != 0 or reader.read_s32_le() != 0:
		push_error("OpenMMO game join authentication fields are incorrect")
		return false
	reader.read_s8()
	reader.read_s16_le()
	reader.read_s16_le()
	reader.read_s8()
	reader.read_u8()
	reader.read_u8()
	reader.read_u8()
	reader.read_u8()
	reader.read_u8()
	if not reader.read_u8_bytes().is_empty() or reader.read_bytes(32).size() != 32 or reader.failed or reader.remaining() != 0:
		push_error("OpenMMO game join metadata shape is incorrect")
		return false
	var response: PackedByteArray = PackedByteArray([1])
	OpenMMOCodec.append_utf16_le_null(response, "")
	OpenMMOCodec.append_u8(response, 0)
	for value in [1337, 420, 187, 1000, 1200]:
		OpenMMOCodec.append_s32_le(response, value)
	var decoded_join: Dictionary = OpenMMOGameProtocol.decode_join_response(response)
	if not decoded_join.ok or not decoded_join.can_join or int(decoded_join.balance) != 187:
		push_error("OpenMMO game join response did not decode")
		return false
	var decoded_characters: Dictionary = OpenMMOGameProtocol.decode_characters(_character_list_fixture())
	if not decoded_characters.ok or decoded_characters.characters.size() != 1:
		push_error("OpenMMO character list did not decode")
		return false
	var character: Dictionary = decoded_characters.characters[0]
	if int(character.id) != 42 or str(character.name) != "Hero" or int(character.money) != 123 or int(character.bank_id) != 3 or int(character.map_id) != 4 or int(character.x) != 5 or int(character.y) != 6:
		push_error("OpenMMO character fields are misaligned")
		return false
	var decoded_party: Dictionary = OpenMMOGameProtocol.decode_pokemon_storage(PackedByteArray([1, 1, 0]))
	if not bool(decoded_party.get("ok", false)) or int(decoded_party.get("container", -1)) != 1 or not bool(decoded_party.get("has_change", false)) or bool(decoded_party.get("delete", true)) or not (decoded_party.get("pokemon", []) as Array).is_empty():
		push_error("OpenMMO Pokemon party storage packet did not decode")
		return false
	var normal_chat: PackedByteArray = OpenMMOGameProtocol.encode_chat_message("hello")
	var normal_chat_reader: OpenMMOCodec.Reader = OpenMMOCodec.Reader.new(normal_chat)
	if normal_chat_reader.read_u8() != 0 or normal_chat_reader.read_s64_le() != 0 or normal_chat_reader.read_utf16_le_null() != "" or normal_chat_reader.read_u8() != 0 or normal_chat_reader.read_u8() != 255 or normal_chat_reader.read_utf16_le_null() != "hello" or normal_chat_reader.failed or normal_chat_reader.remaining() != 0:
		push_error("OpenMMO normal chat packet shape is incorrect")
		return false
	var decoded_chat: Dictionary = OpenMMOGameProtocol.decode_chat_message(normal_chat)
	if not decoded_chat.ok or str(decoded_chat.message.get("text", "")) != "hello" or str(decoded_chat.message.get("channel", "")) != "Local":
		push_error("OpenMMO normal chat message did not decode")
		return false
	var team_chat: PackedByteArray = PackedByteArray([8])
	OpenMMOCodec.append_utf16_le_null(team_chat, "team hello")
	var decoded_team_chat: Dictionary = OpenMMOGameProtocol.decode_chat_message(team_chat)
	if not decoded_team_chat.ok or int(decoded_team_chat.message.get("type", -1)) != 8 or str(decoded_team_chat.message.get("text", "")) != "team hello":
		push_error("OpenMMO team chat message did not decode")
		return false
	var typed_chat: PackedByteArray = OpenMMOGameProtocol.encode_chat_send(0, "hello")
	var typed_reader: OpenMMOCodec.Reader = OpenMMOCodec.Reader.new(typed_chat)
	if typed_reader.read_s8() != 0 or typed_reader.read_utf16_le_null() != "hello" or typed_reader.failed or typed_reader.remaining() != 0:
		push_error("OpenMMO mode-0 chat packet shape is incorrect")
		return false
	var command_chat: PackedByteArray = OpenMMOGameProtocol.encode_chat_send(4, "", "/warp")
	var command_reader: OpenMMOCodec.Reader = OpenMMOCodec.Reader.new(command_chat)
	if command_reader.read_s8() != 4 or command_reader.read_utf16_le_null() != "" or command_reader.read_utf16_le_null() != "/warp" or command_reader.failed or command_reader.remaining() != 0:
		push_error("OpenMMO mode-4 command packet shape is incorrect")
		return false
	var notice: PackedByteArray = PackedByteArray()
	OpenMMOCodec.append_s16_le(notice, 2)
	OpenMMOCodec.append_s32_le(notice, 99)
	OpenMMOCodec.append_utf16_le_null(notice, "Welcome")
	var decoded_notice: Dictionary = OpenMMOGameProtocol.decode_server_notice(notice)
	if not decoded_notice.ok or str(decoded_notice.notice.get("text", "")) != "Welcome" or int(decoded_notice.notice.get("id", -1)) != 99:
		push_error("OpenMMO server notice did not decode")
		return false
	var truncated_chat: Dictionary = OpenMMOGameProtocol.decode_chat_message(normal_chat.slice(0, normal_chat.size() - 1))
	if truncated_chat.ok:
		push_error("OpenMMO truncated chat packet was accepted")
		return false
	return true

func _character_list_fixture() -> PackedByteArray:
	var output: PackedByteArray = PackedByteArray([1])
	OpenMMOCodec.append_s64_le(output, 42)
	OpenMMOCodec.append_utf16_le_null(output, "Hero")
	OpenMMOCodec.append_utf16_le_null(output, "")
	OpenMMOCodec.append_s32_le(output, 7)
	OpenMMOCodec.append_u8(output, 0)
	OpenMMOCodec.append_s32_le(output, 100)
	OpenMMOCodec.append_s32_le(output, 50)
	OpenMMOCodec.append_s32_le(output, 0)
	OpenMMOCodec.append_u8(output, 0)
	OpenMMOCodec.append_s32_le(output, 0)
	OpenMMOCodec.append_s32_le(output, 123)
	OpenMMOCodec.append_s16_le(output, 0)
	OpenMMOCodec.append_s32_le(output, 0)
	OpenMMOCodec.append_u8(output, 0)
	OpenMMOCodec.append_u8(output, 0)
	OpenMMOCodec.append_u8(output, 0)
	OpenMMOCodec.append_s32_le(output, 0)
	output.append_array(PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	OpenMMOCodec.append_s16_le(output, 0)
	OpenMMOCodec.append_u8(output, 0)
	OpenMMOCodec.append_s32_le(output, 0)
	output.append_array(PackedByteArray([0, 0, 0, 0]))
	output.append_array(PackedByteArray([0xFF, 2, 0, 0, 3]))
	OpenMMOCodec.append_s16_le(output, 4)
	OpenMMOCodec.append_s16_le(output, 5)
	OpenMMOCodec.append_s16_le(output, 6)
	OpenMMOCodec.append_u8(output, 0)
	OpenMMOCodec.append_s16_le(output, 0)
	OpenMMOCodec.append_s16_le(output, 0)
	OpenMMOCodec.append_u8(output, 0)
	OpenMMOCodec.append_s16_le(output, 0)
	OpenMMOCodec.append_s16_le(output, 0)
	OpenMMOCodec.append_u16_le(output, 0)
	OpenMMOCodec.append_u8(output, 0)
	OpenMMOCodec.append_u16_le(output, 0)
	OpenMMOCodec.append_u16_le(output, 0)
	OpenMMOCodec.append_bool(output, false)
	OpenMMOCodec.append_u8(output, 0)
	return output

func _test_battle_hp_event() -> bool:
	var game_state = GAME_STATE_SCRIPT.new()
	var payload: PackedByteArray = PackedByteArray()
	OpenMMOCodec.append_s64_le(payload, 10)
	OpenMMOCodec.append_s16_le(payload, 33)
	OpenMMOCodec.append_u8(payload, 1)
	OpenMMOCodec.append_u8(payload, 1)
	OpenMMOCodec.append_s64_le(payload, 20)
	OpenMMOCodec.append_s16_le(payload, 0x20)
	OpenMMOCodec.append_u8(payload, 1)
	OpenMMOCodec.append_u8(payload, 0)
	OpenMMOCodec.append_u8(payload, 0)
	OpenMMOCodec.append_s16_le(payload, 14)
	var decoded: Dictionary = OpenMMOGameProtocol.decode_battle_move_event(payload)
	if not bool(decoded.get("ok", false)) or int(decoded.get("source_entity", 0)) != 10 or int(decoded.get("source_move", 0)) != 33:
		push_error("OpenMMO battle move event header did not decode")
		return false
	var target: Dictionary = decoded.get("targets", [])[0]
	var event: Dictionary = target.get("events", [])[0]
	if int(target.get("entity_id", 0)) != 20 or int(event.get("current_hp", -1)) != 14:
		push_error("OpenMMO battle HP event did not decode")
		return false
	var previous_state: Dictionary = game_state.battle_state.duplicate(true)
	var previous_character: Dictionary = game_state.current_character.duplicate(true)
	game_state.current_character = {"party": [{"id": 10, "container_slot": 0, "hp": 20}]}
	game_state.battle_state = {"player_party": [{"slot": 0, "entity_id": 10, "current_hp": 20, "max_hp": 20}], "opponent_party": [{"slot": 0, "entity_id": 20, "current_hp": 20, "max_hp": 20}]}
	game_state.call("_apply_battle_move_event", decoded)
	var opponent: Dictionary = game_state.battle_state.get("opponent_party", [])[0]
	if int(opponent.get("current_hp", -1)) != 14:
		game_state.battle_state = previous_state
		game_state.current_character = previous_character
		push_error("OpenMMO battle HP event did not update battle state")
		return false
	game_state.call("_apply_battle_entity_delta", {"entity_id": 10, "updates": {"current_hp": 15}})
	var synced_party_value: Variant = game_state.current_character.get("party", [])
	if not synced_party_value is Array or (synced_party_value as Array).is_empty() or int((synced_party_value as Array)[0].get("current_hp", -1)) != 15 or int((synced_party_value as Array)[0].get("max_hp", -1)) != 20:
		game_state.battle_state = previous_state
		game_state.current_character = previous_character
		push_error("OpenMMO battle HP did not update the persistent party state")
		return false
	game_state.call("_apply_pokemon_storage", {"container": 1, "delete": false, "pokemon": [{"id": 10, "container_slot": 0, "dex_id": 4, "level": 5, "hp": 20}]})
	var healed_party_value: Variant = game_state.current_character.get("party", [])
	if not healed_party_value is Array or (healed_party_value as Array).is_empty() or int((healed_party_value as Array)[0].get("current_hp", -1)) != 20 or int((healed_party_value as Array)[0].get("max_hp", -1)) != 20:
		game_state.battle_state = previous_state
		game_state.current_character = previous_character
		push_error("OpenMMO party storage update did not update healed HP")
		return false
	var pp_payload: PackedByteArray = PackedByteArray()
	OpenMMOCodec.append_s64_le(pp_payload, 10)
	OpenMMOCodec.append_u8(pp_payload, 1)
	OpenMMOCodec.append_u8(pp_payload, 24)
	var pp_event: Dictionary = OpenMMOGameProtocol.decode_entity_move_pp(pp_payload)
	game_state.battle_state = {"player_party": [{"slot": 0, "entity_id": 10, "move_ids": [33, 45, 0, 0]}], "opponent_party": []}
	game_state.call("_apply_battle_move_pp", pp_event)
	var player: Dictionary = game_state.battle_state.get("player_party", [])[0]
	game_state.battle_state = previous_state
	game_state.current_character = previous_character
	if not bool(pp_event.get("ok", false)) or int(pp_event.get("move_slot", -1)) != 1 or int(pp_event.get("pp", -1)) != 24 or int(player.get("move_pp", [])[1]) != 24:
		push_error("OpenMMO move PP event did not decode and update battle state")
		return false
	return true

func _hex(value: String) -> PackedByteArray:
	var output: PackedByteArray = PackedByteArray()
	for index in range(0, value.length(), 2):
		output.append(value.substr(index, 2).hex_to_int())
	return output
