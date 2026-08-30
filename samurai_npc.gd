extends CharacterBody2D

const HIT_EFFECT := preload("res://hit_effect.tscn")
const KNOCKBACK_DURATION := 0.1
const STACK_UNSTICK_DURATION := 0.15
## Blip played on every non-whitespace revealed letter while the speech
## bubble types out -- see _on_bubble_letter_spoken().
const TEXT_SFX := preload("res://Audio/Text Fx/text2.mp3")

@export_group("Intro Line")
## Shown once via DialogueManager the first time this NPC spots the player --
## see _show_intro_line(). Fetched as plain text (get_next_dialogue_line, not
## show_dialogue_balloon) and rendered as a speech bubble above this NPC's
## own head instead of the addon's screen-space visual-novel balloon --
## combat keeps running underneath it, no player input needed to dismiss it.
## Swap this in the Inspector to change/remove the line without touching code.
@export var intro_line: DialogueResource = preload("res://dialogue/samurai_intro.dialogue")
@export var speech_bubble_offset_y: float = -100.0
@export var speech_bubble_hold_duration: float = 2.5
@export var speech_bubble_fade_duration: float = 0.35
@export var speech_bubble_font_size: int = 18
## Seconds between each revealed letter (DialogueLabel's default is 0.02, i.e.
## 50 letters/sec -- too fast for TEXT_SFX to finish playing before the next
## letter retriggers it, which just cuts the blip short every time instead of
## it ringing out). Slow this down to roughly match the blip's own length.
@export var speech_bubble_seconds_per_letter: float = 0.045
## Matches level.gd's ACCENT_COLOR -- same neon-pink accent used across the
## pause/death/victory screens.
@export var speech_bubble_color: Color = Color(1, 0.18, 0.66, 1)

## Utility-scored combat actions -- see _score_action(). Only considered
## while _aware (see _update_memory); patrol and the reactive systems
## (defensive dodge, flank roll, squad hold/reinforce) sit outside this and
## are resolved before/instead of it.
enum Action { APPROACH, ATTACK, WAIT_TURN }

## Must stay >= the player's parry_late_limit_frames: this NPC holds its
## damage for that long past its own active-frame moment so a late-but-valid
## player parry always has a chance to cancel it before it lands.
const PARRY_GRACE_FRAMES := 10.0

## Height of the melee hitbox rectangle -- matches debug_visualizer's drawn box.
const HITBOX_HEIGHT := 60.0
## Player is on collision layer 1 -- the hitbox only needs to see that layer.
const HITBOX_MASK := 1
## Walls(4) + player(1) -- deliberately NOT enemies(2): NPCs pass through
## each other so a crowd never physically blocks itself trying to reach the
## player (turn-taking/stand-off already keeps them from all attacking at
## once -- this just keeps them from also jamming each other's movement).
const COLLISION_MASK_NORMAL := 5
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
## Range of the vision cone below -- also just "how far this NPC can
## notice the player at all", same role detect_range always had.
@export var detect_range: float = 260.0
## Full angle (degrees) of the facing-direction vision cone used to decide
## whether this NPC notices the player -- see _can_see_player(). A player
## outside the cone (e.g. behind an NPC facing the other way) goes unnoticed
## even within detect_range.
@export var vision_angle_degrees: float = 55.0
## Seconds an already-noticed player is still tracked (headed toward, via
## _last_known_player_pos) after leaving the vision cone -- see
## _update_memory(). Without this an NPC forgets the instant the player
## ducks out of sight (e.g. jumps past/behind it); with it, it turns to
## face the last-known spot and keeps going there, only giving up and
## returning to patrol once this runs out without re-spotting them.
@export var memory_duration: float = 3.0
## The instant this NPC newly notices the player (not every frame -- only
## the rising edge), it alerts every other enemy within this range: they
## become _aware and head toward the same _last_known_player_pos even
## though their own vision cone never actually saw anything. See
## _alert_nearby_allies()/receive_alert().
@export var alert_call_range: float = 220.0
## Seconds of trying to walk toward a stale _last_known_player_pos while
## making no real progress (wedged against a wall/geometry) before this NPC
## gives up the search and returns to patrol, instead of pushing uselessly
## into an obstacle for the whole memory_duration. Only applies while
## searching (not currently seeing the player) -- see _update_stuck_search().
@export var stuck_give_up_time: float = 0.5
@export var attack_range: float = 46.0
@export var attack_cooldown: float = 1.1
@export var attack_damage: float = 1.0
@export var attack_startup: float = 0.15
## Seconds this NPC is stunned after a parried attack (cancel_attack_parried)
## -- kept at/above the player's own attack_speed (0.5s) so a successful
## parry always leaves a real counter-attack window open. Was 0.3s, shorter
## than the 0.5s swing needed to actually punish it -- landing a hit during
## the "opening" was never possible.
@export var parry_stun_duration: float = 0.55

@export_group("Hit Zones")
## Mirrors player.gd's own Hit Zones group -- how long (seconds) this NPC's
## attack keeps checking for the player after its post-parry-grace window
## opens (see _try_commit_attack_damage), instead of a single instant.
@export var attack_active_duration: float = 0.12
## Fraction of attack_active_duration counted as the sweet spot -- landing
## the hit within this slice deals bonus damage; later in the window deals
## reduced damage.
@export var sweet_spot_ratio: float = 0.35
@export var sweet_spot_damage_multiplier: float = 1.5
@export var late_hit_damage_multiplier: float = 0.75

@export var max_hp: float = 3.0
@export var jump_gravity: float = 900.0
@export var max_fall_speed: float = 1400.0
## Y below which falling off the level counts as death -- set per-level by
## level.gd in _setup_enemies()/register_enemy(), left at INF by default.
@export var death_y: float = INF
## See player.gd's _resolve_character_stacking -- same fix, same reasoning.
@export var stack_push_speed: float = 140.0

@export_group("Dodge")
@export var dodge_distance: float = 60.0
@export var dodge_duration: float = 0.15
@export var dodge_cooldown: float = 1.5
## Chance (0-1) to dodge-roll away the instant the player starts a swing
## within dodge_danger_range -- rolled once per incoming swing, not per frame.
@export var dodge_chance: float = 0.35
@export var dodge_danger_range: float = 90.0

@export_group("Platforming")
## Real jump used only to cross a gap while chasing/reinforcing -- not a
## general combat dodge-jump.
@export var jump_velocity: float = 420.0
## How far ahead of its feet (in its direction of travel) this NPC probes
## for ground before committing to a step, and how deep that probe reaches.
@export var edge_check_ahead: float = 24.0
@export var edge_check_depth: float = 60.0
## Max distance to the player this NPC will attempt to jump a gap for --
## beyond this it just holds at the edge instead of leaping blind.
@export var max_jump_gap: float = 200.0

@export_group("Patrol")
## While not seeing the player, this NPC wanders back and forth within
## patrol_radius of its spawn point instead of standing frozen.
@export var patrol_radius: float = 150.0
@export var patrol_speed_ratio: float = 0.5
@export var patrol_pause_min: float = 1.0
@export var patrol_pause_max: float = 2.5

@export_group("Squad")
## An ally more than this far below (in Y) counts as "a level down" --
## reaching them means crossing a gap, which triggers hold-position instead
## of casually walking/falling down to help.
@export var lower_level_y_threshold: float = 40.0
## Below this fraction of an engaged ally's max HP (or if they've died),
## the nearest holding ally stops holding and commits to reinforce.
@export var reinforce_hp_ratio: float = 0.5

@export_group("AI Pacing")
## After finishing a discrete action (attack, dodge, flank roll) this NPC
## pauses for a random beat in this range before its next decision --
## without it every reaction reads as instant/robotic. Continuous movement
## (chasing) isn't paused mid-stride, only the moment between actions.
@export var think_duration_min: float = 0.15
@export var think_duration_max: float = 0.4
## How often (seconds) this NPC flips which way it's facing while standing
## idle and NOT currently seeing the player -- arrived at the last-known
## spot with nobody there, held up by an uncrossable gap, or paused between
## patrol legs. Not purely cosmetic: facing feeds _can_see_player(), so
## glancing the other way can actually re-spot a player hiding on that side.
@export var scan_interval: float = 0.6

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
@onready var sfx_text: AudioStreamPlayer = _make_sfx_player()

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

var _knockback_timer := 0.0
var _knockback_velocity_x := 0.0
var _stack_unstick_timer := 0.0
var _stack_unstick_velocity_x := 0.0

## Non-null while holding position for a specific lower-level ally that's
## still fighting fine -- read by siblings' _is_nearest_holder_for() so only
## the closest holder breaks formation when that ally needs help.
var _holding_for: Node = null

## "Thinking" beat between discrete actions -- see think_duration_min/max.
var _think_timer := 0.0

## See scan_interval / _update_look_around.
var _scan_timer := 0.0

var _spawn_position := Vector2.ZERO
var _patrol_target_x := 0.0
var _patrol_pause_timer := 0.0

## See memory_duration -- true once the player has ever been spotted and
## still within the memory window (even if not currently in the cone).
var _aware := false
var _last_known_player_pos := Vector2.ZERO
var _memory_timer := 0.0
## Set true the first time this NPC ever spots the player -- gates intro_line
## to a single showing per NPC instance instead of replaying it on every
## re-detection after the player breaks line of sight.
var _intro_line_played := false
var _stuck_timer := 0.0
## True only for frames where _chase_across_terrain actually committed to
## walking (or jumping) toward the search target -- as opposed to holding
## for squad reasons, having just arrived, or not being in APPROACH at all.
## Read post-move_and_slide by _update_stuck_search(), where velocity.x
## itself is unreliable (a wall zeroes it on collision, which would
## otherwise look identical to "chose not to move").
var _attempting_search_move := false


func _ready() -> void:
	sprite.animation_finished.connect(_on_animation_finished)
	current_hp = max_hp
	_hp_bar_full_width = hp_fill.size.x
	_player = get_tree().get_first_node_in_group("player")
	_spawn_position = global_position
	_pick_new_patrol_target()


func _physics_process(delta: float) -> void:
	_update_hitbox_facing()

	# Frozen while the admin panel is open, same reasoning as player.gd.
	if AdminPanel.panel_open:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if not _is_dead and global_position.y > death_y:
		_die()

	# Applies in every branch below (dead/stunned/afk/normal) so this NPC
	# always falls onto and rests on real ground, same as the player.
	if not is_on_floor():
		velocity.y = minf(velocity.y + jump_gravity * delta, max_fall_speed)
	else:
		velocity.y = 0.0

	# Takes priority over every AI branch below -- see _resolve_character_stacking.
	if _stack_unstick_timer > 0.0:
		_stack_unstick_timer = maxf(_stack_unstick_timer - delta, 0.0)
		velocity.x = _stack_unstick_velocity_x
		move_and_slide()
		return

	if _is_dead or _player == null:
		velocity.x = 0.0
		move_and_slide()
		_resolve_character_stacking()
		return

	if _is_stunned:
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			_is_stunned = false
		if _knockback_timer > 0.0:
			_knockback_timer = maxf(_knockback_timer - delta, 0.0)
			velocity.x = _knockback_velocity_x
		else:
			velocity.x = 0.0
		move_and_slide()
		_resolve_character_stacking()
		return

	# AFK: stands down completely (no chase/attack/dodge/flank), but can
	# still be hit and killed normally -- take_damage() isn't gated by this.
	if AdminPanel.npc_afk:
		_is_attacking = false
		_is_dodging = false
		velocity.x = 0.0
		sprite.play("idle")
		move_and_slide()
		_resolve_character_stacking()
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

	var pos_before_x := global_position.x
	_attempting_search_move = false

	if _is_attacking:
		velocity.x = 0.0
	elif _think_timer > 0.0:
		# Deliberate pause between actions -- see think_duration_min/max.
		_think_timer = maxf(_think_timer - delta, 0.0)
		velocity.x = 0.0
		sprite.play("idle")
	else:
		var seeing := _can_see_player()
		_update_memory(seeing, delta)

		if not _aware:
			_update_patrol(delta)
		else:
			# While not currently visible but still within the memory
			# window, chase the last place the player was actually seen
			# instead of the live (unseen) position -- this is what makes
			# the NPC turn to face and head toward where they vanished,
			# rather than either tracking them psychically or forgetting
			# them outright.
			var target_pos: Vector2 = _player.global_position if seeing else _last_known_player_pos
			var to_target: Vector2 = target_pos - global_position
			var target_distance: float = to_target.length()

			var action := _score_action(seeing, target_distance)
			if action != Action.APPROACH:
				_holding_for = null
			match action:
				Action.ATTACK:
					velocity.x = 0.0
					sprite.flip_h = to_target.x < 0.0
					_start_attack()
				Action.WAIT_TURN:
					_hold_at_standoff(to_target, target_distance)
				Action.APPROACH:
					_chase_across_terrain(to_target, delta, seeing)

	move_and_slide()
	_resolve_character_stacking()
	_update_stuck_search(delta, pos_before_x)


## Tracks whether this NPC currently "remembers" the player -- set/refreshed
## every frame the vision cone actually sees them, otherwise counts down and
## eventually lapses back to unaware (patrol). See memory_duration. Alerts
## nearby allies (see _alert_nearby_allies) the instant awareness is newly
## gained, not on every frame it's held.
func _update_memory(seeing: bool, delta: float) -> void:
	if seeing:
		var was_aware := _aware
		_aware = true
		_last_known_player_pos = _player.global_position
		_memory_timer = memory_duration
		if not was_aware:
			_alert_nearby_allies()
			if not _intro_line_played:
				_intro_line_played = true
				_show_intro_line()
	elif _aware:
		_memory_timer = maxf(_memory_timer - delta, 0.0)
		if _memory_timer <= 0.0:
			_aware = false


## Fires once, the instant this NPC newly spots the player -- passes the
## sighting to every other living enemy within alert_call_range so a whole
## cluster reacts to one lookout instead of each member only ever noticing
## independently through its own (narrow) vision cone.
func _alert_nearby_allies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == self or not is_instance_valid(enemy) or enemy.get("_is_dead"):
			continue
		if global_position.distance_to(enemy.global_position) > alert_call_range:
			continue
		if enemy.has_method("receive_alert"):
			enemy.receive_alert(_last_known_player_pos)


## Entry point other NPCs call via _alert_nearby_allies() -- makes this NPC
## aware of a sighting it didn't personally see (no vision-cone check here
## on purpose, that's the whole point of a call-out).
func receive_alert(at_position: Vector2) -> void:
	_aware = true
	_last_known_player_pos = at_position
	_memory_timer = memory_duration


## Gives up early on searching toward a stale _last_known_player_pos if this
## NPC is visibly wedged against something (wall, geometry) rather than
## making real progress -- without this it would just push into the
## obstacle for the whole memory_duration, looking stuck/broken, instead of
## admitting the player is behind unreachable geometry and going back to
## patrol. Gated on _attempting_search_move rather than velocity.x itself:
## move_and_slide() zeroes the blocked axis on a head-on wall hit, which
## would otherwise be indistinguishable from "chose to stand still" (e.g.
## squad hold-position, which must NOT be cut short by this).
func _update_stuck_search(delta: float, pos_before_x: float) -> void:
	if not _aware or _can_see_player() or not _attempting_search_move:
		_stuck_timer = 0.0
		return
	if absf(global_position.x - pos_before_x) < 1.0:
		_stuck_timer += delta
		if _stuck_timer >= stuck_give_up_time:
			_aware = false
			_memory_timer = 0.0
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0


## True if the player is within both detect_range AND this NPC's
## facing-direction vision cone -- the actual "notices the player at all"
## gate. Once already chasing/fighting, facing tracks the player every
## frame elsewhere, so this stays satisfied for the rest of the engagement;
## it's really only a gate on the very first notice (or a stealthy approach
## from directly behind an idle/patrolling NPC).
func _can_see_player() -> bool:
	if _player == null:
		return false
	var to_player: Vector2 = _player.global_position - global_position
	var distance := to_player.length()
	if distance > detect_range:
		return false
	# Point-blank bypass: as distance shrinks toward zero, even a tiny Y gap
	# (collision shape height, hitbox offset, uneven ground) pushes the
	# angle-to-player toward 90 degrees regardless of actual facing, which
	# was rejecting a player standing right next to it -- exactly the
	# "loses sight and walks past right as it closes in to swing" report.
	# Within attack_range you'd notice someone that close no matter which
	# way you're looking.
	if distance <= attack_range:
		return true
	var facing := Vector2(-1.0 if sprite.flip_h else 1.0, 0.0)
	var angle_deg := absf(rad_to_deg(facing.angle_to(to_player)))
	return angle_deg <= vision_angle_degrees / 2.0


## Utility scoring over the combat actions this NPC can choose between on a
## given decision tick, called only while _aware (see _update_memory) --
## everything else (dodge, flank, squad hold/reinforce, patrol) is resolved
## outside this. ATTACK always outranks WAIT_TURN when both are available;
## APPROACH is scored by closing urgency, and is the only option at all
## while not currently seeing (searching toward the last-known position).
func _score_action(seeing: bool, distance: float) -> Action:
	var scores := {Action.APPROACH: 1.0 - clampf(distance / detect_range, 0.0, 1.0)}
	if seeing and distance <= attack_range:
		if _attack_timer <= 0.0 and _can_take_attack_turn():
			scores[Action.ATTACK] = 2.0
		else:
			scores[Action.WAIT_TURN] = 1.5

	var best_action := Action.APPROACH
	var best_score: float = scores[Action.APPROACH]
	for action in scores:
		if scores[action] > best_score:
			best_score = scores[action]
			best_action = action
	return best_action


## True if no other enemy is currently mid-swing, and no other enemy that's
## also ready to attack is closer to the player -- gives a whole squad a
## stable, deterministic turn order instead of everyone piling in on the
## same frame the instant they're all off cooldown.
func _can_take_attack_turn() -> bool:
	var my_dist := global_position.distance_to(_player.global_position)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == self or not is_instance_valid(enemy) or enemy.get("_is_dead"):
			continue
		if enemy.get("_is_attacking") == true:
			return false
		var other_dist: float = enemy.global_position.distance_to(_player.global_position)
		var other_ready: bool = float(enemy.get("_attack_timer")) <= 0.0 \
			and other_dist <= float(enemy.get("attack_range"))
		if other_ready and other_dist < my_dist:
			return false
	return true


## Not this NPC's turn to swing -- hangs back at a slightly wider distance
## instead of freezing shoulder-to-shoulder with the player, so waiting for
## an opening reads as a choice rather than a glitch.
func _hold_at_standoff(to_player: Vector2, distance: float) -> void:
	sprite.flip_h = to_player.x < 0.0
	var stand_off := attack_range * 1.4
	if distance < stand_off:
		velocity.x = -signf(to_player.x) * move_speed * 0.6
		sprite.play("run")
	else:
		velocity.x = 0.0
		sprite.play("idle")


## Chase step that respects real ground: won't walk off an edge blind, will
## jump a gap it judges crossable, and will hold its ground at an edge
## instead of chasing down to a lower level where an ally is already
## fighting -- unless that ally is now in real trouble, see
## _should_hold_position. seeing is passed through only to gate
## _update_look_around -- glancing around make sense while searching, not
## while genuinely chasing a player still in view.
func _chase_across_terrain(to_player: Vector2, delta: float, seeing: bool) -> void:
	# Without an arrival tolerance this NPC would overshoot the target by a
	# step each frame and oscillate sign right on top of it -- harmless
	# against a live, moving player (attack_range is comfortably wider than
	# one step), but against a FIXED point (the last-known position while
	# searching, see _update_memory) the flip-flopping facing could
	# occasionally re-enter the vision cone toward the real player by pure
	# coincidence and never let memory lapse.
	if absf(to_player.x) < 4.0:
		velocity.x = 0.0
		sprite.play("idle")
		if not seeing:
			_update_look_around(delta)
		return

	var dir_x := signf(to_player.x)
	sprite.flip_h = to_player.x < 0.0

	if _should_hold_position(dir_x):
		velocity.x = 0.0
		sprite.play("idle")
		return

	if _has_ground_ahead(dir_x):
		velocity.x = dir_x * move_speed
		sprite.play("run")
		_attempting_search_move = true
		return

	# No ground directly ahead. A player who's meaningfully LOWER is reached
	# by walking off the edge and falling to them -- jumping there only adds
	# upward reach, which used to send this NPC hopping straight back onto
	# the same ledge over and over ("нужно видит меня внизу и с ума сходит").
	# Jumping is reserved for when the player is level with or above the gap.
	if to_player.y > global_position.y + edge_check_depth:
		if _has_safe_landing_ahead(dir_x):
			velocity.x = dir_x * move_speed
			sprite.play("run")
			_attempting_search_move = true
		else:
			# No ground found before the level's death line -- likely a
			# bottomless pit. Hold rather than dive in blind.
			velocity.x = 0.0
			sprite.play("idle")
			if not seeing:
				_update_look_around(delta)
		return

	if to_player.length() <= max_jump_gap:
		velocity.x = dir_x * move_speed
		sprite.play("run")
		_attempting_search_move = true
		if is_on_floor():
			velocity.y = -jump_velocity
		return

	# Gap too wide to trust a blind jump into -- hold at the edge rather
	# than risk falling in trying to reach the player.
	velocity.x = 0.0
	sprite.play("idle")
	if not seeing:
		_update_look_around(delta)


## Glances left/right instead of freezing facing one way -- see
## scan_interval. Not purely cosmetic: facing feeds _can_see_player(), so
## glancing the other way can actually re-spot a player hiding on that side.
func _update_look_around(delta: float) -> void:
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = scan_interval
		sprite.flip_h = not sprite.flip_h


## One-shot downward ray from a point ahead of this NPC's feet, in its
## direction of travel -- no ground within edge_check_depth means the next
## step would be a fall, not a step.
func _has_ground_ahead(dir_x: float) -> bool:
	if dir_x == 0.0:
		return true
	var space := get_world_2d().direct_space_state
	var origin: Vector2 = global_position + Vector2(dir_x * edge_check_ahead, 0.0)
	var query := PhysicsRayQueryParameters2D.create(origin, origin + Vector2(0.0, edge_check_depth))
	query.collision_mask = 4  # Walls only
	query.exclude = [get_rid()]
	var result := space.intersect_ray(query)
	return not result.is_empty()


## Deep probe (all the way down to this level's death_y) from a point ahead
## of this NPC, in its direction of travel -- used only when there's no
## ground within the short edge_check_depth, to tell a real (if long) drop
## to another platform apart from an actual bottomless pit before
## committing to walk off the edge.
func _has_safe_landing_ahead(dir_x: float) -> bool:
	if dir_x == 0.0 or not is_finite(death_y):
		return true
	var space := get_world_2d().direct_space_state
	var origin: Vector2 = global_position + Vector2(dir_x * edge_check_ahead, 0.0)
	var probe_depth: float = death_y - origin.y
	if probe_depth <= 0.0:
		return false
	var query := PhysicsRayQueryParameters2D.create(origin, origin + Vector2(0.0, probe_depth))
	query.collision_mask = 4
	query.exclude = [get_rid()]
	var result := space.intersect_ray(query)
	return not result.is_empty()


## Wander loop used whenever _can_see_player() is false -- walks between
## randomized points within patrol_radius of spawn, pausing between legs,
## and respects the same edge-check as combat movement so patrol never
## walks an NPC off a ledge either.
func _update_patrol(delta: float) -> void:
	if _patrol_pause_timer > 0.0:
		_patrol_pause_timer = maxf(_patrol_pause_timer - delta, 0.0)
		velocity.x = 0.0
		sprite.play("idle")
		_update_look_around(delta)
		return

	var to_target_x := _patrol_target_x - global_position.x
	if absf(to_target_x) < 4.0:
		_patrol_pause_timer = randf_range(patrol_pause_min, patrol_pause_max)
		_pick_new_patrol_target()
		velocity.x = 0.0
		sprite.play("idle")
		return

	var dir_x := signf(to_target_x)
	sprite.flip_h = dir_x < 0.0
	if _has_ground_ahead(dir_x):
		velocity.x = dir_x * move_speed * patrol_speed_ratio
		sprite.play("run")
	else:
		# Patrol never jumps or dives -- just pick a fresh target, which
		# will usually pull it back toward safer ground near spawn.
		_patrol_pause_timer = randf_range(patrol_pause_min, patrol_pause_max)
		_pick_new_patrol_target()
		velocity.x = 0.0
		sprite.play("idle")


func _pick_new_patrol_target() -> void:
	_patrol_target_x = _spawn_position.x + randf_range(-patrol_radius, patrol_radius)


## Nearest other enemy that's meaningfully lower than this one AND actively
## fighting the player (in its own attack range, or mid-swing) -- null if
## no ally down there needs (or has) a fight going.
func _find_engaged_ally_below() -> Node:
	if _player == null:
		return null
	var best: Node = null
	var best_dist := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == self or not is_instance_valid(enemy) or enemy.get("_is_dead"):
			continue
		if enemy.global_position.y <= global_position.y + lower_level_y_threshold:
			continue
		var engaged: bool = enemy.get("_is_attacking") == true \
			or enemy.global_position.distance_to(_player.global_position) <= float(enemy.get("attack_range"))
		if not engaged:
			continue
		var d: float = global_position.distance_to(enemy.global_position)
		if d < best_dist:
			best_dist = d
			best = enemy
	return best


## True only if no other enemy that's ALSO holding for this same ally is
## closer to it -- keeps "the nearest ally reinforces" to a single NPC
## instead of the whole squad piling down at once.
func _is_nearest_holder_for(ally: Node) -> bool:
	var my_dist := global_position.distance_to(ally.global_position)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == self or not is_instance_valid(enemy):
			continue
		if enemy.get("_holding_for") != ally:
			continue
		if enemy.global_position.distance_to(ally.global_position) < my_dist:
			return false
	return true


## Squad discipline: at an edge with no ground ahead, don't chase down to a
## lower level where an ally is already handling the fight -- unless that
## ally is now under half HP or dead, in which case the single nearest
## holder breaks off to help.
func _should_hold_position(dir_x: float) -> bool:
	if _has_ground_ahead(dir_x):
		_holding_for = null
		return false
	var ally := _find_engaged_ally_below()
	if ally == null:
		_holding_for = null
		return false
	_holding_for = ally
	var ally_hp: float = float(ally.get("current_hp"))
	var ally_max_hp: float = float(ally.get("max_hp"))
	var ally_in_trouble: bool = ally_hp <= 0.0 or (ally_max_hp > 0.0 and ally_hp / ally_max_hp < reinforce_hp_ratio)
	if ally_in_trouble and _is_nearest_holder_for(ally):
		_holding_for = null
		return false
	return true


## See player.gd's _resolve_character_stacking -- same fix, same reasoning:
## don't stay balanced on top of another CharacterBody2D, slide off it.
## Arms a timed override (applied at the very top of next frame's
## _physics_process) rather than pushing immediately -- landing on the
## player's head almost always also means being in melee range, and every
## AI branch below sets velocity.x on its own, so a one-frame nudge here
## would just get overwritten right back out next frame.
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
		_think_timer = randf_range(think_duration_min, think_duration_max)


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
## Past that grace period, keeps checking every frame (mirrors player.gd's
## own Hit Zones window) instead of a single instant, graded early/late --
## see _try_commit_damage_in_window.
func _try_commit_attack_damage() -> void:
	if _damage_resolved or _attack_parried:
		return
	var window_open_time := _attack_active_time + PARRY_GRACE_FRAMES / 60.0
	var now := Time.get_ticks_msec() / 1000.0
	if now < window_open_time:
		return
	var active_elapsed := now - window_open_time
	if _try_commit_damage_in_window(active_elapsed):
		_damage_resolved = true
	elif active_elapsed >= attack_active_duration:
		_damage_resolved = true
		var distance_to_player: float = global_position.distance_to(_player.global_position) if _player else 0.0
		TelemetryLogger.log_enemy_attack(distance_to_player, false, 0.0)


## Returns true once the player is found in the hitbox and the swing
## resolves against them (whether or not take_damage() itself is a no-op,
## e.g. the player was mid-dash) -- false means "not there yet, keep the
## window open." active_elapsed grades sweet-spot vs late damage exactly
## like player.gd's _try_hit_enemies.
func _try_commit_damage_in_window(active_elapsed: float) -> bool:
	for body in hitbox.get_overlapping_bodies():
		if not is_instance_valid(body) or not body.is_in_group("player"):
			continue
		var distance_to_player: float = global_position.distance_to(body.global_position)
		var damage := attack_damage
		var sweet_spot_cutoff := attack_active_duration * sweet_spot_ratio
		damage *= sweet_spot_damage_multiplier if active_elapsed <= sweet_spot_cutoff else late_hit_damage_multiplier
		# take_damage() returns false if the player was invincible (mid-dash)
		# -- must not count that as a landed hit (see the matching fix on the
		# player's own _try_hit_enemies for why this matters).
		if body.take_damage(damage):
			_spawn_hit_effect(body.global_position)
			TelemetryLogger.log_enemy_attack(distance_to_player, true, body.current_hp)
			if body.has_method("request_hitstop"):
				body.request_hitstop(body.normal_hit_hitstop_frames, "HIT_PLAYER")
		else:
			TelemetryLogger.log_enemy_attack(distance_to_player, false, 0.0)
		return true
	return false


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		_is_attacking = false
		_think_timer = randf_range(think_duration_min, think_duration_max)


func _spawn_hit_effect(at_position: Vector2) -> void:
	var effect := HIT_EFFECT.instantiate()
	get_parent().add_child(effect)
	effect.global_position = at_position


## Async: get_next_dialogue_line() suspends until DialogueManager resolves the
## "start" cue -- by the time it returns, this NPC could already be dead or
## freed (e.g. the player one-shot it the same frame it spotted them), hence
## the validity/death check before touching self any further.
func _show_intro_line() -> void:
	if intro_line == null:
		return
	var line: DialogueLine = await DialogueManager.get_next_dialogue_line(intro_line, "start")
	if not is_instance_valid(self) or _is_dead or line == null:
		return
	_spawn_speech_bubble(line)


## World-space speech bubble, not the addon's screen-space balloon: a
## DialogueLabel (the addon's own RichTextLabel subclass, reused here for its
## built-in letter-by-letter typewriter, not for its dialogue-graph features)
## added as a sibling of the sprite (so it doesn't inherit sprite.flip_h and
## end up mirror-flipped). Types out with a blip per letter, holds, fades out
## and frees itself -- no player input needed to dismiss it.
func _spawn_speech_bubble(line: DialogueLine) -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Courier New", "Lucida Console", "monospace"])

	var label := DialogueLabel.new()
	label.size = Vector2(220.0, 40.0)
	label.position = Vector2(-110.0, speech_bubble_offset_y)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.bbcode_enabled = true
	label.scroll_active = false
	label.add_theme_font_override("normal_font", font)
	label.add_theme_font_size_override("normal_font_size", speech_bubble_font_size)
	label.add_theme_color_override("default_color", speech_bubble_color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.01, 0.03, 0.95))
	label.add_theme_constant_override("outline_size", 6)
	label.z_index = 10
	label.seconds_per_step = speech_bubble_seconds_per_letter
	label.dialogue_line = line
	add_child(label)

	label.spoke.connect(_on_bubble_letter_spoken)
	label.type_out()
	await label.finished_typing
	if not is_instance_valid(label):
		return

	await get_tree().create_timer(speech_bubble_hold_duration).timeout
	if not is_instance_valid(label):
		return
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 0.0, speech_bubble_fade_duration)
	tween.tween_callback(label.queue_free)


## Skips whitespace so word gaps don't produce a spurious blip between words.
func _on_bubble_letter_spoken(letter: String, _letter_index: int, _speed: float) -> void:
	if letter.strip_edges() == "":
		return
	sfx_text.pitch_scale = randf_range(0.92, 1.08)
	_play_sfx(sfx_text, TEXT_SFX)


## Called by the player the instant a parry beats this NPC's active attack:
## the swing is cancelled (and _try_commit_attack_damage will no longer let
## it land even if already scheduled), this NPC gets knocked back by the
## same distance the parry tier computed, and eats a short stun.
func cancel_attack_parried(_perfect: bool, attacker: Node2D, knockback: float) -> void:
	_attack_parried = true
	_is_attacking = false
	sprite.play("hurt")
	var dir_x := signf(global_position.x - attacker.global_position.x)
	if dir_x == 0.0:
		dir_x = 1.0 if sprite.flip_h else -1.0
	# Real velocity through move_and_slide (see the stunned branch above),
	# not a position tween -- stops at walls/ledges instead of teleporting
	# through them.
	_knockback_velocity_x = dir_x * (knockback / KNOCKBACK_DURATION)
	_knockback_timer = KNOCKBACK_DURATION
	_is_stunned = true
	_stun_timer = parry_stun_duration


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
