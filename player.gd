extends CharacterBody2D

@export var move_speed: float = 250.0
@export var max_hp: float = 3.0
@export var attack_damage: float = 1.0
## Minimum time between attacks. 0.5s = max 2 hits/sec.
@export var attack_speed: float = 0.5
@export var strike_range: float = 50.0
@export var camera_look_ahead: float = 45.0
@export var camera_lead_rate: float = 6.0
## Y below which falling off the level counts as death -- set per-level by
## level.gd in _setup_player(), left at INF (never triggers) by default so
## the standalone player.tscn scene doesn't randomly die if run alone.
@export var death_y: float = INF
## Sideways speed (px/s) applied for a few frames when this body detects it
## landed squarely on top of another CharacterBody2D -- see
## _resolve_character_stacking, breaks the "balanced on someone's head"
## glitch two kinematic bodies can get stuck in.
@export var stack_push_speed: float = 140.0

@export_group("Jump")
## Upward speed (px/s) applied to real velocity.y at takeoff.
## Peak height = jump_velocity^2 / (2*jump_gravity).
@export var jump_velocity: float = 445.0
## Downward acceleration (px/s^2) applied to velocity.y every physics frame
## while airborne -- real gravity, not the old cosmetic hop.
@export var jump_gravity: float = 900.0
@export var max_fall_speed: float = 1400.0
## Seconds after walking off a ledge a jump input still counts as grounded.
@export var coyote_time: float = 0.1
## Seconds a jump press before actually landing is still remembered and
## fires the instant you touch down, instead of being silently dropped.
@export var jump_buffer_time: float = 0.1
## Fraction of upward velocity kept when the jump button is released while
## still rising -- a quick tap yields a short hop, a held press reaches full
## height (Mario/Celeste-style variable jump height). Applies to wall jumps
## too since both share _jump_active.
@export var jump_cut_multiplier: float = 0.45

@export_group("Movement")
## How fast velocity.x ramps toward move_speed while grounded with input held
## (px/s^2). Kept high (reaches top speed in well under a tenth of a second)
## for a snappy, Celeste-like feel rather than a gradual run-up.
@export var ground_acceleration: float = 3200.0
## How fast velocity.x decays to zero while grounded with no input (px/s^2).
@export var ground_friction: float = 4000.0
## Same as above but airborne -- slightly looser than on the ground so a
## jump's arc still feels committed instead of fully steerable mid-air.
@export var air_acceleration: float = 1800.0
@export var air_friction: float = 1400.0
## Fraction of move_speed used while holding the "walk" action (stealth
## mode) -- see is_walking. Also picks the dedicated "walk" animation over
## "run" in _update_movement_animation.
@export var walk_speed_ratio: float = 0.45

@export_group("Wall Movement")
## Downward speed clamp while actively sliding down a wall -- much slower
## than a normal fall; this is what makes clinging to a wall feel like
## clinging instead of just brushing past it on the way down.
@export var wall_slide_speed: float = 90.0
## Push-off speed on a wall jump, away from the wall (x) and upward (y).
@export var wall_jump_speed_x: float = 380.0
@export var wall_jump_speed_y: float = 420.0
## Seconds after a wall jump during which horizontal air control is locked
## to the push-off velocity instead of following input -- without this, the
## very next frame's "velocity.x = move_input * move_speed" would cancel
## the diagonal kick immediately if still holding toward the wall, killing
## the jump before it ever reads as a jump.
@export var wall_jump_control_lock: float = 0.15
## Grace window (like coyote_time, but for walls) after leaving a wall
## during which a jump input still counts as a wall jump.
@export var wall_coyote_time: float = 0.1
## Consecutive wall jumps allowed before a floor landing resets the count --
## without this cap the player could ping-pong straight up between two
## facing walls indefinitely.
@export var max_wall_jump_chain: int = 2

@export_group("Dash")
@export var dash_duration: float = 0.2
@export var dash_distance: float = 60.0
@export var dash_cooldown: float = 2.0
@export var double_tap_window: float = 0.3
## Fraction of dash_duration that must have elapsed before an attack press
## cancels the dash early into a lunging strike -- see _update_dash(). Below
## this point an attack press during a dash is still just dropped, same as
## before this existed.
@export var dash_attack_cancel_ratio: float = 0.6

@export_group("Feel")
## Light freeze-frame on every normal landed hit (not just parries), shared
## by both the player's own swings and the enemy's -- see request_hitstop().
@export var normal_hit_hitstop_frames: float = 2.0
## Sprite scale multiplier applied for an instant on a hard landing, then
## sprung back to normal over landing_squash_duration.
@export var landing_squash_scale: Vector2 = Vector2(1.25, 0.75)
@export var landing_squash_duration: float = 0.12
## How far (px) the camera dips on a hard landing, decaying back to zero at
## the same kind of exponential smoothing as camera_lead_rate.
@export var landing_dip_amount: float = 8.0
@export var landing_dip_recover_rate: float = 8.0
## Fall speed (px/s) a landing must exceed before squash/dust/dip trigger --
## keeps small hops and step-downs from looking exaggerated.
@export var landing_min_fall_speed: float = 250.0

@export_group("Hit Zones")
## How long (seconds) the melee hitbox keeps checking for a target after
## attack_startup elapses -- used to be a single instant, so a target not
## overlapping on that one exact frame made the whole swing whiff for its
## entire duration. Extending it into a real window means the swing keeps
## trying until it lands or the window closes.
@export var attack_active_duration: float = 0.12
## Fraction of attack_active_duration counted as the sweet spot -- landing
## the hit within this slice of the window (from the moment it opens) deals
## bonus damage; landing it later in the window deals reduced damage.
@export var sweet_spot_ratio: float = 0.35
@export var sweet_spot_damage_multiplier: float = 1.5
@export var late_hit_damage_multiplier: float = 0.75

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

const KNOCKBACK_DURATION := 0.1
const STACK_UNSTICK_DURATION := 0.15
const CAMERA_BASE_OFFSET := Vector2(0, -85)
const HIT_EFFECT := preload("res://hit_effect.tscn")
const AFTERIMAGE_COUNT := 4
const AFTERIMAGE_FADE := 0.15
const AFTERIMAGE_COLOR := Color(0.878, 0.251, 0.984, 0.5)
const STREAK_GLOW_COLOR := Color(1.4, 1.1, 0.3, 1)

## Height of the melee hitbox rectangle. Kept in sync with debug_visualizer's
## drawn rectangle so what you see is what actually registers hits.
const HITBOX_HEIGHT := 60.0
## Enemies are on collision layer 2 -- the hitbox only needs to see that layer.
const HITBOX_MASK := 2
## Walls(4) + enemies(2) -- normal solid body collision.
const COLLISION_MASK_NORMAL := 6
## Walls only -- while "phased" (dashing or jumping) the player passes
## through enemy bodies (matches the existing damage-immunity during a
## dash: intangible, not just invincible). Without this, dashing/jumping
## into an enemy would just bounce the player off them via move_and_slide
## instead of sliding/hopping past.
const COLLISION_MASK_PHASED := 4
## Godot checks collision independently from each body's own move_and_slide
## call -- clearing only this body's MASK stops it from being blocked, but
## an enemy would still see this body's LAYER and get blocked *by* it while
## standing still. Clearing collision_layer too makes it invisible to
## everyone else's collision checks as well, for a true two-way phase.
const COLLISION_LAYER_NORMAL := 1
const COLLISION_LAYER_PHASED := 0

## BARE included on purpose: telemetry showed it's ~86% of successful
## parries (the bot's timing is naturally biased toward it), so it was the
## single most common parry outcome with NO spark feedback at all.
const PARRY_SPARK_COLORS := {
	"PERFECT": Color(1.0, 0.85, 0.2, 1),
	"GOOD": Color(1.0, 1.0, 1.0, 1),
	"LATE": Color(0.6, 0.6, 0.6, 1),
	"BARE": Color(0.55, 0.55, 0.6, 1),
}
## More sparks for the tighter-timed tiers -- makes a PERFECT read as a
## bigger deal than a last-instant BARE, on top of the existing
## hitstop/knockback scaling per tier.
const PARRY_SPARK_AMOUNT := {
	"PERFECT": 50,
	"GOOD": 34,
	"LATE": 24,
	"BARE": 16,
}
const ATTACK_SOUNDS := [
	preload("res://Audio/Katana Fx For Playyer/Katana_whoopfx_playeer.wav"),
	preload("res://Audio/Katana Fx For Playyer/Katana_whoopfx_playeer_second.wav"),
]
const DASH_SOUNDS := [
	preload("res://Audio/Dash Fx For Both/Dash_whoop_fx.wav"),
	preload("res://Audio/Dash Fx For Both/Dash_whoop_fx2.wav"),
]
const PARRY_SOUND := preload("res://Audio/Parry Fx/Par_fx.wav")
var _walk_sound: AudioStream = preload("res://Audio/Walk Fx/walksoundforplayer.mp3")

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
@onready var camera: Camera2D = $Camera2D
@onready var dash_smoke: CPUParticles2D = _make_dash_smoke()
@onready var landing_dust: CPUParticles2D = _make_landing_dust()
@onready var spark_particles: CPUParticles2D = _make_spark_particles()
@onready var hitbox: Area2D = _make_hitbox()
@onready var sfx_attack: AudioStreamPlayer = _make_sfx_player()
@onready var sfx_dash: AudioStreamPlayer = _make_sfx_player()
@onready var sfx_parry: AudioStreamPlayer = _make_sfx_player()
@onready var sfx_walk: AudioStreamPlayer = _make_sfx_player()

var _camera_lead_x := 0.0
var _camera_dip_y := 0.0
var _squash_tween: Tween

var current_hp: float
var parries_count := 0

var parry_charges: int
var parry_streak := 0
var last_parry_result := "--"
var _parry_regen_timer := 0.0
var _next_hit_bonus := false

var _is_attacking := false
var _is_dead := false
## True while grounded and holding the "walk" action -- moves at
## walk_speed_ratio instead of full move_speed. Public (no underscore)
## because samurai_npc.gd reads it via get() to shrink its detection range
## against a player who's deliberately moving quietly.
var is_walking := false
## Read by level.gd's _on_player_died() to pick the right telemetry reason.
var death_reason := "defeated_by_enemy"

var _knockback_timer := 0.0
var _knockback_velocity_x := 0.0
var _stack_unstick_timer := 0.0
var _stack_unstick_velocity_x := 0.0
var _attack_index := 0
var _attack_cooldown_timer := 0.0
var _attack_elapsed := 0.0
var _attack_hit_resolved := false

## True only while the current airborne phase was actually started by a jump
## input (as opposed to walking off a ledge) -- gates the landing telemetry
## and the jump-only enemy-phase-through below.
var _jump_active := false
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _jump_start_y := 0.0
var _jump_min_y := 0.0

## True only for frames where this NPC is actually clinging (holding into
## the wall it's touching, airborne, falling) -- as opposed to merely
## brushing a wall in passing. Drives the slower fall-speed clamp and the
## wall-slide read on the animation.
var _is_wall_sliding := false
## Sign of the last touched wall's outward normal (+1 = wall on the left,
## -1 = wall on the right) -- kept even after leaving the wall so
## wall_coyote_time still knows which way to jump away from.
var _wall_normal_x := 0.0
var _wall_coyote_timer := 0.0
var _wall_jump_timer := 0.0
var _wall_jump_velocity_x := 0.0
## Reset on every floor landing (see _physics_process) -- caps how many wall
## jumps in a row are allowed before touching ground again.
var _wall_jump_chain_count := 0

var _is_dashing := false
var _dash_sound_index := 0
var _dash_timer := 0.0
var _dash_cooldown_timer := 0.0
var _dash_velocity := Vector2.ZERO
var _afterimage_timer := 0.0
var _afterimage_count := 0
var _last_tap_time := {
	"move_left": -10.0,
	"move_right": -10.0,
}

var _hitstop_depth := 0
var _time_scale_before_hitstop := 1.0

## Depth-counted like _hitstop_depth -- dash and jump can briefly overlap
## (nothing stops jumping mid-dash or vice versa), and whichever one ends
## first must not restore collision while the other is still active.
var _phase_depth := 0


#region State Machine
## Formal record of "what is the character doing" -- introduced specifically
## to make character-action-style cancels (e.g. dash -> attack, see
## _update_dash) an explicit, declared rule instead of an implicit gap in
## whatever booleans happen to be set. This does NOT replace the existing
## _is_attacking/_is_dashing/etc. flags (removing those would break the
## get()/set() reflection admin_panel.gd, debug_hud.gd and samurai_npc.gd
## already rely on) -- it runs alongside them as the single source of truth
## for "can action X legally interrupt what's happening right now".
enum PlayerState { GROUNDED, AIRBORNE, WALL_SLIDE, DASH, ATTACKING, HURT, DEAD }

## Which states each state may transition into. Mostly codifies what the
## game already permitted implicitly (e.g. attacking mid-air always worked);
## the one new rule this unlocks is DASH -> ATTACKING (see
## dash_attack_cancel_ratio).
const TRANSITIONS := {
	PlayerState.GROUNDED: [PlayerState.AIRBORNE, PlayerState.WALL_SLIDE, PlayerState.DASH, PlayerState.ATTACKING, PlayerState.HURT, PlayerState.DEAD],
	PlayerState.AIRBORNE: [PlayerState.GROUNDED, PlayerState.WALL_SLIDE, PlayerState.DASH, PlayerState.ATTACKING, PlayerState.HURT, PlayerState.DEAD],
	PlayerState.WALL_SLIDE: [PlayerState.AIRBORNE, PlayerState.GROUNDED, PlayerState.ATTACKING, PlayerState.HURT, PlayerState.DEAD],
	PlayerState.DASH: [PlayerState.GROUNDED, PlayerState.AIRBORNE, PlayerState.ATTACKING, PlayerState.HURT, PlayerState.DEAD],
	PlayerState.ATTACKING: [PlayerState.GROUNDED, PlayerState.AIRBORNE, PlayerState.HURT, PlayerState.DEAD],
	PlayerState.HURT: [PlayerState.GROUNDED, PlayerState.AIRBORNE, PlayerState.WALL_SLIDE, PlayerState.DASH, PlayerState.ATTACKING, PlayerState.DEAD],
	PlayerState.DEAD: [],
}

var _state: PlayerState = PlayerState.GROUNDED


func _can_transition(to: PlayerState) -> bool:
	return to in TRANSITIONS.get(_state, [])


func _enter_state(to: PlayerState) -> void:
	_state = to
#endregion


func _ready() -> void:
	sprite.animation_finished.connect(_on_animation_finished)
	# Picks up whatever's currently dialed in on the admin panel -- without
	# this a player spawning after a level switch/restart would silently
	# reset to the hardcoded class defaults instead (see AdminPanel.apply_to_player).
	AdminPanel.apply_to_player(self)
	parry_charges = max_parry_charges
	if _walk_sound is AudioStreamWAV:
		_walk_sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif _walk_sound is AudioStreamMP3:
		_walk_sound.loop = true


func _physics_process(delta: float) -> void:
	# Frozen while the admin panel is open -- otherwise clicking a slider
	# (left mouse button is also the attack input) would throw a punch.
	if AdminPanel.panel_open:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if not _is_dead and global_position.y > death_y:
		death_reason = "fell_off_map"
		_die()

	_attack_cooldown_timer = max(_attack_cooldown_timer - delta, 0.0)
	_dash_cooldown_timer = max(_dash_cooldown_timer - delta, 0.0)
	_update_parry_regen(delta)
	_update_hitbox_facing()

	if _is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		_resolve_character_stacking()
		return

	if _is_dashing:
		_update_dash(delta)
		return

	# Read before move_and_slide() runs this frame -- represents whether we
	# were grounded/on-a-wall going INTO this tick, which is what jump/gravity
	# below need to reason about (move_and_slide() below will overwrite
	# is_on_floor()/is_on_wall() with this frame's result, used afterward for
	# landing detection).
	var was_on_floor := is_on_floor()
	var was_on_wall := is_on_wall()
	var wall_normal := get_wall_normal()

	if _is_attacking:
		_update_attack_active_window(delta)

	var move_input := Input.get_axis("move_left", "move_right")
	is_walking = was_on_floor and Input.is_action_pressed("walk")

	_check_double_tap_dash(move_input)

	if Input.is_action_just_pressed("dash") and _can_dash():
		_start_dash(move_input)
		return

	if Input.is_action_just_pressed("attack"):
		_on_attack_pressed()

	# Wall-slide: airborne, touching a wall, and actively holding into it --
	# holding away (or neutral) just lets you brush past/fall normally, only
	# pressing in clings. was_on_wall already implies not-on-floor is
	# irrelevant to check separately since a body resting in a floor+wall
	# corner reports is_on_floor() true and skips this via the was_on_floor
	# check below.
	if was_on_wall:
		_wall_normal_x = wall_normal.x
	var pressing_into_wall: bool = was_on_wall and move_input != 0.0 \
		and signf(move_input) == -signf(wall_normal.x)
	_is_wall_sliding = not was_on_floor and pressing_into_wall and velocity.y >= 0.0

	# Ambient ground/air/wall-slide classification -- skipped while mid-swing
	# so it doesn't stomp the ATTACKING state _start_attack() just entered
	# this same frame (attacks are allowed mid-air/mid-slide and shouldn't
	# get reclassified away just because the character is still airborne).
	if not _is_attacking:
		if was_on_floor:
			_enter_state(PlayerState.GROUNDED)
		elif _is_wall_sliding:
			_enter_state(PlayerState.WALL_SLIDE)
		else:
			_enter_state(PlayerState.AIRBORNE)

	if was_on_wall and not was_on_floor:
		_wall_coyote_timer = wall_coyote_time
	else:
		_wall_coyote_timer = maxf(_wall_coyote_timer - delta, 0.0)

	if was_on_floor:
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	# Wall jump takes priority over a ground jump when both happen to be
	# available (e.g. stepping off a ledge right next to a wall) -- it's the
	# more specific context. Consumes both grace timers so you can't chain a
	# wall jump straight into a "free" floor-coyote jump on the same press.
	if _jump_buffer_timer > 0.0 and _wall_coyote_timer > 0.0 and not _is_attacking \
			and _wall_jump_chain_count < max_wall_jump_chain:
		_start_wall_jump()
		_jump_buffer_timer = 0.0
		_wall_coyote_timer = 0.0
		_coyote_timer = 0.0
	elif _jump_buffer_timer > 0.0 and _coyote_timer > 0.0 and not _is_attacking:
		_start_jump()
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	# Short-hop: cut the rise short the instant jump is released, instead of
	# always riding out the full jump_velocity arc.
	if Input.is_action_just_released("jump") and _jump_active and velocity.y < 0.0:
		velocity.y *= jump_cut_multiplier

	if was_on_floor and velocity.y >= 0.0:
		velocity.y = 0.0
	elif _is_wall_sliding:
		velocity.y = minf(velocity.y + jump_gravity * delta, wall_slide_speed)
	else:
		velocity.y = minf(velocity.y + jump_gravity * delta, max_fall_speed)

	if _wall_jump_timer > 0.0:
		_wall_jump_timer = maxf(_wall_jump_timer - delta, 0.0)
		velocity.x = _wall_jump_velocity_x
	elif _stack_unstick_timer > 0.0:
		_stack_unstick_timer = maxf(_stack_unstick_timer - delta, 0.0)
		velocity.x = _stack_unstick_velocity_x
	elif _knockback_timer > 0.0:
		_knockback_timer = maxf(_knockback_timer - delta, 0.0)
		velocity.x = _knockback_velocity_x
	elif _is_wall_sliding:
		velocity.x = 0.0
	elif _is_attacking:
		velocity.x = 0.0
	else:
		var target_speed_x := move_input * move_speed * (walk_speed_ratio if is_walking else 1.0)
		var rate: float
		if was_on_floor:
			rate = ground_acceleration if move_input != 0.0 else ground_friction
		else:
			rate = air_acceleration if move_input != 0.0 else air_friction
		velocity.x = move_toward(velocity.x, target_speed_x, rate * delta)

	var fall_speed_before_slide := velocity.y

	move_and_slide()
	_resolve_character_stacking()

	if _jump_active:
		_jump_min_y = minf(_jump_min_y, global_position.y)
	if not was_on_floor and is_on_floor():
		_wall_jump_chain_count = 0
		_on_landed()
		if fall_speed_before_slide >= landing_min_fall_speed:
			_play_landing_impact(fall_speed_before_slide)

	if not _is_attacking:
		_update_movement_animation(move_input)

	_update_camera_lead(delta, move_input)


## Two CharacterBody2Ds landing exactly on top of one another can settle into
## a stable balance point and just sit there stuck -- neither is a floor the
## other should be able to rest on indefinitely. Detect it via the landing
## collision normal and arm a short unstick override (applied next frame,
## see _physics_process) so the top body slides off instead of hanging
## there. Armed as a timed override rather than pushed immediately here,
## because landing on someone's head usually also means being in their
## melee range -- an immediate one-frame nudge just gets zeroed right back
## out by the "_is_attacking -> velocity.x = 0" branch next frame.
func _resolve_character_stacking() -> void:
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if not (collider is CharacterBody2D) or collision.get_normal().y > -0.5:
			continue
		var push_dir := signf(global_position.x - collider.global_position.x)
		if push_dir == 0.0:
			push_dir = 1.0
		_stack_unstick_timer = STACK_UNSTICK_DURATION
		_stack_unstick_velocity_x = push_dir * stack_push_speed
		return


func _update_parry_regen(delta: float) -> void:
	_parry_regen_timer += delta
	if _parry_regen_timer >= parry_regen_interval:
		_parry_regen_timer = 0.0
		if parry_charges < max_parry_charges:
			parry_charges += 1


func _update_camera_lead(delta: float, move_input: float) -> void:
	var target_lead := 0.0
	if not _is_attacking:
		if move_input > 0.1:
			target_lead = camera_look_ahead
		elif move_input < -0.1:
			target_lead = -camera_look_ahead
	var t: float = 1.0 - exp(-camera_lead_rate * delta)
	_camera_lead_x = lerp(_camera_lead_x, target_lead, t)

	var dip_t: float = 1.0 - exp(-landing_dip_recover_rate * delta)
	_camera_dip_y = lerp(_camera_dip_y, 0.0, dip_t)

	camera.position = CAMERA_BASE_OFFSET + Vector2(_camera_lead_x, _camera_dip_y)


## Air attacks are allowed -- _update_movement_animation only runs when
## not _is_attacking, so the attack animation is never fought over by the
## jump/fall animation the way the old cosmetic-hop system used to.
func _on_attack_pressed() -> void:
	if _is_attacking or _attack_cooldown_timer > 0.0:
		return
	_attack_cooldown_timer = attack_speed
	_start_attack()


func _start_attack() -> void:
	_enter_state(PlayerState.ATTACKING)
	_is_attacking = true
	_attack_elapsed = 0.0
	_attack_hit_resolved = false
	var anim := "attack" if _attack_index == 0 else "attack2"
	_play_sfx(sfx_attack, ATTACK_SOUNDS[_attack_index])
	_attack_index = 1 - _attack_index
	# _update_movement_animation (which owns speed_scale) never runs while
	# _is_attacking, so a walk-slowed speed_scale from the frame before would
	# otherwise stick and play the swing itself in slow motion.
	sprite.speed_scale = 1.0
	sprite.play(anim)
	if sfx_walk.playing:
		sfx_walk.stop()


## Hit registration checks every frame once the swing's hitbox goes "active"
## (attack_startup elapsed), not just once at that first instant -- see
## _resolve_attack_hit. Keeps trying until something resolves or
## attack_active_duration runs out, at which point it's a confirmed total
## whiff (see _log_total_whiff).
func _update_attack_active_window(delta: float) -> void:
	if _attack_hit_resolved:
		return
	_attack_elapsed += delta
	if _attack_elapsed < attack_startup:
		return
	var active_elapsed := _attack_elapsed - attack_startup
	if _resolve_attack_hit(active_elapsed):
		_attack_hit_resolved = true
	elif active_elapsed >= attack_active_duration:
		_attack_hit_resolved = true
		_log_total_whiff()


## Returns true once this swing has actually resolved against something --
## either a parry clash or a landed/attempted normal hit -- false means
## "nobody in range yet, keep the window open and try again next frame".
func _resolve_attack_hit(active_elapsed: float) -> bool:
	var enemy := _find_active_attacking_enemy()
	if enemy != null:
		_resolve_parry_attempt(enemy)
		return true
	return _try_hit_enemies(active_elapsed)


## Called only when the active window closes with nobody ever found in the
## hitbox -- previously logged inline in _try_hit_enemies on the single
## instant that used to exist.
func _log_total_whiff() -> void:
	var nearest_distance := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			nearest_distance = minf(nearest_distance, global_position.distance_to(enemy.global_position))
	if nearest_distance < INF:
		TelemetryLogger.log_attack("FORWARD", nearest_distance, false)


## Forward-only melee hitbox: a rectangle in front of the character, flipped
## to match facing. Kept live every physics frame (not just while attacking)
## so an overlap query at the exact active-frame instant is never one frame stale.
func _make_hitbox() -> Area2D:
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = HITBOX_MASK
	area.monitoring = true
	area.monitorable = false
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	area.add_child(shape)
	call_deferred("add_child", area)
	call_deferred("_resize_hitbox_shape")
	return area


func _update_hitbox_facing() -> void:
	hitbox.scale.x = -1.0 if sprite.flip_h else 1.0


## Sizes/positions the hitbox from strike_range/HITBOX_HEIGHT scaled by the
## sprite's own current scale -- the hitbox is a sibling of AnimatedSprite2D
## (child of the CharacterBody2D root), not a child of it, so it does NOT
## automatically inherit sprite.scale the way it would if the whole root
## were scaled instead. Without this, bumping the sprite's scale up to make
## the character look bigger silently leaves the real hit/parry reach at
## the old (now visually undersized) raw pixel value -- swings that look
## like they connect on screen just don't, because the actual Area2D never
## reaches that far.
func _resize_hitbox_shape() -> void:
	var shape: CollisionShape2D = hitbox.get_child(0)
	var rect: RectangleShape2D = shape.shape
	var scaled_range := strike_range * sprite.scale.x
	var scaled_height := HITBOX_HEIGHT * sprite.scale.y
	rect.size = Vector2(scaled_range, scaled_height)
	shape.position = Vector2(scaled_range / 2.0, 0.0)


## Live-resizes the hitbox shape -- setting strike_range directly would not
## touch the already-built CollisionShape2D, so callers who need the change
## to actually take effect (e.g. the admin panel) must go through this.
func set_strike_range(value: float) -> void:
	strike_range = value
	_resize_hitbox_shape()


## Also refills current_hp to the new max -- convenient for live-tuning
## (the admin panel), where you want to see the new HP right away.
func set_max_hp(value: float) -> void:
	max_hp = value
	current_hp = max_hp
	hp_changed.emit(current_hp, max_hp)


## A hit only counts as a parry-eligible clash if the enemy's OWN swing could
## actually reach us -- not just "some enemy somewhere is mid-animation".
## Without the enemy_hitbox overlap check, attacking an enemy that's mid-swing
## but facing away (e.g. right after dashing past/behind them) would hijack a
## clean hit into a parry attempt -- one that then fails (we weren't timing a
## parry), silently dealing zero damage instead of landing normally.
func _find_active_attacking_enemy() -> Node:
	for body in hitbox.get_overlapping_bodies():
		if not is_instance_valid(body):
			continue
		if body.get("_is_attacking") != true:
			continue
		var enemy_hitbox: Area2D = body.get("hitbox")
		if enemy_hitbox == null or not enemy_hitbox.get_overlapping_bodies().has(self):
			continue
		return body
	return null


## Compares this swing's active-frame moment against the enemy's own
## (already scheduled, possibly future) active-frame moment. Symmetric --
## being early counts the same as being late.
func _resolve_parry_attempt(enemy: Node) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var enemy_active_time: float = enemy.get("_attack_active_time")
	var frames_late := absf(now - enemy_active_time) * 60.0

	if frames_late <= parry_late_limit_frames and parry_charges > 0:
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
	_enter_state(PlayerState.HURT)
	_is_attacking = false

	var tier := _parry_tier(frames_late)
	last_parry_result = tier
	## Trimmed down from the old 15-80px range -- with real gravity now in
	## play, that used to be able to shove the player clean off a platform
	## edge, which read as far more violent than the old free-move version.
	var knockback: float = maxf(12.0, 55.0 - (frames_late / 10.0) * 40.0)

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
	_spawn_parry_spark(tier, clash_point)
	_play_sfx(sfx_parry, PARRY_SOUND)

	TelemetryLogger.log_parry(tier, knockback)

	sprite.play("hurt_flash")
	await _apply_hitstop(PARRY_HITSTOP_FRAMES[tier] / 60.0, "PARRY_" + tier)

	_knockback_away_from(enemy.global_position, knockback)
	if enemy.has_method("cancel_attack_parried"):
		enemy.cancel_attack_parried(tier == "PERFECT", self, knockback)


func _apply_parry_fail() -> void:
	_enter_state(PlayerState.HURT)
	_is_attacking = false

	last_parry_result = "MISS"
	parry_streak = 0
	_update_streak_visual()
	TelemetryLogger.log_parry("MISS", 0.0)
	sprite.play("hurt_flash")


## Shared, global freeze-frame -- Engine.time_scale affects the whole game,
## so the enemy routes its own hit-stop requests through this same instance
## (via request_hitstop) rather than each actor tracking time_scale itself,
## which would fight over who gets to restore it.
func request_hitstop(frames: float, reason: String) -> void:
	_apply_hitstop(frames / 60.0, reason)


func _apply_hitstop(duration: float, reason: String = "") -> void:
	if duration <= 0.0:
		return
	TelemetryLogger.log_hitstop(duration * 60.0, reason)
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


## Horizontal-only, and driven through velocity + move_and_slide (not a
## position tween) so it stops at walls/ledges like any other movement
## instead of teleporting through geometry -- see _physics_process, which
## substitutes _knockback_velocity_x for input while _knockback_timer > 0.
func _knockback_away_from(source_pos: Vector2, distance: float) -> void:
	var dir_x := signf(global_position.x - source_pos.x)
	if dir_x == 0.0:
		dir_x = -1.0 if sprite.flip_h else 1.0
	_knockback_velocity_x = dir_x * (distance / KNOCKBACK_DURATION)
	_knockback_timer = KNOCKBACK_DURATION


func _spawn_parry_spark(tier: String, at_position: Vector2) -> void:
	spark_particles.color = PARRY_SPARK_COLORS.get(tier, Color.WHITE)
	spark_particles.amount = PARRY_SPARK_AMOUNT.get(tier, 14)
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
	p.initial_velocity_max = 260.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	p.damping_min = 300.0
	p.damping_max = 400.0
	call_deferred("add_child", p)
	return p


func _make_sfx_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	call_deferred("add_child", p)
	return p


func _play_sfx(player: AudioStreamPlayer, stream: AudioStream) -> void:
	player.stream = stream
	player.play()


func _update_movement_animation(move_input: float) -> void:
	# Skipped during the wall-jump control lock -- otherwise, still holding
	# into the wall you just pushed off from would immediately flip facing
	# back toward it, visually contradicting a jump that's actually carrying
	# you the other way (_start_wall_jump already set the correct facing).
	if move_input != 0.0 and _wall_jump_timer <= 0.0:
		sprite.flip_h = move_input < 0.0

	if not is_on_floor():
		sprite.speed_scale = 1.0
		if velocity.y < 0.0:
			if sprite.animation != "jump":
				sprite.play("jump")
		elif sprite.animation != "fall":
			sprite.play("fall")
		if sfx_walk.playing:
			sfx_walk.stop()
		return

	if move_input != 0.0:
		sprite.play("walk" if is_walking else "run")
	else:
		sprite.play("idle")
	sprite.speed_scale = 1.0
	# Walk loop plays only while actually moving on the ground -- not
	# during attacks/dashes/airborne (those branches never reach here).
	if move_input != 0.0:
		if not sfx_walk.playing:
			sfx_walk.stream = _walk_sound
			sfx_walk.play()
	elif sfx_walk.playing:
		sfx_walk.stop()


#region Dash
func _can_dash() -> bool:
	return not _is_dashing and not _is_attacking and not _is_dead and _dash_cooldown_timer <= 0.0


func _check_double_tap_dash(_move_input: float) -> void:
	for action in _last_tap_time.keys():
		if Input.is_action_just_pressed(action):
			var now := Time.get_ticks_msec() / 1000.0
			if now - _last_tap_time[action] <= double_tap_window and _can_dash():
				_start_dash(-1.0 if action == "move_left" else 1.0)
			_last_tap_time[action] = now


## Ground dodge-roll, horizontal only (matches Dead Cells) -- vertical
## momentum is held at zero for the whole dash, see _update_dash.
func _start_dash(dir_x: float) -> void:
	var dir := signf(dir_x) if dir_x != 0.0 else (-1.0 if sprite.flip_h else 1.0)
	_enter_state(PlayerState.DASH)
	_is_dashing = true
	_dash_timer = 0.0
	_dash_cooldown_timer = dash_cooldown
	_dash_velocity = Vector2(dir * (dash_distance / dash_duration), 0.0)
	_afterimage_timer = 0.0
	_afterimage_count = 0
	_enter_phase()
	sprite.speed_scale = 1.0
	sprite.play("dash")
	dash_smoke.restart()
	dash_smoke.emitting = true
	if sfx_walk.playing:
		sfx_walk.stop()
	_play_sfx(sfx_dash, DASH_SOUNDS[_dash_sound_index])
	_dash_sound_index = 1 - _dash_sound_index
	TelemetryLogger.log_dash(global_position, dash_cooldown)


func _update_dash(delta: float) -> void:
	velocity = _dash_velocity
	move_and_slide()

	_dash_timer += delta
	_afterimage_timer += delta
	var afterimage_interval := dash_duration / float(AFTERIMAGE_COUNT)
	if _afterimage_timer >= afterimage_interval and _afterimage_count < AFTERIMAGE_COUNT:
		_spawn_afterimage()
		_afterimage_timer = 0.0
		_afterimage_count += 1

	# Dash-cancel-into-attack: once far enough into the dash's arc (see
	# dash_attack_cancel_ratio), an attack press cuts it short into a lunging
	# strike instead of being dropped for the rest of the dash's duration --
	# the one new character-action cancel the state machine exists to allow.
	var cancel_window_open := _dash_timer >= dash_duration * dash_attack_cancel_ratio
	if cancel_window_open and _attack_cooldown_timer <= 0.0 \
			and Input.is_action_just_pressed("attack") and _can_transition(PlayerState.ATTACKING):
		_is_dashing = false
		_exit_phase()
		_attack_cooldown_timer = attack_speed
		_start_attack()
		return

	if _dash_timer >= dash_duration:
		_is_dashing = false
		_exit_phase()


func _enter_phase() -> void:
	if _phase_depth == 0:
		collision_mask = COLLISION_MASK_PHASED
		collision_layer = COLLISION_LAYER_PHASED
	_phase_depth += 1


func _exit_phase() -> void:
	_phase_depth = maxi(_phase_depth - 1, 0)
	if _phase_depth == 0:
		collision_mask = COLLISION_MASK_NORMAL
		collision_layer = COLLISION_LAYER_NORMAL


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
#endregion


## Squash-stretch, dust puff, and a camera dip on a hard landing -- purely
## cosmetic feedback, gated by landing_min_fall_speed so ordinary step-downs
## don't trigger it. intensity scales 0..1 with fall speed relative to
## max_fall_speed, so a fast fall reads as a heavier impact than a shallow one.
func _play_landing_impact(fall_speed: float) -> void:
	var intensity := clampf(fall_speed / max_fall_speed, 0.0, 1.0)

	var base_scale := sprite.scale
	var squash := Vector2(1.0, 1.0).lerp(landing_squash_scale, intensity)
	sprite.scale = Vector2(base_scale.x * squash.x, base_scale.y * squash.y)
	if _squash_tween and _squash_tween.is_valid():
		_squash_tween.kill()
	_squash_tween = create_tween()
	_squash_tween.tween_property(sprite, "scale", base_scale, landing_squash_duration) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	landing_dust.global_position = global_position
	landing_dust.amount = roundi(lerp(6.0, 16.0, intensity))
	landing_dust.restart()
	landing_dust.emitting = true

	_camera_dip_y = landing_dip_amount * intensity


func _make_landing_dust() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 10
	p.lifetime = 0.3
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 50.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 120.0
	p.gravity = Vector2(0, 260)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = Color(0.55, 0.5, 0.55, 0.7)
	call_deferred("add_child", p)
	return p


func get_dash_cooldown() -> float:
	return _dash_cooldown_timer


## enter_phase() drops enemy collision for the whole time we're airborne (see
## _on_landed for the matching exit) -- same trick the dash uses -- so a jump
## can actually clear an NPC instead of bouncing off them mid-air.
#region Jump and Wall Jump
func _start_jump() -> void:
	_enter_state(PlayerState.AIRBORNE)
	velocity.y = -jump_velocity
	_jump_active = true
	_jump_start_y = global_position.y
	_jump_min_y = global_position.y
	_enter_phase()
	sprite.play("jump")
	if sfx_walk.playing:
		sfx_walk.stop()


## Diagonal push-off, away from whichever wall was last touched -- a full
## velocity reset (not additive), so it always reads the same regardless of
## how fast you were already sliding down. Shares the jump-telemetry/
## enemy-phase machinery with a normal jump (_jump_active et al.) since it's
## still fundamentally "airborne from an intentional jump input", just off
## a wall instead of the floor.
func _start_wall_jump() -> void:
	var away_dir := signf(_wall_normal_x) if _wall_normal_x != 0.0 else (1.0 if sprite.flip_h else -1.0)
	_enter_state(PlayerState.AIRBORNE)
	velocity = Vector2(away_dir * wall_jump_speed_x, -wall_jump_speed_y)
	_wall_jump_velocity_x = velocity.x
	_wall_jump_timer = wall_jump_control_lock
	_wall_jump_chain_count += 1
	_is_wall_sliding = false
	sprite.flip_h = away_dir < 0.0
	_jump_active = true
	_jump_start_y = global_position.y
	_jump_min_y = global_position.y
	_enter_phase()
	sprite.play("jump")
	if sfx_walk.playing:
		sfx_walk.stop()


## Called the frame is_on_floor() flips false->true. Only true landings from
## an actual jump (not walking off a ledge, which never sets _jump_active)
## exit the enemy-phase and log jump telemetry.
func _on_landed() -> void:
	if not _jump_active:
		return
	_jump_active = false
	_exit_phase()
	TelemetryLogger.log_jump(_jump_start_y - _jump_min_y)
#endregion


func _on_animation_finished() -> void:
	if sprite.animation == "attack" or sprite.animation == "attack2":
		_is_attacking = false
	elif sprite.animation == "hurt_flash":
		sprite.play("hurt")


## active_elapsed is how far past attack_startup we are, in seconds -- 0.0
## the instant the window opens, up to attack_active_duration when it's
## about to close -- used to grade sweet-spot vs late damage. Returns false
## (window stays open, try again next frame) only when nobody is in the
## hitbox at all yet; once someone is, this always resolves the swing even
## if take_damage() itself is a no-op (target invincible mid-dodge/mid-dash),
## matching the old single-instant behavior.
func _try_hit_enemies(active_elapsed: float) -> bool:
	var damage := attack_damage
	var sweet_spot_cutoff := attack_active_duration * sweet_spot_ratio
	damage *= sweet_spot_damage_multiplier if active_elapsed <= sweet_spot_cutoff else late_hit_damage_multiplier
	if _next_hit_bonus:
		damage *= 2.0
		_next_hit_bonus = false
		parry_streak = 0
		_update_streak_visual()

	var hit_any := false
	var found_any := false
	for body in hitbox.get_overlapping_bodies():
		if not is_instance_valid(body) or not body.is_in_group("enemies"):
			continue
		found_any = true
		var distance: float = global_position.distance_to(body.global_position)
		# take_damage() returns false if the target was invincible (mid-dodge,
		# mid-dash) -- the hitbox still geometrically overlapped it, but no
		# damage actually landed, so this must NOT count as a hit (that was
		# silently swallowed before: HIT/hitstop/vfx fired even when the
		# target had already dodged clean out of the swing's real reach).
		if body.take_damage(damage):
			_spawn_hit_effect(body.global_position)
			TelemetryLogger.log_attack("FORWARD", distance, true, body.current_hp)
			hit_any = true
		else:
			TelemetryLogger.log_attack("FORWARD", distance, false)

	if hit_any:
		_apply_hitstop(normal_hit_hitstop_frames / 60.0, "HIT_ENEMY")

	return found_any


func _spawn_hit_effect(at_position: Vector2) -> void:
	var effect := HIT_EFFECT.instantiate()
	get_parent().add_child(effect)
	effect.global_position = at_position


## Returns false (no-op) if invincible (dashing) -- callers must check this
## before treating a hitbox overlap as an actual landed hit.
func take_damage(amount: float) -> bool:
	if _is_dead or _is_dashing or AdminPanel.player_invincible:
		return false

	current_hp = max(current_hp - amount, 0.0)
	hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0.0:
		_die()
	else:
		_enter_state(PlayerState.HURT)
		_is_attacking = false
		sprite.play("hurt_flash")
	return true


func _die() -> void:
	_enter_state(PlayerState.DEAD)
	_is_dead = true
	_is_attacking = false
	if sfx_walk.playing:
		sfx_walk.stop()
	# _is_dead short-circuits _physics_process before _update_movement_animation
	# ever runs again, so a stale walk speed_scale would otherwise play the
	# death animation in slow motion for good.
	sprite.speed_scale = 1.0
	sprite.play("death")
	died.emit()
