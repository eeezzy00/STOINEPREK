extends Node2D

## Settings screen reached from the main menu. Two tabs: Sound (three
## volume sliders wired to SettingsManager, applied live and saved to
## user://settings.cfg on every change) and Controls (a static keybind
## reference -- no rebinding UI yet, just the current scheme as text).

const ACCENT_COLOR := Color(0.878, 0.251, 0.984, 1)
const DIM_TEXT_COLOR := Color(0.62, 0.42, 0.62, 1)
const BG_COLOR := Color(0.015, 0.015, 0.02, 1)

const SLIDERS := [
	{"bus": "Master", "label": "ОБЩАЯ ГРОМКОСТЬ"},
	{"bus": "Music", "label": "МУЗЫКА"},
	{"bus": "SFX", "label": "ЭФФЕКТЫ"},
]

const CONTROLS_TEXT := "A / D        -- движение\nПробел       -- прыжок\nЛКМ          -- атака\nW + ЛКМ      -- удар вверх\nS + ЛКМ      -- удар вниз\nLeft Shift   -- перекат"

var _font: Font


func _ready() -> void:
	_font = _make_font()
	_build_ui()


func _make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "Courier New", "Lucida Console", "monospace"])
	return f


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	canvas.add_child(bg)

	var title := Label.new()
	title.text = "НАСТРОЙКИ"
	title.anchor_right = 1.0
	title.offset_top = 40.0
	title.offset_bottom = 80.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", ACCENT_COLOR)
	canvas.add_child(title)

	var tabs := TabContainer.new()
	tabs.anchor_left = 0.5
	tabs.anchor_right = 0.5
	tabs.anchor_top = 0.5
	tabs.anchor_bottom = 0.5
	tabs.offset_left = -220.0
	tabs.offset_right = 220.0
	tabs.offset_top = -140.0
	tabs.offset_bottom = 120.0
	canvas.add_child(tabs)

	tabs.add_child(_build_sound_tab())
	tabs.add_child(_build_controls_tab())
	tabs.set_tab_title(0, "ЗВУК")
	tabs.set_tab_title(1, "УПРАВЛЕНИЕ")

	var back_btn := Button.new()
	back_btn.text = "НАЗАД"
	back_btn.anchor_left = 0.5
	back_btn.anchor_right = 0.5
	back_btn.anchor_top = 1.0
	back_btn.anchor_bottom = 1.0
	back_btn.offset_left = -70.0
	back_btn.offset_right = 70.0
	back_btn.offset_top = -80.0
	back_btn.offset_bottom = -40.0
	back_btn.add_theme_font_override("font", _font)
	back_btn.add_theme_font_size_override("font_size", 18)
	back_btn.pressed.connect(_on_back_pressed)
	canvas.add_child(back_btn)
	back_btn.grab_focus()


func _build_sound_tab() -> Control:
	var vbox := VBoxContainer.new()
	vbox.name = "Sound"
	vbox.add_theme_constant_override("separation", 20)
	vbox.custom_minimum_size = Vector2(0.0, 20.0)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 24)
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_child(vbox)

	for row in SLIDERS:
		_add_volume_slider(vbox, row["bus"], row["label"])

	var wrapper := Control.new()
	wrapper.name = "Sound"
	wrapper.add_child(pad)
	pad.anchor_right = 1.0
	pad.anchor_bottom = 1.0
	return wrapper


func _add_volume_slider(vbox: VBoxContainer, bus_name: String, label_text: String) -> void:
	var lbl := Label.new()
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", DIM_TEXT_COLOR)
	vbox.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = SettingsManager.get_volume(bus_name)
	slider.custom_minimum_size = Vector2(300.0, 20.0)
	vbox.add_child(slider)

	var refresh := func():
		lbl.text = "%s: %d%%" % [label_text, int(round(slider.value * 100.0))]
	refresh.call()

	slider.value_changed.connect(func(value: float):
		refresh.call()
		SettingsManager.set_volume(bus_name, value)
	)


func _build_controls_tab() -> Control:
	var wrapper := Control.new()
	wrapper.name = "Controls"

	var pad := MarginContainer.new()
	pad.anchor_right = 1.0
	pad.anchor_bottom = 1.0
	pad.add_theme_constant_override("margin_top", 24)
	pad.add_theme_constant_override("margin_left", 12)
	wrapper.add_child(pad)

	var lbl := Label.new()
	lbl.text = CONTROLS_TEXT
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", DIM_TEXT_COLOR)
	pad.add_child(lbl)

	return wrapper


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://men.tscn")
