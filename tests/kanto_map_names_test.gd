extends SceneTree

const OpenMMOContent = preload("res://scripts/content/content.gd")
var content: OpenMMOContent

func _init() -> void:
	content = OpenMMOContent.new()
	content.rom_data.resize(384)
	content.source_profile = {"id": "test", "region": "Kanto", "content_id": "test", "region_map_entries_signature": "AC470000AE470000B0470000", "region_map_entries_signature_pointer_delta": 0, "region_map_section_start": 88}
	var signature: PackedByteArray = PackedByteArray([0xAC, 0x47, 0x00, 0x00, 0xAE, 0x47, 0x00, 0x00, 0xB0, 0x47, 0x00, 0x00])
	for index in range(signature.size()):
		content.rom_data[100 + index] = signature[index]
	_write_u32(112, 0x080000C8)
	_write_u32(200, 0x0800012C)
	for index in range(5):
		content.rom_data[300 + index] = [0xCE, 0xBF, 0xCD, 0xCE, 0xFF][index]
	var name: String = content.call("_map_name_from_descriptor", {"map_group": 3, "map_index": 0, "region_map_section_id": 88, "floor_num": 0})
	if name != "TEST":
		push_error("Kanto ROM region-map pointer catalog did not resolve")
		quit(1)
		return
	print("Kanto map-name catalog test passed")
	quit(0)

func _write_u32(offset: int, value: int) -> void:
	content.rom_data.encode_u32(offset, value)
