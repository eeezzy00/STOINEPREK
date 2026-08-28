extends Node2D

const CURSOR_OFFSET_X := -34.0
const MENU_MUSIC := preload("res://Audio/Song for menu/GAMEDEV@mainthemevol1.mp3")

@onready var menu_list: VBoxContainer = $CanvasLayer/UI/MenuList
@onready var menu_cursor: Label = $CanvasLayer/UI/MenuCursor

var _cursor_tween: Tween


func _ready() -> void:
	%NewGame.grab_focus()
	for button in menu_list.get_children():
		button.mouse_entered.connect(_on_button_focus.bind(button))
		button.focus_entered.connect(_on_button_focus.bind(button))
	_snap_cursor_to(%NewGame)
	# MusicManager is an autoload -- it survives the men.tscn <-> settings.tscn
	# scene swap, so this call is a no-op (keeps playing uninterrupted) if
	# the menu track is already going, and only actually starts it fresh
	# the first time or when coming back from a level (which stops it).
	MusicManager.play_music(MENU_MUSIC)
	MusicManager.stop_ambience()


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://level.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://settings.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_button_focus(button: Button) -> void:
	_move_cursor_to(button)
	_glitch_button(button)


func _cursor_target_position(button: Button) -> Vector2:
	var rect := button.get_global_rect()
	return Vector2(rect.position.x + CURSOR_OFFSET_X, rect.position.y + rect.size.y * 0.5 - menu_cursor.size.y * 0.5)


func _snap_cursor_to(button: Button) -> void:
	menu_cursor.global_position = _cursor_target_position(button)


func _move_cursor_to(button: Button) -> void:
	var target_pos := _cursor_target_position(button)
	if _cursor_tween:
		_cursor_tween.kill()
	_cursor_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_cursor_tween.tween_property(menu_cursor, "global_position", target_pos, 0.18)


func _glitch_button(button: Button) -> void:
	var original_pos: Vector2 = button.position
	for i in range(2):
		button.position = original_pos + Vector2(randf_range(-3.0, 3.0), 0.0)
		await get_tree().create_timer(0.025).timeout
		button.position = original_pos
		await get_tree().create_timer(0.04).timeout
