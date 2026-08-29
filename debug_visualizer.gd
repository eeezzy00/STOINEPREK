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
		_draw_vision_cone(enemy)

	if _player._is_attacking:
		_draw_hitbox(_player, Color(0.2, 1.0, 0.3, 0.9), _player.strike_range)

	if nearest_enemy != null:
		var text := "%d px" % int(round(nearest_dist))
		var pos: Vector2 = _player.global_position + Vector2(-20.0, -78.0)
		draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 1))


## Triangle from roughly eye height in the NPC's facing direction, spanning
## its actual detection cone (vision_angle_degrees wide, detect_range long)
## -- this is the same shape _can_see_player() checks against, not just a
## decorative approximation. Red-tinted while it currently sees the player,
## dim cyan otherwise.
## Fallback (pre-scale, local-space) eye height when an NPC has no
## HealthBar node to read a real head reference from.
const EYE_OFFSET_Y_FALLBACK := -20.0
## Flat screen-space nudge on top of the HealthBar-derived estimate above --
## live-tunable from the admin panel (F5 -> DEBUG VIZ) instead of a fixed
## guess, since "roughly eye height" never quite lines up with the actual
## sprite on the first try. X shifts the apex sideways, Y down (+) / up (-).
var vision_cone_offset := Vector2(0.0, 25.0)

func _draw_vision_cone(enemy: Node2D) -> void:
	if not ("vision_angle_degrees" in enemy):
		return
	var seeing: bool = enemy.call("_can_see_player")
	var color := Color(1.0, 0.25, 0.2, 0.22) if seeing else Color(0.3, 0.9, 1.0, 0.12)
	# Scaled by the enemy's own node scale (placed at 1.55x in most levels)
	# so the cone's apex tracks actual eye height instead of a fixed pixel
	# offset that only happens to look right at one particular scale.
	var eye_local_y := EYE_OFFSET_Y_FALLBACK
	var health_bar := enemy.get_node_or_null("HealthBar")
	if health_bar:
		eye_local_y = health_bar.position.y * 0.8
	var eyes: Vector2 = enemy.global_position + Vector2(0.0, eye_local_y) * enemy.scale
	eyes += vision_cone_offset
	var facing := Vector2(-1.0, 0.0) if enemy.sprite.flip_h else Vector2(1.0, 0.0)
	var half_angle: float = deg_to_rad(enemy.vision_angle_degrees / 2.0)
	var left: Vector2 = eyes + facing.rotated(-half_angle) * enemy.detect_range
	var right: Vector2 = eyes + facing.rotated(half_angle) * enemy.detect_range
	draw_colored_polygon(PackedVector2Array([eyes, left, right]), color)
	draw_polyline(PackedVector2Array([left, eyes, right]), color.lightened(0.4), 1.5)


## range_px is the entity's raw strike_range/attack_range -- scaled here by
## its sprite's own scale so this drawn box matches the real hitbox (see
## player.gd's _resize_hitbox_shape) instead of showing the old unscaled
## reach while the actual Area2D is bigger or smaller.
func _draw_hitbox(entity: Node2D, color: Color, range_px: float) -> void:
	var scaled_range: float = range_px * entity.sprite.scale.x
	var scaled_height: float = HITBOX_HEIGHT * entity.sprite.scale.y
	var facing_right: bool = not entity.sprite.flip_h
	var x0: float = entity.global_position.x if facing_right else entity.global_position.x - scaled_range
	var rect := Rect2(x0, entity.global_position.y - scaled_height / 2.0, scaled_range, scaled_height)
	draw_rect(rect, color, false, 2.0)
