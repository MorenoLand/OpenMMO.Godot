extends SceneTree

const OpenMMOContent = preload("res://scripts/content/content.gd")
var content: OpenMMOContent

func _init() -> void:
	content = OpenMMOContent.new()
	content.rom_data.resize(0x8000)
	content.source_profile = {"id": "test", "region": "Kanto", "content_id": "test", "format": {"tile_bytes": 32}, "object_event_graphics_count": 152, "object_facing_frames": {"south": {"idle": 0, "walk": [0]}, "north": {"idle": 0, "walk": [0]}, "west": {"idle": 0, "walk": [0]}, "east": {"idle": 0, "walk": [0]}}}
	var fixtures: Array = [{"id": 72, "width": 16, "height": 32, "inanimate": false}, {"id": 92, "width": 16, "height": 16, "inanimate": true}, {"id": 94, "width": 16, "height": 16, "inanimate": true}]
	var catalog_fixtures: Array = []
	for graphics_id in range(16):
		catalog_fixtures.append({"id": graphics_id, "width": 16, "height": 32, "inanimate": false})
	catalog_fixtures.append_array(fixtures)
	for fixture_index in range(catalog_fixtures.size()):
		var fixture: Dictionary = catalog_fixtures[fixture_index]
		var graphics_id: int = int(fixture["id"])
		var structure_offset: int = 0x1000 + graphics_id * 0x20
		var image_table_offset: int = 0x3000 + graphics_id * 0x20
		var image_data_offset: int = 0x5000 + fixture_index * 0x100
		var palette_offset: int = 0x7400 + fixture_index * 0x40
		_write_pointer(0x100 + graphics_id * 4, structure_offset)
		_write_u16(structure_offset + 2, 0x1200 + fixture_index)
		_write_u16(structure_offset + 6, int(fixture["width"]) * int(fixture["height"]))
		_write_u16(structure_offset + 8, int(fixture["width"]))
		_write_u16(structure_offset + 10, int(fixture["height"]))
		_write_u16(structure_offset + 12, 0x40 if bool(fixture["inanimate"]) else 0)
		_write_pointer(structure_offset + 0x1C, image_table_offset)
		_write_pointer(image_table_offset, image_data_offset)
		_write_u32(image_table_offset + 4, int(fixture["width"]) * int(fixture["height"]) / 2)
		_write_pointer(0x7000 + fixture_index * 8, palette_offset)
		_write_u16(0x7000 + fixture_index * 8 + 4, 0x1200 + fixture_index)
		for byte_index in range(int(fixture["width"]) * int(fixture["height"]) / 2):
			content.rom_data[image_data_offset + byte_index] = 0x11
	var generated: Dictionary = content.call("_object_sprite_specs")
	for fixture in fixtures:
		var graphics_id: int = int(fixture["id"])
		var result: Dictionary = content.render_object_sprite(graphics_id)
		if not bool(result.get("ok", false)) or int(result.get("resolved_graphics_id", -1)) != graphics_id or int(result.get("width", 0)) != int(fixture["width"]) or int(result.get("height", 0)) != int(fixture["height"]):
			push_error("Kanto object graphics ID %d did not decode from the ROM catalog" % graphics_id)
			quit(1)
			return
		if bool(fixture["inanimate"]) and not bool(generated.get(graphics_id, {}).get("inanimate", false)):
			push_error("Kanto object graphics ID %d lost its inanimate flag" % graphics_id)
			quit(1)
			return
	if generated.has(16) or bool(content.render_object_sprite(16).get("ok", false)):
		push_error("missing Kanto object graphics were incorrectly aliased")
		quit(1)
		return
	print("Kanto object graphics catalog test passed")
	quit(0)

func _write_pointer(offset: int, target: int) -> void:
	content.rom_data.encode_u32(offset, 0x08000000 | target)

func _write_u16(offset: int, value: int) -> void:
	content.rom_data.encode_u16(offset, value)

func _write_u32(offset: int, value: int) -> void:
	content.rom_data.encode_u32(offset, value)
