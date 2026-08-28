extends CharacterBody2D

const HEIGHT_LOW := 0
const HEIGHT_MID := 1
const HEIGHT_HIGH := 2

@export var move_speed: float = 250.0
@export var y_min: float = -INF
@export var y_max: float = INF
@export var max_hp: float = 3.0
@export var attack_damage: float = 1.0
@export var attack_speed: float = 0.35
@export var strike_range: float = 50.0
@export var jump_height: float = 22.0
@export var jump_duration: float = 0.5
@export var camera_look_ahead: float = 45.0
@export var camera_lead_rate: float = 6.0

@export_group("Dash")
@export var dash_duration: float = 0.2
@export var dash_distance: float = 180.0
@export var dash_cooldown: float = 2.0
@export var double_tap_window: float = 0.3

@export_group("Parry")
## Time after an attack starts before its hitbox actually goes "active" --
## this is the instant hit/parry resolution happens, not the button press.
@export var attack_startup: float = 0.15
## Frames (at 60fps) of timing slop still eligible for a parry; beyond this
## the swing just resolves as a normal (unparried) clash.
@export var parry_late_limit_frames: float = 10.0
@export var max_parry_charges: int = 3
@export var parry_regen_interval: float = 3.0
@export var perfect_streak_for_bonus: int = 3

const CAMERA_BASE_OFFSET := Vector2(0, -85)
const HIT_EFFECT := preload("res://hit_effect.tscn")
const AFTERIMAGE_COUNT := 4
const AFTERIMAGE_FADE := 0.15
const AFTERIMAGE_COLOR := Color(0.878, 0.251, 0.984, 0.5)
const STREAK_GLOW_COLOR := Color(1.4, 1.1, 0.3, 1)

const PARRY_SPARK_COLORS := {
	"PERFECT": Color(1.0, 0.85, 0.2, 1),
	"GOOD": Color(1.0, 1.0, 1.0, 1),
	"LATE": Color(0.6, 0.6, 0.6, 1),
}
const PARRY_CHARGE_COST := {
	"PERFECT": 0,
	"GOOD": 1,
	"LATE": 1,
	"BARE": 1,
}
const PARRY_HITSTOP_FRAMES := {
	"PERFECT": 6,
	"GOOD": 4,
	"LATE": 2,
	"BARE": 1,
}

signal hp_changed(current: float, max_hp: float)
signal died
signal parried

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hp_fill: ColorRect = $HealthBar/Fill
@onready var camera: Camera2D = $Camera2D
@onready var dash_smoke: CPUParticles2D = _make_dash_smoke()
@onready var spark_particles: CPUParticles2D = _make_spark_particles()

var _camera_lead_x := 0.0

var current_hp: float
var _hp_bar_full_width: float
var parries_count := 0

var parry_charges: int
var parry_streak := 0
var last_parry_result := "--"
var _parry_regen_timer := 0.0
var _next_hit_bonus := false

var _is_attacking := false
var _is_dead := false
var _attack_index := 0
var _attack_height_current := HEIGHT_MID
var _attack_cooldown_timer := 0.0
var _attack_elapsed := 0.0
var _attack_hit_resolved := false

var _is_jumping := false
var _jump_time := 0.0

var _is_dashing := false
var _dash_timer := 0.0
var _dash_cooldown_timer := 0.0
var _dash_velocity := Vector2.ZERO
var _afterimage_timer := 0.0
var _afterimage_count := 0
var _last_tap_time := {
	"move_left": -10.0,
	"move_right": -10.0,
	"move_up": -10.0,
	"move_down": -10.0,
}

var _hitstop_depth := 0
var _time_scale_before_hitstop := 1.0


func _ready() -> void:
	sprite.animation_finished.connect(_on_animation_finished)
	current_hp = max_hp
	_hp_bar_full_width = hp_fill.size.x
	parry_charges = max_parry_charges


func _physics_process(delta: float) -> void:
	_attack_cooldown_timer = max(_attack_cooldown_timer - delta, 0.0)
	_dash_cooldown_timer = max(_dash_cooldown_timer - delta, 0.0)
	_update_parry_regen(delta)

	if _is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _is_dashing:
		_update_dash(delta)
		return

	if _is_attacking:
		_update_attack_active_window(delta)

	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	_check_double_tap_dash(input_dir)

	if Input.is_action_just_pressed("attack"):
		_on_attack_pressed(input_dir)

	if Input.is_action_just_pressed("jump") and not _is_attacking and not _is_jumping:
		_start_jump()

	if _is_attacking:
		velocity = Vector2.ZERO
	else:
		velocity = input_dir * move_speed
		if not _is_jumping:
			_update_movement_animation(input_dir)

	move_and_slide()
	position.y = clamp(position.y, y_min, y_max)

	if _is_jumping:
		_update_jump(delta)

	_update_camera_lead(delta, input_dir)


func _update_parry_regen(delta: float) -> void:
	_parry_regen_timer += delta
	if _parry_regen_timer >= parry_regen_interval:
		_parry_regen_timer = 0.0
		if parry_charges < max_parry_charges:
			parry_charges += 1


func _update_camera_lead(delta: float, input_dir: Vector2) -> void:
	var target_lead := 0.0
	if not _is_attacking:
		if input_dir.x > 0.1:
			target_lead = camera_look_ahead
		elif input_dir.x < -0.1:
			target_lead = -camera_look_ahead
	var t: float = 1.0 - exp(-camera_lead_rate * delta)
	_camera_lead_x = lerp(_camera_lead_x, target_lead, t)
	camera.position = CAMERA_BASE_OFFSET + Vector2(_camera_lead_x, 0.0)


func _on_attack_pressed(input_dir: Vector2) -> void:
	if _is_attacking or _attack_cooldown_timer > 0.0:
		return
	_attack_cooldown_timer = attack_speed
	_start_attack(_height_from_input(input_dir))


func _height_from_input(input_dir: Vector2) -> int:
	if input_dir.y < -0.3:
		return HEIGHT_HIGH
	elif input_dir.y > 0.3:
		return HEIGHT_LOW
	return HEIGHT_MID


func _start_attack(height: int) -> void:
	_is_attacking = true
	_attack_height_current = height
	_attack_elapsed = 0.0
	_attack_hit_resolved = false
	var anim := "attack" if _attack_index == 0 else "attack2"
	_attack_index = 1 - _attack_index
	sprite.play(anim)
	sprite.rotation_degrees = _height_tilt(height)


## Hit registration happens here, once, the instant the swing's hitbox goes
## "active" (attack_startup elapsed) -- not at the moment of the click.
func _update_attack_active_window(delta: float) -> void:
	if _attack_hit_resolved:
		return
	_attack_elapsed += delta
	if _attack_elapsed >= attack_startup:
		_attack_hit_resolved = true
		_resolve_attack_hit()


func _resolve_attack_hit() -> void:
	var enemy := _find_active_attacking_enemy()
	if enemy != null:
		_resolve_parry_attempt(enemy)
	else:
		_try_hit_enemies()


func _height_tilt(h: int) -> float:
	match h:
		HEIGHT_HIGH:
			return -18.0
		HEIGHT_LOW:
			return 18.0
		_:
			return 0.0


func _find_active_attacking_enemy() -> Node:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		if enemy.get("_is_attacking") != true:
			continue
		if global_position.distance_to(enemy.global_position) > strike_range:
			continue
		if not _is_facing(enemy.global_position):
			continue
		return enemy
	return null


## Compares this swing's active-frame moment against the enemy's own
## (already scheduled, possibly future) active-frame moment. Symmetric --
## being early counts the same as being late.
func _resolve_parry_attempt(enemy: Node) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var enemy_active_time: float = enemy.get("_attack_active_time")
	var enemy_height: int = enemy.get("_attack_height")
	var frames_late := absf(now - enemy_active_time) * 60.0
	var heights_match := _attack_height_current == enemy_height

	if heights_match and frames_late <= parry_late_limit_frames and parry_charges > 0:
		_apply_parry_success(enemy, frames_late)
	else:
		_apply_parry_fail()


func _parry_tier(frames_late: float) -> String:
	if frames_late <= 2.0:
		return "PERFECT"
	elif frames_late <= 5.0:
		return "GOOD"
	elif frames_late <= 8.0:
		return "LATE"
	return "BARE"


func _apply_parry_success(enemy: Node, frames_late: float) -> void:
	# The swing's own "attack"/"attack2" animation gets pre-empted by the
	# hurt_flash below, so it will never fire animation_finished itself --
	# do the cleanup _on_animation_finished would otherwise have done.
	_is_attacking = false
	sprite.rotation_degrees = 0.0

	var tier := _parry_tier(frames_late)
	last_parry_result = tier
	var knockback: float = maxf(15.0, 80.0 - (frames_late / 10.0) * 65.0)

	parry_charges = maxi(parry_charges - PARRY_CHARGE_COST[tier], 0)
	parries_count += 1
	parried.emit()

	if tier == "PERFECT":
		parry_streak += 1
		if parry_streak >= perfect_streak_for_bonus:
			_next_hit_bonus = true
			_update_streak_visual()
	else:
		parry_streak = 0
		_update_streak_visual()

	var clash_point: Vector2 = (global_position + enemy.global_position) / 2.0
	if PARRY_SPARK_COLORS.has(tier):
		_spawn_parry_spark(PARRY_SPARK_COLORS[tier], clash_point)

	TelemetryLogger.log_parry(tier, knockback)

	sprite.play("hurt_flash")
	await _apply_hitstop(PARRY_HITSTOP_FRAMES[tier] / 60.0)

	_knockback_away_from(enemy.global_position, knockback)
	if enemy.has_method("cancel_attack_parried"):
		enemy.cancel_attack_parried(tier == "PERFECT", self, knockback)


func _apply_parry_fail() -> void:
	_is_attacking = false
	sprite.rotation_degrees = 0.0

	last_parry_result = "MISS"
	parry_streak = 0
	_update_streak_visual()
	TelemetryLogger.log_parry("MISS", 0.0)
	sprite.play("hurt_flash")


func _apply_hitstop(duration: float) -> void:
	if duration <= 0.0:
		return
	if _hitstop_depth == 0:
		_time_scale_before_hitstop = Engine.time_scale
	_hitstop_depth += 1
	Engine.time_scale = 0.02
	# ignore_time_scale=true: this wait must elapse in real time, or the
	# game would stay frozen forever once time_scale is dropped above.
	await get_tree().create_timer(duration, true, false, true).timeout
	_hitstop_depth -= 1
	if _hitstop_depth <= 0:
		Engine.time_scale = _time_scale_before_hitstop


func _update_streak_visual() -> void:
	sprite.modulate = STREAK_GLOW_COLOR if _next_hit_bonus else Color.WHITE


func _knockback_away_from(source_pos: Vector2, distance: float) -> void:
	var dir: Vector2 = global_position - source_pos
	dir = dir.normalized() if dir != Vector2.ZERO else (Vector2.LEFT if sprite.flip_h else Vector2.RIGHT)
	var target := global_position + dir * distance
	create_tween().tween_property(self, "global_position", target, 0.1)


func _spawn_parry_spark(color: Color, at_position: Vector2) -> void:
	spark_particles.color = color
	spark_particles.global_position = at_position
	spark_particles.restart()
	spark_particles.emitting = true


func _make_spark_particles() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.25
	p.explosiveness = 1.0
	p.direction = Vector2.ZERO
	p.spread = 180.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 220.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.damping_min = 300.0
	p.damping_max = 400.0
	call_deferred("add_child", p)
	return p


func _update_movement_animation(input_dir: Vector2) -> void:
	if input_dir.x != 0.0:
		sprite.flip_h = input_dir.x < 0.0
	sprite.play("run" if input_dir != Vector2.ZERO else "idle")


func _can_dash() -> bool:
	return not _is_dashing and not _is_attacking and not _is_dead and _dash_cooldown_timer <= 0.0


func _check_double_tap_dash(input_dir: Vector2) -> void:
	for action in _last_tap_time.keys():
		if Input.is_action_just_pressed(action):
			var now := Time.get_ticks_msec() / 1000.0
			if now - _last_tap_time[action] <= double_tap_window and _can_dash():
				_start_dash(_direction_for_action(action))
			_last_tap_time[action] = now


func _direction_for_action(action: String) -> Vector2:
	match action:
		"move_left":
			return Vector2.LEFT
		"move_right":
			return Vector2.RIGHT
		"move_up":
			return Vector2.UP
		"move_down":
			return Vector2.DOWN
	return Vector2.ZERO


func _start_dash(input_dir: Vector2) -> void:
	var dir := input_dir
	if dir == Vector2.ZERO:
		dir = Vector2.LEFT if sprite.flip_h else Vector2.RIGHT
	dir = dir.normalized()
	_is_dashing = true
	_dash_timer = 0.0
	_dash_cooldown_timer = dash_cooldown
	_dash_velocity = dir * (dash_distance / dash_duration)
	_afterimage_timer = 0.0
	_afterimage_count = 0
	sprite.play("run")
	dash_smoke.restart()
	dash_smoke.emitting = true
	TelemetryLogger.log_dash(global_position, dash_cooldown)


func _update_dash(delta: float) -> void:
	velocity = _dash_velocity
	move_and_slide()
	position.y = clamp(position.y, y_min, y_max)

	_dash_timer += delta
	_afterimage_timer += delta
	var afterimage_interval := dash_duration / float(AFTERIMAGE_COUNT)
	if _afterimage_timer >= afterimage_interval and _afterimage_count < AFTERIMAGE_COUNT:
		_spawn_afterimage()
		_afterimage_timer = 0.0
		_afterimage_count += 1

	if _dash_timer >= dash_duration:
		_is_dashing = false


func _spawn_afterimage() -> void:
	var ghost := Sprite2D.new()
	ghost.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	ghost.global_position = global_position
	ghost.flip_h = sprite.flip_h
	ghost.modulate = AFTERIMAGE_COLOR
	ghost.z_index = -1
	get_parent().add_child(ghost)
	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, AFTERIMAGE_FADE)
	tween.tween_callback(ghost.queue_free)


func _make_dash_smoke() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 10
	p.lifetime = 0.4
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 70.0
	p.gravity = Vector2(0, -30)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	p.color = Color(0.08, 0.06, 0.1, 0.85)
	call_deferred("add_child", p)
	return p


func get_dash_cooldown() -> float:
	return _dash_cooldown_timer


func _start_jump() -> void:
	_is_jumping = true
	_jump_time = 0.0
	sprite.play("jump")


func _update_jump(delta: float) -> void:
	_jump_time += delta
	var t: float = _jump_time / jump_duration
	if t >= 1.0:
		_is_jumping = false
		sprite.offset.y = 0.0
		return
	sprite.offset.y = -sin(PI * t) * jump_height
	if t < 0.5:
		if sprite.animation != "jump":
			sprite.play("jump")
	else:
		if sprite.animation != "fall":
			sprite.play("fall")


func _on_animation_finished() -> void:
	if sprite.animation == "attack" or sprite.animation == "attack2":
		_is_attacking = false
		sprite.rotation_degrees = 0.0
	elif sprite.animation == "hurt_flash":
		sprite.play("hurt")


func _try_hit_enemies() -> void:
	var damage := attack_damage
	if _next_hit_bonus:
		damage *= 2.0
		_next_hit_bonus = false
		parry_streak = 0
		_update_streak_visual()

	var direction_name := _direction_name(_attack_height_current)
	var hit_any := false
	var nearest_distance := INF

	for enemy in get_tree().get_nodes_in_group("enemies"):
		var d: float = global_position.distance_to(enemy.global_position)
		nearest_distance = minf(nearest_distance, d)
		if d <= strike_range and _is_facing(enemy.global_position):
			enemy.take_damage(damage, _attack_height_current)
			_spawn_hit_effect(enemy.global_position)
			TelemetryLogger.log_attack(direction_name, d, true)
			hit_any = true

	if not hit_any and nearest_distance < INF:
		TelemetryLogger.log_attack(direction_name, nearest_distance, false)


func _direction_name(height: int) -> String:
	match height:
		HEIGHT_HIGH:
			return "UP"
		HEIGHT_LOW:
			return "DOWN"
		_:
			return "NEUTRAL"


func _spawn_hit_effect(at_position: Vector2) -> void:
	var effect := HIT_EFFECT.instantiate()
	get_parent().add_child(effect)
	effect.global_position = at_position


func _is_facing(target_pos: Vector2) -> bool:
	var dx: float = target_pos.x - global_position.x
	return dx <= 0.0 if sprite.flip_h else dx >= 0.0


func take_damage(amount: float, _attack_height: int = HEIGHT_MID) -> void:
	if _is_dead or _is_dashing:
		return

	current_hp = max(current_hp - amount, 0.0)
	hp_changed.emit(current_hp, max_hp)
	hp_fill.size.x = _hp_bar_full_width * (current_hp / max_hp)
	if current_hp <= 0.0:
		_die()
	else:
		_is_attacking = false
		sprite.play("hurt_flash")


func _die() -> void:
	_is_dead = true
	_is_attacking = false
	sprite.play("death")
	died.emit()
