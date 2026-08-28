extends AnimatedSprite2D

# Standalone showcase rig for the "male_hero_template" asset (Ozzbit Games,
# non-commercial license). Cycles through every animation on a loop so it can
# be eyeballed in-game. Not wired to input or gameplay — for evaluation only.

func _ready() -> void:
	animation_finished.connect(_on_animation_finished)
	_run_showcase_loop()


func _run_showcase_loop() -> void:
	while is_inside_tree():
		play("idle")
		await get_tree().create_timer(1.6).timeout
		play("walk")
		await get_tree().create_timer(1.6).timeout
		play("run")
		await get_tree().create_timer(1.6).timeout
		play("jump")
		await animation_finished
		play("fall_loop")
		await get_tree().create_timer(1.0).timeout
		play("combo1")
		await animation_finished
		play("combo1end")
		await animation_finished


func _on_animation_finished() -> void:
	pass
