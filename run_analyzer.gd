extends CanvasLayer

## Autoload. Builds its own small on-screen panel (hidden by default) and
## prints/shows a run summary whenever TelemetryLogger.log_death/log_victory
## is called by the current level.

var _label: Label


func _ready() -> void:
	layer = 15
	visible = false
	_build_ui()


func _build_ui() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Courier New", "Lucida Console", "monospace"])

	# Anchored to the left side, not centered -- the death/victory screen
	# (level.gd) owns the centered title+buttons and would otherwise be
	# covered by this panel since it renders on a higher CanvasLayer.
	var panel := ColorRect.new()
	panel.color = Color(0.02, 0.02, 0.03, 0.88)
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = 24.0
	panel.offset_right = 340.0
	panel.offset_top = -170.0
	panel.offset_bottom = 170.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	_label = Label.new()
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = 14.0
	_label.offset_top = 12.0
	_label.offset_right = -14.0
	_label.offset_bottom = -12.0
	_label.add_theme_font_override("font", font)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55, 1))
	_label.add_theme_constant_override("line_spacing", 5)
	panel.add_child(_label)


func show_summary(won: bool) -> void:
	var t := get_node("/root/TelemetryLogger")
	var text := (
		"RUN #%d -- %s\n\n" +
		"Duration: %.1fs\n" +
		"Kills: %d | Deaths: %d\n\n" +
		"Parries: %d attempts, %d success, %d perfect (%.0f%%)\n" +
		"Avg hit distance: %.1f px\n" +
		"Avg miss distance: %.1f px\n" +
		"Dashes used: %d"
	) % [
		t.run_count, ("VICTORY" if won else "DEFEAT"),
		t.run_elapsed(),
		t.kills, (0 if won else 1),
		t.parry_attempts, t.parry_successes, t.parry_perfects, t.parry_success_pct(),
		t.average(t.hit_distances),
		t.average(t.miss_distances),
		t.dash_count,
	]
	print(text)
	_label.text = text
	visible = true
