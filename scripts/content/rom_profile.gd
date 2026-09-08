class_name OpenMMORomProfile
extends RefCounted

static func from_header(header: Dictionary) -> Dictionary:
	if str(header.get("maker_code", "")).to_upper() != "01":
		return {}
	var code: String = str(header.get("game_code", "")).to_upper()
	var revision: int = int(header.get("revision", 0))
	var catalog_code: String = "BPR" + code.substr(3, 1) if code.begins_with("BPG") and code.length() == 4 else code
	if catalog_code in ["BPRD", "BPRE", "BPRF", "BPRI", "BPRS"]:
		return _fire_red_profile(catalog_code, revision, "LeafGreen" if code.begins_with("BPG") else "FireRed", code)
	if catalog_code in ["BPED", "BPEE", "BPEF", "BPEI", "BPES"]:
		return _emerald_profile(catalog_code, revision)
	match code:
		"AXVE":
			return _ruby_profile()
		"AXPE":
			return _sapphire_profile()
	return {}

static func _profile(id: String, game: String, region: String, supports_map_rendering: bool, map_groups_offset: int) -> Dictionary:
	var content_id: String = ""
	if region == "Kanto":
		content_id = "kanto-gba-slice-v1"
	elif supports_map_rendering and region == "Hoenn":
		content_id = "hoenn-gba-slice-v1"
	return {"id": id, "game": game, "region": region, "revision": "header-identified", "content_id": content_id, "supports_map_rendering": supports_map_rendering, "server_bank_offset": 50 if region == "Hoenn" else 0, "map_groups_offset": map_groups_offset, "map_group_probe_indices": [0, 1, 19], "map_groups": {}, "region_map_entries_signature": "", "region_map_entries_signature_pointer_delta": 0, "format": {}, "animations": {}, "object_sprites": {}, "audio": {}}

static func _gba_catalog() -> Dictionary:
	return {"BPRD:0": {"map_groups": 0x083525CC, "region_map": 0x083F1504, "ow_graphics": 0x0839FC74, "ow_palettes": 0x083A501C, "battle_moves": 0x08250B28}, "BPRE:0": {"map_groups": 0x083526A8, "region_map": 0x083F1CAC, "ow_graphics": 0x0839FDB0, "ow_palettes": 0x083A5158, "battle_moves": 0x08250C04}, "BPRE:1": {"map_groups": 0x08352718, "region_map": 0x083F1D1C, "ow_graphics": 0x0839FE20, "ow_palettes": 0x083A51C8, "battle_moves": 0x08250C74}, "BPRF:0": {"map_groups": 0x0834CAF8, "region_map": 0x083EA268, "ow_graphics": 0x0839A1A0, "ow_palettes": 0x0839F548, "battle_moves": 0x0824B054}, "BPRI:0": {"map_groups": 0x0834B788, "region_map": 0x083E8F68, "ow_graphics": 0x08398E30, "ow_palettes": 0x0839E1D8, "battle_moves": 0x08249CE4}, "BPRS:0": {"map_groups": 0x0834DE70, "region_map": 0x083EBF80, "ow_graphics": 0x0839B518, "ow_palettes": 0x083A08C0, "battle_moves": 0x0824C3CC}, "BPED:0": {"map_groups": 0x084982A8, "region_map": 0x085B24B4, "ow_graphics": 0x08517350, "ow_palettes": 0x0851D8F8, "battle_moves": 0x08331258}, "BPEE:0": {"map_groups": 0x08486578, "region_map": 0x085A147C, "ow_graphics": 0x08505620, "ow_palettes": 0x0850BBC8, "battle_moves": 0x0831C898}, "BPEF:0": {"map_groups": 0x0848B464, "region_map": 0x085A5ADC, "ow_graphics": 0x0850A50C, "ow_palettes": 0x08510AB4, "battle_moves": 0x08324408}, "BPEI:0": {"map_groups": 0x084832BC, "region_map": 0x0859DEE8, "ow_graphics": 0x08502364, "ow_palettes": 0x0850890C, "battle_moves": 0x0831C298}, "BPES:0": {"map_groups": 0x08489BD4, "region_map": 0x085A41E4, "ow_graphics": 0x08508C7C, "ow_palettes": 0x0850F224, "battle_moves": 0x08322B54}}

static func _gba_file_offset(address: int) -> int:
	return address - 0x08000000 if address >= 0x08000000 else address

static func _catalog_row(code: String, revision: int) -> Dictionary:
	var catalog: Dictionary = _gba_catalog()
	var row: Dictionary = catalog.get("%s:%d" % [code, revision], {})
	if row.is_empty():
		row = catalog.get("%s:0" % code, {})
	return row

static func _fire_red_format() -> Dictionary:
	return {"firered_tileset": 1, "metatile_attributes_pointer_offset": 20, "metatile_attribute_bytes": 4, "map_header_size": 0x1C, "map_render_offset": 7, "map_grid_metatile_id_mask": 0x03FF, "map_grid_collision_mask": 0x0C00, "map_grid_elevation_mask": 0xF000, "map_grid_collision_shift": 10, "map_grid_elevation_shift": 12, "map_grid_undefined": 0x03FF, "metatile_behavior_mask": 0x000001FF, "primary_metatile_count": 640, "primary_tile_count": 640, "primary_palette_count": 7, "secondary_palette_count": 6, "secondary_rom_palette_count": 16, "tile_bytes": 32, "tiles_per_metatile": 8, "map_grid_layer_type_shift": 29, "map_grid_layer_type_mask": 0x60000000, "map_events_header_size": 0x14, "map_object_event_size": 0x18, "map_warp_event_size": 0x08, "map_connections_header_size": 0x08, "map_connection_size": 0x0C, "connection_south": 1, "connection_north": 2, "connection_west": 3, "connection_east": 4, "water_tile_index": 416, "water_tile_count": 48, "sand_tile_index": 464, "sand_tile_count": 18, "flower_tile_index": 508, "flower_tile_count": 4, "animated_tile_start": 416, "animated_tile_end": 482, "rock_stairs_behavior": 0x2A, "stair_warp_behaviors": [0x6C, 0x6D, 0x6E, 0x6F], "dynamic_object_graphics_base": 240, "dynamic_object_graphics_variable_base": 0x10, "dynamic_object_graphics_count": 16, "battle_move_table_offset": 0x250C74, "battle_animation_pic_table_offset": 0x3ACC78, "battle_animation_palette_table_offset": 0x3AD580, "battle_animation_move_table_offset": 0x1C6964, "door_graphics_table_offset": 0x35B648, "object_facing_frames": {"south": {"idle": 0, "walk": [3, 0, 4, 0]}, "north": {"idle": 1, "walk": [5, 1, 6, 1]}, "west": {"idle": 2, "walk": [7, 2, 8, 2]}, "east": {"idle": 2, "walk": [7, 2, 8, 2], "flip_h": true}}}

static func _hoenn_format() -> Dictionary:
	return {"firered_tileset": 0, "metatile_attributes_pointer_offset": 16, "metatile_attribute_bytes": 2, "map_header_size": 0x1C, "map_render_offset": 7, "map_grid_metatile_id_mask": 0x03FF, "map_grid_collision_mask": 0x0C00, "map_grid_elevation_mask": 0xF000, "map_grid_collision_shift": 10, "map_grid_elevation_shift": 12, "map_grid_undefined": 0x03FF, "metatile_behavior_mask": 0x000000FF, "primary_metatile_count": 512, "primary_tile_count": 512, "primary_palette_count": 6, "secondary_palette_count": 7, "secondary_rom_palette_count": 16, "tile_bytes": 32, "tiles_per_metatile": 8, "map_grid_layer_type_shift": 12, "map_grid_layer_type_mask": 0x0000F000, "map_events_header_size": 0x14, "map_object_event_size": 0x18, "map_warp_event_size": 0x08, "map_connections_header_size": 0x08, "map_connection_size": 0x0C, "connection_south": 1, "connection_north": 2, "connection_west": 3, "connection_east": 4, "rock_stairs_behavior": 0x2A, "stair_warp_behaviors": [0x6C, 0x6D, 0x6E, 0x6F], "object_facing_frames": {"south": {"idle": 0, "walk": [3, 0, 4, 0]}, "north": {"idle": 1, "walk": [5, 1, 6, 1]}, "west": {"idle": 2, "walk": [7, 2, 8, 2]}, "east": {"idle": 2, "walk": [7, 2, 8, 2], "flip_h": true}}}

static func _hoenn_base_profile(id: String, game: String, map_groups_offset: int) -> Dictionary:
	var profile: Dictionary = _profile(id, game, "Hoenn", true, map_groups_offset)
	profile["map_group_probe_indices"] = [0, 1, 9, 16]
	profile["map_groups"] = {"towns_and_routes": 0, "dungeons": 24, "indoor_littleroot": 1, "indoor_oldale": 2}
	profile["format"] = _hoenn_format()
	return profile

static func _emerald_profile(code: String = "BPEE", revision: int = 0) -> Dictionary:
	var row: Dictionary = _catalog_row(code, revision)
	if row.is_empty():
		return {}
	var profile_id: String = "pokemon-emerald" if code == "BPEE" else "pokemon-emerald-%s" % code.to_lower()
	var profile: Dictionary = _hoenn_base_profile(profile_id, "Emerald", _gba_file_offset(int(row.get("map_groups", 0))))
	profile["revision"] = "header-%d" % revision
	profile["region_map_entries_table_offset"] = _gba_file_offset(int(row.get("region_map", 0)))
	profile["object_event_graphics_table"] = _gba_file_offset(int(row.get("ow_graphics", 0)))
	profile["object_event_palette_table"] = _gba_file_offset(int(row.get("ow_palettes", 0)))
	profile["object_event_graphics_count"] = 256
	profile["player_object_graphics_id"] = 0
	profile["player_object_graphics_id_female"] = 89
	var format: Dictionary = profile.get("format", {})
	format["battle_move_table_offset"] = _gba_file_offset(int(row.get("battle_moves", 0)))
	if code == "BPEE":
		profile["audio"] = {"song_table_offset": 0x4A3780, "anchor_song_ids": []}
		format["battle_background_table_offset"] = 0x31ABA8
		format["battle_background_count"] = 10
		format["battle_animation_pic_table_offset"] = 0x524B44
		format["battle_animation_palette_table_offset"] = 0x52544C
		format["battle_animation_move_table_offset"] = 0x2C8D6C
	profile["format"] = format
	return profile

static func _ruby_profile() -> Dictionary:
	# AXVE (USA): gMapGroups at 0x3085A0 (Sapphire rev2 table is 0x70 earlier at 0x308530).
	var profile: Dictionary = _hoenn_base_profile("pokemon-ruby", "Ruby", 0x3085A0)
	return profile

static func _sapphire_profile() -> Dictionary:
	var profile: Dictionary = _hoenn_base_profile("pokemon-sapphire", "Sapphire", 0x308530)
	return profile

static func _fire_red_profile(catalog_code: String = "BPRE", revision: int = 0, game: String = "FireRed", profile_code: String = "BPRE") -> Dictionary:
	var row: Dictionary = _catalog_row(catalog_code, revision)
	if row.is_empty():
		return {}
	var profile_id: String = "pokemon-fire-red" if profile_code == "BPRE" else "pokemon-%s" % profile_code.to_lower()
	var profile: Dictionary = _profile(profile_id, game, "Kanto", true, _gba_file_offset(int(row.get("map_groups", 0))))
	profile["revision"] = "header-%d" % revision
	profile["map_groups"] = {"dungeons": 1, "towns_and_routes": 3, "indoor_pallet": 4, "indoor_viridian": 5}
	profile["region_map_entries_table_offset"] = _gba_file_offset(int(row.get("region_map", 0)))
	profile["region_map_section_start"] = 88
	profile["object_event_graphics_table"] = _gba_file_offset(int(row.get("ow_graphics", 0)))
	profile["object_event_palette_table"] = _gba_file_offset(int(row.get("ow_palettes", 0)))
	profile["object_event_graphics_count"] = 152
	profile["player_object_graphics_id"] = 0
	profile["player_object_graphics_id_female"] = 7
	var format: Dictionary = _fire_red_format()
	format["battle_move_table_offset"] = _gba_file_offset(int(row.get("battle_moves", 0)))
	profile["format"] = format
	if profile_code == "BPRE":
		profile["audio"] = {"song_table_offset": 0x4A332C, "anchor_song_ids": [291, 300, 303]}
		profile["animations"] = {"water": [0x3A76E4, 0x3A7CE4, 0x3A82E4, 0x3A88E4, 0x3A8EE4, 0x3A94E4, 0x3A9AE4, 0x3AA0E4], "sand": [0x3AA6E4, 0x3AA924, 0x3AAB64, 0x3AADA4, 0x3AAFE4, 0x3AB224, 0x3AB464, 0x3AB6A4], "flower": [0x3A7450, 0x3A74D0, 0x3A7550, 0x3A75D0, 0x3A7650]}
	return profile
