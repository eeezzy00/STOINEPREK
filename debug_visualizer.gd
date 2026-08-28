extends Node2D

## Autoload, F1 toggles it. Draws attack hitboxes in world space (green =
## player, red = enemy), the distance-to-nearest-enemy readout above the
## player, and a screen-space attack-phase bar at the bottom of the screen.

const PHASES := ["INPUT", "ANTICIPATION", "ACTIVE", "RECOVERY"]
const PHASE_COLOR_ACTIVE := Color(0.4, 1.0, 0.55, 1)
const PHASE_COLOR_INACTIVE := Color(0.35, 0.33, 0.4, 1)
const HITBOX_HEIGHT := 60.0

var enabled := false

var _player: Node
var _canvas: CanvasLayer
var _phase_labels: Array[Label] = []
var _frame_label: Label


func _ready() -> void:
	z_index = 100
	_build_screen_ui()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		enabled = not enabled
		_canvas.visible = enabled


func _build_screen_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 20
	_canvas.visible = false
	add_child(_canvas)

	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Courier New", "Lucida Console", "monospace"])

	var bar := HBoxContainer.new()
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -230.0
	bar.offset_right = 230.0
	bar.offset_top = -34.0
	bar.offset_bottom = -10.0
	bar.add_theme_constant_override("separation", 6)
	_canvas.add_child(bar)

	for phase_name in PHASES:
		var lbl := Label.new()
		lbl.text = phase_name
		lbl.custom_minimum_size = Vector2(108.0, 0.0)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", PHASE_COLOR_INACTIVE)
		bar.add_child(lbl)
		_phase_labels.append(lbl)

	_frame_label = Label.new()
	_frame_label.anchor_left = 0.5
	_frame_label.anchor_right = 0.5
	_frame_label.anchor_top = 1.0
	_frame_label.anchor_bottom = 1.0
	_frame_label.offset_left = -60.0
	_frame_label.offset_right = 60.0
	_frame_label.offset_top = -54.0
	_frame_label.offset_bottom = -34.0
	_frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_frame_label.add_theme_font_override("font", font)
	_frame_label.add_theme_font_size_override("font_size", 12)
	_frame_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 1))
	_canvas.add_child(_frame_label)


func _process(_delta: float) -> void:
	if not enabled:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	_update_phase_bar()
	queue_redraw()


func _update_phase_bar() -> void:
	if _player == null:
		return
	var phase := "INPUT"
	var frame := 0
	if _player._is_attacking:
		var elapsed: float = _player._attack_elapsed
		frame = int(round(elapsed * 60.0))
		if elapsed < _player.attack_startup:
			phase = "ANTICIPATION"
		elif not _player._attack_hit_resolved:
			phase = "ACTIVE"
		else:
			phase = "RECOVERY"
	for i in range(PHASES.size()):
		_phase_labels[i].add_theme_color_override("font_color",
			PHASE_COLOR_ACTIVE if PHASES[i] == phase else PHASE_COLOR_INACTIVE)
	_frame_label.text = "frame %d" % frame


func _draw() -> void:
	if not enabled or _player == null or not is_instance_valid(_player):
		return

	var nearest_enemy: Node = null
	var nearest_dist := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var d: float = _player.global_position.distance_to(enemy.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest_enemy = enemy
		if enemy._is_attacking:
			_draw_hitbox(enemy, Color(1.0, 0.2, 0.2, 0.9), enemy.attack_range)

	if _player._is_attacking:
		_draw_hitbox(_player, Color(0.2, 1.0, 0.3, 0.9), _player.strike_range)

	if nearest_enemy != null:
		var text := "%d px" % int(round(nearest_dist))
		var pos: Vector2 = _player.global_position + Vector2(-20.0, -78.0)
		draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 1))


func _draw_hitbox(entity: Node2D, color: Color, range_px: float) -> void:
	var facing_right: bool = not entity.sprite.flip_h
	var x0: float = entity.global_position.x if facing_right else entity.global_position.x - range_px
	var rect := Rect2(x0, entity.global_position.y - HITBOX_HEIGHT / 2.0, range_px, HITBOX_HEIGHT)
	draw_rect(rect, color, false, 2.0)
