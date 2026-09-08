class_name OpenMMORomProfile
extends RefCounted

static func from_header(header: Dictionary) -> Dictionary:
	if str(header.get("maker_code", "")).to_upper() != "01":
		return {}
	match str(header.get("game_code", "")).to_upper():
		"BPRE":
			return _fire_red_profile()
		"BPRF":
			return _leaf_green_profile()
		"BPEE":
			return _emerald_profile()
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
	return {"id": id, "game": game, "region": region, "revision": "header-identified", "content_id": content_id, "supports_map_rendering": supports_map_rendering, "map_groups_offset": map_groups_offset, "map_group_probe_indices": [0, 1, 19], "map_groups": {}, "region_map_entries_signature": "", "region_map_entries_signature_pointer_delta": 0, "format": {}, "animations": {}, "object_sprites": {}, "audio": {}}

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

static func _emerald_profile() -> Dictionary:
	var profile: Dictionary = _hoenn_base_profile("pokemon-emerald", "Emerald", 0x486578)
	profile["region_map_entries_signature"] = "C078288030BC01BC00470000"
	profile["audio"] = {"song_table_offset": 0x4A3780, "anchor_song_ids": []}
	profile["object_event_graphics_table"] = 0x505620
	profile["object_event_palette_table"] = 0x50BBC8
	profile["object_event_graphics_count"] = 256
	profile["player_object_graphics_id"] = 0
	profile["player_object_graphics_id_female"] = 89
	var format: Dictionary = profile.get("format", {})
	format["battle_move_table_offset"] = 0x31C898
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

static func _fire_red_profile() -> Dictionary:
	var profile: Dictionary = _profile("pokemon-fire-red", "FireRed", "Kanto", true, 0x352718)
	profile["map_groups"] = {"dungeons": 1, "towns_and_routes": 3, "indoor_pallet": 4, "indoor_viridian": 5}
	profile["region_map_entries_signature"] = "AC470000AE470000B0470000"
	profile["region_map_section_start"] = 88
	profile["object_event_graphics_tables"] = {0: {"graphics": 0x39FDB0, "palette": 0x3A501C}, 1: {"graphics": 0x39FE20, "palette": 0x3A51C8}}
	profile["object_event_graphics_count"] = 152
	profile["audio"] = {"song_table_offset": 0x4A332C, "anchor_song_ids": [291, 300, 303]}
	profile["format"] = _fire_red_format()
	profile["animations"] = {"water": [0x3A76E4, 0x3A7CE4, 0x3A82E4, 0x3A88E4, 0x3A8EE4, 0x3A94E4, 0x3A9AE4, 0x3AA0E4], "sand": [0x3AA6E4, 0x3AA924, 0x3AAB64, 0x3AADA4, 0x3AAFE4, 0x3AB224, 0x3AB464, 0x3AB6A4], "flower": [0x3A7450, 0x3A74D0, 0x3A7550, 0x3A75D0, 0x3A7650]}
	return profile

static func _leaf_green_profile() -> Dictionary:
	var profile: Dictionary = _profile("pokemon-leaf-green", "LeafGreen", "Kanto", false, -1)

	profile["audio"] = {"song_table_offset": 0x4A332C, "anchor_song_ids": [291, 300, 303]}
	return profile
