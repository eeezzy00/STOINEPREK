extends CanvasLayer

## Player-child HUD. Also owns the balance-preset save/load tool: F6 opens a
## save-as-name prompt, F7 opens a list of saved presets to load instantly
## (no scene reload). Presets live in user://presets/ as plain JSON so they
## survive between sessions and can be copied/shared as files.

const PRESET_DIR := "user://presets/"
const DEFAULT_PRESET := "default"

## key -> player property name. This is the exact field list requested:
## HP, damage, attack speed, move speed, dash cooldown, parry window,
## gravity, jump force.
const PRESET_FIELDS := [
	"max_hp", "attack_damage", "attack_speed", "move_speed",
	"dash_cooldown", "parry_late_limit_frames", "jump_gravity", "jump_velocity",
]

@onready var label: Label = $Panel/Label

var _player: Node
var _font: Font

var _save_layer: CanvasLayer
var _save_name_edit: LineEdit
var _load_layer: CanvasLayer
var _load_list: VBoxContainer


func _ready() -> void:
	layer = 10
	_player = get_parent()
	_font = _make_font()
	_build_save_ui()
	_build_load_ui()
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	if not FileAccess.file_exists(PRESET_DIR + DEFAULT_PRESET + ".json"):
		_save_preset(DEFAULT_PRESET)


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var dash_cd: float = _player.get_dash_cooldown()
	var dash_status := "READY" if dash_cd <= 0.0 else "COOLDOWN"
	label.text = ("HP: %s / %s\nDMG: %s\nATK SPD: %.2fs\nMOVE SPD: %d px/s\nDASH CD: %.1fs [%s]\n" +
		"PARRIES: %d\nPARRY CHARGES: %d / %d\nPARRY STREAK: %d\nLAST PARRY: %s\n" +
		"[F6 SAVE PRESET] [F7 LOAD PRESET]") % [
		_fmt(_player.current_hp),
		_fmt(_player.max_hp),
		_fmt(_player.attack_damage),
		_player.attack_speed,
		int(_player.move_speed),
		dash_cd,
		dash_status,
		_player.parries_count,
		_player.parry_charges,
		_player.max_parry_charges,
		_player.parry_streak,
		_player.last_parry_result,
	]


func _fmt(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(round(v)))
	return "%.1f" % v


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F6:
			_open_save_ui()
		elif event.keycode == KEY_F7:
			_open_load_ui()
		elif event.keycode == KEY_ESCAPE:
			_save_layer.visible = false
			_load_layer.visible = false


func _make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "Courier New", "Lucida Console", "monospace"])
	return f


# --- Save ---------------------------------------------------------------

func _build_save_ui() -> void:
	_save_layer = CanvasLayer.new()
	_save_layer.layer = 25
	_save_layer.visible = false
	add_child(_save_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.03, 0.85)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	_save_layer.add_child(dim)

	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -140.0
	box.offset_right = 140.0
	box.offset_top = -30.0
	box.add_theme_constant_override("separation", 10)
	_save_layer.add_child(box)

	var title := Label.new()
	title.text = "SAVE PRESET AS:"
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1, 0.18, 0.66, 1))
	box.add_child(title)

	_save_name_edit = LineEdit.new()
	_save_name_edit.placeholder_text = "preset name"
	_save_name_edit.add_theme_font_override("font", _font)
	_save_name_edit.text_submitted.connect(func(_t: String): _confirm_save())
	box.add_child(_save_name_edit)

	var confirm_btn := Button.new()
	confirm_btn.text = "SAVE (Enter)"
	confirm_btn.add_theme_font_override("font", _font)
	confirm_btn.pressed.connect(_confirm_save)
	box.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL (Esc)"
	cancel_btn.add_theme_font_override("font", _font)
	cancel_btn.pressed.connect(func(): _save_layer.visible = false)
	box.add_child(cancel_btn)


func _open_save_ui() -> void:
	_load_layer.visible = false
	_save_layer.visible = true
	_save_name_edit.text = ""
	_save_name_edit.grab_focus()


func _confirm_save() -> void:
	var preset_name := _save_name_edit.text.strip_edges()
	if preset_name == "":
		return
	_save_preset(preset_name)
	_save_layer.visible = false


func _save_preset(preset_name: String) -> void:
	if _player == null:
		return
	var data := {}
	for field in PRESET_FIELDS:
		data[field] = _player.get(field)
	var f := FileAccess.open(PRESET_DIR + preset_name + ".json", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


# --- Load -----------------------------------------------------------------

func _build_load_ui() -> void:
	_load_layer = CanvasLayer.new()
	_load_layer.layer = 25
	_load_layer.visible = false
	add_child(_load_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.03, 0.85)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	_load_layer.add_child(dim)

	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -140.0
	box.offset_right = 140.0
	box.offset_top = -80.0
	box.add_theme_constant_override("separation", 8)
	_load_layer.add_child(box)

	var title := Label.new()
	title.text = "LOAD PRESET:"
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1, 0.18, 0.66, 1))
	box.add_child(title)

	_load_list = VBoxContainer.new()
	_load_list.add_theme_constant_override("separation", 4)
	box.add_child(_load_list)

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL (Esc)"
	cancel_btn.add_theme_font_override("font", _font)
	cancel_btn.pressed.connect(func(): _load_layer.visible = false)
	box.add_child(cancel_btn)


func _open_load_ui() -> void:
	_save_layer.visible = false
	for child in _load_list.get_children():
		child.queue_free()

	var names := _list_preset_names()
	if names.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "(no presets saved yet)"
		empty_lbl.add_theme_font_override("font", _font)
		_load_list.add_child(empty_lbl)
	else:
		for preset_name in names:
			var btn := Button.new()
			btn.text = preset_name
			btn.add_theme_font_override("font", _font)
			btn.pressed.connect(func(): _load_preset(preset_name))
			_load_list.add_child(btn)

	_load_layer.visible = true
	if _load_list.get_child_count() > 0 and _load_list.get_child(0) is Button:
		_load_list.get_child(0).grab_focus()


func _list_preset_names() -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(PRESET_DIR)
	if dir == null:
		return names
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json"):
			names.append(f.trim_suffix(".json"))
		f = dir.get_next()
	names.sort()
	return names


func _load_preset(preset_name: String) -> void:
	if _player == null:
		return
	var text := FileAccess.get_file_as_string(PRESET_DIR + preset_name + ".json")
	var data = JSON.parse_string(text)
	if data == null:
		return
	for field in PRESET_FIELDS:
		if data.has(field):
			_player.set(field, data[field])
	# max_hp needs the dedicated setter to also refill current_hp and the
	# health bar -- a raw property set wouldn't touch either.
	if data.has("max_hp"):
		_player.set_max_hp(data["max_hp"])
	_load_layer.visible = false
