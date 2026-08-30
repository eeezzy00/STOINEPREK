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
## Fixed filename (not timestamped like the snapshots SAVE PRESET writes) --
## loaded automatically by every future _ready() if present, so "SAVE AS
## DEFAULT" actually changes what a fresh session starts with.
const DEFAULT_PRESET_PATH := PRESET_DIR + "/default.json"

const LEVELS := [
	{"label": "LEVEL 1", "path": "res://level.tscn"},
	{"label": "LEVEL 2", "path": "res://level2.tscn"},
	{"label": "LEVEL 3", "path": "res://level3.tscn"},
	{"label": "LEVEL 4", "path": "res://level4.tscn"},
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
## var, not const: _load_default_preset_into_slider_defaults() mutates each
## row's "default" entry in place after SAVE AS DEFAULT -- a const array's
## nested Dictionaries are read-only in GDScript, so const here would throw
## on that very first write.
var PLAYER_SLIDERS := [
	{"key": "max_hp", "label": "HP игрока", "min": 1.0, "max": 10.0, "step": 1.0, "default": 3.0},
	{"key": "move_speed", "label": "Скорость движения, px/s", "min": 50.0, "max": 500.0, "step": 10.0, "default": 250.0},
	{"key": "attack_damage", "label": "Урон атаки", "min": 0.5, "max": 5.0, "step": 0.5, "default": 1.0},
	{"key": "attack_speed", "label": "Кулдаун атаки, сек (меньше = быстрее)", "min": 0.1, "max": 1.5, "step": 0.05, "default": 0.5},
	{"key": "strike_range", "label": "Дальность удара, px", "min": 20.0, "max": 150.0, "step": 5.0, "default": 50.0},
	{"key": "jump_velocity", "label": "Сила прыжка, px/s", "min": 100.0, "max": 500.0, "step": 10.0, "default": 445.0},
	{"key": "jump_gravity", "label": "Гравитация, px/s^2", "min": 300.0, "max": 2000.0, "step": 50.0, "default": 900.0},
	{"key": "max_fall_speed", "label": "Макс. скорость падения, px/s", "min": 400.0, "max": 3000.0, "step": 50.0, "default": 1400.0},
	{"key": "coyote_time", "label": "Coyote time (прыжок с обрыва), сек", "min": 0.0, "max": 0.3, "step": 0.01, "default": 0.1},
	{"key": "jump_buffer_time", "label": "Буфер прыжка, сек", "min": 0.0, "max": 0.3, "step": 0.01, "default": 0.1},
	{"key": "dash_distance", "label": "Дистанция рывка, px", "min": 20.0, "max": 300.0, "step": 10.0, "default": 60.0},
	{"key": "dash_duration", "label": "Длительность рывка, сек", "min": 0.05, "max": 0.6, "step": 0.05, "default": 0.2},
	{"key": "dash_cooldown", "label": "Кулдаун рывка, сек", "min": 0.2, "max": 5.0, "step": 0.1, "default": 2.0},
	{"key": "normal_hit_hitstop_frames", "label": "Хит-стоп на обычный удар, кадры", "min": 0.0, "max": 10.0, "step": 1.0, "default": 2.0},
	{"key": "parry_late_limit_frames", "label": "Окно парирования, кадры", "min": 2.0, "max": 20.0, "step": 1.0, "default": 10.0},
	{"key": "max_parry_charges", "label": "Заряды парирования", "min": 1.0, "max": 6.0, "step": 1.0, "default": 3.0},
	{"key": "parry_regen_interval", "label": "Восст. заряда парирования, сек", "min": 0.5, "max": 10.0, "step": 0.5, "default": 3.0},
	{"key": "perfect_streak_for_bonus", "label": "Серия PERFECT для бонус-урона", "min": 1.0, "max": 10.0, "step": 1.0, "default": 3.0},
	{"key": "wall_slide_speed", "label": "Скорость слайда по стене, px/s", "min": 20.0, "max": 400.0, "step": 10.0, "default": 90.0},
	{"key": "wall_jump_speed_x", "label": "Отпрыг от стены X, px/s", "min": 100.0, "max": 700.0, "step": 10.0, "default": 380.0},
	{"key": "wall_jump_speed_y", "label": "Отпрыг от стены Y, px/s", "min": 100.0, "max": 700.0, "step": 10.0, "default": 420.0},
	{"key": "wall_jump_control_lock", "label": "Блок управления после отпрыга, сек", "min": 0.0, "max": 0.5, "step": 0.01, "default": 0.15},
	{"key": "wall_coyote_time", "label": "Coyote time у стены, сек", "min": 0.0, "max": 0.3, "step": 0.01, "default": 0.1},
	{"key": "attack_active_duration", "label": "Окно попадания удара, сек", "min": 0.02, "max": 0.4, "step": 0.01, "default": 0.12},
	{"key": "sweet_spot_ratio", "label": "Доля окна = sweet spot", "min": 0.05, "max": 1.0, "step": 0.05, "default": 0.35},
	{"key": "sweet_spot_damage_multiplier", "label": "Множитель урона sweet spot", "min": 1.0, "max": 3.0, "step": 0.1, "default": 1.5},
	{"key": "late_hit_damage_multiplier", "label": "Множитель урона поздний хит", "min": 0.1, "max": 1.0, "step": 0.05, "default": 0.75},
]

## "cat" is "combat" or "ai" -- splits this one list across the two NPC tabs
## in the panel (see _build_ui) without needing two separate arrays (which
## would also mean two separate places to keep _npc_overrides/defaults in sync).
var NPC_SLIDERS := [
	{"key": "max_hp", "label": "HP врага", "min": 1.0, "max": 10.0, "step": 1.0, "default": 3.0, "cat": "combat"},
	{"key": "move_speed", "label": "Скорость движения, px/s", "min": 20.0, "max": 400.0, "step": 10.0, "default": 140.0, "cat": "combat"},
	{"key": "attack_damage", "label": "Урон атаки", "min": 0.5, "max": 5.0, "step": 0.5, "default": 1.0, "cat": "combat"},
	{"key": "attack_cooldown", "label": "Кулдаун атаки, сек", "min": 0.2, "max": 3.0, "step": 0.1, "default": 1.1, "cat": "combat"},
	{"key": "attack_startup", "label": "Замах перед ударом, сек", "min": 0.05, "max": 0.6, "step": 0.05, "default": 0.15, "cat": "combat"},
	{"key": "attack_range", "label": "Дальность удара, px", "min": 20.0, "max": 150.0, "step": 5.0, "default": 46.0, "cat": "combat"},
	{"key": "parry_stun_duration", "label": "Стан после парирования, сек", "min": 0.1, "max": 2.0, "step": 0.05, "default": 0.55, "cat": "combat"},
	{"key": "attack_active_duration", "label": "Окно попадания удара, сек", "min": 0.02, "max": 0.4, "step": 0.01, "default": 0.12, "cat": "combat"},
	{"key": "sweet_spot_ratio", "label": "Доля окна = sweet spot", "min": 0.05, "max": 1.0, "step": 0.05, "default": 0.35, "cat": "combat"},
	{"key": "sweet_spot_damage_multiplier", "label": "Множитель урона sweet spot", "min": 1.0, "max": 3.0, "step": 0.1, "default": 1.5, "cat": "combat"},
	{"key": "late_hit_damage_multiplier", "label": "Множитель урона поздний хит", "min": 0.1, "max": 1.0, "step": 0.05, "default": 0.75, "cat": "combat"},
	{"key": "dodge_chance", "label": "Шанс защитного уворота (при угрозе)", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.35, "cat": "combat"},
	{"key": "dodge_distance", "label": "Дистанция уворота, px", "min": 10.0, "max": 150.0, "step": 5.0, "default": 60.0, "cat": "combat"},
	{"key": "dodge_duration", "label": "Длительность уворота, сек", "min": 0.05, "max": 0.5, "step": 0.05, "default": 0.15, "cat": "combat"},
	{"key": "dodge_cooldown", "label": "Кулдаун уворота, сек", "min": 0.2, "max": 5.0, "step": 0.1, "default": 1.5, "cat": "combat"},
	{"key": "dodge_danger_range", "label": "Дальность реакции на замах игрока, px", "min": 30.0, "max": 300.0, "step": 10.0, "default": 90.0, "cat": "combat"},
	{"key": "flank_chance", "label": "Шанс обходного манёвра (заход за спину)", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.3, "cat": "combat"},
	{"key": "flank_range", "label": "Дальность обходного манёвра, px", "min": 30.0, "max": 300.0, "step": 10.0, "default": 160.0, "cat": "combat"},
	{"key": "detect_range", "label": "Дальность обнаружения, px", "min": 50.0, "max": 900.0, "step": 10.0, "default": 260.0, "cat": "ai"},
	{"key": "vision_angle_degrees", "label": "Угол обзора (конус), °", "min": 10.0, "max": 180.0, "step": 5.0, "default": 55.0, "cat": "ai"},
	{"key": "memory_duration", "label": "Память после потери из виду, сек", "min": 0.5, "max": 10.0, "step": 0.5, "default": 3.0, "cat": "ai"},
	{"key": "scan_interval", "label": "Озирание по сторонам, сек", "min": 0.1, "max": 3.0, "step": 0.1, "default": 0.6, "cat": "ai"},
	{"key": "alert_call_range", "label": "Радиус тревоги союзникам, px", "min": 0.0, "max": 600.0, "step": 20.0, "default": 220.0, "cat": "ai"},
	{"key": "jump_velocity", "label": "Сила прыжка через провал, px/s", "min": 100.0, "max": 700.0, "step": 10.0, "default": 420.0, "cat": "ai"},
	{"key": "max_jump_gap", "label": "Макс. дистанция прыжка, px", "min": 50.0, "max": 500.0, "step": 10.0, "default": 200.0, "cat": "ai"},
	{"key": "think_duration_min", "label": "Пауза-\"думает\" мин, сек", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.15, "cat": "ai"},
	{"key": "think_duration_max", "label": "Пауза-\"думает\" макс, сек", "min": 0.0, "max": 2.0, "step": 0.05, "default": 0.4, "cat": "ai"},
	{"key": "patrol_radius", "label": "Радиус патрулирования, px", "min": 0.0, "max": 500.0, "step": 10.0, "default": 150.0, "cat": "ai"},
	{"key": "patrol_speed_ratio", "label": "Скорость патрулирования (доля от бега)", "min": 0.1, "max": 1.0, "step": 0.05, "default": 0.5, "cat": "ai"},
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
var _player_invincible_toggle: CheckButton
var _npc_invincible_toggle: CheckButton
var _npc_afk_toggle: CheckButton
var _load_list_vbox: VBoxContainer
var _all_sliders: Array = []  # [{slider: HSlider, default: float, key: String, group: String}]


func _ready() -> void:
	layer = 30
	_font = _make_font()
	_load_default_preset_into_slider_defaults()
	for row in NPC_SLIDERS:
		_npc_overrides[row["key"]] = row["default"]
	for row in PLAYER_SLIDERS:
		_player_values[row["key"]] = row["default"]
	_build_ui()


## If SAVE AS DEFAULT was ever used, overwrite each slider row's "default"
## value with what was saved -- PLAYER_SLIDERS/NPC_SLIDERS are const arrays,
## but the Dictionaries inside them are still mutable objects, so this
## mutation persists for every level load this session (each _ready() call
## re-reads these same rows). Falls through silently if nothing was ever
## saved as default -- the hardcoded values in the arrays above just stay.
func _load_default_preset_into_slider_defaults() -> void:
	var data := _read_preset_file(DEFAULT_PRESET_PATH)
	if data.is_empty():
		return
	var player_data: Dictionary = data.get("player", {})
	for row in PLAYER_SLIDERS:
		if row["key"] in player_data:
			row["default"] = player_data[row["key"]]
	var npc_data: Dictionary = data.get("npc", {})
	for row in NPC_SLIDERS:
		if row["key"] in npc_data:
			row["default"] = npc_data[row["key"]]


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
	_panel_root.offset_left = -360.0
	_panel_root.offset_right = 0.0
	add_child(_panel_root)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.05, 0.92)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	_panel_root.add_child(bg)

	var title := Label.new()
	title.text = "ADMIN PANEL (F5)"
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1, 0.18, 0.66, 1))
	title.offset_left = 8.0
	title.offset_top = 4.0
	_panel_root.add_child(title)

	var tabs := TabContainer.new()
	tabs.anchor_right = 1.0
	tabs.anchor_bottom = 1.0
	tabs.offset_left = 4.0
	tabs.offset_right = -4.0
	tabs.offset_top = 28.0
	tabs.offset_bottom = -4.0
	tabs.tabs_rearrange_group = -1
	_panel_root.add_child(tabs)

	var general_tab := _make_tab(tabs, "Общее")
	_add_spawn_button(general_tab)
	_add_reset_button(general_tab)
	_add_header(general_tab, "LEVELS")
	for entry in LEVELS:
		_add_level_button(general_tab, entry["label"], entry["path"])
	_add_header(general_tab, "CHEATS")
	_player_invincible_toggle = _add_toggle(general_tab, "БЕССМЕРТИЕ ИГРОКА", player_invincible, func(v: bool): player_invincible = v)
	_npc_invincible_toggle = _add_toggle(general_tab, "БЕССМЕРТИЕ NPC", npc_invincible, func(v: bool): npc_invincible = v)
	_npc_afk_toggle = _add_toggle(general_tab, "NPC АФК (не агрятся, стоят)", npc_afk, func(v: bool): npc_afk = v)

	var presets_tab := _make_tab(tabs, "Пресеты")
	_add_save_preset_button(presets_tab)
	_add_save_default_button(presets_tab)
	var load_toggle_btn := Button.new()
	load_toggle_btn.text = "LOAD PRESET..."
	load_toggle_btn.add_theme_font_override("font", _font)
	load_toggle_btn.add_theme_font_size_override("font_size", 14)
	presets_tab.add_child(load_toggle_btn)
	_load_list_vbox = VBoxContainer.new()
	_load_list_vbox.visible = false
	_load_list_vbox.add_theme_constant_override("separation", 4)
	presets_tab.add_child(_load_list_vbox)
	load_toggle_btn.pressed.connect(func():
		_load_list_vbox.visible = not _load_list_vbox.visible
		if _load_list_vbox.visible:
			_refresh_load_list()
	)

	var player_tab := _make_tab(tabs, "Игрок")
	for row in PLAYER_SLIDERS:
		_add_slider(player_tab, row, "player", func(key: String, value: float): _apply_player_value(key, value))

	var npc_combat_tab := _make_tab(tabs, "Враги - Бой")
	for row in NPC_SLIDERS:
		if row["cat"] == "combat":
			_add_slider(npc_combat_tab, row, "npc", func(key: String, value: float): _apply_npc_override(key, value))

	var npc_ai_tab := _make_tab(tabs, "Враги - ИИ")
	for row in NPC_SLIDERS:
		if row["cat"] == "ai":
			_add_slider(npc_ai_tab, row, "npc", func(key: String, value: float): _apply_npc_override(key, value))

	var audio_tab := _make_tab(tabs, "Звук")
	_music_toggle = _add_toggle(audio_tab, "МУЗЫКА", MusicManager.music_enabled, func(v: bool): MusicManager.set_music_enabled(v))
	_add_toggle(audio_tab, "ЭМБИЕНТ ГОРОДА", MusicManager.ambience_enabled, func(v: bool): MusicManager.set_ambience_enabled(v))
	for entry in MUSIC_TRACKS:
		_add_music_track_button(audio_tab, entry["label"], entry["path"])

	var debug_tab := _make_tab(tabs, "Отладка")
	_add_header(debug_tab, "КОНУС ОБЗОРА (F1)")
	_add_slider(debug_tab, {"key": "cone_offset_x", "label": "Смещение X, px", "min": -150.0, "max": 150.0, "step": 5.0, "default": 0.0}, "debug",
		func(_key: String, value: float): DebugVisualizer.vision_cone_offset.x = value)
	_add_slider(debug_tab, {"key": "cone_offset_y", "label": "Смещение Y, px (+ вниз)", "min": -150.0, "max": 150.0, "step": 5.0, "default": 25.0}, "debug",
		func(_key: String, value: float): DebugVisualizer.vision_cone_offset.y = value)


## One tab's content area: a ScrollContainer (tab titles come from the
## ScrollContainer's own "name", which is what TabContainer reads) holding a
## VBoxContainer sized to the panel width, ready for headers/sliders/buttons.
func _make_tab(tabs: TabContainer, tab_title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_title
	tabs.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(330.0, 0.0)
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)
	return vbox


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


## Distinct from SAVE PRESET's timestamped snapshot -- this overwrites the
## one fixed default.json that _load_default_preset_into_slider_defaults()
## reads on every future _ready(). Use once you're happy with a tuning pass
## and want new sessions (including after closing and reopening the game)
## to start there instead of the numbers hardcoded in this file.
func _add_save_default_button(vbox: VBoxContainer) -> void:
	var btn := Button.new()
	btn.text = "SAVE AS DEFAULT"
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(_save_as_default)
	vbox.add_child(btn)


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
## group is "player" or "npc" -- tags the tracked entry so LOAD PRESET knows
## which half of a loaded file to read this slider's value from.
func _add_slider(vbox: VBoxContainer, row: Dictionary, group: String, on_change: Callable) -> void:
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

	_all_sliders.append({"slider": slider, "default": row["default"], "key": key, "group": group})


func _fmt(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(round(v)))
	return "%.2f" % v


func _reset_all_sliders() -> void:
	for entry in _all_sliders:
		entry["slider"].value = entry["default"]


## Current slider/toggle state as one plain Dictionary -- shared shape for
## both SAVE PRESET's timestamped snapshots and SAVE AS DEFAULT's fixed file.
func _collect_preset_data() -> Dictionary:
	return {
		"player": _player_values,
		"npc": _npc_overrides,
		"cheats": {
			"player_invincible": player_invincible,
			"npc_invincible": npc_invincible,
			"npc_afk": npc_afk,
		},
	}


## Writes the current slider/toggle state to its own timestamped file under
## BAG/admin_presets, separate from telemetry run logs -- so multiple tuning
## passes can be saved side by side and compared later, then reloaded via
## LOAD PRESET. Doesn't touch the live game beyond writing the file.
func _save_preset() -> void:
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	var d := Time.get_datetime_dict_from_system()
	var stamp := "%04d%02d%02d_%02d%02d%02d" % [d.year, d.month, d.day, d.hour, d.minute, d.second]
	var path := "%s/preset_%s.json" % [PRESET_DIR, stamp]

	var data := _collect_preset_data()
	data["timestamp"] = stamp

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		if _preset_status_label:
			_preset_status_label.text = "FAILED TO SAVE PRESET"
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

	if _preset_status_label:
		_preset_status_label.text = "saved: admin_presets/preset_%s.json" % stamp
	_refresh_load_list()


## Overwrites the one fixed default.json -- see
## _load_default_preset_into_slider_defaults(), which reads this back on
## every future _ready(). Live-tuned values (this session's sliders) become
## what new sessions start from; the numbers hardcoded in PLAYER_SLIDERS/
## NPC_SLIDERS above are untouched and stay as the ultimate fallback if
## default.json is ever deleted.
func _save_as_default() -> void:
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	var data := _collect_preset_data()
	var f := FileAccess.open(DEFAULT_PRESET_PATH, FileAccess.WRITE)
	if f == null:
		if _preset_status_label:
			_preset_status_label.text = "FAILED TO SAVE DEFAULT"
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if _preset_status_label:
		_preset_status_label.text = "saved as default -- new sessions start here"


func _read_preset_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}


## Rebuilds the LOAD PRESET... list from whatever preset_*.json snapshots
## currently exist under BAG/admin_presets (newest first) -- called once
## when the list is first opened and again after every SAVE PRESET so a
## freshly-saved snapshot shows up without reopening the panel.
func _refresh_load_list() -> void:
	if _load_list_vbox == null:
		return
	for child in _load_list_vbox.get_children():
		child.queue_free()
	if not DirAccess.dir_exists_absolute(PRESET_DIR):
		return
	var dir := DirAccess.open(PRESET_DIR)
	if dir == null:
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.begins_with("preset_") and fname.ends_with(".json"):
			names.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	names.sort()
	names.reverse()
	for one_name in names:
		var btn := Button.new()
		btn.text = "  " + one_name.trim_prefix("preset_").trim_suffix(".json")
		btn.add_theme_font_override("font", _font)
		btn.add_theme_font_size_override("font_size", 12)
		var full_path := "%s/%s" % [PRESET_DIR, one_name]
		btn.pressed.connect(func(): _load_preset_file(full_path))
		_load_list_vbox.add_child(btn)


## Applies a loaded preset's values to the LIVE sliders (which fires their
## existing value_changed -> _apply_*_value pipeline, same as dragging them
## by hand) plus the cheat toggles. Does not touch default.json.
func _load_preset_file(path: String) -> void:
	var data := _read_preset_file(path)
	if data.is_empty():
		if _preset_status_label:
			_preset_status_label.text = "FAILED TO LOAD PRESET"
		return

	var player_data: Dictionary = data.get("player", {})
	var npc_data: Dictionary = data.get("npc", {})
	for entry in _all_sliders:
		var source: Dictionary = player_data if entry["group"] == "player" else npc_data
		if entry["key"] in source:
			entry["slider"].value = source[entry["key"]]

	var cheats: Dictionary = data.get("cheats", {})
	if "player_invincible" in cheats and _player_invincible_toggle:
		_player_invincible_toggle.button_pressed = cheats["player_invincible"]
	if "npc_invincible" in cheats and _npc_invincible_toggle:
		_npc_invincible_toggle.button_pressed = cheats["npc_invincible"]
	if "npc_afk" in cheats and _npc_afk_toggle:
		_npc_afk_toggle.button_pressed = cheats["npc_afk"]

	if _preset_status_label:
		_preset_status_label.text = "loaded: " + path.get_file()


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
		"perfect_streak_for_bonus":
			player.perfect_streak_for_bonus = int(value)
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
