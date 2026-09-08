extends SceneTree

const HUD_SCRIPT: GDScript = preload("res://scripts/world/hud.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var hud = HUD_SCRIPT.new()
	get_root().add_child(hud)
	var menu_margin: MarginContainer = hud.menu_panel.get_child(0) as MarginContainer
	var menu_box: VBoxContainer = menu_margin.get_child(0) as VBoxContainer
	var labels: PackedStringArray = PackedStringArray()
	for child in menu_box.get_children():
		labels.append((child as Button).text)
	if labels != PackedStringArray(["Return", "Settings", "FAQ", "Support Request", "Logout", "Exit"]):
		push_error("PokeMMO escape menu button order is incorrect")
		quit(1)
		return
	hud.handle_escape()
	if not hud.menu_open or not hud.menu_panel.visible:
		push_error("Escape did not open the menu")
		quit(1)
		return
	hud.handle_escape()
	if hud.menu_open or hud.menu_panel.visible:
		push_error("Escape did not close the menu")
		quit(1)
		return
	hud.queue_free()
	quit(0)
