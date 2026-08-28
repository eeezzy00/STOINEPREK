extends Node

## Autoload, F2 toggles it. Drives the player at 3x game speed via a simple
## state machine, restarting the run automatically on death so it can grind
## out runs for TelemetryLogger/RunAnalyzer. Continuous movement goes through
## the real move_* input actions; the one-shot attack/dodge are invoked
## directly on the player -- repeatedly calling Input.action_press/release
## for those every tick does not reliably re-trigger
## Input.is_action_just_pressed() edge detection frame to frame, so a direct
## call is the robust way to "click" from a script.

enum State { APPROACH, ATTACK, EVADE, RESET }

const APPROACH_DISTANCE := 80.0
const ATTACK_MIN_DISTANCE := 40.0
const ATTACK_MAX_DISTANCE := 80.0
const BOT_TIME_SCALE := 3.0
const RESET_DELAY := 1.2
const AXIS_DEADZONE := 4.0

var active := false

var _state := State.APPROACH
var _player: Node
var _last_hp := -1.0
var _reset_timer := 0.0


func _ready() -> void:
	set_physics_process(false)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		_toggle()


func _toggle() -> void:
	active = not active
	set_physics_process(active)
	if active:
		Engine.time_scale = BOT_TIME_SCALE
		_state = State.APPROACH
		_acquire_player()
	else:
		Engine.time_scale = 1.0
		_release_movement()


func _acquire_player() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player and not _player.died.is_connected(_on_player_died):
		_player.died.connect(_on_player_died)
	if _player:
		_last_hp = _player.current_hp


func _physics_process(delta: float) -> void:
	if _state == State.RESET:
		_reset_timer -= delta
		if _reset_timer <= 0.0:
			get_tree().reload_current_scene()
			_state = State.APPROACH
			call_deferred("_acquire_player")
		return

	if _player == null or not is_instance_valid(_player):
		_acquire_player()
		return

	if _player.current_hp < _last_hp:
		_state = State.EVADE
	_last_hp = _player.current_hp

	var enemy := _nearest_enemy()
	if enemy == null:
		_release_movement()
		return

	var to_enemy: Vector2 = enemy.global_position - _player.global_position
	var distance := to_enemy.length()

	match _state:
		State.EVADE:
			_release_movement()
			if _player._can_dash():
				_player._start_dash(-to_enemy.normalized())
			_state = State.APPROACH
		State.APPROACH:
			_move_toward(to_enemy)
			if distance <= APPROACH_DISTANCE:
				_state = State.ATTACK
		State.ATTACK:
			if distance > ATTACK_MAX_DISTANCE:
				_state = State.APPROACH
			elif distance < ATTACK_MIN_DISTANCE:
				# Too close to swing -- back off until back in the sweet spot.
				_move_toward(-to_enemy)
			else:
				_release_movement()
				# _update_movement_animation() (which normally sets flip_h)
				# only runs while not attacking, so backing off a moment ago
				# can leave the sprite facing away from the target -- force
				# it to face the enemy right before swinging.
				_player.sprite.flip_h = to_enemy.x < 0.0
				_player._on_attack_pressed(Vector2.ZERO)


func _move_toward(to_enemy: Vector2) -> void:
	_set_axis("move_left", "move_right", to_enemy.x)
	_set_axis("move_up", "move_down", to_enemy.y)


func _set_axis(negative_action: String, positive_action: String, value: float) -> void:
	if value < -AXIS_DEADZONE:
		Input.action_press(negative_action)
		Input.action_release(positive_action)
	elif value > AXIS_DEADZONE:
		Input.action_press(positive_action)
		Input.action_release(negative_action)
	else:
		Input.action_release(negative_action)
		Input.action_release(positive_action)


func _release_movement() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_up")
	Input.action_release("move_down")


func _nearest_enemy() -> Node:
	var best: Node = null
	var best_dist := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var d: float = _player.global_position.distance_to(enemy.global_position)
		if d < best_dist:
			best_dist = d
			best = enemy
	return best


func _on_player_died() -> void:
	_release_movement()
	_state = State.RESET
	_reset_timer = RESET_DELAY
