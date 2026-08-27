extends Node2D


func _ready() -> void:
	%NewGame.grab_focus()
	_run_title_glitch_loop()


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://level.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _run_title_glitch_loop() -> void:
	var title := $CanvasLayer/UI/Title
	while is_instance_valid(title):
		await get_tree().create_timer(randf_range(2.5, 5.5)).timeout
		if not is_instance_valid(title):
			break
		await _glitch_title(title)


func _glitch_title(title: Label) -> void:
	var original_pos: Vector2 = title.position
	var original_outline: Color = title.get_theme_color("font_outline_color")
	for i in range(3):
		title.position = original_pos + Vector2(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0))
		title.add_theme_color_override("font_outline_color", Color(1, 1, 1))
		await get_tree().create_timer(0.03).timeout
		title.position = original_pos
		title.add_theme_color_override("font_outline_color", original_outline)
		await get_tree().create_timer(0.05).timeout
