extends CharacterBody2D

const HIT_EFFECT := preload("res://hit_effect.tscn")

## Must stay >= the player's parry_late_limit_frames: this NPC holds its
## damage for that long past its own active-frame moment so a late-but-valid
## player parry always has a chance to cancel it before it lands.
const PARRY_GRACE_FRAMES := 10.0

## Height of the melee hitbox rectangle -- matches debug_visualizer's drawn box.
const HITBOX_HEIGHT := 60.0
## Player is on collision layer 1 -- the hitbox only needs to see that layer.
const HITBOX_MASK := 1
## Walls(4) + enemies(2) + player(1) -- normal solid body collision.
const COLLISION_MASK_NORMAL := 7
## Walls only -- during a dodge/flank this NPC phases through other bodies
## (matches player.gd's dash: intangible, not just invincible). Without
## this, the flank roll -- which deliberately crosses the player's own
## position to land behind them -- would just bounce off the player instead
## of passing through.
const COLLISION_MASK_DODGING := 4
## Godot checks collision independently from each body's own move_and_slide
## call -- clearing only this body's MASK stops it from being blocked, but
## the player would still see this body's LAYER and get blocked *by* it
## while standing still. Clearing collision_layer too makes it invisible to
## everyone else's collision checks as well, for a true two-way phase.
const COLLISION_LAYER_NORMAL := 2
const COLLISION_LAYER_PHASED := 0

const ATTACK_SOUNDS := [
	preload("res://Audio/Katana Fx For NPC/Katana_whoop_npc1.0.wav"),
	preload("res://Audio/Katana Fx For NPC/Katana_whoop_npc second hit.wav"),
]
const DASH_SOUNDS := [
	preload("res://Audio/Dash Fx For Both/Dash_whoop_fx.wav"),
	preload("res://Audio/Dash Fx For Both/Dash_whoop_fx2.wav"),
]
const DEATH_SOUNDS := [
	preload("res://Audio/Death Fx/Death_fx_npc-dead.wav"),
	preload("res://Audio/Death Fx/Death_fx_npc-dead2.wav"),
]

@export var move_speed: float = 140.0
@export var detect_range: float = 260.0
@export var attack_range: float = 46.0
@export var attack_cooldown: float = 1.1
@export var attack_damage: float = 1.0
@export var attack_startup: float = 0.15
@export var max_hp: float = 3.0
@export var jump_gravity: float = 900.0
@export var max_fall_speed: float = 1400.0

@export_group("Dodge")
@export var dodge_distance: float = 60.0
@export var dodge_duration: float = 0.15
@export var dodge_cooldown: float = 1.5
## Chance (0-1) to dodge-roll away the instant the player starts a swing
## within dodge_danger_range -- rolled once per incoming swing, not per frame.
@export var dodge_chance: float = 0.35
@export var dodge_danger_range: float = 90.0

@export_group("Flank")
## Roll speed is shared with the defensive dodge (dodge_distance/dodge_duration);
## only the travel distance differs, since it has to cross past the player.
@export var flank_chance: float = 0.3
@export var flank_range: float = 160.0
## How far past the player's far side to land, so the roll clearly ends up
## behind them instead of just barely alongside.
@export var flank_land_offset: float = 40.0
## How often (seconds) this NPC re-considers flanking while in range -- not
## rolled every physics frame, or flank_chance would stop meaning anything.
@export var flank_check_interval: float = 1.0

signal hp_changed(current: float, max_hp: float)
signal died

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hp_fill: ColorRect = $HealthBar/Fill
@onready var hitbox: Area2D = _make_hitbox()
@onready var sfx_attack: AudioStreamPlayer = _make_sfx_player()
@onready var sfx_dash: AudioStreamPlayer = _make_sfx_player()

var current_hp: float
var _hp_bar_full_width: float
var _player: Node2D
var _is_attacking := false
var _attack_sound_index := 0
var _dash_sound_index := 0
var _is_dead := false
var _attack_timer := 0.0
var _attack_start_time := 0.0
var _attack_active_time := 0.0
var _attack_parried := false
var _damage_resolved := false

var _is_stunned := false
var _stun_timer := 0.0

var _is_dodging := false
var _dodge_timer := 0.0
var _dodge_active_duration := 0.0
var _dodge_cooldown_timer := 0.0
var _dodge_velocity := Vector2.ZERO
var _player_was_attacking := false
var _flank_decision_timer := 0.0


func _ready() -> void:
	sprite.animation_finished.connect(_on_animation_finished)
	current_hp = max_hp
	_hp_bar_full_width = hp_fill.size.x
	_player = get_tree().get_first_node_in_group("player")


func _physics_process(delta: float) -> void:
	_update_hitbox_facing()

	# Frozen while the admin panel is open, same reasoning as player.gd.
	if AdminPanel.panel_open:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Applies in every branch below (dead/stunned/afk/normal) so this NPC
	# always falls onto and rests on real ground, same as the player.
	if not is_on_floor():
		velocity.y = minf(velocity.y + jump_gravity * delta, max_fall_speed)
	else:
		velocity.y = 0.0

	if _is_dead or _player == null:
		velocity.x = 0.0
		move_and_slide()
		return

	if _is_stunned:
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			_is_stunned = false
		velocity.x = 0.0
		move_and_slide()
		return

	# AFK: stands down completely (no chase/attack/dodge/flank), but can
	# still be hit and killed normally -- take_damage() isn't gated by this.
	if AdminPanel.npc_afk:
		_is_attacking = false
		_is_dodging = false
		velocity.x = 0.0
		sprite.play("idle")
		move_and_slide()
		return

	_attack_timer = max(_attack_timer - delta, 0.0)
	_dodge_cooldown_timer = max(_dodge_cooldown_timer - delta, 0.0)
	_flank_decision_timer = max(_flank_decision_timer - delta, 0.0)

	if _is_dodging:
		_update_dodge(delta)
		return

	if _is_attacking:
		_try_commit_attack_damage()

	var to_player: Vector2 = _player.global_position - global_position
	var distance: float = to_player.length()

	_check_dodge_reaction(distance, to_player)
	if _is_dodging:
		return

	_check_flank_reaction(distance)
	if _is_dodging:
		return

	if _is_attacking:
		velocity.x = 0.0
	elif distance <= attack_range:
		velocity.x = 0.0
		sprite.flip_h = to_player.x < 0.0
		if _attack_timer <= 0.0:
			_start_attack()
		else:
			sprite.play("idle")
	elif distance <= detect_range:
		velocity.x = signf(to_player.x) * move_speed
		sprite.flip_h = to_player.x < 0.0
		sprite.play("run")
	else:
		velocity.x = 0.0
		sprite.play("idle")

	move_and_slide()


## Reacts to the player winding up a swing nearby: rolled once on the rising
## edge of _is_attacking (not every frame, or a single windup could re-roll
## for its whole 0.15s startup and the chance would stop meaning anything).
func _check_dodge_reaction(distance: float, to_player: Vector2) -> void:
	var player_attacking: bool = _player.get("_is_attacking") == true
	if player_attacking and not _player_was_attacking and not _is_attacking \
			and _dodge_cooldown_timer <= 0.0 and distance <= dodge_danger_range:
		if randf() < dodge_chance:
			_start_dodge(to_player)
	_player_was_attacking = player_attacking


func _start_dodge(to_player: Vector2) -> void:
	var dir_x: float = -signf(to_player.x) if to_player.x != 0.0 else (1.0 if sprite.flip_h else -1.0)
	_is_dodging = true
	_dodge_timer = 0.0
	_dodge_active_duration = dodge_duration
	_dodge_cooldown_timer = dodge_cooldown
	_dodge_velocity = Vector2(dir_x * (dodge_distance / dodge_duration), 0.0)
	_is_attacking = false
	collision_mask = COLLISION_MASK_DODGING
	collision_layer = COLLISION_LAYER_PHASED
	sprite.play("run")
	_play_sfx(sfx_dash, DASH_SOUNDS[_dash_sound_index])
	_dash_sound_index = 1 - _dash_sound_index
	TelemetryLogger.log_npc_dodge("DEFENSIVE", global_position)


## Periodically (not every frame) considers rolling past the player to land
## on their blind side -- only while approaching from the side the player is
## actually facing (flanking from behind them would be pointless) and not
## already at melee range (that's what the attack/chase state handles).
func _check_flank_reaction(distance: float) -> void:
	if _flank_decision_timer > 0.0:
		return
	_flank_decision_timer = flank_check_interval
	if _is_attacking or _dodge_cooldown_timer > 0.0:
		return
	if distance < attack_range or distance > flank_range:
		return
	var player_facing_x: float = -1.0 if _player.sprite.flip_h else 1.0
	var to_npc_x: float = global_position.x - _player.global_position.x
	var npc_in_front: bool = to_npc_x == 0.0 or signf(to_npc_x) == signf(player_facing_x)
	if not npc_in_front:
		return
	if randf() < flank_chance:
		_start_flank_dodge(player_facing_x)


## Rolls in a straight line past the player's position to a point
## flank_land_offset beyond their far side -- ends up behind them, facing
## resumes automatically next frame via the normal chase/attack branch.
func _start_flank_dodge(player_facing_x: float) -> void:
	var target := Vector2(_player.global_position.x - player_facing_x * flank_land_offset, global_position.y)
	var to_target: Vector2 = target - global_position
	if to_target.length() < 1.0:
		return
	var dodge_speed: float = dodge_distance / dodge_duration
	_is_dodging = true
	_dodge_timer = 0.0
	_dodge_active_duration = to_target.length() / dodge_speed
	_dodge_cooldown_timer = dodge_cooldown
	_dodge_velocity = to_target.normalized() * dodge_speed
	_is_attacking = false
	collision_mask = COLLISION_MASK_DODGING
	collision_layer = COLLISION_LAYER_PHASED
	sprite.play("run")
	_play_sfx(sfx_dash, DASH_SOUNDS[_dash_sound_index])
	_dash_sound_index = 1 - _dash_sound_index
	TelemetryLogger.log_npc_dodge("FLANK", global_position)


func _update_dodge(delta: float) -> void:
	velocity.x = _dodge_velocity.x
	velocity.y = 0.0
	move_and_slide()
	_dodge_timer += delta
	if _dodge_timer >= _dodge_active_duration:
		_is_dodging = false
		collision_mask = COLLISION_MASK_NORMAL
		collision_layer = COLLISION_LAYER_NORMAL


func _start_attack() -> void:
	_is_attacking = true
	_attack_timer = attack_cooldown
	_attack_start_time = Time.get_ticks_msec() / 1000.0
	_attack_active_time = _attack_start_time + attack_startup
	_attack_parried = false
	_damage_resolved = false
	_play_sfx(sfx_attack, ATTACK_SOUNDS[_attack_sound_index])
	_attack_sound_index = 1 - _attack_sound_index
	sprite.play("attack")


## Forward-only melee hitbox: a rectangle in front of the character, flipped
## to match facing. Kept live every physics frame so an overlap query at the
## exact active-frame instant is never one frame stale.
func _make_hitbox() -> Area2D:
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = HITBOX_MASK
	area.monitoring = true
	area.monitorable = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(attack_range, HITBOX_HEIGHT)
	shape.shape = rect
	shape.position = Vector2(attack_range / 2.0, 0.0)
	area.add_child(shape)
	call_deferred("add_child", area)
	return area


func _update_hitbox_facing() -> void:
	hitbox.scale.x = -1.0 if sprite.flip_h else 1.0


func _make_sfx_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	call_deferred("add_child", p)
	return p


func _play_sfx(player: AudioStreamPlayer, stream: AudioStream) -> void:
	player.stream = stream
	player.play()


## Live-resizes the hitbox shape -- see player.gd's set_strike_range for why
## setting attack_range directly wouldn't be enough on its own.
func set_attack_range(value: float) -> void:
	attack_range = value
	var shape: CollisionShape2D = hitbox.get_child(0)
	shape.shape.size = Vector2(attack_range, HITBOX_HEIGHT)
	shape.position = Vector2(attack_range / 2.0, 0.0)


## Also refills current_hp to the new max -- see player.gd's set_max_hp.
func set_max_hp(value: float) -> void:
	max_hp = value
	current_hp = max_hp
	hp_changed.emit(current_hp, max_hp)
	hp_fill.size.x = _hp_bar_full_width


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
	var distance_to_player: float = global_position.distance_to(_player.global_position) if _player else 0.0
	for body in hitbox.get_overlapping_bodies():
		if not is_instance_valid(body) or not body.is_in_group("player"):
			continue
		# take_damage() returns false if the player was invincible (mid-dash)
		# -- must not count that as a landed hit (see the matching fix on the
		# player's own _try_hit_enemies for why this matters).
		if body.take_damage(attack_damage):
			_spawn_hit_effect(body.global_position)
			TelemetryLogger.log_enemy_attack(distance_to_player, true, body.current_hp)
			if body.has_method("request_hitstop"):
				body.request_hitstop(body.normal_hit_hitstop_frames, "HIT_PLAYER")
		else:
			TelemetryLogger.log_enemy_attack(distance_to_player, false, 0.0)
		return
	TelemetryLogger.log_enemy_attack(distance_to_player, false, 0.0)


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		_is_attacking = false


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
	sprite.play("hurt")
	var dir: Vector2 = global_position - attacker.global_position
	dir = dir.normalized() if dir != Vector2.ZERO else (Vector2.RIGHT if sprite.flip_h else Vector2.LEFT)
	create_tween().tween_property(self, "global_position", global_position + dir * knockback, 0.1)
	_is_stunned = true
	_stun_timer = 0.3


## Returns false (no-op) if invincible (mid-dodge) -- callers must check this
## before treating a hitbox overlap as an actual landed hit.
func take_damage(amount: float) -> bool:
	if _is_dead or _is_dodging or AdminPanel.npc_invincible:
		return false
	current_hp = max(current_hp - amount, 0.0)
	hp_changed.emit(current_hp, max_hp)
	hp_fill.size.x = _hp_bar_full_width * (current_hp / max_hp)
	if current_hp <= 0.0:
		_die()
	else:
		_is_attacking = false
		sprite.play("hurt")
	return true


func _die() -> void:
	_is_dead = true
	_is_attacking = false
	sprite.play("hurt")
	_spawn_death_sound()
	died.emit()
	await get_tree().create_timer(0.4).timeout
	queue_free()


## Spawned as its own node (not a child of this NPC) because this NPC
## queue_free()s itself shortly after death -- a child AudioStreamPlayer
## would get cut off mid-clip otherwise.
func _spawn_death_sound() -> void:
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	p.stream = DEATH_SOUNDS[randi() % DEATH_SOUNDS.size()]
	get_parent().add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
