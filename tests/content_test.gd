extends SceneTree

func _init() -> void:
	var invalid_data: PackedByteArray = PackedByteArray([0, 1, 2])
	var rom_result: Dictionary = OpenMMOContent.from_rom_bytes(invalid_data)
	if bool(rom_result.get("ok", false)):
		push_error("invalid ROM bytes were accepted")
		quit(1)
		return
	for profile_case in [{"code": "BPRF", "game": "LeafGreen", "region": "Kanto"}, {"code": "BPEE", "game": "Emerald", "region": "Hoenn"}, {"code": "AXPE", "game": "Sapphire", "region": "Hoenn"}]:
		var profile: Dictionary = OpenMMORomProfile.from_header({"game_code": str(profile_case.get("code", "")), "maker_code": "01"})
		if str(profile.get("game", "")) != str(profile_case.get("game", "")) or str(profile.get("region", "")) != str(profile_case.get("region", "")):
			push_error("ROM profile registry did not identify %s" % str(profile_case.get("code", "")))
			quit(1)
			return
	var item_content: OpenMMOContent = OpenMMOContent.new()
	var item_table_offset: int = 0x100
	var item_count: int = 375
	var species_table_offset: int = item_table_offset + item_count * 44 + 0x100
	item_content.rom_data.resize(species_table_offset + 512 * 11)
	for internal_id in range(item_count):
		var record_offset: int = item_table_offset + internal_id * 44
		item_content.rom_data.encode_u16(record_offset + 14, internal_id)
		item_content.rom_data[record_offset] = 0xBB
		item_content.rom_data[record_offset + 1] = 0xFF
		item_content.rom_data[record_offset + 16] = 0x2C
		item_content.rom_data[record_offset + 17] = 0x01
		item_content.rom_data[record_offset + 26] = 1
	var potion_name: PackedByteArray = PackedByteArray([0xCA, 0xC9, 0xCE, 0xC3, 0xC9, 0xC8, 0xFF])
	for position in range(potion_name.size()):
		item_content.rom_data[item_table_offset + 44 + position] = potion_name[position]
	var parcel_name: PackedByteArray = PackedByteArray([0xC9, 0xBB, 0xC5, 0xB4, 0xCD, 0x00, 0xCA, 0xBB, 0xCC, 0xBD, 0xBF, 0xBB, 0xC6, 0xFF])
	var parcel_offset: int = item_table_offset + 349 * 44
	for position in range(parcel_name.size()):
		item_content.rom_data[parcel_offset + position] = parcel_name[position]
	item_content.rom_data[parcel_offset + 26] = 2
	var charmander_name: PackedByteArray = PackedByteArray([0xBD, 0xC2, 0xBB, 0xCC, 0xC7, 0xBB, 0xC8, 0xBE, 0xBF, 0xCC, 0xFF])
	var charmander_offset: int = species_table_offset + 4 * 11
	for position in range(charmander_name.size()):
		item_content.rom_data[charmander_offset + position] = charmander_name[position]
	var treecko_name: PackedByteArray = PackedByteArray([0xCE, 0xCC, 0xBF, 0xBF, 0xBD, 0xC5, 0xC9, 0xFF])
	var treecko_offset: int = species_table_offset + 277 * 11
	for position in range(treecko_name.size()):
		item_content.rom_data[treecko_offset + position] = treecko_name[position]
	item_content.battle_tables_scanned = true
	item_content.battle_table_cache = {"item_table": item_table_offset, "species_name_table": species_table_offset}
	var potion_info: Dictionary = item_content.battle_item_info(1)
	var parcel_info: Dictionary = item_content.battle_item_info(349)
	var last_info: Dictionary = item_content.battle_item_info(374)
	var parcel_entry: Dictionary = {"entity_id": (5004 << 16) | 0x5000, "front_sprite_id": 5349, "back_sprite_id": 1}
	var charmander: String = item_content.battle_pokemon_name(4)
	var treecko: String = item_content.battle_pokemon_name(252)
	var global_content: OpenMMOContent = OpenMMOContent.new()
	global_content.battle_item_catalog = {"21": {"item_id": 21, "internal_id": 21, "name": "LOCAL NAMESPACE ITEM", "price": 0, "pocket": 0, "category": "items"}, "5021": {"item_id": 5021, "internal_id": 21, "name": "AWAKENING", "price": 250, "pocket": 1, "category": "items"}, "5459": {"item_id": 5459, "internal_id": 459, "name": "PARCEL", "price": 0, "pocket": 0, "category": "items"}}
	global_content.battle_item_catalog_loaded = true
	var global_awaken: Dictionary = global_content.battle_item_info(5021)
	var local_namespace_item: Dictionary = global_content.battle_item_info(21)
	var global_parcel: Dictionary = global_content.battle_item_info(5459)
	var missing_global_content: OpenMMOContent = OpenMMOContent.new()
	missing_global_content.battle_item_catalog = {"21": {"item_id": 21, "internal_id": 21, "name": "LOCAL NAMESPACE ITEM", "price": 0, "pocket": 0, "category": "items"}}
	missing_global_content.battle_item_catalog_loaded = true
	var missing_server_item: Dictionary = missing_global_content.battle_item_info(5021)
	if item_content.battle_item_id(parcel_entry) != 5349 or str(potion_info.get("name", "")) != "POTION" or str(parcel_info.get("name", "")) != "OAK'S PARCEL" or str(parcel_info.get("category", "")) != "key_item" or str(last_info.get("name", "")) != "A" or str(global_awaken.get("name", "")) != "AWAKENING" or str(local_namespace_item.get("name", "")) != "LOCAL NAMESPACE ITEM" or str(global_parcel.get("name", "")) != "PARCEL" or not str(missing_server_item.get("name", "")).is_empty() or charmander != "CHARMANDER" or treecko != "TREECKO":
		push_error("ROM item table catalog did not resolve every item through the dynamic reader")
		quit(1)
		return
	var path: String = OS.get_environment("OPENMMOGO_ROM")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = 0
	while index < args.size():
		if args[index] == "--rom" and index + 1 < args.size():
			path = args[index + 1]
			index += 2
			continue
		index += 1
	if path.is_empty():
		quit(0)
		return
	var result: Dictionary = OpenMMOContent.from_rom_path(path)
	if not bool(result.get("ok", false)):
		push_error(str(result.get("error", "content load failed")))
		quit(1)
		return
	var content: OpenMMOContent = result.get("content") as OpenMMOContent
	if str(content.source_profile.get("id", "")) != "pokemon-fire-red":
		push_error("FireRed ROM did not select the FireRed source profile")
		quit(1)
		return
	var live_parcel: Dictionary = content.battle_item_info(349)
	if str(live_parcel.get("name", "")) != "OAK'S PARCEL" or str(live_parcel.get("category", "")) != "key_item":
		push_error("FireRed item catalog did not resolve Oak's Parcel from the selected ROM")
		quit(1)
		return
	for door_frame_index in range(1, 4):
		var door_frame: Dictionary = content.door_animation_frame("pallet-town", 6, 7, door_frame_index)
		var door_texture: Texture2D = door_frame.get("texture") as Texture2D
		if not bool(door_frame.get("ok", false)) or door_texture == null or door_texture.get_width() != 16 or door_texture.get_height() not in [16, 32]:
			push_error("FireRed door animation frame %d was not decoded" % door_frame_index)
			quit(1)
			return
	var ball_result: Dictionary = content.battle_pokeball_frames()
	if not bool(ball_result.get("ok", false)) or (ball_result.get("frames", []) as Array).size() != 3:
		push_error("FireRed Poké Ball send-out frames were not decoded")
		quit(1)
		return
	var ember_plan: Dictionary = content.battle_move_animation_plan(52)
	if not bool(ember_plan.get("ok", false)) or (ember_plan.get("spawns", []) as Array).is_empty():
		push_error("FireRed Ember animation script was not decoded")
		quit(1)
		return
	var animation_sheet_found: bool = false
	for tag_value in ember_plan.get("tags", []):
		var sheet: Dictionary = content.battle_animation_sheet(int(tag_value))
		if bool(sheet.get("ok", false)) and not (sheet.get("frames", []) as Array).is_empty():
			animation_sheet_found = true
			break
	if not animation_sheet_found:
		push_error("FireRed Ember animation graphics were not decoded")
		quit(1)
		return
	if (content.manifest.get("maps", []) as Array).size() < 50:
		push_error("ROM map manifest did not expose the selectable map table")
		quit(1)
		return
	var online_dialogue: Dictionary = content.dialogue_for_text_id(1639103)
	var online_pages: Array = online_dialogue.get("pages", [])
	if int(online_dialogue.get("text_offset", -1)) != 1639223 or online_pages.size() != 1 or str(online_pages[0]) != "Okay, thanks! Please say hi to\nPROF. OAK for me, too.":
		push_error("Rev1 ROM dialogue relocation or page decoding is incorrect")
		quit(1)
		return
	for dialogue_case in [{"id": 1800324, "offset": 1800439}, {"id": 1856969, "offset": 1857081}]:
		var dialogue_case_result: Dictionary = content.dialogue_for_text_id(int(dialogue_case.get("id", 0)))
		if int(dialogue_case_result.get("text_offset", -1)) != int(dialogue_case.get("offset", -1)):
			push_error("Rev1 ROM dialogue relocation is incorrect for 0x%08X" % int(dialogue_case.get("id", 0)))
			quit(1)
			return
	var patched_data: PackedByteArray = content.rom_data.duplicate()
	patched_data[0x1000] = (int(patched_data[0x1000]) + 1) & 0xFF
	var patched_result: Dictionary = OpenMMOContent.from_rom_bytes(patched_data)
	if not bool(patched_result.get("ok", false)):
		push_error("graphics-patched compatible ROM was rejected: %s" % str(patched_result.get("error", "unknown error")))
		quit(1)
		return
	for extra_map_id in ["rom-map-3-2", "rom-map-3-20", "viridian-forest", "pallet-players-house-1f", "viridian-pokemon-center-1f"]:
		var extra_result: Dictionary = content.render_map(extra_map_id)
		if not bool(extra_result.get("ok", false)):
			push_error("additional map render failed for %s: %s" % [extra_map_id, str(extra_result.get("error", "unknown error"))])
			quit(1)
			return
	var preview_phase: int = clampi(int(OS.get_environment("OPENMMOGO_PREVIEW_PHASE")), 0, 39)
	var preview_map: String = OS.get_environment("OPENMMOGO_PREVIEW_MAP")
	for expected_map in [{"id": "pallet-town", "width": 384, "height": 320}, {"id": "route-1", "width": 384, "height": 640}, {"id": "viridian-city", "width": 768, "height": 640}]:
		var map_id: String = str(expected_map.get("id", ""))
		var render_result: Dictionary = content.render_map(map_id, preview_phase)
		if not bool(render_result.get("ok", false)):
			push_error("map render failed: %s" % str(render_result.get("error", "unknown error")))
			quit(1)
			return
		var image: Image = render_result.get("image") as Image
		if image == null or image.get_width() != int(expected_map.get("width", 0)) or image.get_height() != int(expected_map.get("height", 0)):
			push_error("map render dimensions are incorrect for %s" % map_id)
			quit(1)
			return
		var colors: Dictionary = {}
		var sample_step_x: int = maxi(image.get_width() / 8, 1)
		var sample_step_y: int = maxi(image.get_height() / 8, 1)
		for sample_y in range(0, image.get_height(), sample_step_y):
			for sample_x in range(0, image.get_width(), sample_step_x):
				colors[image.get_pixel(sample_x, sample_y).to_html(false)] = true
		if colors.size() < 2:
			push_error("map render produced no palette variation for %s" % map_id)
			quit(1)
			return
		var preview_path: String = OS.get_environment("OPENMMOGO_PREVIEW_PNG")
		var should_save_preview: bool = map_id == "pallet-town" if preview_map.is_empty() else map_id == preview_map
		if not preview_path.is_empty() and should_save_preview:
			image.save_png(preview_path)
		if map_id == "pallet-town" and (render_result.get("objects", []) as Array).size() < 3:
			push_error("Pallet Town object events were not decoded")
			quit(1)
			return
		if map_id == "pallet-town":
			for y in image.get_height():
				for x in image.get_width():
					if image.get_pixel(x, y) == Color(1, 0, 1):
						push_error("Pallet Town contains an unmapped magenta palette pixel")
						quit(1)
						return
		if map_id == "viridian-city":
			for y in range(image.get_height()):
				for x in range(image.get_width()):
					if image.get_pixel(x, y) == Color(0, 0, 1):
						push_error("Viridian City contains a secondary palette placeholder-blue pixel")
						quit(1)
						return
	var static_result: Dictionary = content.render_map("pallet-town", 0)
	var animated_result: Dictionary = content.render_map("pallet-town", 7)
	var static_image: Image = static_result.get("image") as Image
	var animated_image: Image = animated_result.get("image") as Image
	var differing_pixels: int = 0
	for y in range(0, static_image.get_height(), 8):
		for x in range(0, static_image.get_width(), 8):
			if static_image.get_pixel(x, y) != animated_image.get_pixel(x, y):
				differing_pixels += 1
	if differing_pixels == 0:
		push_error("map animation did not change any pixels")
		quit(1)
		return
	var pallet_result: Dictionary = content.render_map("pallet-town")
	if (pallet_result.get("connections", []) as Array).size() != 2 or (pallet_result.get("warps", []) as Array).size() != 3:
		push_error("Pallet Town connections or warps were not decoded")
		quit(1)
		return
	if pallet_result.get("background_texture") == null or pallet_result.get("foreground_texture") == null:
		push_error("map render did not expose separated draw layers")
		quit(1)
		return
	var prepared_result: Dictionary = content.prepare_map("pallet-town")
	if prepared_result.get("background_texture") == null or prepared_result.get("foreground_texture") == null or animated_result.get("background_texture") == null or animated_result.get("foreground_texture") == null:
		push_error("world renderer did not prepare cached ROM compositor layers")
		quit(1)
		return
	var animated_background_metatiles: Array = prepared_result.get("animated_background_tiles", [])
	var animated_foreground_metatiles: Array = prepared_result.get("animated_foreground_tiles", [])
	var animated_metatile: Dictionary = animated_background_metatiles[0] if not animated_background_metatiles.is_empty() else animated_foreground_metatiles[0] if not animated_foreground_metatiles.is_empty() else {}
	var animated_metatile_texture: Texture2D = content.animated_metatile_texture("pallet-town", animated_metatile, 7, animated_background_metatiles.is_empty()) if not animated_metatile.is_empty() else null
	if animated_metatile_texture == null:
		push_error("world renderer did not prepare a ROM-backed animated metatile replacement")
		quit(1)
		return
	if not animated_background_metatiles.is_empty():
		var animated_metatile_image: Image = animated_metatile_texture.get_image()
		for pixel_y in animated_metatile_image.get_height():
			for pixel_x in animated_metatile_image.get_width():
				if animated_metatile_image.get_pixel(pixel_x, pixel_y).a < 1.0:
					push_error("animated background metatile contains transparent flicker pixels")
					quit(1)
					return
	var connected_world: Dictionary = content.prepare_connected_world("pallet-town")
	var connected_regions: Array = connected_world.get("regions", [])
	if not bool(connected_world.get("ok", false)) or connected_regions.size() < 3:
		push_error("Pallet Town connected overworld was not assembled")
		quit(1)
		return
	var connected_root_ready: bool = false
	for region_value in connected_regions:
		if region_value is Dictionary and str(region_value.get("map_id", "")) == "pallet-town" and bool(region_value.get("ready", false)) and region_value.get("background_texture") != null:
			connected_root_ready = true
			break
	if not connected_root_ready:
		push_error("connected overworld root was not render-ready")
		quit(1)
		return
	var connected_origins: Dictionary = connected_world.get("map_origins", {})
	for connection_value in pallet_result.get("connections", []):
		if not connection_value is Dictionary:
			continue
		var connection: Dictionary = connection_value
		var target_map_id: String = str(connection.get("map_id", ""))
		var target_map: Dictionary = content.map_data(target_map_id)
		var target_origin: Variant = connected_origins.get(target_map_id)
		if target_map.is_empty() or target_origin == null:
			push_error("connected overworld omitted %s" % target_map_id)
			quit(1)
			return
		var expected_origin: Vector2i = content._connected_map_origin(Vector2i.ZERO, int(pallet_result.get("width", 0)), int(pallet_result.get("height", 0)), int(target_map.get("width", 0)), int(target_map.get("height", 0)), int(connection.get("direction", 0)), int(connection.get("offset", 0)))
		if Vector2i(target_origin) != expected_origin:
			push_error("connected overworld placed %s at the wrong offset" % target_map_id)
			quit(1)
			return
	var house_result: Dictionary = content.render_map("pallet-players-house-1f")
	if content.has_animated_tiles("pallet-players-house-1f"):
		push_error("indoor Building tileset was incorrectly marked as animated")
		quit(1)
		return
	var house_phase_result: Dictionary = content.render_map("pallet-players-house-1f", 7)
	var house_image: Image = house_result.get("image") as Image
	var house_phase_image: Image = house_phase_result.get("image") as Image
	if house_image == null or house_phase_image == null or house_image.get_data() != house_phase_image.get_data():
		push_error("indoor Building tileset changed across animation phases")
		quit(1)
		return
	var profile_format: Dictionary = content.source_profile.get("format", {}) as Dictionary
	var map_render_offset: int = int(profile_format.get("map_render_offset", 0))
	if map_render_offset <= 0 or Vector2i(house_result.get("render_origin", Vector2i.ZERO)) != Vector2i(-map_render_offset, -map_render_offset) or int(house_result.get("render_width", 0)) != int(house_result.get("width", 0)) + map_render_offset * 2 + 1 or int(house_result.get("render_height", 0)) != int(house_result.get("height", 0)) + map_render_offset * 2:
		push_error("standalone indoor map did not expose the source padded render geometry")
		quit(1)
		return
	var mom_found: bool = false
	for object_value in house_result.get("objects", []):
		if object_value is Dictionary and int(object_value.get("graphics_id", -1)) == 88:
			mom_found = int(object_value.get("resolved_graphics_id", -1)) == 88 and int(object_value.get("width", 0)) == 16 and int(object_value.get("height", 0)) == 32
			break
	if not mom_found:
		push_error("Pallet Town Mom did not resolve to the source graphics record")
		quit(1)
		return
	var dialogue: Dictionary = content.interaction_at("pallet-players-house-1f", 8, 5, 2, 3, house_result.get("objects", []))
	if not bool(dialogue.get("ok", false)) or (dialogue.get("pages", []) as Array).is_empty() or str(dialogue.get("text", "")).is_empty():
		push_error("object interaction did not produce decoded ROM dialogue")
		quit(1)
		return
	if str(dialogue.get("text", "")).to_lower().contains("groom"):
		push_error("player-house Mom interaction selected Daisy's grooming dialogue")
		quit(1)
		return
	var sign_dialogue: Dictionary = content.interaction_at("pallet-players-house-1f", 6, 2, 2, 3, house_result.get("objects", []))
	if not bool(sign_dialogue.get("ok", false)) or str(sign_dialogue.get("kind", "")) != "sign":
		push_error("ROM background sign interaction was not decoded")
		quit(1)
		return
	var directional_signs: Array = [{"kind": "sign", "background_kind": 2, "local_id": -1, "x": 6, "y": 1, "elevation": 3, "dialogue_pages": ["Synthetic sign"]}]
	var sign_wrong_direction: Dictionary = content.interaction_at("pallet-players-house-1f", 6, 0, 1, 3, directional_signs)
	if bool(sign_wrong_direction.get("ok", false)):
		push_error("directional ROM sign interaction ignored its facing rule")
		quit(1)
		return
	var audio: OpenMMOAudio = OpenMMOAudio.new()
	if audio.has_method("_build_effect_stream") or audio.has_method("_build_music_stream"):
		push_error("procedural audio fallback is still present")
		quit(1)
		return
	var rom_audio: OpenMMORomAudio = OpenMMORomAudio.new()
	for song_id in [291, 300, 30, 241]:
		var audio_result: Dictionary = rom_audio.inspect_song(content, int(song_id))
		if not bool(audio_result.get("ok", false)) or int(audio_result.get("event_count", 0)) <= 0:
			push_error("ROM audio song %d was not decoded: %s" % [song_id, str(audio_result.get("error", "no events"))])
			quit(1)
			return
		var stream: AudioStreamWAV = rom_audio.build_song_stream(content, int(song_id)) as AudioStreamWAV
		if stream == null or stream.data.is_empty() or stream.mix_rate != 13379 or not stream.stereo:
			push_error("ROM audio song %d did not produce a stereo PCM stream" % song_id)
			quit(1)
			return
	audio.free()
	var spawn: Dictionary = content.default_spawn("pallet-town")
	if not bool(spawn.get("ok", false)) or not bool(content.map_cell("pallet-town", int(spawn.get("x", 0)), int(spawn.get("y", 0))).get("collision", 1) == 0):
		push_error("Pallet Town did not produce a walkable spawn")
		quit(1)
		return
	var blocked_cell_found: bool = false
	var walkable_step_found: bool = false
	var jump_behavior_found: bool = false
	var stair_transition_found: bool = false
	for map_id in ["pallet-town", "route-1", "viridian-city", "rom-map-3-20", "viridian-forest", "pallet-players-house-1f", "pallet-players-house-2f"]:
		var map_value: Dictionary = content.map_data(map_id)
		for y in range(int(map_value.get("height", 0))):
			for x in range(int(map_value.get("width", 0))):
				var cell: Dictionary = content.map_cell(map_id, x, y)
				if int(cell.get("collision", 0)) != 0:
					blocked_cell_found = true
				if int(cell.get("behavior", 0)) >= 0x38 and int(cell.get("behavior", 0)) <= 0x3B:
					jump_behavior_found = true
				if blocked_cell_found and jump_behavior_found and walkable_step_found and stair_transition_found:
					break
				for direction in [1, 2, 3, 4]:
					var movement: Dictionary = content.movement_result(map_id, x, y, direction)
					if bool(movement.get("ok", false)) and bool(movement.get("stair", false)):
						stair_transition_found = true
					if bool(movement.get("ok", false)) and not bool(movement.get("jump", false)):
						walkable_step_found = true
					if blocked_cell_found and jump_behavior_found and walkable_step_found and stair_transition_found:
						break
			if blocked_cell_found and jump_behavior_found and walkable_step_found and stair_transition_found:
				break
		if blocked_cell_found and jump_behavior_found and walkable_step_found and stair_transition_found:
			break
	if not blocked_cell_found or not walkable_step_found or not jump_behavior_found or not stair_transition_found:
		push_error("ROM movement data did not expose collision, movement, ledge, and stair behavior")
		quit(1)
		return
	var continuous_step: Dictionary = {}
	for y in range(int(content.map_data("pallet-town").get("height", 0))):
		for x in range(int(content.map_data("pallet-town").get("width", 0))):
			for direction in [1, 2, 3, 4]:
				var first_step: Dictionary = content.movement_result("pallet-town", x, y, direction, 3, pallet_result.get("objects", []))
				if not bool(first_step.get("ok", false)) or bool(first_step.get("jump", false)) or bool(first_step.get("stair", false)) or str(first_step.get("map_id", "")) != "pallet-town":
					continue
				var second_step: Dictionary = content.movement_result("pallet-town", int(first_step.get("x", 0)), int(first_step.get("y", 0)), direction, int(first_step.get("elevation", 3)), pallet_result.get("objects", []))
				if bool(second_step.get("ok", false)) and not bool(second_step.get("jump", false)) and not bool(second_step.get("stair", false)) and str(second_step.get("map_id", "")) == "pallet-town":
					continuous_step = {"x": x, "y": y, "direction": direction, "first": first_step}
					break
			if not continuous_step.is_empty():
				break
		if not continuous_step.is_empty():
			break
	if continuous_step.is_empty():
		push_error("Pallet Town did not expose two consecutive movement cells")
		quit(1)
		return
	var world_view: OpenMMOMapPlayCanvas = OpenMMOMapPlayCanvas.new()
	world_view.set_content(content)
	world_view.set_map(prepared_result.get("texture") as Texture2D, int(prepared_result.get("width", 0)), int(prepared_result.get("height", 0)), prepared_result.get("objects", []), "pallet-town", prepared_result.get("foreground_texture") as Texture2D)
	world_view.set_player_state(int(continuous_step.get("x", 0)), int(continuous_step.get("y", 0)), 3)
	world_view.held_direction = int(continuous_step.get("direction", 0))
	world_view._request_move(world_view.held_direction)
	world_view._process(world_view.movement_duration + 0.001)
	var first_target: Dictionary = continuous_step.get("first", {})
	if not world_view.movement_active or world_view.movement_start != Vector2(int(first_target.get("x", 0)), int(first_target.get("y", 0))):
		push_error("held movement inserted an idle gap between adjacent tiles")
		quit(1)
		return
	world_view.free()
	var connection_step: Dictionary = {}
	var pallet_width: int = int(content.map_data("pallet-town").get("width", 0))
	var pallet_height: int = int(content.map_data("pallet-town").get("height", 0))
	for y in range(pallet_height):
		for edge in [{"x": 0, "y": y, "direction": 3}, {"x": pallet_width - 1, "y": y, "direction": 4}]:
			var movement: Dictionary = content.movement_result("pallet-town", int(edge.x), int(edge.y), int(edge.direction), 3, pallet_result.get("objects", []))
			if bool(movement.get("ok", false)) and str(movement.get("map_id", "pallet-town")) != "pallet-town":
				connection_step = {"x": edge.x, "y": edge.y, "direction": edge.direction}
				break
		if not connection_step.is_empty():
			break
	if connection_step.is_empty():
		for x in range(pallet_width):
			for edge in [{"x": x, "y": 0, "direction": 2}, {"x": x, "y": pallet_height - 1, "direction": 1}]:
				var movement: Dictionary = content.movement_result("pallet-town", int(edge.x), int(edge.y), int(edge.direction), 3, pallet_result.get("objects", []))
				if bool(movement.get("ok", false)) and str(movement.get("map_id", "pallet-town")) != "pallet-town":
					connection_step = {"x": edge.x, "y": edge.y, "direction": edge.direction}
					break
			if not connection_step.is_empty():
				break
	if connection_step.is_empty():
		push_error("Pallet Town did not expose a traversable map connection")
		quit(1)
		return
	var transition_view: OpenMMOMapPlayCanvas = OpenMMOMapPlayCanvas.new()
	transition_view.set_content(content)
	transition_view.set_map(prepared_result.get("texture") as Texture2D, pallet_width, pallet_height, pallet_result.get("objects", []), "pallet-town", prepared_result.get("foreground_texture") as Texture2D)
	transition_view.set_player_state(int(connection_step.x), int(connection_step.y), 3)
	transition_view._request_move(int(connection_step.direction))
	var connection_delta: Vector2 = transition_view.movement_target - transition_view.movement_start
	if not transition_view.movement_active or not is_equal_approx(absf(connection_delta.x) + absf(connection_delta.y), 1.0):
		push_error("map connection movement interpolated across unrelated map coordinates")
		quit(1)
		return
	transition_view.free()
	var warp_result: Dictionary = content.warp_at("pallet-town", 6, 7)
	if not bool(warp_result.get("ok", false)) or str(warp_result.get("map_id", "")).is_empty():
		push_error("Pallet Town warp transition was not resolved")
		quit(1)
		return
	for direction in [1, 2, 3, 4]:
		var direction_sprite: Dictionary = content.render_facing_object_sprite(19, direction, false, 0)
		if not bool(direction_sprite.get("ok", false)) or int(direction_sprite.get("width", 0)) != 16 or int(direction_sprite.get("height", 0)) != 32:
			push_error("player facing sprite was not decoded for direction %d" % direction)
			quit(1)
			return
	var player_idle_a: Dictionary = content.render_facing_object_sprite(19, 1, false, 0)
	var player_idle_b: Dictionary = content.render_facing_object_sprite(19, 1, false, 0)
	if player_idle_a.get("texture") != player_idle_b.get("texture"):
		push_error("player idle sprite was not stable between animation ticks")
		quit(1)
		return
	var door_entry_found: bool = false
	var door_position: Vector2i = Vector2i(6, 7)
	for direction in [1, 2, 3, 4]:
		var vector: Vector2i = Vector2i.ZERO
		match direction:
			1:
				vector = Vector2i(0, 1)
			2:
				vector = Vector2i(0, -1)
			3:
				vector = Vector2i(-1, 0)
			4:
				vector = Vector2i(1, 0)
		var from_position: Vector2i = door_position - vector
		var door_movement: Dictionary = content.movement_result("pallet-town", from_position.x, from_position.y, direction)
		if bool(door_movement.get("ok", false)) and int(door_movement.get("x", -1)) == door_position.x and int(door_movement.get("y", -1)) == door_position.y:
			if not bool(door_movement.get("door", false)):
				push_error("Pallet Town door warp was not identified as a door traversal")
				quit(1)
				return
			door_entry_found = true
			break
	if not door_entry_found:
		push_error("Pallet Town door warp could not be entered from an adjacent tile")
		quit(1)
		return
	var non_door_warp_found: bool = false
	for warp_map_id in ["pallet-oaks-lab", "viridian-pokemon-center-1f", "viridian-pokemon-center-2f"]:
		var warp_map: Dictionary = content.prepare_map(warp_map_id, false)
		for warp_value in warp_map.get("warps", []) as Array:
			if not warp_value is Dictionary:
				continue
			var interior_warp: Dictionary = warp_value
			var warp_x: int = int(interior_warp.get("x", -1))
			var warp_y: int = int(interior_warp.get("y", -1))
			for direction in [1, 2, 3, 4]:
				var vector: Vector2i = Vector2i.ZERO
				match direction:
					1:
						vector = Vector2i(0, 1)
					2:
						vector = Vector2i(0, -1)
					3:
						vector = Vector2i(-1, 0)
					4:
						vector = Vector2i(1, 0)
				var movement: Dictionary = content.movement_result(warp_map_id, warp_x - vector.x, warp_y - vector.y, direction)
				if bool(movement.get("ok", false)) and int(movement.get("x", -1)) == warp_x and int(movement.get("y", -1)) == warp_y and not bool(movement.get("door", false)):
					non_door_warp_found = true
					break
			if non_door_warp_found:
				break
		if non_door_warp_found:
			break
	if not non_door_warp_found:
		push_error("interior non-door warp was incorrectly identified as a door traversal")
		quit(1)
		return
	var provider: OpenMMOContentProvider = OpenMMOContentProvider.new()
	provider._save_rom_path(path)
	if not provider.restore_saved_rom():
		provider._clear_saved_rom()
		push_error("saved ROM path could not be restored")
		quit(1)
		return
	provider._clear_saved_rom()
	provider.free()
	quit(0)
