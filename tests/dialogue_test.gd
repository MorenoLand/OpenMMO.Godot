extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var dialogue: OpenMMODialogue = OpenMMODialogue.new()
	root.add_child(dialogue)
	await process_frame
	dialogue.show_pages(["First page", "Second page"])
	if not dialogue.is_open() or dialogue.arrow_label.visible or dialogue.visible_count != 0:
		_fail("dialogue did not start in typing state")
		return
	dialogue.show_pages(["Anchored page"], false, Vector2(320.0, 240.0))
	if not is_equal_approx(dialogue.size.x, OpenMMODialogue.PANEL_WIDTH) or dialogue.layout_in_progress:
		_fail("actor-anchored dialogue layout recursed or changed its own viewport width")
		return
	dialogue.show_pages(["First page", "Second page"])
	dialogue._process(0.1)
	if dialogue.visible_count <= 0 or dialogue.arrow_label.visible:
		_fail("dialogue typewriter did not advance correctly")
		return
	dialogue.handle_action()
	if dialogue.visible_count != dialogue.current_text.length() or not dialogue.arrow_label.visible:
		_fail("dialogue action did not complete the current page")
		return
	dialogue.handle_action()
	if not dialogue.is_open() or dialogue.page_index != 1 or dialogue.visible_count != 0:
		_fail("dialogue action did not advance to the next page")
		return
	dialogue.handle_action()
	if dialogue.visible_count != dialogue.current_text.length() or not dialogue.arrow_label.visible:
		_fail("dialogue did not complete the final page")
		return
	dialogue.handle_action()
	if dialogue.is_open():
		_fail("dialogue did not close after the final page")
		return
	dialogue.show_choice(["Welcome to the POKEMON CENTER.", "Would you like to rest your POKEMON?"], [{"label": "Yes", "value": 1}, {"label": "No", "value": 0}])
	if dialogue.choice_active or (dialogue.choice_box != null and dialogue.choice_box.visible):
		_fail("yes/no appeared before the last page")
		return
	dialogue.handle_action()
	dialogue.handle_action()
	if dialogue.page_index != 1 or dialogue.choice_active:
		_fail("yes/no appeared before the question finished typing")
		return
	dialogue.handle_action()
	if not dialogue.choice_active or dialogue.choice_box == null or not dialogue.choice_box.visible:
		_fail("yes/no did not appear after the last page finished")
		return
	var previous_character: Dictionary = GameState.current_character.duplicate(true)
	var world: Control = load("res://scripts/world/world.gd").new()
	GameState.current_character = {"name": "KANTO", "rival_sex": 0}
	var resolved: Array = world.call("_resolve_dialogue_pages", ["{01}'s house", "{06}'s house", "{RIVAL}'s house"])
	if resolved != ["KANTO's house", "GREEN's house", "GREEN's house"]:
		_fail("FireRed rival placeholders did not resolve to the male default")
		return
	GameState.current_character = {"name": "KANTO", "rival_name": "BLUE", "rival_sex": 1}
	resolved = world.call("_resolve_dialogue_pages", ["{01}'s house", "{06}'s house", "{RIVAL}'s house"])
	if resolved != ["KANTO's house", "BLUE's house", "BLUE's house"]:
		_fail("FireRed rival placeholders did not preserve the stored rival name")
		return
	GameState.current_character = previous_character
	world.free()
	dialogue.free()
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
