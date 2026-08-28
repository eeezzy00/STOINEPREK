extends Node

## Autoload. F2 toggles endless farming (grinds runs forever, restarting on
## both death and victory). F3 starts a capped batch of runs_per_batch runs
## that stops itself when done -- useful for "run N times and give me the
## numbers" instead of babysitting F2 and stopping it by hand.
##
## Drives the player at 3x game speed via a simple state machine. Continuous
## movement goes through the real move_* input actions; the one-shot
## attack/dodge are invoked directly on the player -- repeatedly calling
## Input.action_press/release for those every tick does not reliably
## re-trigger Input.is_action_just_pressed() edge detection frame to frame,
## so a direct call is the robust way to "click" from a script.

enum State { APPROACH, ATTACK, EVADE, RESET }

## Attack engage/back-off distances are fractions of the player's actual
## strike_range (read live each frame, not cached) -- strike_range is
## tunable via the admin panel, and fixed pixel constants here would drift
## out of sync with it, guaranteeing whiffs whenever it's been retuned.
const ATTACK_MAX_RATIO := 0.7
const ATTACK_MIN_RATIO := 0.2
## Random delay (seconds) between "in range, decided to attack" and
## actually pressing -- see _update_pending_attack for why this matters.
const ATTACK_REACTION_JITTER := 0.2
const BOT_TIME_SCALE := 3.0
const RESET_DELAY := 1.2
const AXIS_DEADZONE := 4.0

## How many runs an F3 batch performs before stopping itself.
@export var runs_per_batch: int = 10

var active := false

var _state := State.APPROACH
var _player: Node
var _last_hp := -1.0
var _reset_timer := 0.0

var _batch_mode := false
var _batch_runs_done := 0

var _pending_attack := false
var _attack_press_delay := 0.0


func _ready() -> void:
	set_physics_process(false)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			_toggle()
		elif event.keycode == KEY_F3:
			_start_batch()


func _toggle() -> void:
	if active:
		_deactivate()
	else:
		_batch_mode = false
		_activate()


func _start_batch() -> void:
	_batch_mode = true
	_batch_runs_done = 0
	if not active:
		_activate()
	print("AutoPlayBot: starting batch of %d runs" % runs_per_batch)


func _activate() -> void:
	active = true
	set_physics_process(true)
	Engine.time_scale = BOT_TIME_SCALE
	_state = State.APPROACH
	_acquire_player()


func _deactivate() -> void:
	active = false
	set_physics_process(false)
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
	var attack_max: float = _player.strike_range * ATTACK_MAX_RATIO
	var attack_min: float = _player.strike_range * ATTACK_MIN_RATIO

	match _state:
		State.EVADE:
			_release_movement()
			_pending_attack = false
			if _player._can_dash():
				_player._start_dash(-to_enemy.normalized())
			_state = State.APPROACH
		State.APPROACH:
			_pending_attack = false
			_move_toward(to_enemy)
			if distance <= attack_max:
				_state = State.ATTACK
		State.ATTACK:
			if distance > attack_max:
				_pending_attack = false
				_state = State.APPROACH
			elif distance < attack_min:
				# Too close to swing -- back off until back in the sweet spot.
				_pending_attack = false
				_move_toward(-to_enemy)
			else:
				_release_movement()
				# _update_movement_animation() (which normally sets flip_h)
				# only runs while not attacking, so backing off a moment ago
				# can leave the sprite facing away from the target -- force
				# it to face the enemy right before swinging.
				_player.sprite.flip_h = to_enemy.x < 0.0
				_update_pending_attack(delta)


## Fires the attack after a small randomized delay instead of the instant
## the bot enters range. An instant press always lands at almost exactly
## the same frames_late relative to the enemy's own swing (both sides tend
## to engage at roughly the same distance/time), which skews every clash to
## the weakest BARE parry tier -- not because parry timing is actually
## that unforgiving, just because the bot's "reflex" is unrealistically
## consistent. The jitter spreads clashes across the real timing tiers,
## which is the point of farming this bot for parry-balance data at all.
func _update_pending_attack(delta: float) -> void:
	if not _pending_attack:
		_pending_attack = true
		_attack_press_delay = randf_range(0.0, ATTACK_REACTION_JITTER)
	_attack_press_delay -= delta
	if _attack_press_delay <= 0.0:
		_pending_attack = false
		_player._on_attack_pressed()


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
	request_restart()


## Called on both death and victory (see level.gd) to end the current run and
## start the next one. In batch mode this also counts the finished run and,
## once runs_per_batch is reached, stops the bot instead of restarting.
func request_restart() -> void:
	_release_movement()
	if _batch_mode:
		_batch_runs_done += 1
		print("AutoPlayBot: batch run %d/%d complete" % [_batch_runs_done, runs_per_batch])
		if _batch_runs_done >= runs_per_batch:
			print("AutoPlayBot: batch finished, stopping")
			_batch_mode = false
			_deactivate()
			return
	_state = State.RESET
	_reset_timer = RESET_DELAY
