extends CharacterBody2D

const HEIGHT_LOW := 0
const HEIGHT_MID := 1
const HEIGHT_HIGH := 2
const HIT_EFFECT := preload("res://hit_effect.tscn")

## Must stay >= the player's parry_late_limit_frames: this NPC holds its
## damage for that long past its own active-frame moment so a late-but-valid
## player parry always has a chance to cancel it before it lands.
const PARRY_GRACE_FRAMES := 10.0

@export var move_speed: float = 140.0
@export var detect_range: float = 260.0
@export var attack_range: float = 46.0
@export var attack_cooldown: float = 1.1
@export var attack_damage: float = 1.0
@export var attack_startup: float = 0.15
@export var max_hp: float = 3.0
@export var y_min: float = -INF
@export var y_max: float = INF

signal hp_changed(current: float, max_hp: float)
signal died

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hp_fill: ColorRect = $HealthBar/Fill

var current_hp: float
var _hp_bar_full_width: float
var _player: Node2D
var _is_attacking := false
var _is_dead := false
var _attack_timer := 0.0
var _attack_height := HEIGHT_MID
var _attack_start_time := 0.0
var _attack_active_time := 0.0
var _attack_parried := false
var _damage_resolved := false

var _is_stunned := false
var _stun_timer := 0.0


func _ready() -> void:
	sprite.animation_finished.connect(_on_animation_finished)
	current_hp = max_hp
	_hp_bar_full_width = hp_fill.size.x
	_player = get_tree().get_first_node_in_group("player")


func _physics_process(delta: float) -> void:
	if _is_dead or _player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		position.y = clamp(position.y, y_min, y_max)
		return

	if _is_stunned:
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			_is_stunned = false
		velocity = Vector2.ZERO
		move_and_slide()
		position.y = clamp(position.y, y_min, y_max)
		return

	_attack_timer = max(_attack_timer - delta, 0.0)

	if _is_attacking:
		_try_commit_attack_damage()

	var to_player: Vector2 = _player.global_position - global_position
	var distance: float = to_player.length()

	if _is_attacking:
		velocity = Vector2.ZERO
	elif distance <= attack_range:
		velocity = Vector2.ZERO
		sprite.flip_h = to_player.x < 0.0
		if _attack_timer <= 0.0:
			_start_attack()
		else:
			sprite.play("idle")
	elif distance <= detect_range:
		velocity = to_player.normalized() * move_speed
		sprite.flip_h = to_player.x < 0.0
		sprite.play("run")
	else:
		velocity = Vector2.ZERO
		sprite.play("idle")

	move_and_slide()
	position.y = clamp(position.y, y_min, y_max)


func _start_attack() -> void:
	_is_attacking = true
	_attack_timer = attack_cooldown
	_attack_height = randi() % 3
	_attack_start_time = Time.get_ticks_msec() / 1000.0
	_attack_active_time = _attack_start_time + attack_startup
	_attack_parried = false
	_damage_resolved = false
	sprite.rotation_degrees = _height_tilt(_attack_height)
	sprite.play("attack")


func _height_tilt(h: int) -> float:
	match h:
		HEIGHT_HIGH:
			return -18.0
		HEIGHT_LOW:
			return 18.0
		_:
			return 0.0


## Damage doesn't land the instant the hitbox goes active -- it's held for
## PARRY_GRACE_FRAMES past that moment so a player parry attempt arriving
## slightly late still has a real chance to cancel it (see cancel_attack_parried).
func _try_commit_attack_damage() -> void:
	if _damage_resolved or _attack_parried:
		return
	var commit_time := _attack_active_time + PARRY_GRACE_FRAMES / 60.0
	if Time.get_ticks_msec() / 1000.0 < commit_time:
		return
	_damage_resolved = true
	if _player and global_position.distance_to(_player.global_position) <= attack_range + 10.0 and _is_facing(_player.global_position):
		_player.take_damage(attack_damage, _attack_height)
		_spawn_hit_effect(_player.global_position)


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		_is_attacking = false
		sprite.rotation_degrees = 0.0


func _is_facing(target_pos: Vector2) -> bool:
	var dx: float = target_pos.x - global_position.x
	return dx <= 0.0 if sprite.flip_h else dx >= 0.0


func _spawn_hit_effect(at_position: Vector2) -> void:
	var effect := HIT_EFFECT.instantiate()
	get_parent().add_child(effect)
	effect.global_position = at_position


## Called by the player the instant a parry beats this NPC's active attack:
## the swing is cancelled (and _try_commit_attack_damage will no longer let
## it land even if already scheduled), this NPC gets knocked back by the
## same distance the parry tier computed, and eats a short stun.
func cancel_attack_parried(_perfect: bool, attacker: Node2D, knockback: float) -> void:
	_attack_parried = true
	_is_attacking = false
	sprite.rotation_degrees = 0.0
	sprite.play("hurt")
	var dir: Vector2 = global_position - attacker.global_position
	dir = dir.normalized() if dir != Vector2.ZERO else (Vector2.RIGHT if sprite.flip_h else Vector2.LEFT)
	create_tween().tween_property(self, "global_position", global_position + dir * knockback, 0.1)
	_is_stunned = true
	_stun_timer = 0.3


func take_damage(amount: float, attack_height: int = HEIGHT_MID) -> void:
	if _is_dead:
		return
	current_hp = max(current_hp - amount, 0.0)
	hp_changed.emit(current_hp, max_hp)
	hp_fill.size.x = _hp_bar_full_width * (current_hp / max_hp)
	if current_hp <= 0.0:
		_die()
	else:
		_is_attacking = false
		sprite.play("hurt")


func _die() -> void:
	_is_dead = true
	_is_attacking = false
	sprite.play("hurt")
	died.emit()
	await get_tree().create_timer(0.4).timeout
	queue_free()
