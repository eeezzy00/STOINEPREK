extends CharacterBody2D

@export var move_speed: float = 220.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _is_attacking := false


func _ready() -> void:
	sprite.animation_finished.connect(_on_animation_finished)


func _physics_process(_delta: float) -> void:
	var move_input := Input.get_axis("move_left", "move_right")

	if Input.is_action_just_pressed("attack") and not _is_attacking:
		_start_attack()

	if _is_attacking:
		velocity = Vector2.ZERO
	else:
		velocity = Vector2(move_input * move_speed, 0.0)
		_update_movement_animation(move_input)

	move_and_slide()


func _update_movement_animation(move_input: float) -> void:
	if move_input != 0.0:
		sprite.flip_h = move_input < 0.0
	sprite.play("run" if move_input != 0.0 else "idle")


func _start_attack() -> void:
	_is_attacking = true
	sprite.play("attack")


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		_is_attacking = false


func take_damage() -> void:
	sprite.play("hurt")
