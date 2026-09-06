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
	return {"id": id, "game": game, "region": region, "revision": "header-identified", "content_id": content_id, "supports_map_rendering": supports_map_rendering, "map_groups_offset": map_groups_offset, "map_group_probe_indices": [0, 1, 19], "map_groups": {}, "map_names": [], "extra_maps": [], "format": {}, "animations": {}, "object_sprites": {}, "audio": {}}

static func _fire_red_format() -> Dictionary:
	return {"firered_tileset": 1, "metatile_attributes_pointer_offset": 20, "metatile_attribute_bytes": 4, "map_header_size": 0x1C, "map_render_offset": 7, "map_grid_metatile_id_mask": 0x03FF, "map_grid_collision_mask": 0x0C00, "map_grid_elevation_mask": 0xF000, "map_grid_collision_shift": 10, "map_grid_elevation_shift": 12, "map_grid_undefined": 0x03FF, "metatile_behavior_mask": 0x000001FF, "primary_metatile_count": 640, "primary_tile_count": 640, "primary_palette_count": 7, "secondary_palette_count": 6, "secondary_rom_palette_count": 16, "tile_bytes": 32, "tiles_per_metatile": 8, "map_grid_layer_type_shift": 29, "map_grid_layer_type_mask": 0x60000000, "map_events_header_size": 0x14, "map_object_event_size": 0x18, "map_warp_event_size": 0x08, "map_connections_header_size": 0x08, "map_connection_size": 0x0C, "connection_south": 1, "connection_north": 2, "connection_west": 3, "connection_east": 4, "water_tile_index": 416, "water_tile_count": 48, "sand_tile_index": 464, "sand_tile_count": 18, "flower_tile_index": 508, "flower_tile_count": 4, "animated_tile_start": 416, "animated_tile_end": 482, "rock_stairs_behavior": 0x2A, "stair_warp_behaviors": [0x6C, 0x6D, 0x6E, 0x6F], "battle_move_table_offset": 0x250C74, "battle_animation_pic_table_offset": 0x3ACC78, "battle_animation_palette_table_offset": 0x3AD580, "battle_animation_move_table_offset": 0x1C6964, "door_graphics_table_offset": 0x35B648, "object_facing_frames": {"south": {"idle": 0, "walk": [3, 0, 4, 0]}, "north": {"idle": 1, "walk": [5, 1, 6, 1]}, "west": {"idle": 2, "walk": [7, 2, 8, 2]}, "east": {"idle": 2, "walk": [7, 2, 8, 2], "flip_h": true}}}

static func _hoenn_format() -> Dictionary:
	return {"firered_tileset": 0, "metatile_attributes_pointer_offset": 16, "metatile_attribute_bytes": 2, "map_header_size": 0x1C, "map_render_offset": 7, "map_grid_metatile_id_mask": 0x03FF, "map_grid_collision_mask": 0x0C00, "map_grid_elevation_mask": 0xF000, "map_grid_collision_shift": 10, "map_grid_elevation_shift": 12, "map_grid_undefined": 0x03FF, "metatile_behavior_mask": 0x000000FF, "primary_metatile_count": 512, "primary_tile_count": 512, "primary_palette_count": 6, "secondary_palette_count": 7, "secondary_rom_palette_count": 16, "tile_bytes": 32, "tiles_per_metatile": 8, "map_grid_layer_type_shift": 12, "map_grid_layer_type_mask": 0x0000F000, "map_events_header_size": 0x14, "map_object_event_size": 0x18, "map_warp_event_size": 0x08, "map_connections_header_size": 0x08, "map_connection_size": 0x0C, "connection_south": 1, "connection_north": 2, "connection_west": 3, "connection_east": 4, "rock_stairs_behavior": 0x2A, "stair_warp_behaviors": [0x6C, 0x6D, 0x6E, 0x6F], "object_facing_frames": {"south": {"idle": 0, "walk": [3, 0, 4, 0]}, "north": {"idle": 1, "walk": [5, 1, 6, 1]}, "west": {"idle": 2, "walk": [7, 2, 8, 2]}, "east": {"idle": 2, "walk": [7, 2, 8, 2], "flip_h": true}}}

static func _hoenn_town_map_names() -> Array:
	return ["PetalburgCity", "SlateportCity", "MauvilleCity", "RustboroCity", "FortreeCity", "LilycoveCity", "MossdeepCity", "SootopolisCity", "EverGrandeCity", "LittlerootTown", "OldaleTown", "DewfordTown", "LavaridgeTown", "FallarborTown", "VerdanturfTown", "PacifidlogTown", "Route101", "Route102", "Route103", "Route104", "Route105", "Route106", "Route107", "Route108", "Route109", "Route110", "Route111", "Route112", "Route113", "Route114", "Route115", "Route116", "Route117", "Route118", "Route119", "Route120", "Route121", "Route122", "Route123", "Route124", "Route125", "Route126", "Route127", "Route128", "Route129", "Route130", "Route131", "Route132", "Route133", "Route134"]

# Emerald/RSE MAPSEC order (start=0). Includes Inside of Truck at index 84.
static func _hoenn_region_map_section_names() -> Array:
	return ["Littleroot Town", "Oldale Town", "Dewford Town", "Lavaridge Town", "Fallarbor Town", "Verdanturf Town", "Pacifidlog Town", "Petalburg City", "Slateport City", "Mauville City", "Rustboro City", "Fortree City", "Lilycove City", "Mossdeep City", "Sootopolis City", "Ever Grande City", "Route 101", "Route 102", "Route 103", "Route 104", "Route 105", "Route 106", "Route 107", "Route 108", "Route 109", "Route 110", "Route 111", "Route 112", "Route 113", "Route 114", "Route 115", "Route 116", "Route 117", "Route 118", "Route 119", "Route 120", "Route 121", "Route 122", "Route 123", "Route 124", "Route 125", "Route 126", "Route 127", "Route 128", "Route 129", "Route 130", "Route 131", "Route 132", "Route 133", "Route 134", "Underwater", "Underwater", "Underwater", "Underwater", "Underwater", "Granite Cave", "Mt. Chimney", "Safari Zone", "Battle Frontier", "Petalburg Woods", "Rusturf Tunnel", "Abandoned Ship", "New Mauville", "Meteor Falls", "Meteor Falls", "Mt. Pyre", "Aqua Hideout", "Shoal Cave", "Seafloor Cavern", "Underwater", "Victory Road", "Mirage Island", "Cave of Origin", "Southern Island", "Fiery Path", "Fiery Path", "Jagged Pass", "Jagged Pass", "Sealed Chamber", "Underwater", "Scorched Slab", "Island Cave", "Desert Ruins", "Ancient Tomb", "Inside of Truck", "Sky Pillar", "Secret Base", ""]

static func _hoenn_base_profile(id: String, game: String, map_groups_offset: int) -> Dictionary:
	var profile: Dictionary = _profile(id, game, "Hoenn", true, map_groups_offset)
	profile["map_group_probe_indices"] = [0, 1, 9, 16]
	profile["map_groups"] = {"towns_and_routes": 0, "dungeons": 24, "indoor_littleroot": 1, "indoor_oldale": 2}
	profile["map_names"] = _hoenn_town_map_names()
	profile["region_map_section_start"] = 0
	profile["region_map_section_names"] = _hoenn_region_map_section_names()
	profile["extra_maps"] = [{"group": 1, "index": 0, "id": "littleroot-brendans-house-1f", "name": "Littleroot Town Brendans House 1F"}, {"group": 1, "index": 1, "id": "littleroot-brendans-house-2f", "name": "Littleroot Town Brendans House 2F"}, {"group": 1, "index": 2, "id": "littleroot-mays-house-1f", "name": "Littleroot Town Mays House 1F"}, {"group": 1, "index": 3, "id": "littleroot-mays-house-2f", "name": "Littleroot Town Mays House 2F"}, {"group": 1, "index": 4, "id": "littleroot-birchs-lab", "name": "Littleroot Town Professor Birchs Lab"}, {"group": 2, "index": 0, "id": "oldale-house-1", "name": "Oldale Town House 1"}, {"group": 2, "index": 2, "id": "oldale-pokemon-center-1f", "name": "Oldale Town Pokemon Center 1F"}, {"group": 2, "index": 4, "id": "oldale-mart", "name": "Oldale Town Mart"}, {"group": 24, "index": 11, "id": "petalburg-woods", "name": "Petalburg Woods"}, {"group": 25, "index": 40, "id": "inside-of-truck", "name": "Inside of Truck"}]
	profile["format"] = _hoenn_format()
	return profile

static func _emerald_profile() -> Dictionary:
	var profile: Dictionary = _hoenn_base_profile("pokemon-emerald", "Emerald", 0x486578)
	profile["audio"] = {"song_table_offset": 0x4A3780, "anchor_song_ids": []}
	profile["object_event_graphics_table"] = 0x505620
	profile["object_event_palette_table"] = 0x50BBC8
	profile["object_event_graphics_count"] = 256
	profile["player_object_graphics_id"] = 0
	profile["player_object_graphics_id_female"] = 89
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
	profile["map_names"] = ["PalletTown", "ViridianCity", "PewterCity", "CeruleanCity", "LavenderTown", "VermilionCity", "CeladonCity", "FuchsiaCity", "CinnabarIsland", "IndigoPlateau_Exterior", "SaffronCity", "SaffronCity_Connection", "OneIsland", "TwoIsland", "ThreeIsland", "FourIsland", "FiveIsland", "SevenIsland", "SixIsland", "Route1", "Route2", "Route3", "Route4", "Route5", "Route6", "Route7", "Route8", "Route9", "Route10", "Route11", "Route12", "Route13", "Route14", "Route15", "Route16", "Route17", "Route18", "Route19", "Route20", "Route21_North", "Route21_South", "Route22", "Route23", "Route24", "Route25"]
	profile["region_map_section_start"] = 88
	profile["region_map_section_names"] = ["Pallet Town", "Viridian City", "Pewter City", "Cerulean City", "Lavender Town", "Vermilion City", "Celadon City", "Fuchsia City", "Cinnabar Island", "Indigo Plateau", "Saffron City", "Route 4 Pokemon Center", "Route 10 Pokemon Center", "Route 1", "Route 2", "Route 3", "Route 4", "Route 5", "Route 6", "Route 7", "Route 8", "Route 9", "Route 10", "Route 11", "Route 12", "Route 13", "Route 14", "Route 15", "Route 16", "Route 17", "Route 18", "Route 19", "Route 20", "Route 21", "Route 22", "Route 23", "Route 24", "Route 25", "Viridian Forest", "Mt. Moon", "S.S. Anne", "Underground Path", "Underground Path 2", "Diglett's Cave", "Kanto Victory Road", "Rocket Hideout", "Silph Co.", "Pokemon Mansion", "Kanto Safari Zone", "Pokemon League", "Rock Tunnel", "Seafoam Islands", "Pokemon Tower", "Cerulean Cave", "Power Plant", "One Island", "Two Island", "Three Island", "Four Island", "Five Island", "Seven Island", "Six Island", "Kindle Road", "Treasure Beach", "Cape Brink", "Bond Bridge", "Three Isle Port", "Sevii Isle 6", "Sevii Isle 7", "Sevii Isle 8", "Sevii Isle 9", "Resort Gorgeous", "Water Labyrinth", "Five Isle Meadow", "Memorial Pillar", "Outcast Island", "Green Path", "Water Path", "Ruin Valley", "Trainer Tower", "Canyon Entrance", "Sevault Canyon", "Tanoby Ruins", "Sevii Isle 22", "Sevii Isle 23", "Sevii Isle 24", "Navel Rock", "Mt. Ember", "Berry Forest", "Icefall Cave", "Rocket Warehouse", "Trainer Tower 2", "Dotted Hole", "Lost Cave", "Pattern Bush", "Altering Cave", "Tanoby Chambers", "Three Isle Path", "Tanoby Key", "Birth Island", "Monean Chamber", "Liptoo Chamber", "Weepth Chamber", "Dilford Chamber", "Scufib Chamber", "Rixy Chamber", "Viapois Chamber", "Ember Spa", "Special Area"]
	profile["audio"] = {"song_table_offset": 0x4A332C, "anchor_song_ids": [291, 300, 303]}
	profile["extra_maps"] = [{"group": 1, "index": 0, "id": "viridian-forest", "name": "Viridian Forest"}, {"group": 4, "index": 0, "id": "pallet-players-house-1f", "name": "Pallet Town Players House 1F"}, {"group": 4, "index": 1, "id": "pallet-players-house-2f", "name": "Pallet Town Players House 2F"}, {"group": 4, "index": 2, "id": "pallet-rivals-house", "name": "Pallet Town Rivals House"}, {"group": 4, "index": 3, "id": "pallet-oaks-lab", "name": "Pallet Town Professor Oaks Lab"}, {"group": 5, "index": 0, "id": "viridian-house", "name": "Viridian City House"}, {"group": 5, "index": 1, "id": "viridian-gym", "name": "Viridian City Gym"}, {"group": 5, "index": 2, "id": "viridian-school", "name": "Viridian City School"}, {"group": 5, "index": 3, "id": "viridian-mart", "name": "Viridian City Mart"}, {"group": 5, "index": 4, "id": "viridian-pokemon-center-1f", "name": "Viridian City Pokemon Center 1F"}, {"group": 5, "index": 5, "id": "viridian-pokemon-center-2f", "name": "Viridian City Pokemon Center 2F"}]
	profile["format"] = _fire_red_format()
	profile["animations"] = {"water": [0x3A76E4, 0x3A7CE4, 0x3A82E4, 0x3A88E4, 0x3A8EE4, 0x3A94E4, 0x3A9AE4, 0x3AA0E4], "sand": [0x3AA6E4, 0x3AA924, 0x3AAB64, 0x3AADA4, 0x3AAFE4, 0x3AB224, 0x3AB464, 0x3AB6A4], "flower": [0x3A7450, 0x3A74D0, 0x3A7550, 0x3A75D0, 0x3A7650]}
	profile["object_sprites"] = {16: {"data_offset": 0x36D998, "width": 16, "height": 16, "frame_bytes": 128, "frame_count": 9, "palette_offset": 0x36D8F8}, 18: {"data_offset": 0x36F018, "width": 16, "height": 32, "frame_bytes": 256, "frame_count": 10, "palette_offset": 0x36D898}, 19: {"data_offset": 0x36FA18, "width": 16, "height": 32, "frame_bytes": 256, "frame_count": 10, "palette_offset": 0x36D8D8}, 23: {"data_offset": 0x370418, "width": 16, "height": 32, "frame_bytes": 256, "frame_count": 10, "palette_offset": 0x36D8D8}, 27: {"data_offset": 0x373418, "width": 16, "height": 32, "frame_bytes": 256, "frame_count": 9, "palette_offset": 0x36D8F8}, 31: {"data_offset": 0x370E18, "width": 16, "height": 32, "frame_bytes": 256, "frame_count": 9, "palette_offset": 0x36D8F8}, 32: {"data_offset": 0x375118, "width": 16, "height": 32, "frame_bytes": 256, "frame_count": 10, "palette_offset": 0x36D8B8}, 68: {"data_offset": 0x38C718, "width": 16, "height": 32, "frame_bytes": 256, "frame_count": 9, "palette_offset": 0x36D8F8}, 71: {"data_offset": 0x389B98, "width": 16, "height": 32, "frame_bytes": 256, "frame_count": 9, "palette_offset": 0x36D8F8}, 88: {"data_offset": 0x391B98, "width": 16, "height": 32, "frame_bytes": 256, "frame_count": 9, "frame_sequence": [0, 1, 2, 0, 0, 1, 1, 2, 2], "palette_offset": 0x36D898}, 92: {"data_offset": 0x38BA98, "width": 16, "height": 16, "frame_bytes": 128, "frame_count": 1, "palette_offset": 0x36D8F8}, 95: {"data_offset": 0x394618, "width": 16, "height": 16, "frame_bytes": 128, "frame_count": 4, "palette_offset": 0x36D8D8}}
	return profile

static func _leaf_green_profile() -> Dictionary:
	var profile: Dictionary = _profile("pokemon-leaf-green", "LeafGreen", "Kanto", false, -1)
	profile["map_names"] = _fire_red_profile().get("map_names", [])
	profile["extra_maps"] = _fire_red_profile().get("extra_maps", [])
	profile["audio"] = {"song_table_offset": 0x4A332C, "anchor_song_ids": [291, 300, 303]}
	return profile
