extends CanvasLayer

## Autoload. F5 toggles a live-tuning admin panel: spawn extra Samurai NPCs
## and drag sliders to retune balance values on the fly, without editing
## code or reloading the scene. While the panel is open, player.gd and
## samurai_npc.gd freeze themselves (see AdminPanel.panel_open) -- mainly so
## clicking a slider (left mouse button is also the attack input) can't
## accidentally throw a punch.
##
## NPC sliders are a "profile": changing one immediately re-applies to every
## enemy currently in the "enemies" group AND gets stamped onto any NPC
## spawned afterward via the SPAWN button, so the whole roster stays in sync.

const ENEMY_SCENE := preload("res://samurai_npc.tscn")
const SPAWN_OFFSET := 220.0
const PRESET_DIR := "res://BAG/admin_presets"

const LEVELS := [
	{"label": "LEVEL 1", "path": "res://level.tscn"},
	{"label": "LEVEL 2", "path": "res://level2.tscn"},
	{"label": "LEVEL 3", "path": "res://level3.tscn"},
]

## Lets you preview-switch which track is playing regardless of current
## scene -- just a flat list, so adding a new track later is one more line.
const MUSIC_TRACKS := [
	{"label": "LEVEL TRACK", "path": "res://Audio/Song for lvl1/LVL1NDLVL2SONG.mp3"},
	{"label": "MENU TRACK", "path": "res://Audio/Song for menu/GAMEDEV@mainthemevol1.mp3"},
]

## key -> {label, min, max, step, default}. "key" is the exact property name
## on player.gd, except max_hp/strike_range which route through the
## dedicated setters below (direct assignment wouldn't refill HP / resize
## the hitbox shape).
const PLAYER_SLIDERS := [
	{"key": "max_hp", "label": "HP игрока", "min": 1.0, "max": 10.0, "step": 1.0, "default": 3.0},
	{"key": "move_speed", "label": "Скорость движения, px/s", "min": 50.0, "max": 500.0, "step": 10.0, "default": 250.0},
	{"key": "attack_damage", "label": "Урон атаки", "min": 0.5, "max": 5.0, "step": 0.5, "default": 1.0},
	{"key": "attack_speed", "label": "Кулдаун атаки, сек (меньше = быстрее)", "min": 0.1, "max": 1.5, "step": 0.05, "default": 0.5},
	{"key": "strike_range", "label": "Дальность удара, px", "min": 20.0, "max": 150.0, "step": 5.0, "default": 50.0},
	{"key": "jump_velocity", "label": "Сила прыжка, px/s", "min": 100.0, "max": 500.0, "step": 10.0, "default": 322.0},
	{"key": "jump_gravity", "label": "Гравитация прыжка, px/s^2", "min": 300.0, "max": 2000.0, "step": 50.0, "default": 900.0},
	{"key": "dash_distance", "label": "Дистанция рывка, px", "min": 20.0, "max": 300.0, "step": 10.0, "default": 60.0},
	{"key": "dash_cooldown", "label": "Кулдаун рывка, сек", "min": 0.2, "max": 5.0, "step": 0.1, "default": 2.0},
	{"key": "normal_hit_hitstop_frames", "label": "Хит-стоп на обычный удар, кадры", "min": 0.0, "max": 10.0, "step": 1.0, "default": 2.0},
	{"key": "parry_late_limit_frames", "label": "Окно парирования, кадры", "min": 2.0, "max": 20.0, "step": 1.0, "default": 10.0},
	{"key": "max_parry_charges", "label": "Заряды парирования", "min": 1.0, "max": 6.0, "step": 1.0, "default": 3.0},
]

const NPC_SLIDERS := [
	{"key": "max_hp", "label": "HP врага", "min": 1.0, "max": 10.0, "step": 1.0, "default": 3.0},
	{"key": "move_speed", "label": "Скорость движения, px/s", "min": 20.0, "max": 400.0, "step": 10.0, "default": 140.0},
	{"key": "attack_damage", "label": "Урон атаки", "min": 0.5, "max": 5.0, "step": 0.5, "default": 1.0},
	{"key": "attack_cooldown", "label": "Кулдаун атаки, сек", "min": 0.2, "max": 3.0, "step": 0.1, "default": 1.1},
	{"key": "detect_range", "label": "Дальность обнаружения, px", "min": 50.0, "max": 600.0, "step": 10.0, "default": 260.0},
	{"key": "attack_range", "label": "Дальность удара, px", "min": 20.0, "max": 150.0, "step": 5.0, "default": 46.0},
	{"key": "dodge_chance", "label": "Шанс защитного уворота (при угрозе)", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.35},
	{"key": "dodge_distance", "label": "Дистанция уворота, px", "min": 10.0, "max": 150.0, "step": 5.0, "default": 60.0},
	{"key": "flank_chance", "label": "Шанс обходного манёвра (заход за спину)", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.3},
	{"key": "flank_range", "label": "Дальность обходного манёвра, px", "min": 30.0, "max": 300.0, "step": 10.0, "default": 160.0},
]

var panel_open := false

## Checked by player.gd/samurai_npc.gd's take_damage() -- true means every
## hit is a no-op (same code path as being invincible mid-dash/mid-dodge).
var player_invincible := false
var npc_invincible := false
## Checked by samurai_npc.gd's _physics_process -- true means every enemy
## just stands there (idle, no chase/attack/dodge/flank), but can still be
## hit and killed normally.
var npc_afk := false

## Current NPC slider values, applied to every enemy in the scene and
## stamped onto anything spawned afterward.
var _npc_overrides := {}
## Current player slider values, kept only for SAVE PRESET (each slider
## already applies itself straight to the live player on change).
var _player_values := {}

var _font: Font
var _panel_root: Control
var _preset_status_label: Label
var _music_toggle: CheckButton
var _all_sliders: Array = []  # [{slider: HSlider, default: float}]


func _ready() -> void:
	layer = 30
	_font = _make_font()
	for row in NPC_SLIDERS:
		_npc_overrides[row["key"]] = row["default"]
	for row in PLAYER_SLIDERS:
		_player_values[row["key"]] = row["default"]
	_build_ui()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		_toggle()


func _toggle() -> void:
	panel_open = not panel_open
	_panel_root.visible = panel_open


func _make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "Courier New", "Lucida Console", "monospace"])
	return f


func _build_ui() -> void:
	_panel_root = Control.new()
	_panel_root.visible = false
	_panel_root.anchor_left = 1.0
	_panel_root.anchor_right = 1.0
	_panel_root.anchor_top = 0.0
	_panel_root.anchor_bottom = 1.0
	_panel_root.offset_left = -340.0
	_panel_root.offset_right = 0.0
	add_child(_panel_root)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.05, 0.92)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	_panel_root.add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 8.0
	scroll.offset_right = -8.0
	scroll.offset_top = 8.0
	scroll.offset_bottom = -8.0
	_panel_root.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(316.0, 0.0)
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	_add_header(vbox, "ADMIN PANEL (F5)")
	_add_spawn_button(vbox)
	_add_reset_button(vbox)
	_add_save_preset_button(vbox)

	_add_header(vbox, "LEVELS")
	for entry in LEVELS:
		_add_level_button(vbox, entry["label"], entry["path"])

	_add_header(vbox, "AUDIO")
	_music_toggle = _add_toggle(vbox, "МУЗЫКА", MusicManager.music_enabled, func(v: bool): MusicManager.set_music_enabled(v))
	_add_toggle(vbox, "ЭМБИЕНТ ГОРОДА", MusicManager.ambience_enabled, func(v: bool): MusicManager.set_ambience_enabled(v))
	for entry in MUSIC_TRACKS:
		_add_music_track_button(vbox, entry["label"], entry["path"])

	_add_header(vbox, "CHEATS")
	_add_toggle(vbox, "БЕССМЕРТИЕ ИГРОКА", player_invincible, func(v: bool): player_invincible = v)
	_add_toggle(vbox, "БЕССМЕРТИЕ NPC", npc_invincible, func(v: bool): npc_invincible = v)
	_add_toggle(vbox, "NPC АФК (не агрятся, стоят)", npc_afk, func(v: bool): npc_afk = v)

	_add_header(vbox, "PLAYER")
	for row in PLAYER_SLIDERS:
		_add_slider(vbox, row, func(key: String, value: float): _apply_player_value(key, value))

	_add_header(vbox, "NPC (все враги + новые)")
	for row in NPC_SLIDERS:
		_add_slider(vbox, row, func(key: String, value: float): _apply_npc_override(key, value))


func _add_header(vbox: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(1, 0.18, 0.66, 1))
	vbox.add_child(lbl)


func _add_spawn_button(vbox: VBoxContainer) -> void:
	var btn := Button.new()
	btn.text = "SPAWN SAMURAI NPC"
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(_spawn_npc)
	vbox.add_child(btn)


func _add_reset_button(vbox: VBoxContainer) -> void:
	var btn := Button.new()
	btn.text = "RESET SLIDERS TO DEFAULTS"
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(_reset_all_sliders)
	vbox.add_child(btn)


func _add_save_preset_button(vbox: VBoxContainer) -> void:
	var btn := Button.new()
	btn.text = "SAVE PRESET"
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(_save_preset)
	vbox.add_child(btn)

	_preset_status_label = Label.new()
	_preset_status_label.add_theme_font_override("font", _font)
	_preset_status_label.add_theme_font_size_override("font_size", 11)
	_preset_status_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.6, 1))
	_preset_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_preset_status_label)


func _add_level_button(vbox: VBoxContainer, label_text: String, path: String) -> void:
	var btn := Button.new()
	btn.text = label_text
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(func(): _go_to_level(path))
	vbox.add_child(btn)


## Closes the panel on switch -- otherwise the new level would load already
## frozen (see the panel_open freeze in player.gd/samurai_npc.gd) with no
## obvious reason why, since F5 wasn't pressed again for this scene.
func _go_to_level(path: String) -> void:
	panel_open = false
	if _panel_root:
		_panel_root.visible = false
	get_tree().change_scene_to_file(path)


## Previewing a track forces music back on -- otherwise clicking one while
## the MUSIC toggle is off would silently do nothing audible, which reads
## as broken rather than muted.
func _add_music_track_button(vbox: VBoxContainer, label_text: String, path: String) -> void:
	var btn := Button.new()
	btn.text = label_text
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(func():
		if _music_toggle:
			_music_toggle.button_pressed = true
		MusicManager.set_music_enabled(true)
		MusicManager.play_music(load(path))
	)
	vbox.add_child(btn)


func _add_toggle(vbox: VBoxContainer, label_text: String, initial: bool, on_toggle: Callable) -> CheckButton:
	var btn := CheckButton.new()
	btn.text = label_text
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 13)
	btn.button_pressed = initial
	btn.toggled.connect(on_toggle)
	vbox.add_child(btn)
	return btn


## Builds one labeled slider row. on_change is called with (key, new_value)
## every time the slider moves, including the very first layout pass so
## whatever's currently running matches the slider's starting position.
func _add_slider(vbox: VBoxContainer, row: Dictionary, on_change: Callable) -> void:
	var key: String = row["key"]
	var label_text: String = row["label"]

	var lbl := Label.new()
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 1))
	vbox.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = row["min"]
	slider.max_value = row["max"]
	slider.step = row["step"]
	slider.value = row["default"]
	slider.custom_minimum_size = Vector2(300.0, 20.0)
	vbox.add_child(slider)

	var refresh_label := func():
		lbl.text = "%s: %s" % [label_text, _fmt(slider.value)]
	refresh_label.call()

	slider.value_changed.connect(func(value: float):
		refresh_label.call()
		on_change.call(key, value)
	)

	_all_sliders.append({"slider": slider, "default": row["default"]})


func _fmt(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(round(v)))
	return "%.2f" % v


func _reset_all_sliders() -> void:
	for entry in _all_sliders:
		entry["slider"].value = entry["default"]


## Writes the current slider/toggle state to its own timestamped file under
## BAG/admin_presets, separate from telemetry run logs -- so multiple tuning
## passes can be saved side by side and compared later. Doesn't touch the
## live game; this is a snapshot, not a save/load system.
func _save_preset() -> void:
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	var d := Time.get_datetime_dict_from_system()
	var stamp := "%04d%02d%02d_%02d%02d%02d" % [d.year, d.month, d.day, d.hour, d.minute, d.second]
	var path := "%s/preset_%s.json" % [PRESET_DIR, stamp]

	var data := {
		"timestamp": stamp,
		"player": _player_values,
		"npc": _npc_overrides,
		"cheats": {
			"player_invincible": player_invincible,
			"npc_invincible": npc_invincible,
			"npc_afk": npc_afk,
		},
	}

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		if _preset_status_label:
			_preset_status_label.text = "FAILED TO SAVE PRESET"
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

	if _preset_status_label:
		_preset_status_label.text = "saved: admin_presets/preset_%s.json" % stamp


func _get_player() -> Node:
	return get_tree().get_first_node_in_group("player")


func _apply_player_value(key: String, value: float) -> void:
	_player_values[key] = value
	var player := _get_player()
	if player == null:
		return
	match key:
		"max_hp":
			player.set_max_hp(value)
		"strike_range":
			player.set_strike_range(value)
		"max_parry_charges":
			player.max_parry_charges = int(value)
		_:
			player.set(key, value)


func _apply_npc_override(key: String, value: float) -> void:
	_npc_overrides[key] = value
	for enemy in get_tree().get_nodes_in_group("enemies"):
		_apply_one_npc_value(enemy, key, value)


func _apply_one_npc_value(enemy: Node, key: String, value: float) -> void:
	match key:
		"max_hp":
			enemy.set_max_hp(value)
		"attack_range":
			enemy.set_attack_range(value)
		_:
			enemy.set(key, value)


func _spawn_npc() -> void:
	var player := _get_player()
	if player == null:
		return

	var enemy := ENEMY_SCENE.instantiate()
	var facing_offset := -SPAWN_OFFSET if player.sprite.flip_h else SPAWN_OFFSET
	enemy.global_position = player.global_position + Vector2(facing_offset, 0.0)
	enemy.add_to_group("enemies")

	var level := get_tree().get_first_node_in_group("level")
	var parent: Node = level if level else get_tree().current_scene
	parent.add_child(enemy)

	for key in _npc_overrides.keys():
		_apply_one_npc_value(enemy, key, _npc_overrides[key])

	if level and level.has_method("register_enemy"):
		level.register_enemy(enemy)
