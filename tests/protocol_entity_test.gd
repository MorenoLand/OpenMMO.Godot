extends SceneTree

const GAME_PROTOCOL: GDScript = preload("res://scripts/net/game_protocol.gd")

func _init() -> void:
	var payload: PackedByteArray = PackedByteArray()
	OpenMMOCodec.append_s64_le(payload, 123456789)
	OpenMMOCodec.append_u8(payload, 0)
	OpenMMOCodec.append_u8(payload, 2)
	OpenMMOCodec.append_u16_le(payload, (1 << 1) | (1 << 6))
	OpenMMOCodec.append_u16_le(payload, 7 | 8 << 10)
	OpenMMOCodec.append_u16_le(payload, 9 | 10 << 10)
	OpenMMOCodec.append_utf16_le_null(payload, "Hero")
	OpenMMOCodec.append_u8(payload, 0)
	OpenMMOCodec.append_u8(payload, 3)
	OpenMMOCodec.append_u8(payload, 4)
	OpenMMOCodec.append_s16_le(payload, 12)
	OpenMMOCodec.append_s16_le(payload, 13)
	OpenMMOCodec.append_u8(payload, 3)
	OpenMMOCodec.append_u8(payload, 1)
	OpenMMOCodec.append_u8(payload, 0)
	OpenMMOCodec.append_u8(payload, 1)
	OpenMMOCodec.append_u8(payload, 0x1F)
	OpenMMOCodec.append_u8(payload, 0xFE)
	OpenMMOCodec.append_u8(payload, 0xFD)
	OpenMMOCodec.append_u16_le(payload, 0x1234)
	OpenMMOCodec.append_s16_le(payload, 25)
	OpenMMOCodec.append_u8(payload, 0xFC)
	OpenMMOCodec.append_s32_le(payload, -77)
	OpenMMOCodec.append_utf16_le_null(payload, "ignored")
	var result: Dictionary = GAME_PROTOCOL.decode_load_entity(payload)
	var entity: Dictionary = result.get("entity", {})
	var skins: Array = (entity.get("skin", {}) as Dictionary).get("skins", [])
	if not bool(result.get("ok", false)) or int(entity.get("entity_id", 0)) != 123456789 or str(entity.get("name", "")) != "Hero" or int(entity.get("bank_id", 0)) != 3 or int(entity.get("wire_map_id", 0)) != 4 or int(entity.get("x", 0)) != 12 or int(entity.get("y", 0)) != 13 or int(entity.get("elevation", 0)) != 3 or int(entity.get("facing", 0)) != 2 or int(entity.get("follower_dex_id", 0)) != 25 or skins.size() != 2:
		push_error("OpenMMO entity packet decoding failed")
		quit(1)
		return
	var screen: Dictionary = GAME_PROTOCOL.decode_render_screen(PackedByteArray([1]))
	if not bool(screen.get("ok", false)) or not bool(screen.get("visible", false)):
		push_error("OpenMMO render-screen packet decoding failed")
		quit(1)
		return
	quit(0)
