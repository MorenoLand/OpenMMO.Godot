extends SceneTree

const GAME_STATE_SCRIPT: GDScript = preload("res://scripts/game_state.gd")

func _init() -> void:
	var game_state = GAME_STATE_SCRIPT.new()
	var previous_contents: Dictionary = game_state.contents
	var previous_content: OpenMMOContent = game_state.content
	var kanto: OpenMMOContent = OpenMMOContent.new()
	kanto.source_profile = {"region": "Kanto"}
	kanto.manifest = {"maps": [{"id": "rom-map-4-1", "name": "Kanto bedroom", "map_group": 4, "map_index": 1}]}
	var hoenn: OpenMMOContent = OpenMMOContent.new()
	hoenn.source_profile = {"region": "Hoenn"}
	hoenn.manifest = {"maps": [{"id": "rom-map-4-1", "name": "Hoenn interior", "map_group": 4, "map_index": 1}]}
	game_state.contents = {"kanto": kanto, "hoenn": hoenn}
	game_state.content = hoenn
	if game_state.map_id_for_location(4, 1, 0) != "rom-map-4-1" or game_state.content_for_location(4, 1, 0) != kanto:
		push_error("Kanto region did not win the Kanto bank/map collision")
		_quit_with_state(game_state, previous_contents, previous_content, 1)
		return
	if game_state.map_id_for_location(4, 1, 1) != "rom-map-4-1" or game_state.content_for_location(4, 1, 1) != hoenn:
		push_error("Hoenn region did not win the Hoenn bank/map collision")
		_quit_with_state(game_state, previous_contents, previous_content, 1)
		return
	if int(game_state.call("_effective_location_region", 0, 75, 1)) != 1 or int(game_state.call("_effective_location_region", 0, 4, 1)) != 0 or int(game_state.call("_effective_location_region", 0, 75, 2)) != 0:
		push_error("OpenMMO GBA region normalization is incorrect")
		_quit_with_state(game_state, previous_contents, previous_content, 1)
		return
	_quit_with_state(game_state, previous_contents, previous_content, 0)

func _quit_with_state(game_state, previous_contents: Dictionary, previous_content: OpenMMOContent, code: int) -> void:
	game_state.contents = previous_contents
	game_state.content = previous_content
	quit(code)
