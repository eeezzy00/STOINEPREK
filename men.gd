extends Node2D

const CURSOR_OFFSET_X := -34.0
const MENU_MUSIC := preload("res://Audio/Song for menu/GAMEDEV@mainthemevol1.mp3")

## Selected-state icon per menu button (see assets/MYASSETS/main menu/).
## The "not selected" counterpart isn't listed here: _ready() reads it
## straight back from whatever's already set on each button's Icon child in
## the .tscn (see _idle_icons below), so there's only one place (the .tscn)
## that names the idle texture per button.
const SELECTED_ICONS := {
	"NewGame": preload("res://assets/MYASSETS/main menu/selected/NEWGAMESELECT3.png"),
	"Continue": preload("res://assets/MYASSETS/main menu/selected/continueselect3.png"),
	"Settings": preload("res://assets/MYASSETS/main menu/selected/settingsselect3.png"),
	"Quit": preload("res://assets/MYASSETS/main menu/selected/exitselect3.png"),
}

@onready var menu_list: VBoxContainer = $CanvasLayer/UI/MenuList
@onready var menu_cursor: Label = $CanvasLayer/UI/MenuCursor
@onready var sfx_hover: AudioStreamPlayer = $SfxHover
@onready var sfx_click: AudioStreamPlayer = $SfxClick

var _cursor_tween: Tween
## Whichever button currently owns the cursor/glitch/icon-highlight -- lets
## _on_button_focus tell "still the same button, ignore" (mouse_entered and
## focus_entered can both fire for one hover, e.g. a click both enters and
## focuses) from "actually moved to a new button".
var _current_button: Button
## button name -> its Icon child's "not selected" texture, captured once in
## _ready() from the .tscn instead of duplicated as a second constant here.
var _idle_icons := {}


func _ready() -> void:
	for button_name in SELECTED_ICONS:
		var icon: TextureRect = menu_list.get_node(button_name).get_node("Icon")
		_idle_icons[button_name] = icon.texture

	%NewGame.grab_focus()
	for button in menu_list.get_children():
		button.mouse_entered.connect(_on_button_focus.bind(button))
		button.focus_entered.connect(_on_button_focus.bind(button))
	_snap_cursor_to(%NewGame)
	# Seeds the initial highlight without going through _on_button_focus --
	# grab_focus() above fires before these signals are even connected, and
	# this is the menu opening, not a user hovering, so it shouldn't play
	# the hover sound either.
	_current_button = %NewGame
	_set_icon(%NewGame, true)
	# MusicManager is an autoload -- it survives the men.tscn <-> settings.tscn
	# scene swap, so this call is a no-op (keeps playing uninterrupted) if
	# the menu track is already going, and only actually starts it fresh
	# the first time or when coming back from a level (which stops it).
	MusicManager.play_music(MENU_MUSIC)
	MusicManager.stop_ambience()


func _on_new_game_pressed() -> void:
	_release_click_sfx()
	get_tree().change_scene_to_file("res://level.tscn")


func _on_settings_pressed() -> void:
	_release_click_sfx()
	get_tree().change_scene_to_file("res://settings.tscn")


## quit() ends the process almost immediately -- unlike the scene-change
## cases above, there's no "let it keep playing in the background" option,
## so this is the one caller that actually waits out the confirm sound
## instead of just releasing it.
func _on_quit_pressed() -> void:
	sfx_click.play()
	await sfx_click.finished
	get_tree().quit()


## sfx_click is a child of this Men node, so the instant a caller above
## swaps scenes, freeing this whole scene would cut the (1.75s) confirm
## sound off before it's audible -- MusicManager exists as an autoload for
## exactly this reason on the continuous tracks, but a one-shot SFX doesn't
## need a whole persistent manager: reparenting it under the tree root lets
## it survive this scene's teardown and finish playing on its own, then
## free itself once done.
func _release_click_sfx() -> void:
	sfx_click.get_parent().remove_child(sfx_click)
	get_tree().root.add_child(sfx_click)
	sfx_click.play()
	sfx_click.finished.connect(sfx_click.queue_free)


## Fires on mouse hover and keyboard focus alike (both connected the same
## way in _ready()) -- deduped via _current_button so the two signals
## overlapping on one real hover (e.g. clicking a button both enters and
## focuses it) don't double up the cursor move / glitch / hover sound.
func _on_button_focus(button: Button) -> void:
	if button == _current_button:
		return
	if _current_button != null:
		_set_icon(_current_button, false)
	_current_button = button
	_set_icon(button, true)
	_move_cursor_to(button)
	_glitch_button(button)
	sfx_hover.play()


## No-op for any button not in SELECTED_ICONS/_idle_icons -- lets a future
## text-only button (no icon art yet) coexist without special-casing it here.
func _set_icon(button: Button, selected: bool) -> void:
	var button_name: String = str(button.name)
	if not _idle_icons.has(button_name):
		return
	var icon: TextureRect = button.get_node("Icon")
	icon.texture = SELECTED_ICONS[button_name] if selected else _idle_icons[button_name]


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


func _on_new_game_minimum_size_changed() -> void:
	pass # Replace with function body.
