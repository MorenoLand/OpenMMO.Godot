class_name OpenMMOContent
extends RefCounted

const ROM_PROFILE_SCRIPT: GDScript = preload("res://scripts/content/rom_profile.gd")
const ANIMATION_PHASE_COUNT: int = 40

const SCHEMA_VERSION: int = 1
const KANTO_GBA_CONTENT_ID: String = "kanto-gba-slice-v1"
const FIRE_RED_REV1_SHA1: String = "dd5945db9b930750cb39d00c84da8571feebf417"
const FIRE_RED_SHA1: String = "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc"
# Server dialog tables use Rev0 file offsets; Rev1 strings are shifted by these deltas.
const FIRE_RED_REV1_DIALOGUE_DELTAS: Array = [0x78, 0x73, 0x70]
const ITEM_RECORD_SIZE: int = 44
const ITEM_NAME_LENGTH: int = 14
const ITEM_RECORD_ID_OFFSET: int = 14
const ITEM_TABLE_MIN_RECORDS: int = 300
const ITEM_TABLE_MAX_RECORDS: int = 512
const GLOBAL_ITEM_CACHE_NAME: String = "items-global"
const GLOBAL_ITEM_CACHE_SCHEMA_VERSION: int = 1
const GLOBAL_ITEM_DATA_ENVIRONMENTS: Array = ["OPENMMOGO_ITEM_DATA"]
const SPECIES_NAME_LENGTH: int = 11
const SPECIES_TABLE_MAX_RECORDS: int = 512
const GBA_TITLE_OFFSET: int = 0xA0
const GBA_TITLE_LENGTH: int = 12
const GBA_GAME_CODE_OFFSET: int = 0xAC
const GBA_GAME_CODE_LENGTH: int = 4
const GBA_MAKER_CODE_OFFSET: int = 0xB0
const GBA_MAKER_CODE_LENGTH: int = 2
const MAP_HEADER_SIZE: int = 0x1C
const MAPGRID_METATILE_ID_MASK: int = 0x03FF
const MAPGRID_COLLISION_MASK: int = 0x0C00
const MAPGRID_ELEVATION_MASK: int = 0xF000
const MAPGRID_COLLISION_SHIFT: int = 10
const MAPGRID_ELEVATION_SHIFT: int = 12
const MAPGRID_UNDEFINED: int = 0x03FF
const METATILE_BEHAVIOR_MASK: int = 0x000001FF
const PRIMARY_METATILE_COUNT: int = 640
const PRIMARY_TILE_COUNT: int = 640
const PRIMARY_PALETTE_COUNT: int = 7
const SECONDARY_PALETTE_COUNT: int = 6
const SECONDARY_ROM_PALETTE_COUNT: int = 16
const TILE_BYTES: int = 32
const TILES_PER_METATILE: int = 8
const MAPGRID_LAYER_TYPE_SHIFT: int = 29
const MAPGRID_LAYER_TYPE_MASK: int = 0x60000000
const MAP_EVENTS_HEADER_SIZE: int = 0x14
const MAP_OBJECT_EVENT_SIZE: int = 0x18
const MAP_WARP_EVENT_SIZE: int = 0x08
const MAP_BG_EVENT_SIZE: int = 0x0C
const MAP_CONNECTIONS_HEADER_SIZE: int = 0x08
const MAP_CONNECTION_SIZE: int = 0x0C
const CONNECTION_SOUTH: int = 1
const CONNECTION_NORTH: int = 2
const CONNECTION_WEST: int = 3
const CONNECTION_EAST: int = 4
const MAP_TYPE_INSIDE: int = 8
const MAP_TYPE_SECRET_BASE: int = 9
const MAX_CORNER_FILLER_SIZE: int = 128
const ROCK_STAIRS_BEHAVIOR: int = 0x2A
const FLOOR_ROOFTOP: int = 127
const MAP_GROUP_DUNGEONS: int = 1
const MAP_GROUP_TOWNS_AND_ROUTES: int = 3
const MAP_GROUP_INDOOR_PALLET: int = 4
const MAP_GROUP_INDOOR_VIRIDIAN: int = 5
var manifest: Dictionary = {}
var rom_data: PackedByteArray = PackedByteArray()
var rom_sha1: String = ""
var rom_header: Dictionary = {}
var source_profile: Dictionary = {}
var map_cache: Dictionary = {}
var map_topology_cache: Dictionary = {}
var tileset_cache: Dictionary = {}
var sprite_cache: Dictionary = {}
var battle_table_cache: Dictionary = {}
var battle_tables_scanned: bool = false
var battle_sprite_cache: Dictionary = {}
var battle_name_cache: Dictionary = {}
var battle_species_catalog: Dictionary = {}
var battle_species_catalog_loaded: bool = false
var battle_move_name_cache: Dictionary = {}
var battle_item_info_cache: Dictionary = {}
var battle_item_table_cache: Dictionary = {}
var battle_item_table_scanned: bool = false
var battle_item_catalog: Dictionary = {}
var battle_item_catalog_loaded: bool = false
var battle_global_item_catalog: Dictionary = {}
var battle_global_item_catalog_loaded: bool = false
var battle_move_info_cache: Dictionary = {}
var battle_animation_sheet_cache: Dictionary = {}
var battle_animation_plan_cache: Dictionary = {}
var battle_ball_cache: Dictionary = {}
var door_animation_texture_cache: Dictionary = {}
var follower_sprite_cache: Dictionary = {}
var follower_source_path: String = ""
var string_catalog: Dictionary = {}
var detached_map_cache_result: Dictionary = {}

static func from_rom_path(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "could not open ROM"}
	var length: int = int(file.get_length())
	var data: PackedByteArray = file.get_buffer(length)
	file.close()
	return from_rom_bytes(data)

static func from_rom_bytes(data: PackedByteArray) -> Dictionary:
	var header: Dictionary = _read_gba_header(data)
	if header.is_empty():
		return {"ok": false, "error": "ROM is too small to contain a valid GBA header"}
	var source_profile: Dictionary = ROM_PROFILE_SCRIPT.from_header(header)
	if source_profile.is_empty():
		return {"ok": false, "error": "unsupported GBA game code %s" % str(header.get("game_code", ""))}
	if bool(source_profile.get("supports_map_rendering", false)) and not _has_map_layout(data, source_profile):
		return {"ok": false, "error": "%s header found, but no compatible map layout was discovered" % str(source_profile.get("game", "GBA"))}
	var context: HashingContext = HashingContext.new()
	var rom_sha1: String = ""
	if context.start(HashingContext.HASH_SHA1) == OK:
		context.update(data)
		rom_sha1 = context.finish().hex_encode()
	var content: OpenMMOContent = OpenMMOContent.new()
	content.rom_data = data
	content.rom_sha1 = rom_sha1
	content.rom_header = header
	content.source_profile = source_profile
	content.manifest = _manifest_for_profile(source_profile, rom_sha1)
	content.string_catalog = OpenMMOStorage.read_strings(content.string_catalog_id())
	content._hydrate_manifest()
	return {"ok": true, "content": content}

static func _read_gba_header(data: PackedByteArray) -> Dictionary:
	if data.size() < GBA_MAKER_CODE_OFFSET + GBA_MAKER_CODE_LENGTH:
		return {}
	return {"title": data.slice(GBA_TITLE_OFFSET, GBA_TITLE_OFFSET + GBA_TITLE_LENGTH).get_string_from_ascii().strip_edges(), "game_code": data.slice(GBA_GAME_CODE_OFFSET, GBA_GAME_CODE_OFFSET + GBA_GAME_CODE_LENGTH).get_string_from_ascii(), "maker_code": data.slice(GBA_MAKER_CODE_OFFSET, GBA_MAKER_CODE_OFFSET + GBA_MAKER_CODE_LENGTH).get_string_from_ascii()}

static func _has_map_layout(data: PackedByteArray, profile: Dictionary) -> bool:
	var map_groups_offset: int = int(profile.get("map_groups_offset", -1))
	if map_groups_offset < 0:
		return false
	var map_groups: Dictionary = profile.get("map_groups", {})
	var towns_group: int = int(map_groups.get("towns_and_routes", MAP_GROUP_TOWNS_AND_ROUTES))
	var format: Dictionary = profile.get("format", {})
	var map_header_size: int = int(format.get("map_header_size", MAP_HEADER_SIZE))
	var towns_table_offset: int = _read_gba_pointer(data, map_groups_offset + towns_group * 4)
	if towns_table_offset < 0:
		return false
	for map_index in profile.get("map_group_probe_indices", [0, 1, 19]):
		var header_offset: int = _read_gba_pointer(data, towns_table_offset + int(map_index) * 4)
		if header_offset < 0 or not _valid_data_range(data, header_offset, map_header_size):
			return false
		var layout_offset: int = _read_gba_pointer(data, header_offset)
		if layout_offset < 0 or not _valid_data_range(data, layout_offset, map_header_size):
			return false
		var width: int = _read_data_u32(data, layout_offset)
		var height: int = _read_data_u32(data, layout_offset + 4)
		if width <= 0 or height <= 0 or width > 512 or height > 512:
			return false
	return true

static func _read_gba_pointer(data: PackedByteArray, offset: int) -> int:
	if not _valid_data_range(data, offset, 4):
		return -1
	var value: int = _read_data_u32(data, offset)
	var region: int = value & 0xFF000000
	if region != 0x08000000 and region != 0x09000000 and region != 0x0A000000:
		return -1
	var file_offset: int = value & 0x01FFFFFF
	return file_offset if _valid_data_range(data, file_offset, 1) else -1

static func _read_data_u32(data: PackedByteArray, offset: int) -> int:
	return int(data[offset]) | (int(data[offset + 1]) << 8) | (int(data[offset + 2]) << 16) | (int(data[offset + 3]) << 24)

static func _read_data_u16(data: PackedByteArray, offset: int) -> int:
	return int(data[offset]) | (int(data[offset + 1]) << 8)

static func _valid_data_range(data: PackedByteArray, offset: int, length: int) -> bool:
	return offset >= 0 and length >= 0 and offset <= data.size() and length <= data.size() - offset

static func _manifest_for_profile(profile: Dictionary, rom_sha1: String) -> Dictionary:
	var source_game: String = str(profile.get("game", "Unknown"))
	var maps: Array = []
	var map_names: Array = profile.get("map_names", [])
	var map_groups: Dictionary = profile.get("map_groups", {})
	var towns_group: int = int(map_groups.get("towns_and_routes", MAP_GROUP_TOWNS_AND_ROUTES))
	for map_index in range(map_names.size()):
		var raw_name: String = map_names[map_index]
		var map_id: String = _slugify_map_name(raw_name)
		if map_id.is_empty():
			map_id = "rom-map-%d-%d" % [towns_group, map_index]
		maps.append({"id": map_id, "name": _pretty_map_name(raw_name), "map_group": towns_group, "map_index": map_index, "width": 0, "height": 0})
	var extra_maps: Array = profile.get("extra_maps", [])
	for extra_map in extra_maps:
		maps.append({"id": str(extra_map.get("id", "")), "name": str(extra_map.get("name", "ROM map")), "map_group": int(extra_map.get("group", -1)), "map_index": int(extra_map.get("index", -1)), "width": 0, "height": 0})
	return {"schema_version": SCHEMA_VERSION, "content_id": str(profile.get("content_id", "")), "source": {"profile_id": str(profile.get("id", "")), "game": source_game, "region": str(profile.get("region", "")), "revision": str(profile.get("revision", "")), "rom_sha1": rom_sha1}, "maps": maps}

static func _pretty_map_name(raw_name: String) -> String:
	var value: String = _split_map_identifier(raw_name.replace("_", " "))
	if value.begins_with("Route ") or value.begins_with("Route"):
		var route_value: String = value.trim_prefix("Route").strip_edges()
		value = "Route " + route_value
	return value

static func _slugify_map_name(raw_name: String) -> String:
	return _split_map_identifier(raw_name.replace("_", " ")).to_lower().replace(" ", "-").replace("--", "-")

static func _split_map_identifier(raw_name: String) -> String:
	var value: String = ""
	for index in raw_name.length():
		var ch: String = raw_name.substr(index, 1)
		var is_upper: bool = ch.to_upper() == ch and ch.to_lower() != ch
		var is_digit: bool = ch >= "0" and ch <= "9"
		if index > 0 and (is_upper or is_digit):
			var prev: String = raw_name.substr(index - 1, 1)
			var prev_is_digit: bool = prev >= "0" and prev <= "9"
			var prev_is_space: bool = prev == " " or prev == "-"
			if not prev_is_space and ((is_upper and not prev_is_digit) or (is_digit and not prev_is_digit)):
				value += " "
		value += ch
	return value.strip_edges()

func _map_name_from_descriptor(descriptor: Dictionary) -> String:
	var section_id: int = int(descriptor.get("region_map_section_id", -1))
	var section_start: int = int(source_profile.get("region_map_section_start", -1))
	var section_names: Array = source_profile.get("region_map_section_names", [])
	if section_start < 0 or section_id < section_start or section_id - section_start >= section_names.size():
		return ""
	var name: String = str(section_names[section_id - section_start]).strip_edges()
	if name.is_empty():
		return ""
	var floor_num: int = int(descriptor.get("floor_num", 0))
	if floor_num == 0:
		return name
	if floor_num == FLOOR_ROOFTOP:
		return "%s Rooftop" % name
	return "%s %s%dF" % [name, "B" if floor_num < 0 else "", absi(floor_num)]

func _fallback_map_name(map_group: int, map_index: int, map_type: int, section_id: int) -> String:
	for map_value in manifest.get("maps", []):
		if map_value is Dictionary and int(map_value.get("map_group", -1)) == map_group and int(map_value.get("map_index", -1)) == map_index:
			var listed: String = str(map_value.get("name", "")).strip_edges()
			if not listed.is_empty() and listed != "Unlisted area" and not listed.begins_with("ROM map"):
				return listed
	if map_type == MAP_TYPE_INSIDE or map_type == MAP_TYPE_SECRET_BASE:
		if section_id >= 0:
			return "Indoor area"
		return "Indoor map"
	if map_group >= 0 and map_index >= 0:
		return "Map %d-%d" % [map_group, map_index]
	return "Unknown area"

func _format_int(key: String, fallback: int) -> int:
	var format: Dictionary = source_profile.get("format", {})
	return int(format.get(key, fallback))

func _animation_offsets(kind: String) -> Array:
	var animations: Dictionary = source_profile.get("animations", {})
	return animations.get(kind, [])

func _object_sprite_specs() -> Dictionary:
	var object_sprites: Dictionary = source_profile.get("object_sprites", {})
	if not bool(object_sprites.get("__generated", false)):
		_populate_fire_red_object_sprites(object_sprites)
		object_sprites["__generated"] = true
	return object_sprites

func _read_rom_u16(offset: int) -> int:
	if not _valid_range(offset, 2):
		return -1
	return int(rom_data[offset]) | (int(rom_data[offset + 1]) << 8)

func _populate_fire_red_object_sprites(object_sprites: Dictionary) -> void:
	if str(source_profile.get("region", "")) != "Kanto" or rom_data.is_empty():
		return
	var table_offset: int = -1
	for candidate in [0x39FE20, 0x39FDB0]:
		var valid_entries: int = 0
		for entry in range(16):
			var structure_offset: int = _read_rom_pointer(candidate + entry * 4)
			if structure_offset < 0 or not _valid_range(structure_offset + 0x08, 4):
				continue
			var width: int = _read_s16(structure_offset + 0x08)
			var height: int = _read_s16(structure_offset + 0x0A)
			if width > 0 and height > 0 and width % 8 == 0 and height % 8 == 0 and width <= 64 and height <= 64:
				valid_entries += 1
		if valid_entries >= 4:
			table_offset = candidate
			break
	if table_offset < 0:
		return
	var palette_table_offset: int = 0x3A51C8 if table_offset == 0x39FE20 else 0x3A501C
	for entry in range(152):
		var structure_offset: int = _read_rom_pointer(table_offset + entry * 4)
		if structure_offset < 0 or not _valid_range(structure_offset + 0x20, 4):
			continue
		var width: int = _read_s16(structure_offset + 0x08)
		var height: int = _read_s16(structure_offset + 0x0A)
		if width <= 0 or height <= 0 or width % 8 != 0 or height % 8 != 0 or width > 64 or height > 64:
			continue
		var images_offset: int = _read_rom_pointer(structure_offset + 0x1C)
		if images_offset < 0:
			continue
		var expected_bytes: int = width * height / 2
		var inanimate: bool = (_read_rom_u16(structure_offset + 0x0C) & 0x40) != 0
		var max_frames: int = 1 if inanimate or (width <= 16 and height <= 16) else 9
		var first_data_offset: int = -1
		var frame_count: int = 0
		for frame in range(max_frames):
			var frame_offset: int = images_offset + frame * 8
			var data_offset: int = _read_rom_pointer(frame_offset)
			var frame_size: int = _read_rom_u16(frame_offset + 4)
			if data_offset < 0 or frame_size != expected_bytes or not _valid_range(data_offset, frame_size):
				break
			if frame > 0:
				var previous_data_offset: int = _read_rom_pointer(frame_offset - 8)
				var previous_size: int = _read_rom_u16(frame_offset - 4)
				if data_offset != previous_data_offset + previous_size:
					break
			if frame == 0:
				first_data_offset = data_offset
			frame_count += 1
		if frame_count <= 0:
			continue
		var palette_tag: int = _read_rom_u16(structure_offset + 2)
		var palette_offset: int = -1
		for palette_entry in range(256):
			var palette_record: int = palette_table_offset + palette_entry * 8
			var palette_pointer: int = _read_rom_pointer(palette_record)
			if palette_pointer < 0:
				break
			if _read_rom_u16(palette_record + 4) == palette_tag:
				palette_offset = palette_pointer
				break
		if palette_offset < 0:
			continue
		if not object_sprites.has(entry):
			# FireRed town-map: PNG 32x16, gbagfx -mwidth 2 -mheight 2 stores two 16x16 blocks as 16x32; OAM shows 32x16.
			var storage_width: int = 16 if width == 32 and height == 16 else width
			var storage_height: int = 32 if width == 32 and height == 16 else height
			object_sprites[entry] = {"data_offset": first_data_offset, "width": width, "height": height, "storage_width": storage_width, "storage_height": storage_height, "frame_bytes": expected_bytes, "frame_count": frame_count, "palette_offset": palette_offset, "inanimate": inanimate}

func _hydrate_manifest() -> void:
	var maps: Array = manifest.get("maps", [])
	for map_index in range(maps.size()):
		if not maps[map_index] is Dictionary:
			continue
		var map_value: Dictionary = maps[map_index]
		var descriptor: Dictionary = _read_map_descriptor(map_value)
		if bool(descriptor.get("ok", false)):
			map_value["width"] = int(descriptor.get("width", 0))
			map_value["height"] = int(descriptor.get("height", 0))
			map_value["music_id"] = int(descriptor.get("music_id", 0))
			map_value["map_type"] = int(descriptor.get("map_type", 0))
			var source_name: String = _map_name_from_descriptor(descriptor)
			var current_name: String = str(map_value.get("name", "")).strip_edges()
			if not source_name.is_empty() and (current_name.begins_with("ROM map ") or current_name.is_empty() or current_name == "Unlisted area"):
				map_value["name"] = source_name
		maps[map_index] = map_value
	manifest["maps"] = maps

func _map_reference_from_id(map_id: String) -> Dictionary:
	var parts: PackedStringArray = map_id.split("-")
	if parts.size() != 4 or parts[0] != "rom" or parts[1] != "map":
		return {}
	if not parts[2].is_valid_int() or not parts[3].is_valid_int():
		return {}
	return {"id": map_id, "map_group": int(parts[2]), "map_index": int(parts[3])}

func _read_map_descriptor(map_value: Dictionary) -> Dictionary:
	var map_group: int = int(map_value.get("map_group", -1))
	var map_index: int = int(map_value.get("map_index", -1))
	if map_group < 0 or map_index < 0:
		return {"ok": false, "error": "map has no verified ROM group identity"}
	var map_groups_offset: int = int(source_profile.get("map_groups_offset", -1))
	if map_groups_offset < 0:
		return {"ok": false, "error": "the selected ROM profile has no map group table"}
	var group_table_offset: int = _read_rom_pointer(map_groups_offset + map_group * 4)
	if group_table_offset < 0:
		return {"ok": false, "error": "could not resolve the ROM map group"}
	var header_offset: int = _read_rom_pointer(group_table_offset + map_index * 4)
	if header_offset < 0 or not _valid_range(header_offset, _format_int("map_header_size", MAP_HEADER_SIZE)):
		return {"ok": false, "error": "could not resolve the ROM map header"}
	var layout_offset: int = _read_rom_pointer(header_offset)
	if layout_offset < 0 or not _valid_range(layout_offset, 0x1C):
		return {"ok": false, "error": "could not resolve the ROM map layout"}
	var width: int = _read_u32(layout_offset)
	var height: int = _read_u32(layout_offset + 4)
	var map_offset: int = _read_rom_pointer(layout_offset + 12)
	var primary_offset: int = _read_rom_pointer(layout_offset + 16)
	var secondary_offset: int = _read_rom_pointer(layout_offset + 20)
	var border_offset: int = _read_rom_pointer(layout_offset + 8)
	var border_width: int = int(rom_data[layout_offset + 24])
	var border_height: int = int(rom_data[layout_offset + 25])
	if width <= 0 or height <= 0 or width > 512 or height > 512:
		return {"ok": false, "error": "ROM map dimensions are invalid"}
	var floor_num: int = int(rom_data[header_offset + 0x1A])
	if floor_num >= 0x80:
		floor_num -= 0x100
	return {"ok": true, "map_group": map_group, "map_index": map_index, "header_offset": header_offset, "layout_offset": layout_offset, "width": width, "height": height, "map_offset": map_offset, "primary_offset": primary_offset, "secondary_offset": secondary_offset, "border_offset": border_offset, "border_width": border_width, "border_height": border_height, "music_id": _read_u16(header_offset + 0x10), "region_map_section_id": int(rom_data[header_offset + 0x14]), "map_type": int(rom_data[header_offset + 0x17]), "floor_num": floor_num}

func _map_id_for_location(map_group: int, map_index: int) -> String:
	for map_value in manifest.get("maps", []):
		if map_value is Dictionary and int(map_value.get("map_group", -1)) == map_group and int(map_value.get("map_index", -1)) == map_index:
			return str(map_value.get("id", ""))
	return "rom-map-%d-%d" % [map_group, map_index]

func map_id_for_location(map_group: int, map_index: int) -> String:
	return _map_id_for_location(map_group, map_index)

func content_id() -> String:
	return str(manifest.get("content_id", ""))

func string_catalog_id() -> String:
	var region: String = str(source_profile.get("region", "unknown")).strip_edges().to_lower().replace(" ", "-")
	var profile_id: String = str(source_profile.get("id", "")).strip_edges().to_lower()
	if region.is_empty():
		region = "unknown"
	if profile_id.is_empty():
		profile_id = content_id()
	return region.path_join(profile_id)

func battle_pokemon_name(species_id: int) -> String:
	if species_id <= 0:
		return "Pokemon"
	var cache_key: String = str(species_id)
	if battle_name_cache.has(cache_key):
		return str(battle_name_cache[cache_key])
	var internal_id: int = _battle_internal_species_id(species_id)
	var names: Dictionary = _battle_species_catalog()
	var name: String = str(names.get(str(internal_id), "")).strip_edges()
	if not name.is_empty():
		battle_name_cache[cache_key] = name
		return name
	var tables: Dictionary = _battle_rom_tables()
	if bool(tables.get("pending", false)):
		return "POKEMON #%d" % species_id
	name = _battle_fixed_name(int(tables.get("species_name_table", -1)), internal_id, SPECIES_NAME_LENGTH, "")
	if name.is_empty():
		return "POKEMON #%d" % species_id
	battle_name_cache[cache_key] = name
	return name

func _battle_species_catalog() -> Dictionary:
	if battle_species_catalog_loaded:
		return battle_species_catalog
	if rom_data.is_empty():
		return {}
	if not rom_sha1.is_empty():
		var cached: Dictionary = OpenMMOStorage.read_strings_cache(string_catalog_id(), "pokemon-%s" % rom_sha1)
		var cached_names: Variant = cached.get("names", null)
		if str(cached.get("rom_sha1", "")) == rom_sha1 and int(cached.get("schema_version", 0)) == 1 and cached_names is Dictionary:
			battle_species_catalog = cached_names as Dictionary
			battle_species_catalog_loaded = true
			return battle_species_catalog
	var tables: Dictionary = _battle_rom_tables()
	if bool(tables.get("pending", false)):
		return {}
	var table_offset: int = int(tables.get("species_name_table", -1))
	if table_offset < 0 or not _valid_range(table_offset + SPECIES_NAME_LENGTH, SPECIES_NAME_LENGTH):
		battle_species_catalog_loaded = true
		return {}
	var names: Dictionary = {}
	for internal_id in range(1, SPECIES_TABLE_MAX_RECORDS):
		var name: String = _battle_fixed_name(table_offset, internal_id, SPECIES_NAME_LENGTH, "")
		if not name.is_empty() and name.find("{0x") < 0:
			names[str(internal_id)] = name
	battle_species_catalog = names
	battle_species_catalog_loaded = true
	if not rom_sha1.is_empty():
		OpenMMOStorage.write_strings_cache(string_catalog_id(), "pokemon-%s" % rom_sha1, {"schema_version": 1, "content_id": content_id(), "catalog_id": string_catalog_id(), "rom_sha1": rom_sha1, "record_size": SPECIES_NAME_LENGTH, "names": names})
	return battle_species_catalog

func battle_move_name(move_id: int) -> String:
	if move_id <= 0:
		return "Move"
	var cache_key: String = str(move_id)
	if battle_move_name_cache.has(cache_key):
		return str(battle_move_name_cache[cache_key])
	var tables: Dictionary = _battle_rom_tables()
	if bool(tables.get("pending", false)):
		return "MOVE %d" % move_id
	var name: String = _battle_fixed_name(int(tables.get("move_name_table", -1)), move_id, 13, "MOVE %d" % move_id)
	battle_move_name_cache[cache_key] = name
	return name

func battle_item_id(value: Variant) -> int:
	if value is Dictionary:
		var item: Dictionary = value
		for key in ["item_id", "front_sprite_id", "id"]:
			var candidate: int = int(item.get(key, 0))
			if candidate > 0:
				return candidate
		var internal_id: int = int(item.get("internal_id", 0))
		if internal_id > 0:
			return internal_id
		var object_id: int = int(item.get("object_id", item.get("entity_id", 0)))
		if (object_id & 0xFFFF) == 0x5000:
			return object_id >> 16
	elif value is int or value is float:
		return int(value)
	return 0

func battle_item_info(item_id: int) -> Dictionary:
	var cache_key: String = str(item_id)
	if battle_item_info_cache.has(cache_key):
		return battle_item_info_cache[cache_key]
	var internal_id: int = item_id - 5000 if item_id >= 5000 else item_id
	var info: Dictionary = {"item_id": item_id, "internal_id": internal_id, "name": "", "price": 0, "pocket": 0, "category": "items"}
	var catalog: Dictionary = _battle_item_catalog()
	var cached_info: Variant = catalog.get(cache_key, null)
	if cached_info == null and item_id < 5000:
		cached_info = catalog.get(str(internal_id), null)
	if cached_info is Dictionary and not str((cached_info as Dictionary).get("name", "")).strip_edges().is_empty() and str((cached_info as Dictionary).get("name", "")).strip_edges().to_lower() != "item":
		info = (cached_info as Dictionary).duplicate(true)
		info["item_id"] = item_id
		info["internal_id"] = internal_id
		battle_item_info_cache[cache_key] = info
		return info
	var table: Dictionary = _battle_item_table()
	var table_offset: int = int(table.get("offset", -1))
	var item_count: int = int(table.get("count", 0))
	if internal_id >= 0 and internal_id < item_count and table_offset >= 0 and _item_table_record_matches_index(table_offset, internal_id):
		info = _battle_item_info_from_record(table_offset, internal_id)
		info["item_id"] = item_id
		info["internal_id"] = internal_id
		if not str(info.get("name", "")).strip_edges().is_empty():
			battle_item_info_cache[cache_key] = info
	return info

func _battle_global_item_catalog() -> Dictionary:
	if battle_global_item_catalog_loaded:
		return battle_global_item_catalog
	var cached: Dictionary = OpenMMOStorage.read_strings_cache(string_catalog_id(), GLOBAL_ITEM_CACHE_NAME)
	var cached_items: Variant = cached.get("items", null)
	var data_dir: String = _global_item_data_directory()
	var source_signature: String = _global_item_data_signature(data_dir) if not data_dir.is_empty() else ""
	if int(cached.get("schema_version", 0)) == GLOBAL_ITEM_CACHE_SCHEMA_VERSION and cached_items is Dictionary and (source_signature.is_empty() or str(cached.get("source_signature", "")) == source_signature):
		battle_global_item_catalog = cached_items as Dictionary
		battle_global_item_catalog_loaded = true
		return battle_global_item_catalog
	if data_dir.is_empty():
		battle_global_item_catalog = cached_items as Dictionary if cached_items is Dictionary else {}
		battle_global_item_catalog_loaded = true
		return battle_global_item_catalog
	var names_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_dir.path_join("item_names.json")))
	var items_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_dir.path_join("items.json")))
	if not names_value is Array:
		battle_global_item_catalog_loaded = true
		return {}
	var prices: Dictionary = {}
	if items_value is Array:
		for item_value in items_value:
			if item_value is Dictionary:
				var item: Dictionary = item_value
				var index: int = int(item.get("index", -1))
				if index >= 0:
					prices[str(index)] = int(item.get("price", 0))
	var catalog: Dictionary = {}
	for index in (names_value as Array).size():
		var name: String = _global_item_name(str((names_value as Array)[index]))
		if _global_item_name_is_placeholder(name):
			continue
		var item_id: int = 5000 + index
		catalog[str(item_id)] = {"item_id": item_id, "internal_id": index, "name": name, "price": int(prices.get(str(index), 0)), "pocket": 0, "category": "items"}
	battle_global_item_catalog = catalog
	battle_global_item_catalog_loaded = true
	OpenMMOStorage.write_strings_cache(string_catalog_id(), GLOBAL_ITEM_CACHE_NAME, {"schema_version": GLOBAL_ITEM_CACHE_SCHEMA_VERSION, "content_id": content_id(), "catalog_id": string_catalog_id(), "source_signature": source_signature, "items": catalog})
	return battle_global_item_catalog

func _global_item_data_directory() -> String:
	for environment_name in GLOBAL_ITEM_DATA_ENVIRONMENTS:
		var configured_path: String = OS.get_environment(str(environment_name)).strip_edges()
		if configured_path.is_empty():
			continue
		var data_dir: String = configured_path.get_base_dir() if configured_path.to_lower().ends_with("item_names.json") else configured_path
		if FileAccess.file_exists(data_dir.path_join("item_names.json")) and FileAccess.file_exists(data_dir.path_join("items.json")):
			return data_dir
	return ""

func _global_item_data_signature(data_dir: String) -> String:
	if data_dir.is_empty():
		return ""
	var names_sha1: String = _file_sha1(data_dir.path_join("item_names.json"))
	var items_sha1: String = _file_sha1(data_dir.path_join("items.json"))
	return "%s:%s" % [names_sha1, items_sha1] if not names_sha1.is_empty() and not items_sha1.is_empty() else ""

func _file_sha1(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context: HashingContext = HashingContext.new()
	var result: String = ""
	if context.start(HashingContext.HASH_SHA1) == OK:
		context.update(file.get_buffer(int(file.get_length())))
		result = context.finish().hex_encode()
	file.close()
	return result

func _global_item_name(value: String) -> String:
	var name: String = value.strip_edges()
	if name.find("Ã") < 0 and name.find("Â") < 0:
		return name.to_upper()
	var bytes: PackedByteArray = PackedByteArray()
	for index in name.length():
		var codepoint: int = name.unicode_at(index)
		if codepoint > 255:
			return name.to_upper()
		bytes.append(codepoint)
	var decoded: String = bytes.get_string_from_utf8().strip_edges()
	return decoded.to_upper() if not decoded.is_empty() else name.to_upper()

func _global_item_name_is_placeholder(name: String) -> bool:
	return name.is_empty() or name in ["NONE", "?????", "???", "-", "?"]

func _battle_item_catalog() -> Dictionary:
	if battle_item_catalog_loaded:
		return battle_item_catalog
	var catalog: Dictionary = _battle_global_item_catalog().duplicate(true)
	var local_catalog: Dictionary = {}
	if rom_data.is_empty():
		battle_item_catalog = catalog
		battle_item_catalog_loaded = true
		return battle_item_catalog
	if not rom_sha1.is_empty():
		var cached: Dictionary = OpenMMOStorage.read_strings_cache(string_catalog_id(), "items-%s" % rom_sha1)
		var cached_items: Variant = cached.get("items", null)
		if str(cached.get("rom_sha1", "")) == rom_sha1 and int(cached.get("schema_version", 0)) == 1 and cached_items is Dictionary:
			local_catalog = cached_items as Dictionary
			for key in local_catalog:
				catalog[key] = local_catalog[key]
			battle_item_catalog = catalog
			battle_item_catalog_loaded = true
			return battle_item_catalog
	var table: Dictionary = _battle_item_table()
	var table_offset: int = int(table.get("offset", -1))
	var item_count: int = int(table.get("count", 0))
	if table_offset < 0 or item_count <= 0:
		battle_item_catalog = catalog
		battle_item_catalog_loaded = true
		return battle_item_catalog
	for internal_id in range(item_count):
		if not _item_table_record_matches_index(table_offset, internal_id):
			continue
		var info: Dictionary = _battle_item_info_from_record(table_offset, internal_id)
		if not str(info.get("name", "")).strip_edges().is_empty():
			local_catalog[str(internal_id)] = info
			catalog[str(internal_id)] = info
	battle_item_catalog = catalog
	battle_item_catalog_loaded = true
	if not rom_sha1.is_empty():
		OpenMMOStorage.write_strings_cache(string_catalog_id(), "items-%s" % rom_sha1, {"schema_version": 1, "content_id": content_id(), "catalog_id": string_catalog_id(), "rom_sha1": rom_sha1, "record_size": ITEM_RECORD_SIZE, "items": local_catalog})
	return battle_item_catalog

func _battle_item_table() -> Dictionary:
	if battle_item_table_scanned:
		return battle_item_table_cache
	var tables: Dictionary = _battle_rom_tables()
	if bool(tables.get("pending", false)):
		return {}
	battle_item_table_scanned = true
	var table_offset: int = int(tables.get("item_table", -1))
	var item_count: int = _item_table_count(table_offset, ITEM_TABLE_MIN_RECORDS)
	if item_count <= 0:
		table_offset = _find_battle_item_table()
		item_count = _item_table_count(table_offset, ITEM_TABLE_MIN_RECORDS)
	if item_count <= 0:
		battle_item_table_cache = {"offset": -1, "count": 0}
		return battle_item_table_cache
	battle_item_table_cache = {"offset": table_offset, "count": item_count}
	tables["item_table"] = table_offset
	battle_table_cache = tables
	return battle_item_table_cache

func _find_battle_item_table() -> int:
	var cursor: int = 0
	while cursor < rom_data.size():
		var marker: int = rom_data.find(0x01, cursor)
		if marker < 0:
			return -1
		if marker + 1 < rom_data.size() and int(rom_data[marker + 1]) == 0:
			var candidate: int = marker - ITEM_RECORD_ID_OFFSET
			if _valid_item_table_candidate(candidate):
				return candidate
		cursor = marker + 1
	return -1

func _valid_item_table_candidate(table_offset: int) -> bool:
	if table_offset < 0 or table_offset % 4 != 0:
		return false
	for internal_id in [0, 1, 2, 3, 10, 50, 100, 200]:
		if not _item_table_record_matches_index(table_offset, int(internal_id)):
			return false
	var item_count: int = _item_table_count(table_offset, ITEM_TABLE_MIN_RECORDS)
	if item_count <= 0:
		return false
	for internal_id in [1, 2, 3]:
		if _battle_item_name_from_record(table_offset + int(internal_id) * ITEM_RECORD_SIZE).is_empty():
			return false
	return true

func _item_table_count(table_offset: int, minimum_count: int = 0) -> int:
	if table_offset < 0 or table_offset % 4 != 0:
		return 0
	var item_count: int = 0
	while item_count < ITEM_TABLE_MAX_RECORDS:
		if not _item_table_record_matches_index(table_offset, item_count):
			break
		item_count += 1
	return item_count if item_count >= minimum_count else 0

func _item_table_record_matches_index(table_offset: int, internal_id: int) -> bool:
	var offset: int = table_offset + internal_id * ITEM_RECORD_SIZE
	if not _valid_range(offset, ITEM_RECORD_SIZE):
		return false
	if _read_u16(offset + ITEM_RECORD_ID_OFFSET) == internal_id:
		return true
	if internal_id <= 0 or _read_u16(offset + ITEM_RECORD_ID_OFFSET) != 0:
		return false
	for position in range(ITEM_RECORD_SIZE):
		if int(rom_data[offset + position]) != int(rom_data[table_offset + position]):
			return false
	return true

func _battle_item_info_from_record(table_offset: int, internal_id: int) -> Dictionary:
	var offset: int = table_offset + internal_id * ITEM_RECORD_SIZE
	var pocket: int = int(rom_data[offset + 26])
	var category: String = "items"
	match pocket:
		2: category = "key_item"
		3: category = "balls"
		4: category = "tm"
		5: category = "berries"
	return {"item_id": 5000 + internal_id, "internal_id": internal_id, "name": _battle_item_name_from_record(offset), "price": _read_u16(offset + 16), "pocket": pocket, "category": category}

func _battle_item_name_from_record(offset: int) -> String:
	if not _valid_range(offset, ITEM_NAME_LENGTH):
		return ""
	var item_name: String = ""
	for position in range(ITEM_NAME_LENGTH):
		var value: int = int(rom_data[offset + position])
		if value == 0xFF:
			break
		item_name += _decode_rom_character(value)
	return item_name.strip_edges()

func battle_move_info(move_id: int) -> Dictionary:
	if move_id <= 0:
		return {"id": move_id, "name": "Move", "effect": -1, "type": -1, "type_name": "Unknown", "power": 0, "accuracy": 0, "pp": 0, "effect_chance": 0, "target": 0, "priority": 0, "flags": 0}
	var cache_key: String = str(move_id)
	if battle_move_info_cache.has(cache_key):
		return battle_move_info_cache[cache_key]
	var info: Dictionary = {"id": move_id, "name": battle_move_name(move_id), "effect": -1, "type": -1, "type_name": "Unknown", "power": 0, "accuracy": 0, "pp": 0, "effect_chance": 0, "target": 0, "priority": 0, "flags": 0}
	var tables: Dictionary = _battle_rom_tables()
	var table_offset: int = int(tables.get("move_table", -1))
	var offset: int = table_offset + move_id * 12
	if table_offset >= 0 and _valid_range(offset, 12):
		var move_type: int = int(rom_data[offset + 2])
		info["effect"] = int(rom_data[offset])
		info["type"] = move_type
		info["type_name"] = _battle_move_type_name(move_type)
		info["power"] = int(rom_data[offset + 1])
		info["accuracy"] = int(rom_data[offset + 3])
		info["pp"] = int(rom_data[offset + 4])
		info["effect_chance"] = int(rom_data[offset + 5])
		info["target"] = int(rom_data[offset + 6])
		info["priority"] = int(rom_data[offset + 7]) - 256 if int(rom_data[offset + 7]) >= 128 else int(rom_data[offset + 7])
		info["flags"] = int(rom_data[offset + 8])
	battle_move_info_cache[cache_key] = info
	return info

func battle_pokemon_sprite(species_id: int, back: bool = false) -> Dictionary:
	if species_id <= 0:
		return {"ok": false}
	var cache_key: String = "%d:%s" % [species_id, "back" if back else "front"]
	if battle_sprite_cache.has(cache_key):
		return battle_sprite_cache[cache_key]
	var tables: Dictionary = _battle_rom_tables()
	var table_offset: int = int(tables.get("back_sprite_table" if back else "front_sprite_table", -1))
	var palette_table_offset: int = int(tables.get("palette_table", -1))
	var internal_id: int = _battle_internal_species_id(species_id)
	var sprite_entry: int = table_offset + internal_id * 8
	var palette_entry: int = palette_table_offset + internal_id * 8
	if table_offset < 0 or palette_table_offset < 0 or not _valid_range(sprite_entry, 8) or not _valid_range(palette_entry, 4):
		return {"ok": false}
	var sprite_offset: int = _read_rom_pointer(sprite_entry)
	var sprite_size: int = _read_u16(sprite_entry + 4)
	var sprite_data: PackedByteArray = _read_lz77(sprite_offset)
	if sprite_data.size() < 2048 and sprite_size > 0 and _valid_range(sprite_offset, sprite_size):
		sprite_data = rom_data.slice(sprite_offset, sprite_offset + sprite_size)
	if sprite_data.size() < 2048:
		return {"ok": false}
	var palette_offset: int = _read_rom_pointer(palette_entry)
	var palette_data: PackedByteArray = _read_lz77(palette_offset)
	if palette_data.size() < 32 and _valid_range(palette_offset, 32):
		palette_data = rom_data.slice(palette_offset, palette_offset + 32)
	if palette_data.size() < 32:
		return {"ok": false}
	var image: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var tile_offset: int = ((y / 8) * 8 + (x / 8)) * 32
			var pixel_offset: int = tile_offset + (y % 8) * 4 + (x % 8) / 2
			var packed: int = int(sprite_data[pixel_offset])
			var palette_index: int = (packed & 0x0F) if x % 2 == 0 else ((packed >> 4) & 0x0F)
			var color_value: int = int(palette_data[palette_index * 2]) | (int(palette_data[palette_index * 2 + 1]) << 8)
			var color := _rgb555_color(color_value)
			if palette_index == 0:
				color.a = 0.0
			image.set_pixel(x, y, color)
	var result: Dictionary = {"ok": true, "texture": ImageTexture.create_from_image(image), "width": 64, "height": 64, "species_id": species_id, "back": back}
	battle_sprite_cache[cache_key] = result
	return result

func battle_pokeball_frames(ball_id: int = 0) -> Dictionary:
	var cache_key: String = str(ball_id)
	if battle_ball_cache.has(cache_key):
		return battle_ball_cache[cache_key]
	var sheet_table: int = _find_ball_sheet_table()
	var palette_table: int = _find_ball_palette_table()
	var sheet_entry: int = sheet_table + ball_id * 8
	var palette_entry: int = palette_table + ball_id * 8
	if ball_id < 0 or ball_id >= 12 or sheet_table < 0 or palette_table < 0 or not _valid_range(sheet_entry, 8) or not _valid_range(palette_entry, 8):
		return {"ok": false}
	var pixels: PackedByteArray = _read_lz77(_read_rom_pointer(sheet_entry))
	var palette: PackedByteArray = _read_lz77(_read_rom_pointer(palette_entry))
	if pixels.size() < 384 or palette.size() < 32:
		return {"ok": false}
	var frames: Array = []
	for frame_index in range(3):
		var image: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in range(16):
			for x in range(16):
				var tile_offset: int = (frame_index * 4 + (y / 8) * 2 + x / 8) * 32
				var pixel_offset: int = tile_offset + (y % 8) * 4 + (x % 8) / 2
				var packed: int = int(pixels[pixel_offset])
				var palette_index: int = packed & 0x0F if x % 2 == 0 else (packed >> 4) & 0x0F
				var color_value: int = int(palette[palette_index * 2]) | int(palette[palette_index * 2 + 1]) << 8
				var color: Color = _rgb555_color(color_value)
				if palette_index == 0:
					color.a = 0.0
				image.set_pixel(x, y, color)
		frames.append(ImageTexture.create_from_image(image))
	var result: Dictionary = {"ok": true, "frames": frames, "width": 16, "height": 16, "ball_id": ball_id}
	battle_ball_cache[cache_key] = result
	return result

func _find_ball_sheet_table() -> int:
	var cursor: int = 4
	while cursor < rom_data.size():
		var marker: int = rom_data.find(0x80, cursor)
		if marker < 0:
			return -1
		var offset: int = marker - 4
		if offset % 4 == 0 and _valid_range(offset, 12 * 8):
			var valid: bool = true
			for index in range(12):
				var record: int = offset + index * 8
				if _read_u16(record + 4) != 384 or _read_u16(record + 6) != 55000 + index or _read_rom_pointer(record) < 0:
					valid = false
					break
			if valid:
				return offset
		cursor = marker + 1
	return -1

func _find_ball_palette_table() -> int:
	var cursor: int = 4
	while cursor < rom_data.size():
		var marker: int = rom_data.find(0xD8, cursor)
		if marker < 0:
			return -1
		var offset: int = marker - 4
		if offset % 4 == 0 and _valid_range(offset, 12 * 8):
			var valid: bool = true
			for index in range(12):
				var record: int = offset + index * 8
				if _read_u16(record + 4) != 55000 + index or _read_rom_pointer(record) < 0:
					valid = false
					break
			if valid:
				return offset
		cursor = marker + 1
	return -1

func follower_pokemon_sprite(species_id: int, gender: int = -1, shiny: bool = false, form: int = 0) -> Dictionary:
	if species_id <= 0:
		return {"ok": false, "error": "Invalid follower species"}
	var cache_key: String = "%d:%d:%d:%d" % [species_id, gender, int(shiny), form]
	if follower_sprite_cache.has(cache_key):
		return follower_sprite_cache[cache_key]
	if not follower_source_path.is_empty():
		var hgss_result: Dictionary = _hgss_follower_sprite(species_id, gender, shiny, form)
		if bool(hgss_result.get("ok", false)):
			follower_sprite_cache[cache_key] = hgss_result
			return hgss_result
	var gender_tags: Array = ["b", "m", "f"]
	if gender == 0:
		gender_tags = ["m", "b", "f"]
	elif gender == 1:
		gender_tags = ["f", "b", "m"]
	var shine_tag: String = "s" if shiny else "n"
	var roots: Array = ["res://assets/sprites/followsprites", "res://content/%s/sprites/followsprites" % string_catalog_id()]
	var paths: Array = []
	for root_value in roots:
		var root: String = str(root_value)
		for gender_tag in gender_tags:
			if form > 0:
				paths.append(root.path_join("%d-%s-%s-%d.png" % [species_id, gender_tag, shine_tag, form]))
			paths.append(root.path_join("%d-%s-%s.png" % [species_id, gender_tag, shine_tag]))
	for path_value in paths:
		var path: String = str(path_value)
		if not ResourceLoader.exists(path):
			continue
		var texture: Texture2D = load(path) as Texture2D
		if texture == null:
			continue
		var result: Dictionary = {"ok": true, "texture": texture, "width": texture.get_width(), "height": texture.get_height(), "source": "followsprite", "path": path}
		follower_sprite_cache[cache_key] = result
		return result
	var missing: Dictionary = {"ok": false, "error": "No PokeMMO followsprite resource is mounted for this species"}
	follower_sprite_cache[cache_key] = missing
	return missing

func set_follower_source(path: String) -> Dictionary:
	var resolved_path: String = resolve_follower_source_path(path)
	if resolved_path.is_empty():
		return {"ok": false, "error": "The selected folder does not contain extracted HeartGold/SoulSilver follower models"}
	follower_source_path = resolved_path
	follower_sprite_cache.clear()
	return {"ok": true, "path": resolved_path}

static func resolve_follower_source_path(path: String) -> String:
	var selected_path: String = path.replace("\\", "/").trim_suffix("/")
	var candidates: Array[String] = [selected_path, selected_path.path_join("mmodel"), selected_path.path_join("files/data/mmodel/mmodel")]
	for candidate in candidates:
		if FileAccess.file_exists(candidate.path_join("mmodel_00000297.NSBTX")):
			return candidate
	return ""

func _hgss_follower_sprite(species_id: int, gender: int, shiny: bool, form: int) -> Dictionary:
	if species_id < 1 or species_id > 151 or form != 0:
		return {"ok": false, "error": "No extracted HGSS follower model is available for this species or form"}
	var model_id: int = 296 + species_id
	if species_id >= 4:
		model_id += 1
	if species_id >= 26:
		model_id += 1
	if gender == 1 and species_id in [3, 25]:
		model_id += 1
	var path: String = follower_source_path.path_join("mmodel_%08d.NSBTX" % model_id)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "The extracted HGSS follower model is missing", "path": path}
	var data: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var decoded: Dictionary = _decode_hgss_follower_texture(data, shiny)
	if bool(decoded.get("ok", false)):
		decoded["source"] = "hgss_follower_model"
		decoded["path"] = path
	return decoded

func _decode_hgss_follower_texture(data: PackedByteArray, shiny: bool) -> Dictionary:
	if not _valid_data_range(data, 0, 0x14) or data[0] != 0x42 or data[1] != 0x54 or data[2] != 0x58 or data[3] != 0x30:
		return {"ok": false, "error": "Invalid HGSS follower texture container"}
	var section_offset: int = _read_data_u32(data, 0x10)
	if not _valid_data_range(data, section_offset, 0x3C) or data[section_offset] != 0x54 or data[section_offset + 1] != 0x45 or data[section_offset + 2] != 0x58 or data[section_offset + 3] != 0x30:
		return {"ok": false, "error": "Invalid HGSS follower texture section"}
	var texture_size: int = _read_data_u16(data, section_offset + 0x0C) * 8
	var texture_offset: int = section_offset + _read_data_u32(data, section_offset + 0x14)
	var palette_size: int = _read_data_u16(data, section_offset + 0x30) * 8
	var palette_offset: int = section_offset + _read_data_u32(data, section_offset + 0x38)
	var dictionary_offset: int = section_offset + _read_data_u16(data, section_offset + 0x0E)
	if not _valid_data_range(data, dictionary_offset + 48, 4):
		return {"ok": false, "error": "Invalid HGSS follower texture dictionary"}
	var texture_parameter: int = _read_data_u32(data, dictionary_offset + 48)
	var width: int = 8 << ((texture_parameter >> 20) & 7)
	var height: int = 8 << ((texture_parameter >> 23) & 7)
	var texture_format: int = (texture_parameter >> 26) & 7
	var frame_bytes: int = (width * height) >> 1
	var frame_count: int = floori(float(texture_size) / float(frame_bytes)) if frame_bytes > 0 else 0
	var selected_palette_offset: int = palette_offset + (32 if shiny else 0)
	if texture_format != 3 or width != 32 or height != 32 or frame_count < 8 or palette_size < (64 if shiny else 32) or not _valid_data_range(data, texture_offset, frame_bytes * 8) or not _valid_data_range(data, selected_palette_offset, 32):
		return {"ok": false, "error": "Unsupported HGSS follower texture layout"}
	var frames: Array[Texture2D] = []
	for frame_index in range(8):
		var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
		for pixel_index in range(width * height):
			var packed: int = int(data[texture_offset + frame_index * frame_bytes + (pixel_index >> 1)])
			var palette_index: int = ((packed >> 4) & 15) if (pixel_index & 1) != 0 else (packed & 15)
			var color_value: int = _read_data_u16(data, selected_palette_offset + palette_index * 2)
			var color: Color = Color(float(color_value & 31) / 31.0, float((color_value >> 5) & 31) / 31.0, float((color_value >> 10) & 31) / 31.0, 0.0 if palette_index == 0 else 1.0)
			image.set_pixel(pixel_index % width, floori(float(pixel_index) / float(width)), color)
		frames.append(ImageTexture.create_from_image(image))
	return {"ok": true, "texture": frames[0], "frames": frames, "width": width, "height": height}

func _battle_internal_species_id(species_id: int) -> int:
	return species_id if species_id <= 251 else species_id + 25

func _battle_rom_tables() -> Dictionary:
	if battle_tables_scanned:
		return battle_table_cache
	if rom_data.is_empty():
		return {"pending": true}
	var header_offset: int = 0x100
	if not _valid_range(header_offset, 76):
		battle_table_cache = {"available": false}
		battle_tables_scanned = true
		return battle_table_cache
	var tables: Dictionary = {"header_offset": header_offset, "front_sprite_table": _read_rom_pointer(header_offset + 40), "back_sprite_table": _read_rom_pointer(header_offset + 44), "palette_table": _read_rom_pointer(header_offset + 48), "species_name_table": _read_rom_pointer(header_offset + 68), "move_name_table": _read_rom_pointer(header_offset + 72), "item_table": _read_rom_pointer(header_offset + 200), "move_table": _format_int("battle_move_table_offset", -1), "animation_pic_table": _format_int("battle_animation_pic_table_offset", -1), "animation_palette_table": _format_int("battle_animation_palette_table_offset", -1), "animation_move_table": _format_int("battle_animation_move_table_offset", -1)}
	if str(source_profile.get("id", "")) == "pokemon-fire-red" and rom_sha1 == FIRE_RED_SHA1:
		tables["animation_pic_table"] = 0x3ACC08
		tables["animation_palette_table"] = 0x3AD510
		tables["animation_move_table"] = 0x1C68F4
	if not _valid_range(int(tables.get("front_sprite_table", -1)), 8) or not _valid_range(int(tables.get("back_sprite_table", -1)), 8) or not _valid_range(int(tables.get("palette_table", -1)), 8) or not _valid_range(int(tables.get("species_name_table", -1)), 11) or not _valid_range(int(tables.get("move_name_table", -1)), 13):
		battle_table_cache = {"available": false}
		battle_tables_scanned = true
		return battle_table_cache
	battle_table_cache = tables
	battle_tables_scanned = true
	battle_name_cache.clear()
	battle_move_name_cache.clear()
	battle_item_info_cache.clear()
	return battle_table_cache

func battle_move_animation_plan(move_id: int) -> Dictionary:
	if move_id <= 0:
		return {"ok": false}
	var cache_key: String = str(move_id)
	if battle_animation_plan_cache.has(cache_key):
		return battle_animation_plan_cache[cache_key]
	var tables: Dictionary = _battle_animation_tables()
	var move_table: int = int(tables.get("animation_move_table", -1))
	if move_table < 0 or not _valid_range(move_table + move_id * 4, 4):
		return {"ok": false}
	var move_info: Dictionary = battle_move_info(move_id)
	var state: Dictionary = {"delay": 0, "loaded": [], "tags": [], "spawns": [], "visited": {}}
	_walk_battle_animation_script(_read_rom_pointer(move_table + move_id * 4), int(move_info.get("power", 0)), 0, state)
	var tags: Array = state.get("tags", [])
	if tags.is_empty():
		tags.append(_battle_animation_fallback_tag(int(move_info.get("type", -1))))
	var spawns: Array = state.get("spawns", [])
	if spawns.is_empty():
		var count: int = 6 if int(move_info.get("power", 0)) <= 0 else 5
		for index in range(count):
			spawns.append({"tag": int(tags[index % tags.size()]), "kind": "aura" if int(move_info.get("power", 0)) <= 0 else "travel", "delay": index * 3, "offset": Vector2((index - count / 2) * 8, ((index * 5) % 13) - 6)})
	var duration: int = clampi(int(state.get("delay", 0)) + 24, 48, 96)
	var result: Dictionary = {"ok": true, "tags": tags, "spawns": spawns, "duration_frames": duration, "hit_frame": clampi(duration - 18, 12, 72)}
	battle_animation_plan_cache[cache_key] = result
	return result

func battle_animation_sheet(tag: int) -> Dictionary:
	var cache_key: String = str(tag)
	if battle_animation_sheet_cache.has(cache_key):
		return battle_animation_sheet_cache[cache_key]
	var tables: Dictionary = _battle_animation_tables()
	var pic_table: int = int(tables.get("animation_pic_table", -1))
	var palette_table: int = int(tables.get("animation_palette_table", -1))
	var index: int = tag - 10000
	var record: int = pic_table + index * 8
	var palette_record: int = palette_table + index * 8
	if index < 0 or index >= 289 or pic_table < 0 or palette_table < 0 or not _valid_range(record, 8) or not _valid_range(palette_record, 8):
		return {"ok": false}
	var size: int = _read_u16(record + 4)
	var data_offset: int = _read_rom_pointer(record)
	var pixels: PackedByteArray = _read_lz77(data_offset)
	if pixels.size() < 32 and size >= 32 and _valid_range(data_offset, size):
		pixels = rom_data.slice(data_offset, data_offset + size)
	var palette_offset: int = _read_rom_pointer(palette_record)
	var palette: PackedByteArray = _read_lz77(palette_offset)
	if palette.size() < 32 and _valid_range(palette_offset, 32):
		palette = rom_data.slice(palette_offset, palette_offset + 32)
	if pixels.size() < 32 or palette.size() < 32:
		return {"ok": false}
	var dimensions: Vector3i = _battle_animation_dimensions(pixels.size())
	var width: int = dimensions.x
	var height: int = dimensions.y
	var frame_count: int = dimensions.z
	var tiles_wide: int = width / 8
	var tiles_high: int = height / 8
	var frame_tiles: int = tiles_wide * tiles_high
	frame_count = mini(frame_count, maxi(1, pixels.size() / maxi(frame_tiles * 32, 1)))
	var frames: Array = []
	for frame_index in range(frame_count):
		var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
		var frame_offset: int = frame_index * frame_tiles * 32
		for tile_y in range(tiles_high):
			for tile_x in range(tiles_wide):
				var tile_offset: int = frame_offset + (tile_y * tiles_wide + tile_x) * 32
				for pixel_y in range(8):
					for pixel_x in range(8):
						var packed: int = int(pixels[tile_offset + pixel_y * 4 + pixel_x / 2])
						var palette_index: int = (packed & 0x0F) if pixel_x % 2 == 0 else ((packed >> 4) & 0x0F)
						if palette_index == 0:
							continue
						var color_value: int = int(palette[palette_index * 2]) | (int(palette[palette_index * 2 + 1]) << 8)
						image.set_pixel(tile_x * 8 + pixel_x, tile_y * 8 + pixel_y, _rgb555_color(color_value))
		frames.append(ImageTexture.create_from_image(image))
	var result: Dictionary = {"ok": not frames.is_empty(), "frames": frames, "width": width, "height": height, "tag": tag}
	battle_animation_sheet_cache[cache_key] = result
	return result

func _battle_animation_tables() -> Dictionary:
	var tables: Dictionary = _battle_rom_tables()
	if int(tables.get("animation_pic_table", -1)) >= 0 and int(tables.get("animation_move_table", -1)) >= 0:
		return tables
	var pic_table: int = _find_battle_animation_pic_table()
	var move_table: int = _find_battle_animation_move_table()
	if pic_table >= 0:
		tables["animation_pic_table"] = pic_table
		var palette_table: int = pic_table + 289 * 8
		if _valid_range(palette_table, 8) and _read_u16(palette_table + 4) == 10000:
			tables["animation_palette_table"] = palette_table
	if move_table >= 0:
		tables["animation_move_table"] = move_table
	battle_table_cache = tables
	return tables

func _find_battle_animation_pic_table() -> int:
	var cursor: int = 7
	while cursor < rom_data.size():
		var marker: int = rom_data.find(0x27, cursor)
		if marker < 0:
			return -1
		var offset: int = marker - 7
		if offset % 4 == 0 and _valid_range(offset, 32):
			var valid: bool = true
			for index in range(4):
				var record: int = offset + index * 8
				if _read_u16(record + 6) != 10000 + index or _read_u16(record + 4) < 32 or _read_rom_pointer(record) < 0:
					valid = false
					break
			if valid:
				return offset
		cursor = marker + 1
	return -1

func _find_battle_animation_move_table() -> int:
	var cursor: int = 7
	while cursor < rom_data.size():
		var marker: int = rom_data.find(0x08, cursor)
		if marker < 0:
			return -1
		var offset: int = marker - 3
		if offset % 4 == 0 and _valid_range(offset, 355 * 4) and _read_u32(offset) == _read_u32(offset + 4) and _read_rom_pointer(offset) >= 0:
			var valid: bool = true
			var unique_scripts: Dictionary = {}
			for index in range(355):
				var script: int = _read_rom_pointer(offset + index * 4)
				if script < 0 or int(rom_data[script]) > 0x2F:
					valid = false
					break
				unique_scripts[script] = true
			if valid and unique_scripts.size() > 120:
				return offset
		cursor = marker + 1
	return -1

func _walk_battle_animation_script(address: int, power: int, depth: int, state: Dictionary) -> void:
	if depth > 6 or address < 0 or not _valid_range(address, 1):
		return
	var command_lengths: Array = [2, 2, -1, -1, 1, 0, 0, 0, 0, 2, 1, 1, 2, 0, 4, 0, 3, 8, 5, 4, 1, 0, 0, 0, 1, 3, 1, 6, 5, 4, 2, -1, 0, 7, 1, 1, 4, 3, 6, 6, 1, 0, 1, 1, 1, 1, 1, 0]
	var pc: int = address
	var steps: int = 0
	while _valid_range(pc, 1) and steps < 400:
		steps += 1
		var visited: Dictionary = state.get("visited", {})
		if visited.has(pc):
			break
		visited[pc] = true
		state["visited"] = visited
		var command: int = int(rom_data[pc])
		if command > 0x2F or command == 0x08:
			break
		if command == 0x0F:
			return
		if command == 0x00 and _valid_range(pc, 3):
			var tag: int = _read_u16(pc + 1)
			if tag >= 10000 and tag < 10289:
				var loaded: Array = state.get("loaded", [])
				loaded.append(tag)
				state["loaded"] = loaded
				var tags: Array = state.get("tags", [])
				if not tags.has(tag):
					tags.append(tag)
				state["tags"] = tags
			state["delay"] = int(state.get("delay", 0)) + 1
			pc += 3
			continue
		if command == 0x01 and _valid_range(pc, 3):
			var loaded: Array = state.get("loaded", [])
			loaded.erase(_read_u16(pc + 1))
			state["loaded"] = loaded
			pc += 3
			continue
		if command in [0x02, 0x03, 0x1F] and _valid_range(pc, 7):
			var argument_count: int = int(rom_data[pc + 6])
			var total: int = 7 + argument_count * 2
			if not _valid_range(pc, total):
				break
			var loaded: Array = state.get("loaded", [])
			var spawns: Array = state.get("spawns", [])
			if command == 0x02 and not loaded.is_empty() and spawns.size() < 20:
				var offset_x: int = _read_u16(pc + 7) if argument_count >= 1 else 0
				var offset_y: int = _read_u16(pc + 9) if argument_count >= 2 else 0
				if offset_x >= 0x8000:
					offset_x -= 0x10000
				if offset_y >= 0x8000:
					offset_y -= 0x10000
				if absi(offset_x) >= 80:
					offset_x = 0
				if absi(offset_y) >= 80:
					offset_y = 0
				var tag: int = int(loaded.back())
				var on_target: bool = (int(rom_data[pc + 5]) & 0x80) != 0
				spawns.append({"tag": tag, "kind": _battle_animation_kind(tag, power, on_target), "delay": int(state.get("delay", 0)), "offset": Vector2(offset_x, offset_y)})
				state["spawns"] = spawns
			pc += total
			continue
		if command == 0x04 and _valid_range(pc, 2):
			state["delay"] = int(state.get("delay", 0)) + int(rom_data[pc + 1])
			pc += 2
			continue
		if command == 0x05:
			state["delay"] = int(state.get("delay", 0)) + 12
			pc += 1
			continue
		if command == 0x0E and _valid_range(pc, 5):
			_walk_battle_animation_script(_read_rom_pointer(pc + 1), power, depth + 1, state)
			pc += 5
			continue
		if command == 0x11 and _valid_range(pc, 9):
			_walk_battle_animation_script(_read_rom_pointer(pc + 1), power, depth + 1, state)
			pc += 9
			continue
		if command == 0x13 and _valid_range(pc, 5):
			pc = _read_rom_pointer(pc + 1)
			if pc < 0:
				break
			continue
		if command == 0x12 and _valid_range(pc, 6):
			if int(rom_data[pc + 1]) == 0:
				var destination: int = _read_rom_pointer(pc + 2)
				if destination >= 0:
					pc = destination
					continue
			pc += 6
			continue
		if command == 0x21 and _valid_range(pc, 8):
			pc += 8
			continue
		if command == 0x24 and _valid_range(pc, 5):
			pc += 5
			continue
		var extra: int = int(command_lengths[command])
		if extra < 0 or not _valid_range(pc, extra + 1):
			break
		pc += extra + 1

func _battle_animation_kind(tag: int, power: int, on_target: bool) -> String:
	var index: int = tag - 10000
	if index in [21, 22, 26, 38, 39, 40, 41, 50, 51, 52, 55, 56, 116, 135, 136, 137, 138, 139, 143, 192, 204, 222, 245, 246, 285, 286, 287]:
		return "impact"
	if index in [65, 67, 68, 69, 115, 146]:
		return "rain" if power <= 0 else "travel"
	if power <= 0:
		return "rain" if on_target else "aura"
	return "travel"

func _battle_animation_fallback_tag(move_type: int) -> int:
	var tags: Dictionary = {1: 10143, 2: 10003, 3: 10065, 4: 10058, 5: 10058, 6: 10020, 7: 10200, 8: 10001, 10: 10029, 11: 10146, 12: 10063, 13: 10037, 14: 10004, 15: 10043, 16: 10033, 17: 10017}
	return int(tags.get(move_type, 10135))

func _battle_animation_dimensions(byte_count: int) -> Vector3i:
	var tiles: int = byte_count / 32
	if tiles <= 0:
		return Vector3i(8, 8, 1)
	if tiles % 16 == 0 and tiles / 16 <= 12:
		return Vector3i(32, 32, tiles / 16)
	if tiles == 64:
		return Vector3i(64, 64, 1)
	if tiles % 4 == 0 and tiles / 4 <= 16:
		return Vector3i(16, 16, tiles / 4)
	return Vector3i(8, 8, tiles)

func _battle_move_type_name(move_type: int) -> String:
	match move_type:
		0: return "Normal"
		1: return "Fighting"
		2: return "Flying"
		3: return "Poison"
		4: return "Ground"
		5: return "Rock"
		6: return "Bug"
		7: return "Ghost"
		8: return "Steel"
		10: return "Fire"
		11: return "Water"
		12: return "Grass"
		13: return "Electric"
		14: return "Psychic"
		15: return "Ice"
		16: return "Dragon"
		17: return "Dark"
	return "Unknown"

func _battle_fixed_name(table_offset: int, index: int, width: int, fallback: String) -> String:
	var offset: int = table_offset + index * width
	if table_offset < 0 or index < 0 or not _valid_range(offset, width):
		return fallback
	var output: String = ""
	for position in range(width):
		var value: int = int(rom_data[offset + position])
		if value == 0xFF:
			break
		if value != 0:
			output += _decode_rom_character(value)
	output = output.strip_edges()
	return output if not output.is_empty() else fallback

func _rgb555_color(value: int) -> Color:
	return Color(float(value & 0x1F) / 31.0, float((value >> 5) & 0x1F) / 31.0, float((value >> 10) & 0x1F) / 31.0, 1.0)

func map_data(map_id: String) -> Dictionary:
	for map_value in manifest.get("maps", []):
		if map_value is Dictionary and str(map_value.get("id", "")) == map_id:
			return map_value
	var reference: Dictionary = _map_reference_from_id(map_id)
	if not reference.is_empty():
		var descriptor: Dictionary = _read_map_descriptor(reference)
		if bool(descriptor.get("ok", false)):
			var name: String = _map_name_from_descriptor(descriptor)
			if name.is_empty():
				name = _fallback_map_name(int(reference.get("map_group", -1)), int(reference.get("map_index", -1)), int(descriptor.get("map_type", 0)), int(descriptor.get("region_map_section_id", -1)))
			return {"id": map_id, "name": name, "map_group": int(reference.get("map_group", -1)), "map_index": int(reference.get("map_index", -1)), "width": int(descriptor.get("width", 0)), "height": int(descriptor.get("height", 0)), "music_id": int(descriptor.get("music_id", 0)), "map_type": int(descriptor.get("map_type", 0)), "region_map_section_id": int(descriptor.get("region_map_section_id", -1)), "floor_num": int(descriptor.get("floor_num", 0))}
	return {}

func _get_or_build_map_topology(map_id: String) -> Dictionary:
	var cached_topology: Dictionary = map_topology_cache.get(map_id, {})
	if not cached_topology.is_empty():
		return cached_topology
	var map_value: Dictionary = map_data(map_id)
	if map_value.is_empty():
		return {"ok": false, "error": "unknown map"}
	var descriptor: Dictionary = _read_map_descriptor(map_value)
	if not bool(descriptor.get("ok", false)):
		return descriptor
	var topology: Dictionary = {"ok": true, "map_id": map_id, "width": int(descriptor.get("width", 0)), "height": int(descriptor.get("height", 0)), "header_offset": int(descriptor.get("header_offset", -1)), "music_id": int(descriptor.get("music_id", 0)), "map_type": int(descriptor.get("map_type", 0)), "connections": _read_map_connections(int(descriptor.get("header_offset", -1)))}
	map_topology_cache[map_id] = topology
	return topology

func render_map(map_id: String, animation_tick: int = 0) -> Dictionary:
	var map_value: Dictionary = map_data(map_id)
	var cached_map: Dictionary = map_cache.get(map_id, {})
	if map_value.is_empty() and cached_map.is_empty():
		return {"ok": false, "error": "unknown map"}
	var source: Dictionary = manifest.get("source", {})
	if not bool(source_profile.get("supports_map_rendering", false)):
		return {"ok": false, "error": "%s map reader is not enabled yet" % str(source.get("game", "GBA"))}
	cached_map = _get_or_build_map_cache(map_id, map_value, true)
	if not bool(cached_map.get("ok", false)):
		return cached_map
	var animation_phase: int = posmod(animation_tick, 40)
	var texture_cache: Dictionary = cached_map.get("textures", {})
	var image_cache: Dictionary = cached_map.get("images", {})
	var background_texture_cache: Dictionary = cached_map.get("background_textures", {})
	var foreground_texture_cache: Dictionary = cached_map.get("foreground_textures", {})
	var animated_tiles: Array = cached_map.get("animated_tiles", [])
	if animated_tiles.is_empty() or animation_phase == 0:
		var prepared: Dictionary = prepare_map(map_id)
		if not bool(prepared.get("ok", false)):
			return prepared
		prepared["image"] = cached_map.get("base_image") as Image
		prepared["animation_phase"] = animation_phase
		return prepared
	var cache_key: String = str(animation_phase)
	var texture: Texture2D = texture_cache.get(cache_key) as Texture2D
	var image: Image = image_cache.get(cache_key) as Image
	if texture == null or image == null:
		image = _render_cached_map(cached_map, animation_phase)
		texture = ImageTexture.create_from_image(image)
		texture_cache.clear()
		texture_cache[cache_key] = texture
		image_cache.clear()
		image_cache[cache_key] = image
		map_cache[map_id] = cached_map
	var background_texture: Texture2D = background_texture_cache.get(cache_key) as Texture2D
	if background_texture == null:
		var background_image: Image = _render_cached_layer(cached_map, animation_phase, false)
		background_texture = ImageTexture.create_from_image(background_image)
		background_texture_cache.clear()
		background_texture_cache[cache_key] = background_texture
	var foreground_texture: Texture2D = foreground_texture_cache.get(cache_key) as Texture2D
	if foreground_texture == null:
		var foreground_image: Image = _render_cached_layer(cached_map, animation_phase, true)
		foreground_texture = ImageTexture.create_from_image(foreground_image)
		foreground_texture_cache.clear()
		foreground_texture_cache[cache_key] = foreground_texture
	map_cache[map_id] = cached_map
	return {"ok": true, "texture": texture, "image": image, "background_texture": background_texture, "foreground_texture": foreground_texture, "width": int(cached_map.get("width", 0)), "height": int(cached_map.get("height", 0)), "render_origin": cached_map.get("render_origin", Vector2i.ZERO), "render_width": int(cached_map.get("render_width", cached_map.get("width", 0))), "render_height": int(cached_map.get("render_height", cached_map.get("height", 0))), "header_offset": int(cached_map.get("header_offset", -1)), "layout_offset": int(cached_map.get("layout_offset", -1)), "objects": cached_map.get("objects", []), "warps": cached_map.get("warps", []), "connections": cached_map.get("connections", []), "map_cells": cached_map.get("map_cells", PackedInt32Array()), "music_id": int(cached_map.get("music_id", 0)), "map_type": int(cached_map.get("map_type", 0)), "animation_phase": animation_phase}

func prepare_map(map_id: String, include_composite_texture: bool = true) -> Dictionary:
	var cached_map: Dictionary = _get_or_build_map_cache(map_id)
	if not bool(cached_map.get("ok", false)):
		return cached_map
	var world_texture: Texture2D = cached_map.get("world_texture") as Texture2D
	var background_texture: Texture2D = cached_map.get("world_background_texture") as Texture2D
	var foreground_texture: Texture2D = cached_map.get("world_foreground_texture") as Texture2D
	if background_texture == null or foreground_texture == null:
		var background_image: Image = cached_map.get("base_background_image") as Image
		var foreground_image: Image = cached_map.get("base_foreground_image") as Image
		background_texture = ImageTexture.create_from_image(background_image)
		foreground_texture = ImageTexture.create_from_image(foreground_image)
		cached_map["world_background_texture"] = background_texture
		cached_map["world_foreground_texture"] = foreground_texture
	if include_composite_texture and world_texture == null:
		world_texture = background_texture
		cached_map["world_texture"] = world_texture
	return {"ok": true, "texture": world_texture if world_texture != null else background_texture, "background_texture": background_texture, "foreground_texture": foreground_texture, "world_texture": world_texture, "width": int(cached_map.get("width", 0)), "height": int(cached_map.get("height", 0)), "render_origin": cached_map.get("render_origin", Vector2i.ZERO), "render_width": int(cached_map.get("render_width", cached_map.get("width", 0))), "render_height": int(cached_map.get("render_height", cached_map.get("height", 0))), "header_offset": int(cached_map.get("header_offset", -1)), "layout_offset": int(cached_map.get("layout_offset", -1)), "objects": cached_map.get("objects", []), "warps": cached_map.get("warps", []), "connections": cached_map.get("connections", []), "animated_background_tiles": cached_map.get("animated_background_tiles", []), "animated_foreground_tiles": cached_map.get("animated_foreground_tiles", []), "map_cells": cached_map.get("map_cells", PackedInt32Array()), "music_id": int(cached_map.get("music_id", 0)), "map_type": int(cached_map.get("map_type", 0)), "animation_phase": 0}

func create_map_cache_worker() -> OpenMMOContent:
	var worker: OpenMMOContent = OpenMMOContent.new()
	worker.manifest = manifest.duplicate(true)
	worker.rom_data = rom_data
	worker.rom_sha1 = rom_sha1
	worker.rom_header = rom_header.duplicate(true)
	worker.source_profile = source_profile.duplicate(true)
	return worker

func build_detached_map_cache(map_id: String) -> void:
	detached_map_cache_result = _get_or_build_map_cache(map_id)

func install_detached_map_cache(map_id: String, cached_map: Dictionary) -> void:
	if not map_cache.has(map_id) and bool(cached_map.get("ok", false)):
		map_cache[map_id] = cached_map

func has_prepared_map(map_id: String) -> bool:
	var cached_value: Variant = map_cache.get(map_id, {})
	return cached_value is Dictionary and bool((cached_value as Dictionary).get("ok", false))

func prepare_server_map(map_id: String, server_map: Dictionary, server_maps: Dictionary, include_composite_texture: bool = true) -> Dictionary:
	var cached_map: Dictionary = map_cache.get(map_id, {})
	if cached_map.is_empty():
		cached_map = _build_server_map_cache(map_id, server_map, server_maps)
		if bool(cached_map.get("ok", false)):
			map_cache[map_id] = cached_map
	if not bool(cached_map.get("ok", false)):
		return cached_map
	var world_texture: Texture2D = cached_map.get("world_texture") as Texture2D
	var background_texture: Texture2D = cached_map.get("world_background_texture") as Texture2D
	var foreground_texture: Texture2D = cached_map.get("world_foreground_texture") as Texture2D
	if background_texture == null or foreground_texture == null:
		background_texture = ImageTexture.create_from_image(cached_map.get("base_background_image") as Image)
		foreground_texture = ImageTexture.create_from_image(cached_map.get("base_foreground_image") as Image)
		cached_map["world_background_texture"] = background_texture
		cached_map["world_foreground_texture"] = foreground_texture
	if include_composite_texture and world_texture == null:
		world_texture = background_texture
		cached_map["world_texture"] = world_texture
	return {"ok": true, "texture": world_texture if world_texture != null else background_texture, "background_texture": background_texture, "foreground_texture": foreground_texture, "world_texture": world_texture, "width": int(cached_map.get("width", 0)), "height": int(cached_map.get("height", 0)), "render_origin": cached_map.get("render_origin", Vector2i.ZERO), "render_width": int(cached_map.get("render_width", cached_map.get("width", 0))), "render_height": int(cached_map.get("render_height", cached_map.get("height", 0))), "header_offset": -1, "layout_offset": -1, "objects": [], "warps": [], "connections": cached_map.get("connections", []), "animated_background_tiles": cached_map.get("animated_background_tiles", []), "animated_foreground_tiles": cached_map.get("animated_foreground_tiles", []), "map_cells": cached_map.get("map_cells", PackedInt32Array()), "music_id": int(cached_map.get("music_id", 0)), "map_type": int(cached_map.get("map_type", 0)), "animation_phase": 0}

func prepare_connected_world(root_map_id: String, max_maps: int = 96, preload_depth: int = 1, server_maps: Dictionary = {}, max_depth: int = -1) -> Dictionary:
	if root_map_id.is_empty() or max_maps <= 0 or preload_depth < 0:
		return {"ok": false, "error": "invalid connected-world root"}
	var regions: Array = []
	var placed: Dictionary = {}
	var queued: Dictionary = {root_map_id: true}
	var pending: Array = [{"map_id": root_map_id, "origin": Vector2i.ZERO, "depth": 0}]
	while not pending.is_empty() and regions.size() < max_maps:
		var pending_value: Variant = pending.pop_front()
		if not pending_value is Dictionary:
			continue
		var pending_map: Dictionary = pending_value
		var map_id: String = str(pending_map.get("map_id", ""))
		if map_id.is_empty() or placed.has(map_id):
			continue
		var topology: Dictionary = _connected_world_topology(map_id, server_maps)
		if not bool(topology.get("ok", false)):
			continue
		var origin: Vector2i = pending_map.get("origin", Vector2i.ZERO)
		var depth: int = int(pending_map.get("depth", 0))
		var width: int = int(topology.get("width", 0))
		var height: int = int(topology.get("height", 0))
		if width <= 0 or height <= 0:
			continue
		var server_map: Dictionary = _server_map_for_local_map(map_id, server_maps)
		var prepared: Dictionary = {}
		if depth <= preload_depth or _is_server_custom_map(server_map):
			prepared = prepare_server_map(map_id, server_map, server_maps, false) if _is_server_custom_map(server_map) else prepare_map(map_id, false)
		if map_id == root_map_id and not bool(prepared.get("ok", false)):
			return prepared
		var region: Dictionary = {"map_id": map_id, "origin": origin, "width": width, "height": height, "render_origin": origin + prepared.get("render_origin", Vector2i.ZERO), "render_width": int(prepared.get("render_width", width)), "render_height": int(prepared.get("render_height", height)), "background_texture": prepared.get("background_texture"), "foreground_texture": prepared.get("foreground_texture"), "objects": prepared.get("objects", []), "warps": prepared.get("warps", []), "connections": topology.get("connections", []), "animated_background_tiles": prepared.get("animated_background_tiles", []), "animated_foreground_tiles": prepared.get("animated_foreground_tiles", []), "music_id": int(topology.get("music_id", 0)), "map_type": int(topology.get("map_type", 0)), "depth": depth, "ready": bool(prepared.get("ok", false))}
		regions.append(region)
		placed[map_id] = origin
		if max_depth >= 0 and depth >= max_depth:
			continue
		for connection_value in topology.get("connections", []):
			if not connection_value is Dictionary:
				continue
			var connection: Dictionary = connection_value
			var direction: int = int(connection.get("direction", 0))
			if direction < CONNECTION_SOUTH or direction > CONNECTION_EAST:
				continue
			var target_map_id: String = str(connection.get("map_id", ""))
			if target_map_id.is_empty() or placed.has(target_map_id) or queued.has(target_map_id):
				continue
			var target_topology: Dictionary = _connected_world_topology(target_map_id, server_maps)
			if not bool(target_topology.get("ok", false)):
				continue
			var target_width: int = int(target_topology.get("width", 0))
			var target_height: int = int(target_topology.get("height", 0))
			var target_origin: Vector2i = _connected_map_origin(origin, width, height, target_width, target_height, direction, int(connection.get("offset", 0)))
			queued[target_map_id] = true
			pending.append({"map_id": target_map_id, "origin": target_origin, "depth": depth + 1})
	if regions.is_empty():
		return {"ok": false, "error": "connected-world root map is not renderable"}
	var corner_regions: Array = _build_corner_filler_regions(regions, root_map_id)
	for corner_value in corner_regions:
		if not corner_value is Dictionary:
			continue
		var corner_region: Dictionary = corner_value
		regions.append(corner_region)
		placed[str(corner_region.get("map_id", ""))] = corner_region.get("origin", Vector2i.ZERO)
	return {"ok": true, "root_map_id": root_map_id, "regions": regions, "map_origins": placed}

func _build_corner_filler_regions(source_regions: Array, root_map_id: String) -> Array:
	var placed_regions: Array = []
	for region_value in source_regions:
		if not region_value is Dictionary:
			continue
		var region: Dictionary = region_value
		if bool(region.get("corner_filler", false)):
			continue
		if int(region.get("map_type", -1)) == MAP_TYPE_INSIDE or int(region.get("map_type", -1)) == MAP_TYPE_SECRET_BASE:
			continue
		if str(region.get("map_id", "")).is_empty():
			continue
		if int(region.get("width", 0)) <= 0 or int(region.get("height", 0)) <= 0:
			continue
		placed_regions.append(region)
	var gaps: Array = []
	var gap_keys: Dictionary = {}
	var edge_gap_donors: Dictionary = {}
	for center_value in placed_regions:
		var center: Dictionary = center_value
		var center_rect: Rect2i = _corner_region_rect(center)
		var top_regions: Array = _corner_touching_regions(center_rect, placed_regions, CONNECTION_NORTH)
		var bottom_regions: Array = _corner_touching_regions(center_rect, placed_regions, CONNECTION_SOUTH)
		var left_regions: Array = _corner_touching_regions(center_rect, placed_regions, CONNECTION_WEST)
		var right_regions: Array = _corner_touching_regions(center_rect, placed_regions, CONNECTION_EAST)
		for top_value in top_regions:
			var top: Dictionary = top_value
			var top_rect: Rect2i = _corner_region_rect(top)
			for side_value in left_regions:
				var side: Dictionary = side_value
				var side_rect: Rect2i = _corner_region_rect(side)
				_add_corner_gap(gaps, gap_keys, Rect2i(Vector2i(side_rect.position.x, top_rect.position.y), Vector2i(mini(center_rect.position.x, top_rect.position.x) - side_rect.position.x, mini(center_rect.position.y, side_rect.position.y) - top_rect.position.y)), placed_regions)
			for side_value in right_regions:
				var side: Dictionary = side_value
				var side_rect: Rect2i = _corner_region_rect(side)
				_add_corner_gap(gaps, gap_keys, Rect2i(Vector2i(maxi(center_rect.end.x, top_rect.end.x), top_rect.position.y), Vector2i(side_rect.end.x - maxi(center_rect.end.x, top_rect.end.x), mini(center_rect.position.y, side_rect.position.y) - top_rect.position.y)), placed_regions)
		for bottom_value in bottom_regions:
			var bottom: Dictionary = bottom_value
			var bottom_rect: Rect2i = _corner_region_rect(bottom)
			for side_value in left_regions:
				var side: Dictionary = side_value
				var side_rect: Rect2i = _corner_region_rect(side)
				_add_corner_gap(gaps, gap_keys, Rect2i(Vector2i(side_rect.position.x, maxi(center_rect.end.y, bottom_rect.end.y)), Vector2i(mini(center_rect.position.x, bottom_rect.position.x) - side_rect.position.x, bottom_rect.end.y - maxi(center_rect.end.y, side_rect.end.y))), placed_regions)
			for side_value in right_regions:
				var side: Dictionary = side_value
				var side_rect: Rect2i = _corner_region_rect(side)
				_add_corner_gap(gaps, gap_keys, Rect2i(Vector2i(maxi(center_rect.end.x, bottom_rect.end.x), maxi(center_rect.end.y, side_rect.end.y)), Vector2i(side_rect.end.x - maxi(center_rect.end.x, bottom_rect.end.x), bottom_rect.end.y - maxi(center_rect.end.y, side_rect.end.y))), placed_regions)
		for left_value in left_regions:
			var left_neighbor: Dictionary = left_value
			var left_neighbor_rect: Rect2i = _corner_region_rect(left_neighbor)
			for right_value in right_regions:
				var right_neighbor: Dictionary = right_value
				var right_neighbor_rect: Rect2i = _corner_region_rect(right_neighbor)
				var horizontal_gap_x: int = right_neighbor_rect.position.x - left_neighbor_rect.end.x
				var upper_gap_y: int = maxi(left_neighbor_rect.position.y, right_neighbor_rect.position.y)
				_add_corner_gap(gaps, gap_keys, Rect2i(Vector2i(left_neighbor_rect.end.x, upper_gap_y), Vector2i(horizontal_gap_x, center_rect.position.y - upper_gap_y)), placed_regions)
				var lower_gap_y: int = center_rect.end.y
				_add_corner_gap(gaps, gap_keys, Rect2i(Vector2i(left_neighbor_rect.end.x, lower_gap_y), Vector2i(horizontal_gap_x, mini(left_neighbor_rect.end.y, right_neighbor_rect.end.y) - lower_gap_y)), placed_regions)
		for top_value in top_regions:
			var top_neighbor: Dictionary = top_value
			var top_neighbor_rect: Rect2i = _corner_region_rect(top_neighbor)
			for bottom_value in bottom_regions:
				var bottom_neighbor: Dictionary = bottom_value
				var bottom_neighbor_rect: Rect2i = _corner_region_rect(bottom_neighbor)
				var vertical_gap_y: int = bottom_neighbor_rect.position.y - top_neighbor_rect.end.y
				var left_gap_x: int = maxi(top_neighbor_rect.position.x, bottom_neighbor_rect.position.x)
				_add_corner_gap(gaps, gap_keys, Rect2i(Vector2i(left_gap_x, top_neighbor_rect.end.y), Vector2i(center_rect.position.x - left_gap_x, vertical_gap_y)), placed_regions)
				_add_corner_gap(gaps, gap_keys, Rect2i(Vector2i(center_rect.end.x, top_neighbor_rect.end.y), Vector2i(mini(top_neighbor_rect.end.x, bottom_neighbor_rect.end.x) - center_rect.end.x, vertical_gap_y)), placed_regions)
	_add_edge_corner_gaps(gaps, gap_keys, edge_gap_donors, placed_regions)
	var filler_regions: Array = []
	var filler_index: int = 0
	for gap_value in gaps:
		if not gap_value is Rect2i:
			continue
		var gap: Rect2i = gap_value
		var links: Array = _corner_adjacent_links(gap, placed_regions)
		if links.is_empty():
			continue
		var gap_key: String = "%d:%d:%d:%d" % [gap.position.x, gap.position.y, gap.end.x, gap.end.y]
		var donor_link: Dictionary = {}
		var preferred_donor_id: String = str(edge_gap_donors.get(gap_key, ""))
		if not preferred_donor_id.is_empty():
			for link_value in links:
				var link: Dictionary = link_value
				var link_region: Dictionary = link.get("region", {})
				if str(link_region.get("map_id", "")) == preferred_donor_id:
					donor_link = link
					break
		if donor_link.is_empty():
			donor_link = links[0]
			for link_value in links:
				var link: Dictionary = link_value
				if int(link.get("overlap", 0)) > int(donor_link.get("overlap", 0)):
					donor_link = link
		var donor: Dictionary = donor_link.get("region", {})
		var filler_id: String = "corner-filler:%s:%d:%d:%d:%d" % [root_map_id, gap.position.x, gap.position.y, gap.end.x, gap.end.y]
		var filler: Dictionary = _create_corner_filler_region(filler_id, gap, donor, filler_index)
		if filler.is_empty():
			continue
		filler_regions.append(filler)
		filler_index += 1
	return filler_regions

func _add_edge_corner_gaps(gaps: Array, gap_keys: Dictionary, edge_gap_donors: Dictionary, regions: Array) -> void:
	for first_index in range(regions.size()):
		var first: Dictionary = regions[first_index]
		var first_rect: Rect2i = _corner_region_rect(first)
		for second_index in range(first_index + 1, regions.size()):
			var second: Dictionary = regions[second_index]
			var second_rect: Rect2i = _corner_region_rect(second)
			if first_rect.end.x == second_rect.position.x or second_rect.end.x == first_rect.position.x:
				var left_rect: Rect2i = first_rect
				var right_rect: Rect2i = second_rect
				var left_region: Dictionary = first
				var right_region: Dictionary = second
				if second_rect.end.x == first_rect.position.x:
					left_rect = second_rect
					right_rect = first_rect
					left_region = second
					right_region = first
				if _corner_y_overlap(left_rect, right_rect) > 0:
					if left_rect.position.y > right_rect.position.y:
						_add_edge_corner_gap(gaps, gap_keys, edge_gap_donors, Rect2i(Vector2i(left_rect.position.x, right_rect.position.y), Vector2i(left_rect.size.x, left_rect.position.y - right_rect.position.y)), regions, right_region)
					elif right_rect.position.y > left_rect.position.y:
						_add_edge_corner_gap(gaps, gap_keys, edge_gap_donors, Rect2i(Vector2i(right_rect.position.x, left_rect.position.y), Vector2i(right_rect.size.x, right_rect.position.y - left_rect.position.y)), regions, left_region)
					if left_rect.end.y < right_rect.end.y:
						_add_edge_corner_gap(gaps, gap_keys, edge_gap_donors, Rect2i(Vector2i(left_rect.position.x, left_rect.end.y), Vector2i(left_rect.size.x, right_rect.end.y - left_rect.end.y)), regions, right_region)
					elif right_rect.end.y < left_rect.end.y:
						_add_edge_corner_gap(gaps, gap_keys, edge_gap_donors, Rect2i(Vector2i(right_rect.position.x, right_rect.end.y), Vector2i(right_rect.size.x, left_rect.end.y - right_rect.end.y)), regions, left_region)
			if first_rect.end.y == second_rect.position.y or second_rect.end.y == first_rect.position.y:
				var top_rect: Rect2i = first_rect
				var bottom_rect: Rect2i = second_rect
				var top_region: Dictionary = first
				var bottom_region: Dictionary = second
				if second_rect.end.y == first_rect.position.y:
					top_rect = second_rect
					bottom_rect = first_rect
					top_region = second
					bottom_region = first
				if _corner_x_overlap(top_rect, bottom_rect) > 0:
					if top_rect.position.x < bottom_rect.position.x:
						_add_edge_corner_gap(gaps, gap_keys, edge_gap_donors, Rect2i(Vector2i(top_rect.position.x, bottom_rect.position.y), Vector2i(bottom_rect.position.x - top_rect.position.x, bottom_rect.size.y)), regions, top_region)
					elif bottom_rect.position.x < top_rect.position.x:
						_add_edge_corner_gap(gaps, gap_keys, edge_gap_donors, Rect2i(Vector2i(bottom_rect.position.x, top_rect.position.y), Vector2i(top_rect.position.x - bottom_rect.position.x, top_rect.size.y)), regions, bottom_region)
					if top_rect.end.x > bottom_rect.end.x:
						_add_edge_corner_gap(gaps, gap_keys, edge_gap_donors, Rect2i(Vector2i(bottom_rect.end.x, bottom_rect.position.y), Vector2i(top_rect.end.x - bottom_rect.end.x, bottom_rect.size.y)), regions, top_region)
					elif bottom_rect.end.x > top_rect.end.x:
						_add_edge_corner_gap(gaps, gap_keys, edge_gap_donors, Rect2i(Vector2i(top_rect.end.x, top_rect.position.y), Vector2i(bottom_rect.end.x - top_rect.end.x, top_rect.size.y)), regions, bottom_region)

func _add_edge_corner_gap(gaps: Array, gap_keys: Dictionary, edge_gap_donors: Dictionary, gap: Rect2i, regions: Array, donor: Dictionary) -> void:
	if gap.size.x <= 0 or gap.size.y <= 0 or gap.size.x > MAX_CORNER_FILLER_SIZE or gap.size.y > MAX_CORNER_FILLER_SIZE:
		return
	var fragments: Array = [gap]
	for region_value in regions:
		if not region_value is Dictionary:
			continue
		var occupied: Rect2i = _corner_region_rect(region_value)
		var next_fragments: Array = []
		for fragment_value in fragments:
			var fragment: Rect2i = fragment_value
			if not _corner_rect_intersects(fragment, occupied):
				next_fragments.append(fragment)
				continue
			var intersection_left: int = maxi(fragment.position.x, occupied.position.x)
			var intersection_top: int = maxi(fragment.position.y, occupied.position.y)
			var intersection_right: int = mini(fragment.end.x, occupied.end.x)
			var intersection_bottom: int = mini(fragment.end.y, occupied.end.y)
			if intersection_top > fragment.position.y:
				next_fragments.append(Rect2i(fragment.position, Vector2i(fragment.size.x, intersection_top - fragment.position.y)))
			if intersection_bottom < fragment.end.y:
				next_fragments.append(Rect2i(Vector2i(fragment.position.x, intersection_bottom), Vector2i(fragment.size.x, fragment.end.y - intersection_bottom)))
			if intersection_left > fragment.position.x:
				next_fragments.append(Rect2i(Vector2i(fragment.position.x, intersection_top), Vector2i(intersection_left - fragment.position.x, intersection_bottom - intersection_top)))
			if intersection_right < fragment.end.x:
				next_fragments.append(Rect2i(Vector2i(intersection_right, intersection_top), Vector2i(fragment.end.x - intersection_right, intersection_bottom - intersection_top)))
		fragments = next_fragments
		if fragments.is_empty():
			return
	for fragment_value in fragments:
		if fragment_value is Rect2i:
			var fragment: Rect2i = fragment_value
			var key: String = "%d:%d:%d:%d" % [fragment.position.x, fragment.position.y, fragment.end.x, fragment.end.y]
			var existed: bool = gap_keys.has(key)
			_add_corner_gap(gaps, gap_keys, fragment, regions)
			if not existed and gap_keys.has(key):
				edge_gap_donors[key] = str(donor.get("map_id", ""))

func _corner_region_rect(region: Dictionary) -> Rect2i:
	var origin: Vector2i = region.get("origin", Vector2i.ZERO)
	return Rect2i(origin, Vector2i(int(region.get("width", 0)), int(region.get("height", 0))))

func _corner_touching_regions(center: Rect2i, regions: Array, direction: int) -> Array:
	var result: Array = []
	for region_value in regions:
		if not region_value is Dictionary:
			continue
		var region: Dictionary = region_value
		var candidate: Rect2i = _corner_region_rect(region)
		var overlap: int = 0
		match direction:
			CONNECTION_NORTH, CONNECTION_SOUTH:
				overlap = _corner_x_overlap(center, candidate)
			CONNECTION_WEST, CONNECTION_EAST:
				overlap = _corner_y_overlap(center, candidate)
		if overlap <= 0:
			continue
		var touches: bool = false
		match direction:
			CONNECTION_NORTH:
				touches = candidate.end.y == center.position.y
			CONNECTION_SOUTH:
				touches = candidate.position.y == center.end.y
			CONNECTION_WEST:
				touches = candidate.end.x == center.position.x
			CONNECTION_EAST:
				touches = candidate.position.x == center.end.x
		if touches:
			result.append(region)
	return result

func _corner_x_overlap(first: Rect2i, second: Rect2i) -> int:
	return maxi(0, mini(first.end.x, second.end.x) - maxi(first.position.x, second.position.x))

func _corner_y_overlap(first: Rect2i, second: Rect2i) -> int:
	return maxi(0, mini(first.end.y, second.end.y) - maxi(first.position.y, second.position.y))

func _corner_rect_intersects(first: Rect2i, second: Rect2i) -> bool:
	return _corner_x_overlap(first, second) > 0 and _corner_y_overlap(first, second) > 0

func _add_corner_gap(gaps: Array, gap_keys: Dictionary, gap: Rect2i, regions: Array) -> void:
	if gap.size.x <= 0 or gap.size.y <= 0 or gap.size.x > MAX_CORNER_FILLER_SIZE or gap.size.y > MAX_CORNER_FILLER_SIZE:
		return
	for region_value in regions:
		if not region_value is Dictionary:
			continue
		if _corner_rect_intersects(gap, _corner_region_rect(region_value)):
			return
	if _corner_adjacent_links(gap, regions).is_empty():
		return
	var key: String = "%d:%d:%d:%d" % [gap.position.x, gap.position.y, gap.end.x, gap.end.y]
	if gap_keys.has(key):
		return
	gap_keys[key] = true
	gaps.append(gap)

func _corner_adjacent_links(gap: Rect2i, regions: Array) -> Array:
	var result: Array = []
	for region_value in regions:
		if not region_value is Dictionary:
			continue
		var region: Dictionary = region_value
		var host: Rect2i = _corner_region_rect(region)
		if host.end.y == gap.position.y:
			var overlap: int = _corner_x_overlap(host, gap)
			if overlap > 0:
				result.append({"region": region, "direction": CONNECTION_SOUTH, "offset": gap.position.x - host.position.x, "overlap": overlap})
		elif host.position.y == gap.end.y:
			var overlap: int = _corner_x_overlap(host, gap)
			if overlap > 0:
				result.append({"region": region, "direction": CONNECTION_NORTH, "offset": gap.position.x - host.position.x, "overlap": overlap})
		elif host.end.x == gap.position.x:
			var overlap: int = _corner_y_overlap(host, gap)
			if overlap > 0:
				result.append({"region": region, "direction": CONNECTION_EAST, "offset": gap.position.y - host.position.y, "overlap": overlap})
		elif host.position.x == gap.end.x:
			var overlap: int = _corner_y_overlap(host, gap)
			if overlap > 0:
				result.append({"region": region, "direction": CONNECTION_WEST, "offset": gap.position.y - host.position.y, "overlap": overlap})
	return result

func _create_corner_filler_region(filler_id: String, gap: Rect2i, donor: Dictionary, filler_index: int) -> Dictionary:
	var donor_id: String = str(donor.get("map_id", ""))
	var donor_cache: Dictionary = _get_or_build_map_cache(donor_id)
	if not bool(donor_cache.get("ok", false)):
		return {}
	var border_tiles: PackedInt32Array = donor_cache.get("border_tiles", PackedInt32Array())
	var border_width: int = int(donor_cache.get("border_width", 0))
	var border_height: int = int(donor_cache.get("border_height", 0))
	if border_width <= 0 or border_height <= 0 or border_tiles.size() < border_width * border_height:
		return {}
	var width: int = gap.size.x
	var height: int = gap.size.y
	var background_image: Image = Image.create(width * 16, height * 16, false, Image.FORMAT_RGBA8)
	background_image.fill(Color.BLACK)
	var foreground_image: Image = Image.create(width * 16, height * 16, false, Image.FORMAT_RGBA8)
	foreground_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var animated_background_tiles: Array = []
	var animated_foreground_tiles: Array = []
	var primary: Dictionary = donor_cache.get("primary", {})
	var secondary: Dictionary = donor_cache.get("secondary", {})
	var primary_metatile_count: int = _format_int("primary_metatile_count", PRIMARY_METATILE_COUNT)
	var metatile_id_mask: int = _format_int("map_grid_metatile_id_mask", MAPGRID_METATILE_ID_MASK)
	for map_y in range(height):
		for map_x in range(width):
			var border_index: int = (map_y % border_height) * border_width + (map_x % border_width)
			var metatile_id: int = int(border_tiles[border_index]) & metatile_id_mask
			if metatile_id == _format_int("map_grid_undefined", MAPGRID_UNDEFINED):
				continue
			var tileset: Dictionary = primary
			var metatile_index: int = metatile_id
			if metatile_id >= primary_metatile_count:
				tileset = secondary
				metatile_index = metatile_id - primary_metatile_count
			_draw_map_metatile_layers(background_image, foreground_image, map_x * 16, map_y * 16, tileset, metatile_index, primary, secondary, animated_background_tiles, animated_foreground_tiles)
	var background_texture: ImageTexture = ImageTexture.create_from_image(background_image)
	var foreground_texture: ImageTexture = ImageTexture.create_from_image(foreground_image)
	var filler_cache: Dictionary = {"ok": true, "base_image": background_image, "base_background_image": background_image, "base_foreground_image": foreground_image, "primary": primary, "secondary": secondary, "primary_tiles": donor_cache.get("primary_tiles", PackedByteArray()), "primary_animation_enabled": bool(donor_cache.get("primary_animation_enabled", false)), "animated_tiles": [], "animated_background_tiles": animated_background_tiles, "animated_foreground_tiles": animated_foreground_tiles, "animated_primary_tiles": PackedByteArray(), "animated_tile_phase": -1, "animated_tile_textures": {}, "map_cells": PackedInt32Array(), "objects": [], "warps": [], "connections": [], "textures": {}, "images": {}, "background_textures": {}, "foreground_textures": {}, "width": width, "height": height, "header_offset": -1, "layout_offset": -1, "border_offset": -1, "border_width": border_width, "border_height": border_height, "border_tiles": border_tiles, "map_group": -1, "map_index": filler_index, "music_id": 0, "map_type": int(donor_cache.get("map_type", 0))}
	map_cache[filler_id] = filler_cache
	return {"map_id": filler_id, "origin": gap.position, "width": width, "height": height, "background_texture": background_texture, "foreground_texture": foreground_texture, "objects": [], "warps": [], "connections": [], "animated_background_tiles": animated_background_tiles, "animated_foreground_tiles": animated_foreground_tiles, "music_id": 0, "map_type": int(donor_cache.get("map_type", 0)), "ready": true, "corner_filler": true}

func _is_server_custom_map(server_map: Dictionary) -> bool:
	var custom_value: Variant = server_map.get("custom_map_gzip", PackedByteArray())
	return custom_value is PackedByteArray and not (custom_value as PackedByteArray).is_empty()

func _connected_world_topology(map_id: String, server_maps: Dictionary) -> Dictionary:
	var server_map: Dictionary = _server_map_for_local_map(map_id, server_maps)
	if not server_map.is_empty():
		var width: int = int(server_map.get("width", 0))
		var height: int = int(server_map.get("height", 0))
		if width > 0 and height > 0:
			var local_topology: Dictionary = _get_or_build_map_topology(map_id) if not _is_server_custom_map(server_map) else {}
			return {"ok": true, "map_id": map_id, "width": width, "height": height, "header_offset": int(local_topology.get("header_offset", -1)), "music_id": int(local_topology.get("music_id", 0)), "map_type": int(server_map.get("map_type", local_topology.get("map_type", 0))), "connections": _server_connections(server_map, server_maps)}
	return _get_or_build_map_topology(map_id)

func _server_connections(server_map: Dictionary, server_maps: Dictionary) -> Array:
	var connections: Array = []
	for connection_value in server_map.get("connections", []):
		if not connection_value is Dictionary:
			continue
		var connection: Dictionary = connection_value
		var target_map_id: String = _client_map_id_for_server_location(int(connection.get("bank_id", -1)), int(connection.get("map_id", -1)), server_maps)
		if target_map_id.is_empty():
			continue
		var direction: int = int(connection.get("direction", 0))
		if direction < CONNECTION_SOUTH or direction > CONNECTION_EAST:
			continue
		connections.append({"direction": direction, "offset": int(connection.get("offset", 0)), "map_id": target_map_id})
	return connections

func _client_map_id_for_server_location(bank_id: int, map_index: int, server_maps: Dictionary) -> String:
	for value in server_maps.values():
		if not value is Dictionary:
			continue
		var candidate: Dictionary = value
		if int(candidate.get("bank_id", -1)) != bank_id or int(candidate.get("map_id", -1)) != map_index:
			continue
		var candidate_map_id: String = str(candidate.get("local_map_id", ""))
		if not candidate_map_id.is_empty():
			return candidate_map_id
	return map_id_for_location(bank_id, map_index)

func _build_server_map_cache(map_id: String, server_map: Dictionary, server_maps: Dictionary) -> Dictionary:
	var width: int = int(server_map.get("width", 0))
	var height: int = int(server_map.get("height", 0))
	if width <= 0 or height <= 0 or width > 512 or height > 512:
		return {"ok": false, "error": "OpenMMO custom map dimensions are invalid"}
	var custom_value: Variant = server_map.get("custom_map_gzip", PackedByteArray())
	if not custom_value is PackedByteArray:
		return {"ok": false, "error": "OpenMMO custom map data is invalid"}
	var expected_bytes: int = width * height * 2
	var map_bytes: PackedByteArray = _gzip_decompress(custom_value as PackedByteArray, expected_bytes)
	if map_bytes.size() != expected_bytes:
		return {"ok": false, "error": "OpenMMO custom map data could not be decompressed"}
	var donor_cache: Dictionary = _server_map_donor_cache(server_map, server_maps)
	if not bool(donor_cache.get("ok", false)):
		return {"ok": false, "error": "OpenMMO custom map has no local tileset donor"}
	var primary: Dictionary = donor_cache.get("primary", {})
	var secondary: Dictionary = donor_cache.get("secondary", {})
	if primary.is_empty() or secondary.is_empty():
		return {"ok": false, "error": "OpenMMO custom map donor tileset is unavailable"}
	var map_cells: PackedInt32Array = PackedInt32Array()
	for cell_index in range(width * height):
		map_cells.append(int(map_bytes[cell_index * 2]) | int(map_bytes[cell_index * 2 + 1]) << 8)
	var background_image: Image = Image.create(width * 16, height * 16, false, Image.FORMAT_RGBA8)
	background_image.fill(Color.BLACK)
	var foreground_image: Image = Image.create(width * 16, height * 16, false, Image.FORMAT_RGBA8)
	foreground_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var animated_background_tiles: Array = []
	var animated_foreground_tiles: Array = []
	var metatile_id_mask: int = _format_int("map_grid_metatile_id_mask", MAPGRID_METATILE_ID_MASK)
	var primary_metatile_count: int = _format_int("primary_metatile_count", PRIMARY_METATILE_COUNT)
	for map_y in range(height):
		for map_x in range(width):
			var metatile_id: int = int(map_cells[map_y * width + map_x]) & metatile_id_mask
			var tileset: Dictionary = primary if metatile_id < primary_metatile_count else secondary
			var metatile_index: int = metatile_id if metatile_id < primary_metatile_count else metatile_id - primary_metatile_count
			_draw_map_metatile_layers(background_image, foreground_image, map_x * 16, map_y * 16, tileset, metatile_index, primary, secondary, animated_background_tiles, animated_foreground_tiles)
	return {"ok": true, "base_image": background_image, "base_background_image": background_image, "base_foreground_image": foreground_image, "primary": primary, "secondary": secondary, "primary_tiles": primary.get("tiles", PackedByteArray()), "primary_animation_enabled": bool(primary.get("animation_enabled", false)), "animated_tiles": [], "animated_background_tiles": animated_background_tiles, "animated_foreground_tiles": animated_foreground_tiles, "map_cells": map_cells, "objects": [], "warps": [], "connections": _server_connections(server_map, server_maps), "textures": {}, "images": {}, "background_textures": {}, "foreground_textures": {}, "width": width, "height": height, "render_origin": Vector2i.ZERO, "render_width": width, "render_height": height, "header_offset": -1, "layout_offset": -1, "border_offset": -1, "border_width": int(server_map.get("border_width", 0)), "border_height": int(server_map.get("border_height", 0)), "map_group": int(server_map.get("bank_id", -1)), "map_index": int(server_map.get("map_id", -1)), "music_id": 0, "map_type": int(server_map.get("map_type", 0))}

func _gzip_decompress(data: PackedByteArray, expected_bytes: int) -> PackedByteArray:
	if data.is_empty() or expected_bytes <= 0:
		return PackedByteArray()
	var stream: StreamPeerGZIP = StreamPeerGZIP.new()
	if stream.start_decompression(false, expected_bytes) != OK:
		return PackedByteArray()
	if stream.put_data(data) != OK:
		return PackedByteArray()
	var available_bytes: int = stream.get_available_bytes()
	if available_bytes != expected_bytes:
		return PackedByteArray()
	var result: Array = stream.get_data(expected_bytes)
	if result.size() != 2 or int(result[0]) != OK or not result[1] is PackedByteArray:
		return PackedByteArray()
	return result[1] as PackedByteArray

func _server_map_donor_cache(server_map: Dictionary, server_maps: Dictionary) -> Dictionary:
	for connection_value in server_map.get("connections", []):
		if not connection_value is Dictionary:
			continue
		var connection: Dictionary = connection_value
		var donor_map_id: String = _client_map_id_for_server_location(int(connection.get("bank_id", -1)), int(connection.get("map_id", -1)), server_maps)
		if donor_map_id.is_empty() or donor_map_id.begins_with("server-map-"):
			continue
		var donor_cache: Dictionary = _get_or_build_map_cache(donor_map_id)
		if bool(donor_cache.get("ok", false)):
			return donor_cache
	return {}

func _server_map_for_local_map(map_id: String, server_maps: Dictionary) -> Dictionary:
	var direct: Variant = server_maps.get(map_id, {})
	if direct is Dictionary and not (direct as Dictionary).is_empty():
		return direct
	var local_map: Dictionary = map_data(map_id)
	var local_bank: int = int(local_map.get("map_group", -1))
	var local_wire_map: int = int(local_map.get("map_index", -1))
	for value in server_maps.values():
		if not value is Dictionary:
			continue
		var candidate: Dictionary = value
		if str(candidate.get("local_map_id", "")) == map_id:
			return candidate
		if int(candidate.get("bank_id", -1)) == local_bank and int(candidate.get("map_id", -1)) == local_wire_map:
			return candidate
	return {}

func animated_metatile_texture(map_id: String, metatile: Dictionary, animation_tick_value: int, foreground: bool) -> Texture2D:
	var cached_map: Dictionary = _get_or_build_map_cache(map_id)
	if not bool(cached_map.get("ok", false)) or not bool(cached_map.get("primary_animation_enabled", false)):
		return null
	var phase: int = posmod(animation_tick_value, ANIMATION_PHASE_COUNT)
	var tile_cache: Dictionary = cached_map.get("animated_tile_textures", {})
	var cached_phase: int = int(cached_map.get("animated_tile_phase", -1))
	if cached_phase != phase:
		tile_cache.clear()
		cached_map["animated_primary_tiles"] = _animated_primary_tiles(cached_map.get("primary_tiles", PackedByteArray()), phase, true)
		cached_map["animated_tile_phase"] = phase
	var cache_key: String = "%d:%d:%d:%d" % [phase, int(metatile.get("metatile_index", -1)), 1 if bool(metatile.get("secondary", false)) else 0, 1 if foreground else 0]
	var cached_texture: Texture2D = tile_cache.get(cache_key) as Texture2D
	if cached_texture != null:
		return cached_texture
	var image: Image = _render_animated_metatile(cached_map, metatile, foreground)
	if image == null:
		return null
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	tile_cache[cache_key] = texture
	cached_map["animated_tile_textures"] = tile_cache
	map_cache[map_id] = cached_map
	return texture

func door_animation_frame(map_id: String, x: int, y: int, frame: int) -> Dictionary:
	if frame <= 0:
		return {"ok": false}
	var cached_map: Dictionary = _get_or_build_map_cache(map_id)
	var width: int = int(cached_map.get("width", 0))
	var height: int = int(cached_map.get("height", 0))
	var map_cells: PackedInt32Array = cached_map.get("map_cells", PackedInt32Array())
	if not bool(cached_map.get("ok", false)) or x < 0 or y < 0 or x >= width or y >= height or y * width + x >= map_cells.size():
		return {"ok": false}
	var metatile_id: int = int(map_cells[y * width + x]) & _format_int("map_grid_metatile_id_mask", MAPGRID_METATILE_ID_MASK)
	var cache_key: String = "%s:%d:%d" % [map_id, metatile_id, frame]
	if door_animation_texture_cache.has(cache_key):
		return door_animation_texture_cache[cache_key]
	var table_offset: int = _format_int("door_graphics_table_offset", -1)
	if str(source_profile.get("id", "")) == "pokemon-fire-red" and rom_sha1 == FIRE_RED_SHA1:
		table_offset = 0x35B5D8
	if table_offset < 0:
		return {"ok": false}
	var record: int = -1
	for index in range(33):
		var candidate: int = table_offset + index * 12
		if not _valid_range(candidate, 12) or _read_rom_pointer(candidate + 4) < 0:
			break
		if _read_u16(candidate) == metatile_id:
			record = candidate
			break
	if record < 0:
		return {"ok": false}
	var large: bool = int(rom_data[record + 3]) == 1
	var tiles_offset: int = _read_rom_pointer(record + 4)
	var palette_numbers_offset: int = _read_rom_pointer(record + 8)
	var frame_offsets: Array = [0, 256, 512] if large else [0, 128, 256]
	var frame_index: int = clampi(frame - 1, 0, frame_offsets.size() - 1)
	var tile_count: int = 8 if large else 4
	var image_height: int = 32 if large else 16
	var source_offset: int = tiles_offset + int(frame_offsets[frame_index])
	if source_offset < 0 or palette_numbers_offset < 0 or not _valid_range(source_offset, tile_count * 32) or not _valid_range(palette_numbers_offset, tile_count):
		return {"ok": false}
	var image: Image = Image.create(16, image_height, false, Image.FORMAT_RGBA8)
	var primary: Dictionary = cached_map.get("primary", {})
	var secondary: Dictionary = cached_map.get("secondary", {})
	for tile_index in range(tile_count):
		var tile_x: int = (tile_index % 4) & 1
		var tile_y: int = ((tile_index % 4) >> 1) + (2 if tile_index >= 4 else 0)
		var palette_bank: int = int(rom_data[palette_numbers_offset + tile_index])
		var palette_values: Array = primary.get("palettes", [])
		var primary_palette_count: int = _format_int("primary_palette_count", PRIMARY_PALETTE_COUNT)
		var secondary_palette_count: int = _format_int("secondary_palette_count", SECONDARY_PALETTE_COUNT)
		if palette_bank >= primary_palette_count:
			palette_values = secondary.get("palettes", [])
			palette_bank = clampi(palette_bank, primary_palette_count, primary_palette_count + secondary_palette_count - 1)
		if palette_bank * 16 + 15 >= palette_values.size():
			continue
		var tile_offset: int = source_offset + tile_index * 32
		for pixel_y in range(8):
			for pixel_x in range(8):
				var packed: int = int(rom_data[tile_offset + pixel_y * 4 + (pixel_x >> 1)])
				var color_index: int = packed & 0x0F if (pixel_x & 1) == 0 else packed >> 4
				image.set_pixel(tile_x * 8 + pixel_x, tile_y * 8 + pixel_y, palette_values[palette_bank * 16 + color_index])
	var result: Dictionary = {"ok": true, "texture": ImageTexture.create_from_image(image), "width": 16, "height": image_height, "offset_y": -16 if large else 0}
	door_animation_texture_cache[cache_key] = result
	return result

func _connected_map_origin(origin: Vector2i, width: int, height: int, target_width: int, target_height: int, direction: int, offset: int) -> Vector2i:
	match direction:
		CONNECTION_SOUTH:
			return Vector2i(origin.x + offset, origin.y + height)
		CONNECTION_NORTH:
			return Vector2i(origin.x + offset, origin.y - target_height)
		CONNECTION_WEST:
			return Vector2i(origin.x - target_width, origin.y + offset)
		CONNECTION_EAST:
			return Vector2i(origin.x + width, origin.y + offset)
	return origin

func has_animated_tiles(map_id: String) -> bool:
	var cached_map: Dictionary = _get_or_build_map_cache(map_id)
	return bool(cached_map.get("ok", false)) and (not (cached_map.get("animated_tiles", []) as Array).is_empty() or not (cached_map.get("animated_background_tiles", []) as Array).is_empty() or not (cached_map.get("animated_foreground_tiles", []) as Array).is_empty())

func _get_or_build_map_cache(map_id: String, map_value: Dictionary = {}, include_composite: bool = false) -> Dictionary:
	var cached_map: Dictionary = map_cache.get(map_id, {})
	if not cached_map.is_empty():
		var base_image: Image = cached_map.get("base_image") as Image
		if include_composite and base_image == null:
			cached_map = _build_map_composite_cache(cached_map)
			map_cache[map_id] = cached_map
		return cached_map
	var selected_map: Dictionary = map_value if not map_value.is_empty() else map_data(map_id)
	if selected_map.is_empty():
		return {"ok": false, "error": "unknown map"}
	var built_map: Dictionary = _build_map_cache(map_id, selected_map, include_composite)
	if bool(built_map.get("ok", false)):
		map_cache[map_id] = built_map
	return built_map

func _build_map_cache(map_id: String, map_value: Dictionary, include_composite: bool = false) -> Dictionary:
	var descriptor: Dictionary = _read_map_descriptor(map_value)
	if not bool(descriptor.get("ok", false)):
		return descriptor
	var header_offset: int = int(descriptor.get("header_offset", -1))
	var layout_offset: int = int(descriptor.get("layout_offset", -1))
	var width: int = int(descriptor.get("width", 0))
	var height: int = int(descriptor.get("height", 0))
	var expected_width: int = int(map_value.get("width", 0))
	var expected_height: int = int(map_value.get("height", 0))
	if expected_width > 0 and expected_height > 0 and (width != expected_width or height != expected_height):
		return {"ok": false, "error": "ROM map layout dimensions do not match the selected map"}
	var map_offset: int = int(descriptor.get("map_offset", -1))
	var primary_offset: int = int(descriptor.get("primary_offset", -1))
	var secondary_offset: int = int(descriptor.get("secondary_offset", -1))
	var map_bytes: int = width * height * 2
	if map_offset < 0 or not _valid_range(map_offset, map_bytes):
		return {"ok": false, "error": "could not read the ROM map cells"}
	var map_cells: PackedInt32Array = PackedInt32Array()
	var metatile_id_mask: int = _format_int("map_grid_metatile_id_mask", MAPGRID_METATILE_ID_MASK)
	var undefined_metatile: int = _format_int("map_grid_undefined", MAPGRID_UNDEFINED)
	var primary_metatile_count: int = _format_int("primary_metatile_count", PRIMARY_METATILE_COUNT)
	var max_secondary_metatile: int = -1
	for cell_index in range(width * height):
		var map_word: int = _read_u16(map_offset + cell_index * 2)
		map_cells.append(map_word)
		var metatile_id: int = map_word & metatile_id_mask
		if metatile_id != undefined_metatile and metatile_id >= primary_metatile_count:
			max_secondary_metatile = maxi(max_secondary_metatile, metatile_id - primary_metatile_count)
	var primary: Dictionary = _read_tileset(primary_offset, _format_int("primary_tile_count", PRIMARY_TILE_COUNT), primary_metatile_count, _format_int("primary_palette_count", PRIMARY_PALETTE_COUNT), "primary")
	var secondary: Dictionary = _read_tileset(secondary_offset, 0, maxi(max_secondary_metatile + 1, 1), _format_int("secondary_rom_palette_count", SECONDARY_ROM_PALETTE_COUNT), "secondary")
	if primary.is_empty() or secondary.is_empty():
		return {"ok": false, "error": "could not read the ROM map tilesets"}
	primary["is_secondary"] = false
	secondary["is_secondary"] = true
	primary["animation_enabled"] = _tileset_animation_enabled(primary)
	secondary["animation_enabled"] = false
	var connections: Array = _read_map_connections(header_offset)
	var border_offset: int = int(descriptor.get("border_offset", -1))
	var border_width: int = int(descriptor.get("border_width", 0))
	var border_height: int = int(descriptor.get("border_height", 0))
	var border_tiles: PackedInt32Array = PackedInt32Array()
	var border_bytes: int = border_width * border_height * 2
	if border_width > 0 and border_height > 0 and border_offset >= 0 and _valid_range(border_offset, border_bytes):
		for border_index in range(border_width * border_height):
			border_tiles.append(_read_u16(border_offset + border_index * 2))
	var map_type: int = int(descriptor.get("map_type", 0))
	# Indoor/truck maps keep a black void; border metatile wrap bleeds trees/siding into camera space.
	var render_border: bool = connections.is_empty() and not border_tiles.is_empty() and map_type != MAP_TYPE_INSIDE and map_type != MAP_TYPE_SECRET_BASE
	var map_render_offset: int = _format_int("map_render_offset", 7) if render_border else 0
	var render_origin: Vector2i = Vector2i(-map_render_offset, -map_render_offset)
	var render_width: int = width + map_render_offset * 2 + (1 if render_border else 0)
	var render_height: int = height + map_render_offset * 2
	var image: Image
	if include_composite:
		image = Image.create(render_width * 16, render_height * 16, false, Image.FORMAT_RGBA8)
		image.fill(Color.BLACK)
	var background_image: Image = Image.create(render_width * 16, render_height * 16, false, Image.FORMAT_RGBA8)
	background_image.fill(Color.BLACK)
	var foreground_image: Image = Image.create(render_width * 16, render_height * 16, false, Image.FORMAT_RGBA8)
	foreground_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var animated_tiles: Array = []
	var animated_background_tiles: Array = []
	var animated_foreground_tiles: Array = []
	for render_y in range(render_height):
		for render_x in range(render_width):
			var map_x: int = render_x + render_origin.x
			var map_y: int = render_y + render_origin.y
			var map_word: int = _render_map_word(map_cells, width, height, map_x, map_y, border_tiles, border_width, border_height)
			var metatile_id: int = map_word & metatile_id_mask
			if metatile_id == undefined_metatile:
				continue
			var tileset: Dictionary = primary
			var metatile_index: int = metatile_id
			if metatile_id >= primary_metatile_count:
				tileset = secondary
				metatile_index = metatile_id - primary_metatile_count
			if include_composite:
				_draw_metatile(image, render_x * 16, render_y * 16, tileset, metatile_index, primary, secondary, animated_tiles)
			_draw_map_metatile_layers(background_image, foreground_image, render_x * 16, render_y * 16, tileset, metatile_index, primary, secondary, animated_background_tiles, animated_foreground_tiles)
	var objects: Array = _read_map_objects(header_offset, map_id)
	objects.append_array(_read_map_background_events(header_offset, map_id))
	return {"ok": true, "base_image": image, "base_background_image": background_image, "base_foreground_image": foreground_image, "primary": primary, "secondary": secondary, "primary_tiles": primary.get("tiles", PackedByteArray()), "primary_animation_enabled": bool(primary.get("animation_enabled", false)), "animated_tiles": animated_tiles, "animated_background_tiles": animated_background_tiles, "animated_foreground_tiles": animated_foreground_tiles, "map_cells": map_cells, "objects": objects, "warps": _read_map_warps(header_offset), "connections": connections, "textures": {}, "images": {}, "background_textures": {}, "foreground_textures": {}, "width": width, "height": height, "render_origin": render_origin, "render_width": render_width, "render_height": render_height, "header_offset": header_offset, "layout_offset": layout_offset, "border_offset": border_offset, "border_width": border_width, "border_height": border_height, "border_tiles": border_tiles, "map_group": int(map_value.get("map_group", -1)), "map_index": int(map_value.get("map_index", -1)), "music_id": int(map_value.get("music_id", 0)), "map_type": map_type}

func _render_map_word(map_cells: PackedInt32Array, width: int, height: int, map_x: int, map_y: int, border_tiles: PackedInt32Array, border_width: int, border_height: int) -> int:
	if map_x >= 0 and map_y >= 0 and map_x < width and map_y < height:
		return int(map_cells[map_y * width + map_x])
	if border_width <= 0 or border_height <= 0 or border_tiles.size() < border_width * border_height:
		return _format_int("map_grid_undefined", MAPGRID_UNDEFINED)
	var border_x: int = posmod(map_x + border_width * 8, border_width)
	var border_y: int = posmod(map_y + border_height * 8, border_height)
	return int(border_tiles[border_y * border_width + border_x])

func _build_map_composite_cache(cached_map: Dictionary) -> Dictionary:
	var width: int = int(cached_map.get("width", 0))
	var height: int = int(cached_map.get("height", 0))
	var render_origin: Vector2i = cached_map.get("render_origin", Vector2i.ZERO)
	var render_width: int = int(cached_map.get("render_width", width))
	var render_height: int = int(cached_map.get("render_height", height))
	var image: Image = Image.create(render_width * 16, render_height * 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	var map_cells: PackedInt32Array = cached_map.get("map_cells", PackedInt32Array())
	var primary: Dictionary = cached_map.get("primary", {})
	var secondary: Dictionary = cached_map.get("secondary", {})
	var animated_tiles: Array = []
	var metatile_id_mask: int = _format_int("map_grid_metatile_id_mask", MAPGRID_METATILE_ID_MASK)
	var primary_metatile_count: int = _format_int("primary_metatile_count", PRIMARY_METATILE_COUNT)
	var border_tiles: PackedInt32Array = cached_map.get("border_tiles", PackedInt32Array())
	var border_width: int = int(cached_map.get("border_width", 0))
	var border_height: int = int(cached_map.get("border_height", 0))
	var undefined_metatile: int = _format_int("map_grid_undefined", MAPGRID_UNDEFINED)
	for render_y in range(render_height):
		for render_x in range(render_width):
			var map_x: int = render_x + render_origin.x
			var map_y: int = render_y + render_origin.y
			var map_word: int = _render_map_word(map_cells, width, height, map_x, map_y, border_tiles, border_width, border_height)
			var metatile_id: int = map_word & metatile_id_mask
			if metatile_id == undefined_metatile:
				continue
			var tileset: Dictionary = primary
			var metatile_index: int = metatile_id
			if metatile_id >= primary_metatile_count:
				tileset = secondary
				metatile_index = metatile_id - primary_metatile_count
			_draw_metatile(image, render_x * 16, render_y * 16, tileset, metatile_index, primary, secondary, animated_tiles)
	cached_map["base_image"] = image
	cached_map["animated_tiles"] = animated_tiles
	return cached_map

func map_cell(map_id: String, x: int, y: int) -> Dictionary:
	var cached_map: Dictionary = _get_or_build_map_cache(map_id)
	if not bool(cached_map.get("ok", false)):
		return cached_map
	return _map_cell_from_cache(cached_map, x, y)

func _map_cell_from_cache(cached_map: Dictionary, x: int, y: int) -> Dictionary:
	var width: int = int(cached_map.get("width", 0))
	var height: int = int(cached_map.get("height", 0))
	if x < 0 or y < 0 or x >= width or y >= height:
		return {"ok": false, "undefined": true, "collision": 1, "elevation": 0, "behavior": 0}
	var map_cells: PackedInt32Array = cached_map.get("map_cells", PackedInt32Array())
	var map_word: int = int(map_cells[y * width + x])
	var metatile_id_mask: int = _format_int("map_grid_metatile_id_mask", MAPGRID_METATILE_ID_MASK)
	var collision_mask: int = _format_int("map_grid_collision_mask", MAPGRID_COLLISION_MASK)
	var collision_shift: int = _format_int("map_grid_collision_shift", MAPGRID_COLLISION_SHIFT)
	var elevation_mask: int = _format_int("map_grid_elevation_mask", MAPGRID_ELEVATION_MASK)
	var elevation_shift: int = _format_int("map_grid_elevation_shift", MAPGRID_ELEVATION_SHIFT)
	var undefined_metatile: int = _format_int("map_grid_undefined", MAPGRID_UNDEFINED)
	var metatile_id: int = map_word & metatile_id_mask
	var undefined: bool = metatile_id == undefined_metatile
	var attributes: int = _metatile_attributes(cached_map, metatile_id)
	return {"ok": true, "undefined": undefined, "map_word": map_word, "metatile_id": metatile_id, "collision": 1 if undefined else ((map_word & collision_mask) >> collision_shift), "elevation": (map_word & elevation_mask) >> elevation_shift, "behavior": attributes & _format_int("metatile_behavior_mask", METATILE_BEHAVIOR_MASK), "attributes": attributes, "layer_type": (attributes & _format_int("map_grid_layer_type_mask", MAPGRID_LAYER_TYPE_MASK)) >> _format_int("map_grid_layer_type_shift", MAPGRID_LAYER_TYPE_SHIFT)}

func _metatile_attributes(cached_map: Dictionary, metatile_id: int) -> int:
	if metatile_id == _format_int("map_grid_undefined", MAPGRID_UNDEFINED):
		return 0
	var primary_metatile_count: int = _format_int("primary_metatile_count", PRIMARY_METATILE_COUNT)
	var tileset: Dictionary = cached_map.get("primary", {}) if metatile_id < primary_metatile_count else cached_map.get("secondary", {})
	var attribute_index: int = metatile_id if metatile_id < primary_metatile_count else metatile_id - primary_metatile_count
	var attributes: PackedInt32Array = tileset.get("attributes", PackedInt32Array())
	return int(attributes[attribute_index]) if attribute_index >= 0 and attribute_index < attributes.size() else 0

func default_spawn(map_id: String) -> Dictionary:
	var cached_map: Dictionary = _get_or_build_map_cache(map_id)
	if not bool(cached_map.get("ok", false)):
		return cached_map
	var width: int = int(cached_map.get("width", 0))
	var height: int = int(cached_map.get("height", 0))
	var center: Vector2i = Vector2i(width / 2, height / 2)
	var objects: Array = cached_map.get("objects", [])
	var best_position: Vector2i = center
	var best_distance: int = 1 << 30
	for y in range(height):
		for x in range(width):
			var cell: Dictionary = _map_cell_from_cache(cached_map, x, y)
			if not _cell_can_stand(cell) or _position_occupied(objects, x, y):
				continue
			var distance: int = absi(x - center.x) + absi(y - center.y)
			if distance < best_distance:
				best_distance = distance
				best_position = Vector2i(x, y)
	var spawn_cell: Dictionary = _map_cell_from_cache(cached_map, best_position.x, best_position.y)
	var elevation: int = int(spawn_cell.get("elevation", 0))
	if elevation == 0 or elevation == 15:
		elevation = 3
	return {"ok": true, "map_id": map_id, "x": best_position.x, "y": best_position.y, "elevation": elevation}

func can_walk(map_id: String, from_x: int, from_y: int, to_x: int, to_y: int, elevation: int = 3, occupied: Variant = null) -> bool:
	var cached_map: Dictionary = _get_or_build_map_cache(map_id)
	if not bool(cached_map.get("ok", false)):
		return false
	var dx: int = to_x - from_x
	var dy: int = to_y - from_y
	var direction: int = _direction_from_delta(dx, dy)
	if direction == 0:
		return false
	var destination: Dictionary = _map_cell_from_cache(cached_map, to_x, to_y)
	if not bool(destination.get("ok", false)) or bool(destination.get("undefined", false)):
		return false
	var destination_warp: Dictionary = _warp_record_at(cached_map, to_x, to_y, elevation)
	if not _cell_can_stand_for_direction(destination, direction) and destination_warp.is_empty():
		return false
	var occupied_objects: Array = cached_map.get("objects", []) if occupied == null else occupied
	if _position_occupied(occupied_objects, to_x, to_y):
		return false
	if not _elevations_compatible(elevation, int(destination.get("elevation", 0))):
		return false
	if destination_warp.is_empty() and _directionally_blocked(int(destination.get("behavior", 0)), direction):
		return false
	var source: Dictionary = _map_cell_from_cache(cached_map, from_x, from_y)
	if _directionally_blocked(int(source.get("behavior", 0)), _opposite_direction(direction)):
		return false
	return true

func movement_result(map_id: String, x: int, y: int, direction: int, elevation: int = 3, occupied: Variant = null) -> Dictionary:
	var vector: Vector2i = _direction_vector(direction)
	if vector == Vector2i.ZERO:
		return {"ok": false, "error": "invalid movement direction"}
	var destination: Vector2i = Vector2i(x, y) + vector
	var map_value: Dictionary = map_data(map_id)
	if map_value.is_empty():
		var cached_map: Variant = map_cache.get(map_id, {})
		if cached_map is Dictionary and bool((cached_map as Dictionary).get("ok", false)):
			map_value = {"id": map_id, "width": int((cached_map as Dictionary).get("width", 0)), "height": int((cached_map as Dictionary).get("height", 0))}
	if map_value.is_empty():
		return {"ok": false, "error": "unknown map"}
	var width: int = int(map_value.get("width", 0))
	var height: int = int(map_value.get("height", 0))
	if destination.x < 0 or destination.y < 0 or destination.x >= width or destination.y >= height:
		return _movement_through_connection(map_id, x, y, direction, elevation, occupied)
	var source_cell: Dictionary = map_cell(map_id, x, y)
	var source_behavior: int = int(source_cell.get("behavior", 0))
	if _is_directional_stair_warp_behavior(source_behavior, direction):
		var stair_warp: Dictionary = warp_at(map_id, x, y, elevation)
		if bool(stair_warp.get("ok", false)):
			return {"ok": true, "map_id": map_id, "x": x, "y": y, "from_x": x, "from_y": y, "jump": false, "stair": true, "stair_behavior": source_behavior, "warp": stair_warp, "elevation": elevation}
	var destination_cell: Dictionary = map_cell(map_id, destination.x, destination.y)
	var destination_behavior: int = int(destination_cell.get("behavior", 0))
	var jump_direction: int = _jump_direction(destination_behavior)
	if jump_direction != 0:
		if jump_direction != direction:
			return {"ok": false, "error": "ledge"}
		var landing: Vector2i = destination + vector
		var landing_cell: Dictionary = map_cell(map_id, landing.x, landing.y) if landing.x >= 0 and landing.y >= 0 and landing.x < width and landing.y < height else {}
		if landing_cell.is_empty() or not can_walk(map_id, destination.x, destination.y, landing.x, landing.y, elevation, occupied):
			return {"ok": false, "error": "jump landing is blocked"}
		if _is_surfable_behavior(int(landing_cell.get("behavior", 0))):
			return {"ok": false, "error": "water"}
		return {"ok": true, "map_id": map_id, "x": landing.x, "y": landing.y, "from_x": x, "from_y": y, "intermediate_x": destination.x, "intermediate_y": destination.y, "jump": true, "elevation": int(_map_cell_from_cache(_get_or_build_map_cache(map_id), landing.x, landing.y).get("elevation", elevation))}
	if _is_surfable_behavior(destination_behavior):
		return {"ok": false, "error": "water"}
	if not can_walk(map_id, x, y, destination.x, destination.y, elevation, occupied):
		return {"ok": false, "error": "blocked"}
	var destination_warp: Dictionary = warp_at(map_id, destination.x, destination.y, elevation)
	var has_warp: bool = bool(destination_warp.get("ok", false))
	# Only outdoor-style animated doors play the open graphic. Indoor carpet /
	# non-anim warps may share metatile IDs with the door graphics table.
	var has_door_warp: bool = has_warp and _is_animated_door_behavior(destination_behavior) and bool(door_animation_frame(map_id, destination.x, destination.y, 1).get("ok", false))
	return {"ok": true, "map_id": map_id, "x": destination.x, "y": destination.y, "from_x": x, "from_y": y, "jump": false, "stair": false, "door": has_door_warp, "warp": destination_warp if has_warp else {}, "elevation": int(destination_cell.get("elevation", elevation))}

func interaction_at(map_id: String, x: int, y: int, direction: int, elevation: int = 3, visible_objects: Array = []) -> Dictionary:
	var vector: Vector2i = _direction_vector(direction)
	if vector == Vector2i.ZERO:
		return {"ok": false, "error": "invalid interaction direction"}
	var objects_to_check: Array = visible_objects
	if objects_to_check.is_empty():
		var cached_map: Dictionary = _get_or_build_map_cache(map_id)
		objects_to_check = cached_map.get("objects", [])
	var target: Vector2i = Vector2i(x, y) + vector
	for object_value in objects_to_check:
		if not object_value is Dictionary:
			continue
		var object: Dictionary = object_value
		if not bool(object.get("interactable", true)):
			continue
		if int(object.get("x", -1)) != target.x or int(object.get("y", -1)) != target.y:
			continue
		var object_elevation: int = int(object.get("elevation", elevation))
		if object_elevation != 0 and object_elevation != elevation:
			continue
		var background_kind: int = int(object.get("background_kind", 0))
		if background_kind > 0 and background_kind != direction:
			continue
		var pages: Array = object.get("dialogue_pages", [])
		var text: String = str(pages[0]) if not pages.is_empty() else "Someone is standing here."
		return {"ok": true, "kind": str(object.get("kind", "object")), "dialogue_id": str(object.get("dialogue_id", "")), "pages": pages, "text": text, "object": object}
	return {"ok": false, "error": "nothing to interact with"}

func _movement_through_connection(map_id: String, x: int, y: int, direction: int, elevation: int, occupied: Variant = null) -> Dictionary:
	var cached_map: Dictionary = _get_or_build_map_cache(map_id)
	if not bool(cached_map.get("ok", false)):
		return cached_map
	for connection_value in cached_map.get("connections", []):
		if not connection_value is Dictionary or int(connection_value.get("direction", 0)) != direction:
			continue
		var connection: Dictionary = connection_value
		var target_map_id: String = str(connection.get("map_id", ""))
		var target_map: Dictionary = map_data(target_map_id)
		var target_cache: Dictionary = _get_or_build_map_cache(target_map_id, target_map)
		if not bool(target_cache.get("ok", false)):
			continue
		var offset: int = int(connection.get("offset", 0))
		var target_x: int = 0
		var target_y: int = 0
		match direction:
			CONNECTION_EAST:
				target_x = 0
				target_y = y - offset
			CONNECTION_WEST:
				target_x = int(target_cache.get("width", 0)) - 1
				target_y = y - offset
			CONNECTION_SOUTH:
				target_x = x - offset
				target_y = 0
			CONNECTION_NORTH:
				target_x = x - offset
				target_y = int(target_cache.get("height", 0)) - 1
		var target_cell: Dictionary = _map_cell_from_cache(target_cache, target_x, target_y)
		var target_occupied: Array = target_cache.get("objects", []) if occupied == null else occupied
		if not _cell_can_stand(target_cell) or _position_occupied(target_occupied, target_x, target_y):
			continue
		var target_elevation: int = int(target_cell.get("elevation", elevation))
		if target_elevation == 0 or target_elevation == 15:
			target_elevation = elevation
		if not _elevations_compatible(elevation, target_elevation):
			continue
		return {"ok": true, "map_id": target_map_id, "x": target_x, "y": target_y, "from_x": x, "from_y": y, "transition": true, "jump": false, "elevation": target_elevation}
	return {"ok": false, "error": "map edge is blocked"}

func warp_at(map_id: String, x: int, y: int, elevation: int = 3) -> Dictionary:
	var cached_map: Dictionary = _get_or_build_map_cache(map_id)
	if not bool(cached_map.get("ok", false)):
		return cached_map
	for warp_value in cached_map.get("warps", []):
		if not warp_value is Dictionary:
			continue
		var warp: Dictionary = warp_value
		if int(warp.get("x", -1)) != x or int(warp.get("y", -1)) != y:
			continue
		var warp_elevation: int = int(warp.get("elevation", 0))
		if warp_elevation != 0 and warp_elevation != elevation:
			continue
		var target_map_id: String = str(warp.get("map_id", ""))
		var target_metadata: Dictionary = _map_warp_metadata(target_map_id)
		if not bool(target_metadata.get("ok", false)):
			return {"ok": false, "error": "warp destination is not available"}
		var destination_warp_id: int = int(warp.get("warp_id", -1))
		var destination_x: int = -1
		var destination_y: int = -1
		var destination_elevation: int = elevation
		var target_warps: Array = target_metadata.get("warps", [])
		if destination_warp_id >= 0 and destination_warp_id < target_warps.size() and target_warps[destination_warp_id] is Dictionary:
			var destination_warp: Dictionary = target_warps[destination_warp_id]
			destination_x = int(destination_warp.get("x", -1))
			destination_y = int(destination_warp.get("y", -1))
			destination_elevation = int(destination_warp.get("elevation", destination_elevation))
		if destination_x < 0 or destination_y < 0:
			var spawn: Dictionary = default_spawn(target_map_id)
			if not bool(spawn.get("ok", false)):
				return spawn
			destination_x = int(spawn.get("x", 0))
			destination_y = int(spawn.get("y", 0))
			destination_elevation = int(spawn.get("elevation", destination_elevation))
		return {"ok": true, "map_id": target_map_id, "x": destination_x, "y": destination_y, "elevation": destination_elevation, "warp": true}
	return {"ok": false, "error": "no warp at position"}

func _map_warp_metadata(map_id: String) -> Dictionary:
	var cached_value: Variant = map_cache.get(map_id, {})
	if cached_value is Dictionary and bool((cached_value as Dictionary).get("ok", false)):
		return {"ok": true, "warps": (cached_value as Dictionary).get("warps", [])}
	var map_value: Dictionary = map_data(map_id)
	if map_value.is_empty():
		return {"ok": false}
	var descriptor: Dictionary = _read_map_descriptor(map_value)
	if not bool(descriptor.get("ok", false)):
		return descriptor
	return {"ok": true, "warps": _read_map_warps(int(descriptor.get("header_offset", -1)))}

func _warp_record_at(cached_map: Dictionary, x: int, y: int, elevation: int = -1) -> Dictionary:
	for warp_value in cached_map.get("warps", []):
		if not warp_value is Dictionary:
			continue
		var warp: Dictionary = warp_value
		if int(warp.get("x", -1)) != x or int(warp.get("y", -1)) != y:
			continue
		var warp_elevation: int = int(warp.get("elevation", 0))
		if elevation >= 0 and warp_elevation != 0 and warp_elevation != elevation:
			continue
		return warp
	return {}

func _cell_can_stand(cell: Dictionary) -> bool:
	return bool(cell.get("ok", false)) and not bool(cell.get("undefined", false)) and int(cell.get("collision", 1)) == 0

func _cell_can_stand_for_direction(cell: Dictionary, direction: int) -> bool:
	if _cell_can_stand(cell):
		return true
	return (direction == CONNECTION_NORTH or direction == CONNECTION_SOUTH) and int(cell.get("behavior", 0)) == _format_int("rock_stairs_behavior", ROCK_STAIRS_BEHAVIOR)

func _position_occupied(objects: Array, x: int, y: int) -> bool:
	for object_value in objects:
		if object_value is Dictionary and bool(object_value.get("blocks_movement", true)) and int(object_value.get("x", -1)) == x and int(object_value.get("y", -1)) == y:
			return true
	return false

func _elevations_compatible(source_elevation: int, destination_elevation: int) -> bool:
	return source_elevation == 0 or destination_elevation == 0 or destination_elevation == 15 or source_elevation == destination_elevation

func _directionally_blocked(behavior: int, direction: int) -> bool:
	match direction:
		1:
			return behavior == 0x33 or behavior == 0x36 or behavior == 0x37
		2:
			return behavior == 0x32 or behavior == 0x34 or behavior == 0x35
		3:
			return behavior == 0x31 or behavior == 0x35 or behavior == 0x37
		4:
			return behavior == 0x30 or behavior == 0x34 or behavior == 0x36
	return false

func _jump_direction(behavior: int) -> int:
	match behavior:
		0x38:
			return CONNECTION_EAST
		0x39:
			return CONNECTION_WEST
		0x3A:
			return CONNECTION_NORTH
		0x3B:
			return CONNECTION_SOUTH
	return 0

func _is_surfable_behavior(behavior: int) -> bool:
	return behavior == 0x10 or behavior == 0x11 or behavior == 0x12 or behavior == 0x13 or behavior == 0x15 or behavior == 0x1A or behavior == 0x1B or behavior >= 0x50 and behavior <= 0x53

func _is_animated_door_behavior(behavior: int) -> bool:
	# pret: MB_ANIMATED_DOOR. Carpet / arrow / hole warps must not use door gfx.
	var format: Dictionary = source_profile.get("format", {})
	var door_behaviors: Array = format.get("animated_door_behaviors", [0x69])
	return door_behaviors.has(behavior)

func _is_stair_warp_behavior(behavior: int) -> bool:
	var format: Dictionary = source_profile.get("format", {})
	var stair_behaviors: Array = format.get("stair_warp_behaviors", [0x6C, 0x6D, 0x6E, 0x6F])
	return stair_behaviors.has(behavior)

func _is_directional_stair_warp_behavior(behavior: int, direction: int) -> bool:
	if direction == CONNECTION_WEST:
		return behavior == 0x6D or behavior == 0x6F
	if direction == CONNECTION_EAST:
		return behavior == 0x6C or behavior == 0x6E
	return false

func _direction_from_delta(dx: int, dy: int) -> int:
	if dx == 0 and dy == 1:
		return CONNECTION_SOUTH
	if dx == 0 and dy == -1:
		return CONNECTION_NORTH
	if dx == -1 and dy == 0:
		return CONNECTION_WEST
	if dx == 1 and dy == 0:
		return CONNECTION_EAST
	return 0

func _opposite_direction(direction: int) -> int:
	match direction:
		CONNECTION_SOUTH:
			return CONNECTION_NORTH
		CONNECTION_NORTH:
			return CONNECTION_SOUTH
		CONNECTION_WEST:
			return CONNECTION_EAST
		CONNECTION_EAST:
			return CONNECTION_WEST
	return 0

func _direction_vector(direction: int) -> Vector2i:
	match direction:
		CONNECTION_SOUTH:
			return Vector2i(0, 1)
		CONNECTION_NORTH:
			return Vector2i(0, -1)
		CONNECTION_WEST:
			return Vector2i(-1, 0)
		CONNECTION_EAST:
			return Vector2i(1, 0)
	return Vector2i.ZERO

func _render_cached_map(cached_map: Dictionary, animation_phase: int) -> Image:
	var image: Image = _render_cached_layer(cached_map, animation_phase, false)
	var foreground: Image = _render_cached_layer(cached_map, animation_phase, true)
	image.blend_rect(foreground, Rect2i(Vector2i.ZERO, foreground.get_size()), Vector2i.ZERO)
	return image

func _render_cached_layer(cached_map: Dictionary, animation_phase: int, foreground: bool) -> Image:
	var image: Image = (cached_map.get("base_foreground_image" if foreground else "base_background_image") as Image).duplicate()
	cached_map["animated_primary_tiles"] = _animated_primary_tiles(cached_map.get("primary_tiles", PackedByteArray()), animation_phase, bool(cached_map.get("primary_animation_enabled", false)))
	for metatile_value in cached_map.get("animated_foreground_tiles" if foreground else "animated_background_tiles", []):
		if not metatile_value is Dictionary:
			continue
		var metatile: Dictionary = metatile_value
		var replacement: Image = _render_animated_metatile(cached_map, metatile, foreground)
		if replacement != null:
			image.blend_rect(replacement, Rect2i(Vector2i.ZERO, replacement.get_size()), Vector2i(int(metatile.get("x", 0)), int(metatile.get("y", 0))))
	return image

func _render_animated_metatile(cached_map: Dictionary, metatile: Dictionary, foreground: bool) -> Image:
	var primary: Dictionary = cached_map.get("primary", {})
	var secondary: Dictionary = cached_map.get("secondary", {})
	var tileset: Dictionary = secondary if bool(metatile.get("secondary", false)) else primary
	var metatile_index: int = int(metatile.get("metatile_index", -1))
	if metatile_index < 0 or tileset.is_empty():
		return null
	var background_image: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	background_image.fill(Color.BLACK)
	var foreground_image: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	foreground_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var ignored_background: Array = []
	var ignored_foreground: Array = []
	_draw_metatile_layers(background_image, foreground_image, 0, 0, tileset, metatile_index, primary, secondary, ignored_background, ignored_foreground, cached_map.get("animated_primary_tiles", PackedByteArray()))
	return foreground_image if foreground else background_image

func _animated_primary_tiles(base_tiles: PackedByteArray, animation_phase: int, enabled: bool) -> PackedByteArray:
	var tiles: PackedByteArray = base_tiles.duplicate()
	if not enabled:
		return tiles
	var tile_bytes: int = _format_int("tile_bytes", TILE_BYTES)
	var water_offsets: Array = _animation_offsets("water")
	var sand_offsets: Array = _animation_offsets("sand")
	var flower_offsets: Array = _animation_offsets("flower")
	if not water_offsets.is_empty():
		_copy_rom_bytes(tiles, _format_int("water_tile_index", 416) * tile_bytes, int(water_offsets[animation_phase % water_offsets.size()]), _format_int("water_tile_count", 48) * tile_bytes)
	if not sand_offsets.is_empty():
		_copy_rom_bytes(tiles, _format_int("sand_tile_index", 464) * tile_bytes, int(sand_offsets[animation_phase % sand_offsets.size()]), _format_int("sand_tile_count", 18) * tile_bytes)
	if not flower_offsets.is_empty():
		_copy_rom_bytes(tiles, _format_int("flower_tile_index", 508) * tile_bytes, int(flower_offsets[animation_phase % flower_offsets.size()]), _format_int("flower_tile_count", 4) * tile_bytes)
	return tiles

func _copy_rom_bytes(destination: PackedByteArray, destination_offset: int, source_offset: int, length: int) -> void:
	if destination_offset < 0 or destination_offset + length > destination.size() or not _valid_range(source_offset, length):
		return
	for index in range(length):
		destination[destination_offset + index] = rom_data[source_offset + index]

func _read_map_objects(header_offset: int, map_id: String) -> Array:
	var objects: Array = []
	var events_offset: int = _read_rom_pointer(header_offset + 4)
	var events_header_size: int = _format_int("map_events_header_size", MAP_EVENTS_HEADER_SIZE)
	var object_event_size: int = _format_int("map_object_event_size", MAP_OBJECT_EVENT_SIZE)
	if events_offset < 0 or not _valid_range(events_offset, events_header_size):
		return objects
	var object_count: int = int(rom_data[events_offset])
	var objects_offset: int = _read_rom_pointer(events_offset + 4)
	if object_count <= 0 or objects_offset < 0 or not _valid_range(objects_offset, object_count * object_event_size):
		return objects
	for object_index in range(object_count):
		var offset: int = objects_offset + object_index * object_event_size
		var kind: int = int(rom_data[offset + 2])
		if kind != 0:
			continue
		var graphics_id: int = int(rom_data[offset + 1])
		var movement_type: int = int(rom_data[offset + 9])
		var default_facing: int = _initial_object_facing(movement_type)
		var sprite: Dictionary = render_object_sprite(graphics_id, 0)
		if not bool(sprite.get("ok", false)):
			continue
		var local_id: int = int(rom_data[offset])
		var script_offset: int = _read_rom_pointer(offset + 0x10)
		var dialogue: Dictionary = _read_dialogue_for_script(script_offset)
		if not dialogue.is_empty():
			dialogue["id"] = "%s:%d" % [map_id, local_id]
			_register_dialogue(map_id, local_id, script_offset, dialogue)
		var object_spec: Dictionary = _object_sprite_specs().get(int(sprite.get("resolved_graphics_id", graphics_id)), {})
		var inanimate_object: bool = bool(object_spec.get("inanimate", false))
		objects.append({"kind": "object", "local_id": local_id, "graphics_id": graphics_id, "resolved_graphics_id": int(sprite.get("resolved_graphics_id", graphics_id)), "hide_flag_id": _read_u16(offset + 0x14), "x": _read_s16(offset + 4), "y": _read_s16(offset + 6), "elevation": int(rom_data[offset + 8]), "movement_type": movement_type, "default_facing": default_facing, "facing": default_facing, "script_offset": script_offset, "dialogue_id": str(dialogue.get("id", "")), "dialogue_pages": dialogue.get("pages", []), "texture": sprite.get("texture"), "width": int(sprite.get("width", 0)), "height": int(sprite.get("height", 0)), "frame_count": int(sprite.get("frame_count", 1)), "render": true, "blocks_movement": true, "interactable": true, "inanimate": inanimate_object})
	return objects

func _initial_object_facing(movement_type: int) -> int:
	match movement_type:
		0x03, 0x07, 0x19, 0x1D, 0x21, 0x26, 0x2A, 0x2D, 0x31, 0x40, 0x45:
			return CONNECTION_NORTH
		0x04, 0x08, 0x1A, 0x1F, 0x23, 0x28, 0x2C, 0x30, 0x32, 0x41, 0x44:
			return CONNECTION_SOUTH
		0x05, 0x09, 0x1B, 0x20, 0x22, 0x25, 0x2B, 0x2F, 0x33, 0x42, 0x46:
			return CONNECTION_WEST
		0x06, 0x0A, 0x1C, 0x1E, 0x24, 0x27, 0x29, 0x2E, 0x34, 0x43, 0x47:
			return CONNECTION_EAST
	return CONNECTION_SOUTH

func _read_map_background_events(header_offset: int, map_id: String) -> Array:
	var events: Array = []
	var events_offset: int = _read_rom_pointer(header_offset + 4)
	if events_offset < 0 or not _valid_range(events_offset, MAP_EVENTS_HEADER_SIZE):
		return events
	var event_count: int = int(rom_data[events_offset + 3])
	var events_data_offset: int = _read_rom_pointer(events_offset + 16)
	if event_count <= 0 or events_data_offset < 0 or not _valid_range(events_data_offset, event_count * MAP_BG_EVENT_SIZE):
		return events
	for event_index in range(event_count):
		var offset: int = events_data_offset + event_index * MAP_BG_EVENT_SIZE
		var event_kind: int = int(rom_data[offset + 5])
		if event_kind < 0 or event_kind > 4:
			continue
		var script_offset: int = _read_rom_pointer(offset + 8)
		var dialogue: Dictionary = _read_dialogue_for_script(script_offset)
		if not dialogue.is_empty():
			dialogue["id"] = "%s:bg:%d" % [map_id, event_index]
			_register_dialogue(map_id, -event_index - 1, script_offset, dialogue)
		events.append({"kind": "sign", "background_kind": event_kind, "local_id": -event_index - 1, "x": int(_read_u16(offset)), "y": int(_read_u16(offset + 2)), "elevation": int(rom_data[offset + 4]), "script_offset": script_offset, "dialogue_id": str(dialogue.get("id", "")), "dialogue_pages": dialogue.get("pages", []), "render": false, "blocks_movement": false, "interactable": true})
	return events

func _register_dialogue(map_id: String, local_id: int, script_offset: int, dialogue: Dictionary) -> void:
	var records: Dictionary = string_catalog.get("records", {})
	if not records is Dictionary:
		records = {}
	var key: String = "%s:%d" % [map_id, local_id]
	records[key] = {"map_id": map_id, "local_id": local_id, "script_offset": script_offset, "text_offset": int(dialogue.get("text_offset", -1)), "raw": str(dialogue.get("raw", "")), "pages": dialogue.get("pages", [])}
	string_catalog["schema_version"] = 1
	string_catalog["content_id"] = content_id()
	string_catalog["catalog_id"] = string_catalog_id()
	string_catalog["language"] = "en"
	string_catalog["source"] = manifest.get("source", {})
	string_catalog["records"] = records
	OpenMMOStorage.write_strings(string_catalog_id(), string_catalog)

func _read_dialogue_for_script(script_offset: int) -> Dictionary:
	if script_offset < 0 or not _valid_range(script_offset, 1):
		return {}
	var walked: Dictionary = _walk_dialogue_for_script(script_offset)
	if not walked.is_empty() and not _dialogue_pages_are_garbage(walked.get("pages", [])):
		return walked
	var scanned: Dictionary = _scan_dialogue_for_script(script_offset)
	if not scanned.is_empty() and not _dialogue_pages_are_garbage(scanned.get("pages", [])):
		return scanned
	return walked if not walked.is_empty() else scanned

func _walk_dialogue_for_script(script_offset: int) -> Dictionary:
	var cursor: int = script_offset
	var limit: int = mini(rom_data.size(), script_offset + 512)
	var data_slot_zero: int = -1
	while cursor < limit:
		var opcode: int = int(rom_data[cursor])
		if opcode == 0x02 or opcode == 0x03:
			break
		var command_size: int = _script_command_size(opcode)
		if command_size <= 0:
			# Unknown opcode: stop walking so scored scan can recover nearby msgbox/loadword.
			break
		if cursor + command_size > limit:
			return {}
		if opcode == 0x0F and int(rom_data[cursor + 1]) == 0:
			var loadword_offset: int = _read_rom_pointer(cursor + 2)
			if loadword_offset >= 0:
				data_slot_zero = loadword_offset
		if opcode == 0x67:
			var message_offset: int = _read_rom_pointer(cursor + 1)
			if message_offset < 0:
				message_offset = data_slot_zero
			if message_offset < 0:
				return {}
			return _decode_rom_text(message_offset)
		if opcode == 0x0F and int(rom_data[cursor + 1]) == 0 and cursor + 8 <= limit:
			var standard_message_offset: int = _read_rom_pointer(cursor + 2)
			var standard_call: int = int(rom_data[cursor + 6])
			var standard_id: int = int(rom_data[cursor + 7])
			if standard_call == 0x09 and standard_id >= 2 and standard_id <= 6:
				var standard_dialogue: Dictionary = _decode_rom_text(standard_message_offset)
				if not standard_dialogue.is_empty():
					return standard_dialogue
		# loadword + following callstd (separate opcodes) — famechecker macros use this.
		if opcode == 0x0F and int(rom_data[cursor + 1]) == 0 and data_slot_zero >= 0 and cursor + 6 <= limit:
			var trailed_call: int = int(rom_data[cursor + 6]) if cursor + 6 < limit else -1
			var trailed_id: int = int(rom_data[cursor + 7]) if cursor + 7 < limit else -1
			if trailed_call == 0x09 and trailed_id >= 2 and trailed_id <= 6:
				var trailed: Dictionary = _decode_rom_text(data_slot_zero)
				if not trailed.is_empty():
					return trailed
		cursor += command_size
	return {}

func _script_command_size(opcode: int) -> int:
	# Subset of pret firered/pokeemerald script command sizes used by signs/NPCs.
	match opcode:
		0x00, 0x01, 0x02, 0x03, 0x0C, 0x0D, 0x27, 0x30, 0x32, 0x35, 0x5A, 0x66, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D:
			return 1
		0x08, 0x09, 0x0E, 0x2F, 0x31, 0x34, 0x36, 0x37, 0x38:
			return 2
		0x0A, 0x0B, 0x10, 0x25, 0x28, 0x29, 0x2A, 0x2B:
			return 3
		0x04, 0x05, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x26, 0x67:
			return 5
		0x06, 0x07, 0x0F:
			return 6
		0x4F:
			return 7
		0x50:
			return 9
	return 0

func _scan_dialogue_for_script(script_offset: int) -> Dictionary:
	# Fallback only: never trust the first raw 0x67/0x0F byte hit (pointers can embed those bytes).
	var limit: int = mini(rom_data.size(), script_offset + 512)
	var best: Dictionary = {}
	var best_score: int = -1
	for scan_offset in range(script_offset, limit):
		var scan_opcode: int = int(rom_data[scan_offset])
		var candidate_offset: int = -1
		if scan_opcode == 0x67 and scan_offset + 5 <= limit:
			candidate_offset = _read_rom_pointer(scan_offset + 1)
		elif scan_opcode == 0x0F and scan_offset + 8 <= limit and int(rom_data[scan_offset + 1]) == 0:
			var standard_call: int = int(rom_data[scan_offset + 6])
			var standard_id: int = int(rom_data[scan_offset + 7])
			if standard_call == 0x09 and standard_id >= 2 and standard_id <= 6:
				candidate_offset = _read_rom_pointer(scan_offset + 2)
		if candidate_offset < 0:
			continue
		var dialogue: Dictionary = _decode_rom_text(candidate_offset)
		if dialogue.is_empty() or _dialogue_pages_are_garbage(dialogue.get("pages", [])):
			continue
		var score: int = _dialogue_candidate_score(candidate_offset, dialogue)
		if score > best_score:
			best = dialogue
			best_score = score
	return best

func _decode_rom_text(text_offset: int) -> Dictionary:
	if not _valid_range(text_offset, 1):
		return {}
	var cursor: int = text_offset
	var raw: PackedByteArray = PackedByteArray()
	var pages: Array = []
	var current: String = ""
	var terminated: bool = false
	var unknown_glyphs: int = 0
	var glyph_count: int = 0
	while cursor < rom_data.size() and raw.size() < 4096:
		var value: int = int(rom_data[cursor])
		raw.append(value)
		cursor += 1
		match value:
			0xFF:
				terminated = true
				break
			0xFE:
				current += "\n"
			0xFB:
				pages.append(current)
				current = ""
			0xFA:
				# \l: scroll/wait — keep as newline (matches pret / OpenMMO-Client), not a page break.
				current += "\n"
			0xFD:
				if cursor >= rom_data.size():
					break
				var placeholder: int = int(rom_data[cursor])
				raw.append(placeholder)
				cursor += 1
				current += _placeholder_name(placeholder)
			0xF7:
				current += "{DYNAMIC}"
			0xF8, 0xF9:
				if cursor < rom_data.size():
					raw.append(rom_data[cursor])
					cursor += 1
				current += "{CONTROL}"
			0xFC:
				if cursor >= rom_data.size():
					break
				var control: int = int(rom_data[cursor])
				raw.append(control)
				cursor += 1
				var argument_count: int = _rom_text_control_argument_count(control)
				if argument_count < 0 or not _valid_range(cursor, argument_count):
					break
				for argument_index in range(argument_count):
					raw.append(rom_data[cursor + argument_index])
				cursor += argument_count
			_:
				var glyph: String = _decode_rom_character(value)
				current += glyph
				glyph_count += 1
				if glyph == "?":
					unknown_glyphs += 1
	if not terminated:
		return {}
	if not current.is_empty() or pages.is_empty():
		pages.append(current)
	while not pages.is_empty() and str(pages[pages.size() - 1]).is_empty():
		pages.pop_back()
	if pages.is_empty():
		return {}
	if glyph_count > 0 and float(unknown_glyphs) / float(glyph_count) >= 0.45:
		return {}
	return {"text_offset": text_offset, "raw": raw.hex_encode(), "pages": pages, "unknown_glyphs": unknown_glyphs, "glyph_count": glyph_count}

func _gba_text_file_offset(text_id: int) -> int:
	# OpenMMO textId: 0x08xxxxxx = GBA bus address; 0x10xxxxxx = Emerald file offset; else low 24 bits.
	var id_value: int = text_id & 0xFFFFFFFF
	if (id_value & 0xFF000000) == 0x08000000:
		return id_value - 0x08000000
	return id_value & 0x00FFFFFF

func dialogue_for_text_id(text_id: int) -> Dictionary:
	if text_id == 0:
		return {}
	var base_offset: int = _gba_text_file_offset(text_id)
	var candidates: Array = [base_offset]
	# OpenMMO server dialog enums are Rev0 file offsets. FireRed Rev1 shifts many
	# Pallet strings by +0x78 (see OakPokemonResearchLab 0x17D866 -> 0x17D8DE).
	if str(source_profile.get("id", "")) == "pokemon-fire-red" and rom_sha1 == FIRE_RED_REV1_SHA1:
		for delta_value in FIRE_RED_REV1_DIALOGUE_DELTAS:
			candidates.append(base_offset + int(delta_value))
	var best_dialogue: Dictionary = {}
	var best_score: int = -1
	for candidate_value in candidates:
		var candidate: int = int(candidate_value)
		if not _valid_range(candidate, 1):
			continue
		var dialogue: Dictionary = _decode_rom_text(candidate)
		if dialogue.is_empty() or _dialogue_pages_are_garbage(dialogue.get("pages", [])):
			continue
		var score: int = _dialogue_candidate_score(candidate, dialogue)
		# Strongly prefer true string starts (prev 0xFF). Mid-page (0xFB) stays weak so
		# Rev0 textIds on Rev1 ROMs do not keep truncated fragments like "t strong...".
		if score > best_score:
			best_dialogue = dialogue
			best_score = score
	if not best_dialogue.is_empty():
		return best_dialogue
	if _valid_range(base_offset, 1):
		return _dialogue_unavailable_stub(base_offset)
	return _dialogue_unavailable_stub(base_offset)

func _dialogue_unavailable_stub(text_offset: int) -> Dictionary:
	var region: String = str(source_profile.get("region", "this"))
	var game: String = str(source_profile.get("game", "ROM"))
	return {"text_offset": text_offset, "raw": "", "pages": ["(%s / %s dialogue unavailable.)" % [region, game]], "stub": true}

func _dialogue_candidate_score(text_offset: int, dialogue: Dictionary) -> int:
	var score: int = 1
	if text_offset > 0 and int(rom_data[text_offset - 1]) == 0xFF:
		score += 1000
	elif text_offset > 0 and int(rom_data[text_offset - 1]) == 0xFB:
		# Mid-page pointer — keep weaker than a real string start.
		score += 10
	var pages: Array = dialogue.get("pages", [])
	var joined: String = ""
	for page_value in pages:
		joined += str(page_value)
	score += mini(joined.length(), 80)
	score -= int(dialogue.get("unknown_glyphs", 0)) * 3
	return score

func _dialogue_pages_are_garbage(pages: Array) -> bool:
	if pages.is_empty():
		return true
	var joined: String = ""
	for page_value in pages:
		joined += str(page_value)
	if joined.strip_edges().is_empty():
		return true
	var question_marks: int = joined.count("?")
	if question_marks >= 8 and question_marks * 2 >= joined.length():
		return true
	if joined.count("{") >= 12:
		return true
	return false

func _rom_text_control_argument_count(control: int) -> int:
	# Match OpenMMO-Client gbaExtCtrlSkip / pret ext control sizes.
	match control:
		0x04:
			return 3
		0x06, 0x08, 0x11:
			return 1
		0x0B, 0x10:
			return 2
		0x07, 0x09, 0x0A, 0x15, 0x16, 0x17, 0x18:
			return 0
	return 1

func _decode_rom_character(value: int) -> String:
	if value == 0x00:
		return " "
	if value >= 0xA1 and value <= 0xAA:
		return char(48 + value - 0xA1)
	if value >= 0xBB and value <= 0xD4:
		return char(65 + value - 0xBB)
	if value >= 0xD5 and value <= 0xEE:
		return char(97 + value - 0xD5)
	match value:
		0x1B:
			return "Ac"
		0xAB:
			return "!"
		0xAC:
			return "?"
		0xAD:
			return "."
		0xAE:
			return "-"
		0xB0:
			return "..."
		0xB4:
			return "'"
		0xB6:
			return "\""
		0xB8:
			return ","
		0xBA:
			return "/"
		0xF0:
			return ":"
	# Keep out of {..} placeholder grammar used by world._resolve_dialogue_pages.
	return "?"

func _placeholder_name(value: int) -> String:
	return "{%02X}" % value

func _read_map_warps(header_offset: int) -> Array:
	var warps: Array = []
	var events_offset: int = _read_rom_pointer(header_offset + 4)
	var events_header_size: int = _format_int("map_events_header_size", MAP_EVENTS_HEADER_SIZE)
	var warp_event_size: int = _format_int("map_warp_event_size", MAP_WARP_EVENT_SIZE)
	if events_offset < 0 or not _valid_range(events_offset, events_header_size):
		return warps
	var warp_count: int = int(rom_data[events_offset + 1])
	var warps_offset: int = _read_rom_pointer(events_offset + 8)
	if warp_count <= 0 or warps_offset < 0 or not _valid_range(warps_offset, warp_count * warp_event_size):
		return warps
	for warp_index in range(warp_count):
		var offset: int = warps_offset + warp_index * warp_event_size
		var map_index: int = int(rom_data[offset + 6])
		var map_group: int = int(rom_data[offset + 7])
		warps.append({"warp_index": warp_index, "x": _read_s16(offset), "y": _read_s16(offset + 2), "elevation": int(rom_data[offset + 4]), "warp_id": int(rom_data[offset + 5]), "map_index": map_index, "map_group": map_group, "map_id": _map_id_for_location(map_group, map_index)})
	return warps

func _read_map_connections(header_offset: int) -> Array:
	var connections: Array = []
	var connections_offset: int = _read_rom_pointer(header_offset + 12)
	var connections_header_size: int = _format_int("map_connections_header_size", MAP_CONNECTIONS_HEADER_SIZE)
	var connection_size: int = _format_int("map_connection_size", MAP_CONNECTION_SIZE)
	if connections_offset < 0 or not _valid_range(connections_offset, connections_header_size):
		return connections
	var connection_count: int = _read_s32(connections_offset)
	var records_offset: int = _read_rom_pointer(connections_offset + 4)
	if connection_count <= 0 or records_offset < 0 or not _valid_range(records_offset, connection_count * connection_size):
		return connections
	for connection_index in range(connection_count):
		var offset: int = records_offset + connection_index * connection_size
		var map_group: int = int(rom_data[offset + 8])
		var map_index: int = int(rom_data[offset + 9])
		connections.append({"direction": int(rom_data[offset]), "offset": _read_s32(offset + 4), "map_group": map_group, "map_index": map_index, "map_id": _map_id_for_location(map_group, map_index)})
	return connections

func render_facing_object_sprite(graphics_id: int, direction: int, moving: bool = false, frame_step: int = 0) -> Dictionary:
	var object_sprites: Dictionary = _object_sprite_specs()
	var resolved_id: int = graphics_id
	if resolved_id < 0 or resolved_id >= 152 or not object_sprites.has(resolved_id):
		resolved_id = 16
	var spec: Dictionary = object_sprites.get(resolved_id, {})
	if bool(spec.get("inanimate", false)):
		return render_object_sprite(graphics_id, 0, false)
	var direction_name: String = "south"
	match direction:
		CONNECTION_NORTH:
			direction_name = "north"
		CONNECTION_WEST:
			direction_name = "west"
		CONNECTION_EAST:
			direction_name = "east"
	var format: Dictionary = source_profile.get("format", {})
	var facing_frames: Dictionary = format.get("object_facing_frames", {})
	var direction_spec: Dictionary = facing_frames.get(direction_name, {})
	var frame_index: int = int(direction_spec.get("idle", 0))
	var flip_h: bool = bool(direction_spec.get("flip_h", false))
	if moving:
		var walk_frames: Array = direction_spec.get("walk", [])
		if not walk_frames.is_empty():
			frame_index = int(walk_frames[posmod(frame_step, walk_frames.size())])
	return render_object_sprite(graphics_id, frame_index, flip_h)

func render_object_sprite(graphics_id: int, frame: int = 0, flip_h: bool = false) -> Dictionary:
	var resolved_graphics_id: int = graphics_id
	var object_sprites: Dictionary = _object_sprite_specs()
	if resolved_graphics_id < 0 or resolved_graphics_id >= 152 or not object_sprites.has(resolved_graphics_id):
		resolved_graphics_id = 16
	var spec: Dictionary = object_sprites.get(resolved_graphics_id, {})
	if spec.is_empty():
		return {"ok": false, "error": "FireRed object graphics are not available for this graphics ID"}
	var frame_count: int = int(spec.get("frame_count", 1))
	var logical_frame_index: int = posmod(frame, maxi(frame_count, 1))
	var frame_index: int = logical_frame_index
	var frame_sequence: Array = spec.get("frame_sequence", [])
	if not frame_sequence.is_empty():
		frame_index = int(frame_sequence[posmod(logical_frame_index, frame_sequence.size())])
	var cache_key: String = "%d:%d:%d" % [resolved_graphics_id, logical_frame_index, int(flip_h)]
	var cached_texture: Texture2D = sprite_cache.get(cache_key) as Texture2D
	if cached_texture != null:
		return {"ok": true, "texture": cached_texture, "width": int(spec.get("width", 0)), "height": int(spec.get("height", 0)), "frame_count": frame_count, "resolved_graphics_id": resolved_graphics_id}
	var width: int = int(spec.get("width", 0))
	var height: int = int(spec.get("height", 0))
	var frame_bytes: int = int(spec.get("frame_bytes", 0))
	var data_offset: int = int(spec.get("data_offset", -1)) + frame_index * frame_bytes
	var palette_offset: int = int(spec.get("palette_offset", -1))
	if width <= 0 or height <= 0 or frame_bytes <= 0 or width % 8 != 0 or height % 8 != 0 or not _valid_range(data_offset, frame_bytes) or not _valid_range(palette_offset, 32):
		return {"ok": false, "error": "FireRed object graphics data is outside the selected ROM"}
	var storage_width: int = int(spec.get("storage_width", width))
	var storage_height: int = int(spec.get("storage_height", height))
	if storage_width <= 0 or storage_height <= 0 or storage_width % 8 != 0 or storage_height % 8 != 0 or storage_width * storage_height / 2 != frame_bytes:
		storage_width = width
		storage_height = height
	var storage_image: Image = Image.create(storage_width, storage_height, false, Image.FORMAT_RGBA8)
	var tiles_wide: int = storage_width / 8
	var tile_bytes_per_tile: int = _format_int("tile_bytes", TILE_BYTES)
	for pixel_y in range(storage_height):
		for pixel_x in range(storage_width):
			var tile_index: int = (pixel_y >> 3) * tiles_wide + (pixel_x >> 3)
			var packed: int = int(rom_data[data_offset + tile_index * tile_bytes_per_tile + (pixel_y & 7) * 4 + ((pixel_x & 7) >> 1)])
			var color_index: int = packed & 0x0F if (pixel_x & 1) == 0 else (packed >> 4) & 0x0F
			var color: Color = _read_palette_color(palette_offset + color_index * 2)
			if color_index == 0:
				color = Color(color.r, color.g, color.b, 0.0)
			storage_image.set_pixel(pixel_x, pixel_y, color)
	var image: Image = storage_image
	if storage_width != width or storage_height != height:
		image = Image.create(width, height, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		# gbagfx -mwidth 2 -mheight 2: ROM is a vertical strip of 16x16 blocks; pack LTR into 32x16.
		var block: int = 16
		var blocks: int = int((storage_width * storage_height) / (block * block))
		var storage_blocks_wide: int = storage_width / block
		var display_blocks_wide: int = width / block
		for block_index in range(blocks):
			var src_bx: int = block_index % storage_blocks_wide
			var src_by: int = int(block_index / storage_blocks_wide)
			var dst_bx: int = block_index % display_blocks_wide
			var dst_by: int = int(block_index / display_blocks_wide)
			image.blit_rect(storage_image, Rect2i(src_bx * block, src_by * block, block, block), Vector2i(dst_bx * block, dst_by * block))
	if flip_h:
		image.flip_x()
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	sprite_cache[cache_key] = texture
	return {"ok": true, "texture": texture, "width": width, "height": height, "frame_count": frame_count, "resolved_graphics_id": resolved_graphics_id}

func _read_tileset(offset: int, tile_count: int, metatile_count: int, palette_count: int, cache_namespace: String) -> Dictionary:
	if offset < 0 or metatile_count <= 0 or not _valid_range(offset, 0x18):
		return {}
	var cache_key: String = "%s:%d:%d:%d:%d" % [cache_namespace, offset, tile_count, metatile_count, palette_count]
	var cached_value: Variant = tileset_cache.get(cache_key, {})
	if cached_value is Dictionary and not (cached_value as Dictionary).is_empty():
		return cached_value as Dictionary
	var tile_bytes_per_tile: int = _format_int("tile_bytes", TILE_BYTES)
	var tiles_per_metatile: int = _format_int("tiles_per_metatile", TILES_PER_METATILE)
	var primary_tile_count: int = _format_int("primary_tile_count", PRIMARY_TILE_COUNT)
	var tiles_offset: int = _read_rom_pointer(offset + 4)
	var palettes_offset: int = _read_rom_pointer(offset + 8)
	var metatiles_offset: int = _read_rom_pointer(offset + 12)
	if tiles_offset < 0 or palettes_offset < 0 or metatiles_offset < 0:
		return {}
	var metatile_words: PackedInt32Array = PackedInt32Array()
	var metatile_bytes: int = metatile_count * tiles_per_metatile * 2
	if not _valid_range(metatiles_offset, metatile_bytes):
		return {}
	for index in range(metatile_count * tiles_per_metatile):
		metatile_words.append(_read_u16(metatiles_offset + index * 2))
	var effective_tile_count: int = tile_count
	var tiles: PackedByteArray = PackedByteArray()
	if int(rom_data[offset]) != 0:
		var compressed_tiles: PackedByteArray = _read_lz77(tiles_offset)
		if compressed_tiles.is_empty():
			return {}
		if effective_tile_count <= 0:
			effective_tile_count = compressed_tiles.size() / tile_bytes_per_tile
		if compressed_tiles.size() < effective_tile_count * tile_bytes_per_tile:
			return {}
		if compressed_tiles.size() > effective_tile_count * tile_bytes_per_tile:
			tiles = compressed_tiles.slice(0, effective_tile_count * tile_bytes_per_tile)
		else:
			tiles = compressed_tiles
	else:
		if effective_tile_count <= 0:
			var max_tile_index: int = -1
			for tile_entry in metatile_words:
				var global_tile_index: int = int(tile_entry) & _format_int("map_grid_metatile_id_mask", MAPGRID_METATILE_ID_MASK)
				if global_tile_index >= primary_tile_count:
					max_tile_index = maxi(max_tile_index, global_tile_index - primary_tile_count)
			effective_tile_count = maxi(max_tile_index + 1, 1)
		var tile_bytes: int = effective_tile_count * tile_bytes_per_tile
		if not _valid_range(tiles_offset, tile_bytes):
			return {}
		tiles = rom_data.slice(tiles_offset, tiles_offset + tile_bytes)
	if tiles.size() < effective_tile_count * tile_bytes_per_tile:
		return {}
	var palettes: Array = []
	var palette_bytes: int = palette_count * 16 * 2
	if not _valid_range(palettes_offset, palette_bytes):
		return {}
	for palette_index in range(palette_count * 16):
		palettes.append(_read_palette_color(palettes_offset + palette_index * 2))
	var attributes: PackedInt32Array = PackedInt32Array()
	var attribute_pointer_offset: int = _format_int("metatile_attributes_pointer_offset", 20)
	var attribute_bytes: int = _format_int("metatile_attribute_bytes", 4)
	var attributes_offset: int = _read_rom_pointer(offset + attribute_pointer_offset)
	if attributes_offset < 0 or attribute_bytes <= 0 or not _valid_range(attributes_offset, metatile_count * attribute_bytes):
		return {}
	for attribute_index in range(metatile_count):
		if attribute_bytes == 2:
			attributes.append(_read_u16(attributes_offset + attribute_index * 2))
		else:
			attributes.append(_read_u32(attributes_offset + attribute_index * attribute_bytes))
	var result: Dictionary = {"tiles": tiles, "metatiles": metatile_words, "palettes": palettes, "attributes": attributes, "tile_count": effective_tile_count, "animation_callback": _read_rom_pointer(offset + 16)}
	tileset_cache[cache_key] = result
	return result

func _draw_metatile(image: Image, destination_x: int, destination_y: int, tileset: Dictionary, metatile_index: int, primary: Dictionary, secondary: Dictionary, animated_tiles: Array, primary_override: PackedByteArray = PackedByteArray()) -> void:
	if not primary_override.is_empty():
		_draw_metatile_uncached(image, destination_x, destination_y, tileset, metatile_index, primary, secondary, animated_tiles, primary_override)
		return
	var cache: Dictionary = tileset.get("_metatile_cache", {})
	var cache_key: String = str(metatile_index)
	var cached: Dictionary = cache.get(cache_key, {})
	if cached.is_empty():
		var cached_image: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		cached_image.fill(Color(0.0, 0.0, 0.0, 0.0))
		var cached_animated_tiles: Array = []
		_draw_metatile_uncached(cached_image, 0, 0, tileset, metatile_index, primary, secondary, cached_animated_tiles)
		cached = {"image": cached_image, "animated_tiles": cached_animated_tiles}
		cache[cache_key] = cached
		tileset["_metatile_cache"] = cache
	var cached_image_value: Image = cached.get("image") as Image
	if cached_image_value == null:
		return
	image.blend_rect(cached_image_value, Rect2i(0, 0, 16, 16), Vector2i(destination_x, destination_y))
	for tile_value in cached.get("animated_tiles", []):
		if tile_value is Dictionary:
			var tile: Dictionary = tile_value
			animated_tiles.append({"x": destination_x + int(tile.get("x", 0)), "y": destination_y + int(tile.get("y", 0)), "entry": int(tile.get("entry", 0)), "transparent_zero": bool(tile.get("transparent_zero", true))})

func _draw_metatile_uncached(image: Image, destination_x: int, destination_y: int, tileset: Dictionary, metatile_index: int, primary: Dictionary, secondary: Dictionary, animated_tiles: Array, primary_override: PackedByteArray = PackedByteArray()) -> void:
	var metatiles: PackedInt32Array = tileset.get("metatiles", PackedInt32Array())
	var tiles_per_metatile: int = _format_int("tiles_per_metatile", TILES_PER_METATILE)
	var base: int = metatile_index * tiles_per_metatile
	if metatile_index < 0 or base + tiles_per_metatile > metatiles.size():
		return
	var attributes: PackedInt32Array = tileset.get("attributes", PackedInt32Array())
	var layer_type: int = 0
	if metatile_index < attributes.size():
		layer_type = (int(attributes[metatile_index]) & _format_int("map_grid_layer_type_mask", MAPGRID_LAYER_TYPE_MASK)) >> _format_int("map_grid_layer_type_shift", MAPGRID_LAYER_TYPE_SHIFT)
	match layer_type:
		1:
			_draw_metatile_layer(image, destination_x, destination_y, metatiles, base, 0, primary, secondary, animated_tiles, primary_override, false)
			_draw_metatile_layer(image, destination_x, destination_y, metatiles, base, 4, primary, secondary, animated_tiles, primary_override, true)
		2:
			_draw_metatile_layer(image, destination_x, destination_y, metatiles, base, 0, primary, secondary, animated_tiles, primary_override, false)
			_draw_metatile_layer(image, destination_x, destination_y, metatiles, base, 4, primary, secondary, animated_tiles, primary_override, true)
		_:
			_draw_metatile_layer(image, destination_x, destination_y, metatiles, base, 0, primary, secondary, animated_tiles, primary_override, false)
			_draw_metatile_layer(image, destination_x, destination_y, metatiles, base, 4, primary, secondary, animated_tiles, primary_override, true)

func _draw_metatile_layers(background_image: Image, foreground_image: Image, destination_x: int, destination_y: int, tileset: Dictionary, metatile_index: int, primary: Dictionary, secondary: Dictionary, animated_background_tiles: Array = [], animated_foreground_tiles: Array = [], primary_override: PackedByteArray = PackedByteArray()) -> void:
	if not primary_override.is_empty():
		_draw_metatile_layers_uncached(background_image, foreground_image, destination_x, destination_y, tileset, metatile_index, primary, secondary, animated_background_tiles, animated_foreground_tiles, primary_override)
		return
	var cache: Dictionary = tileset.get("_layer_cache", {})
	var cache_key: String = str(metatile_index)
	var cached: Dictionary = cache.get(cache_key, {})
	if cached.is_empty():
		var cached_background: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		cached_background.fill(Color.BLACK)
		var cached_foreground: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		cached_foreground.fill(Color(0.0, 0.0, 0.0, 0.0))
		var cached_background_tiles: Array = []
		var cached_foreground_tiles: Array = []
		_draw_metatile_layers_uncached(cached_background, cached_foreground, 0, 0, tileset, metatile_index, primary, secondary, cached_background_tiles, cached_foreground_tiles)
		cached = {"background": cached_background, "foreground": cached_foreground, "background_tiles": cached_background_tiles, "foreground_tiles": cached_foreground_tiles}
		cache[cache_key] = cached
		tileset["_layer_cache"] = cache
	var cached_background_value: Image = cached.get("background") as Image
	var cached_foreground_value: Image = cached.get("foreground") as Image
	if cached_background_value == null or cached_foreground_value == null:
		return
	background_image.blend_rect(cached_background_value, Rect2i(0, 0, 16, 16), Vector2i(destination_x, destination_y))
	foreground_image.blend_rect(cached_foreground_value, Rect2i(0, 0, 16, 16), Vector2i(destination_x, destination_y))
	for tile_value in cached.get("background_tiles", []):
		if tile_value is Dictionary:
			var background_tile: Dictionary = tile_value
			animated_background_tiles.append({"x": destination_x + int(background_tile.get("x", 0)), "y": destination_y + int(background_tile.get("y", 0)), "entry": int(background_tile.get("entry", 0)), "transparent_zero": bool(background_tile.get("transparent_zero", true))})
	for tile_value in cached.get("foreground_tiles", []):
		if tile_value is Dictionary:
			var foreground_tile: Dictionary = tile_value
			animated_foreground_tiles.append({"x": destination_x + int(foreground_tile.get("x", 0)), "y": destination_y + int(foreground_tile.get("y", 0)), "entry": int(foreground_tile.get("entry", 0)), "transparent_zero": bool(foreground_tile.get("transparent_zero", true))})

func _draw_map_metatile_layers(background_image: Image, foreground_image: Image, destination_x: int, destination_y: int, tileset: Dictionary, metatile_index: int, primary: Dictionary, secondary: Dictionary, animated_background_metatiles: Array, animated_foreground_metatiles: Array) -> void:
	var background_tiles: Array = []
	var foreground_tiles: Array = []
	_draw_metatile_layers(background_image, foreground_image, destination_x, destination_y, tileset, metatile_index, primary, secondary, background_tiles, foreground_tiles)
	var descriptor: Dictionary = {"x": destination_x, "y": destination_y, "metatile_index": metatile_index, "secondary": bool(tileset.get("is_secondary", false))}
	if not background_tiles.is_empty():
		animated_background_metatiles.append(descriptor)
	if not foreground_tiles.is_empty():
		foreground_image.fill_rect(Rect2i(destination_x, destination_y, 16, 16), Color(0.0, 0.0, 0.0, 0.0))
		animated_foreground_metatiles.append(descriptor)

func _draw_metatile_layers_uncached(background_image: Image, foreground_image: Image, destination_x: int, destination_y: int, tileset: Dictionary, metatile_index: int, primary: Dictionary, secondary: Dictionary, animated_background_tiles: Array = [], animated_foreground_tiles: Array = [], primary_override: PackedByteArray = PackedByteArray()) -> void:
	var metatiles: PackedInt32Array = tileset.get("metatiles", PackedInt32Array())
	var tiles_per_metatile: int = _format_int("tiles_per_metatile", TILES_PER_METATILE)
	var base: int = metatile_index * tiles_per_metatile
	if metatile_index < 0 or base + tiles_per_metatile > metatiles.size():
		return
	var attributes: PackedInt32Array = tileset.get("attributes", PackedInt32Array())
	var layer_type: int = 0
	if metatile_index < attributes.size():
		layer_type = (int(attributes[metatile_index]) & _format_int("map_grid_layer_type_mask", MAPGRID_LAYER_TYPE_MASK)) >> _format_int("map_grid_layer_type_shift", MAPGRID_LAYER_TYPE_SHIFT)
	_draw_metatile_layer(background_image, destination_x, destination_y, metatiles, base, 0, primary, secondary, animated_background_tiles, primary_override, false)
	if layer_type == 1:
		_draw_metatile_layer(background_image, destination_x, destination_y, metatiles, base, 4, primary, secondary, animated_background_tiles, primary_override, true)
	else:
		_draw_metatile_layer(foreground_image, destination_x, destination_y, metatiles, base, 4, primary, secondary, animated_foreground_tiles, primary_override, true)

func _draw_metatile_layer(image: Image, destination_x: int, destination_y: int, metatiles: PackedInt32Array, base: int, start: int, primary: Dictionary, secondary: Dictionary, animated_tiles: Array, primary_override: PackedByteArray = PackedByteArray(), transparent_zero: bool = true) -> void:
	var tiles_per_metatile: int = _format_int("tiles_per_metatile", TILES_PER_METATILE)
	for local_index in range(4):
		var tile_index: int = start + local_index
		if tile_index >= tiles_per_metatile:
			continue
		_draw_tile(image, destination_x + (local_index & 1) * 8, destination_y + (local_index >> 1) * 8, int(metatiles[base + tile_index]), primary, secondary, animated_tiles, primary_override, transparent_zero)

func _draw_tile(image: Image, destination_x: int, destination_y: int, tile_entry: int, primary: Dictionary, secondary: Dictionary, animated_tiles: Array = [], primary_override: PackedByteArray = PackedByteArray(), transparent_zero: bool = true) -> void:
	var tile_bytes_per_tile: int = _format_int("tile_bytes", TILE_BYTES)
	var primary_tile_count: int = _format_int("primary_tile_count", PRIMARY_TILE_COUNT)
	var metatile_id_mask: int = _format_int("map_grid_metatile_id_mask", MAPGRID_METATILE_ID_MASK)
	var global_tile_index: int = tile_entry & metatile_id_mask
	var tileset: Dictionary = primary if global_tile_index < primary_tile_count else secondary
	var tile_index: int = global_tile_index if global_tile_index < primary_tile_count else global_tile_index - primary_tile_count
	var tile_count: int = int(tileset.get("tile_count", 0))
	if tile_index < 0 or tile_index >= tile_count:
		return
	var tile_bytes: PackedByteArray = primary_override if global_tile_index < primary_tile_count and primary_override.size() > 0 else tileset.get("tiles", PackedByteArray())
	var palette_bank: int = (tile_entry >> 12) & 0x0F
	var palette_values: Array = primary.get("palettes", [])
	var primary_palette_count: int = _format_int("primary_palette_count", PRIMARY_PALETTE_COUNT)
	var secondary_palette_count: int = _format_int("secondary_palette_count", SECONDARY_PALETTE_COUNT)
	if palette_bank < primary_palette_count:
		palette_bank = mini(palette_bank, primary_palette_count - 1)
	else:
		palette_values = secondary.get("palettes", [])
		palette_bank = clampi(palette_bank, primary_palette_count, primary_palette_count + secondary_palette_count - 1)
	var h_flip: bool = (tile_entry & 0x0400) != 0
	var v_flip: bool = (tile_entry & 0x0800) != 0
	var tile_offset: int = tile_index * tile_bytes_per_tile
	for pixel_y in range(8):
		var sample_y: int = 7 - pixel_y if v_flip else pixel_y
		for pixel_x in range(8):
			var sample_x: int = 7 - pixel_x if h_flip else pixel_x
			var packed: int = int(tile_bytes[tile_offset + sample_y * 4 + (sample_x >> 1)])
			var color_index: int = packed & 0x0F if (sample_x & 1) == 0 else packed >> 4
			if color_index == 0 and transparent_zero:
				continue
			var color: Color = palette_values[palette_bank * 16 + color_index]
			image.set_pixel(destination_x + pixel_x, destination_y + pixel_y, color)
	if animated_tiles != null and bool(primary.get("animation_enabled", false)) and _is_animated_tile(global_tile_index):
		animated_tiles.append({"x": destination_x, "y": destination_y, "entry": tile_entry, "transparent_zero": transparent_zero})

func _tileset_animation_enabled(tileset: Dictionary) -> bool:
	if bool(tileset.get("is_secondary", true)):
		return false
	if int(tileset.get("animation_callback", -1)) < 0:
		return false
	var animations: Dictionary = source_profile.get("animations", {})
	return not animations.is_empty()

func _is_animated_tile(tile_index: int) -> bool:
	var water_start: int = _format_int("water_tile_index", 416)
	var sand_start: int = _format_int("sand_tile_index", 464)
	var flower_start: int = _format_int("flower_tile_index", 508)
	return (tile_index >= water_start and tile_index < water_start + _format_int("water_tile_count", 48)) or (tile_index >= sand_start and tile_index < sand_start + _format_int("sand_tile_count", 18)) or (tile_index >= flower_start and tile_index < flower_start + _format_int("flower_tile_count", 4))

func _read_s16(offset: int) -> int:
	var value: int = _read_u16(offset)
	return value - 0x10000 if value >= 0x8000 else value

func _read_palette_color(offset: int) -> Color:
	var value: int = _read_u16(offset)
	return Color(float(value & 0x1F) / 31.0, float((value >> 5) & 0x1F) / 31.0, float((value >> 10) & 0x1F) / 31.0, 1.0)

func _read_lz77(offset: int) -> PackedByteArray:
	if offset < 0 or not _valid_range(offset, 4) or int(rom_data[offset]) != 0x10:
		return PackedByteArray()
	var output_size: int = int(rom_data[offset + 1]) | (int(rom_data[offset + 2]) << 8) | (int(rom_data[offset + 3]) << 16)
	var output: PackedByteArray = PackedByteArray()
	output.resize(output_size)
	var input_offset: int = offset + 4
	var output_offset: int = 0
	while output_offset < output_size:
		if not _valid_range(input_offset, 1):
			return PackedByteArray()
		var flags: int = int(rom_data[input_offset])
		input_offset += 1
		for bit in range(8):
			if output_offset >= output_size:
				break
			if (flags & (0x80 >> bit)) == 0:
				if not _valid_range(input_offset, 1):
					return PackedByteArray()
				output[output_offset] = rom_data[input_offset]
				input_offset += 1
				output_offset += 1
				continue
			if not _valid_range(input_offset, 2):
				return PackedByteArray()
			var first: int = int(rom_data[input_offset])
			var second: int = int(rom_data[input_offset + 1])
			input_offset += 2
			var copy_length: int = (first >> 4) + 3
			var displacement: int = ((first & 0x0F) << 8) | second
			var source_offset: int = output_offset - displacement - 1
			if source_offset < 0:
				return PackedByteArray()
			for copy_index in range(copy_length):
				if output_offset >= output_size:
					break
				output[output_offset] = output[source_offset + copy_index]
				output_offset += 1
	return output

func _read_rom_pointer(offset: int) -> int:
	if not _valid_range(offset, 4):
		return -1
	var value: int = _read_u32(offset)
	var region: int = value & 0xFF000000
	if region != 0x08000000 and region != 0x09000000 and region != 0x0A000000:
		return -1
	var file_offset: int = value & 0x01FFFFFF
	return file_offset if _valid_range(file_offset, 1) else -1

func _read_u16(offset: int) -> int:
	return int(rom_data[offset]) | (int(rom_data[offset + 1]) << 8)

func _read_u32(offset: int) -> int:
	return int(rom_data[offset]) | (int(rom_data[offset + 1]) << 8) | (int(rom_data[offset + 2]) << 16) | (int(rom_data[offset + 3]) << 24)

func _read_s32(offset: int) -> int:
	var value: int = _read_u32(offset)
	return value - 0x100000000 if value >= 0x80000000 else value

func _valid_range(offset: int, length: int) -> bool:
	return offset >= 0 and length >= 0 and offset <= rom_data.size() and length <= rom_data.size() - offset