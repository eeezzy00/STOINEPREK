extends Node

## Autoload. Raw per-event logging plus per-run aggregates, all written under
## res://BAG so the data lives in the project folder instead of user://.

const BAG_DIR := "res://BAG"
const TELEMETRY_DIR := BAG_DIR + "/telemetry"
const RUNS_SUMMARY_PATH := BAG_DIR + "/runs_summary.csv"

var run_count := 0

var attacks_landed := 0
var attacks_missed := 0
var parry_attempts := 0
var parry_successes := 0
var parry_perfects := 0
var dash_count := 0
var kills := 0
var jumps := 0
var npc_dodges := 0
var hit_distances: Array[float] = []
var miss_distances: Array[float] = []

var _log_file: FileAccess
var _run_start_time := 0.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(TELEMETRY_DIR)


func start_run() -> void:
	run_count += 1
	_run_start_time = Time.get_ticks_msec() / 1000.0
	attacks_landed = 0
	attacks_missed = 0
	parry_attempts = 0
	parry_successes = 0
	parry_perfects = 0
	dash_count = 0
	kills = 0
	jumps = 0
	npc_dodges = 0
	hit_distances.clear()
	miss_distances.clear()

	if _log_file:
		_log_file.close()
	var d := Time.get_datetime_dict_from_system()
	var stamp := "%04d%02d%02d_%02d%02d%02d" % [d.year, d.month, d.day, d.hour, d.minute, d.second]
	_log_file = FileAccess.open("%s/run_%s.log" % [TELEMETRY_DIR, stamp], FileAccess.WRITE)
	_write("RUN_START run=%d" % run_count)
	_write("SETTINGS player=%s npc=%s cheats=%s" % [
		JSON.stringify(AdminPanel._player_values),
		JSON.stringify(AdminPanel._npc_overrides),
		JSON.stringify({
			"player_invincible": AdminPanel.player_invincible,
			"npc_invincible": AdminPanel.npc_invincible,
			"npc_afk": AdminPanel.npc_afk,
		}),
	])

	if has_node("/root/RunAnalyzer"):
		get_node("/root/RunAnalyzer").hide()


func run_elapsed() -> float:
	return Time.get_ticks_msec() / 1000.0 - _run_start_time


func log_attack(direction: String, distance: float, hit: bool, target_hp_after: float = -1.0) -> void:
	var hp_str := " target_hp=%.1f" % target_hp_after if hit and target_hp_after >= 0.0 else ""
	_write("ATTACK actor=PLAYER dir=%s distance=%.1f result=%s%s" % [direction, distance, "HIT" if hit else "MISS", hp_str])
	if hit:
		attacks_landed += 1
		hit_distances.append(distance)
	else:
		attacks_missed += 1
		miss_distances.append(distance)


## Mirrors log_attack but for the enemy's swings at the player -- kept
## separate from attacks_landed/attacks_missed, which stay player-specific
## for the existing RunAnalyzer summary.
func log_enemy_attack(distance: float, hit: bool, player_hp_after: float) -> void:
	var hp_str := " player_hp=%.1f" % player_hp_after if hit else ""
	_write("ATTACK actor=ENEMY distance=%.1f result=%s%s" % [distance, "HIT" if hit else "MISS", hp_str])


func log_jump(peak_height: float) -> void:
	jumps += 1
	_write("JUMP actor=PLAYER peak_height=%.1f" % peak_height)


func log_npc_dodge(kind: String, pos: Vector2) -> void:
	npc_dodges += 1
	_write("DODGE actor=ENEMY kind=%s pos=(%.1f,%.1f)" % [kind, pos.x, pos.y])


func log_hitstop(frames: float, reason: String) -> void:
	_write("HITSTOP frames=%.1f reason=%s" % [frames, reason])


func log_parry(quality: String, knockback: float) -> void:
	parry_attempts += 1
	if quality != "MISS":
		parry_successes += 1
		if quality == "PERFECT":
			parry_perfects += 1
	_write("PARRY quality=%s knockback=%.1f" % [quality, knockback])


func log_dash(pos: Vector2, cooldown: float) -> void:
	dash_count += 1
	_write("DASH pos=(%.1f,%.1f) cooldown=%.2f" % [pos.x, pos.y, cooldown])


func log_kill() -> void:
	kills += 1
	_write("KILL total=%d" % kills)


func log_death(reason: String, hp_at_death: float) -> void:
	_write("DEATH reason=%s hp=%.1f duration=%.2f" % [reason, hp_at_death, run_elapsed()])
	_finish_run(false)


func log_victory() -> void:
	_write("VICTORY duration=%.2f" % run_elapsed())
	_finish_run(true)


func parry_success_pct() -> float:
	return (float(parry_successes) / parry_attempts * 100.0) if parry_attempts > 0 else 0.0


func average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()


func _finish_run(won: bool) -> void:
	_write("RUN_END run=%d won=%s" % [run_count, won])
	_append_summary_csv(won)


func _write(line: String) -> void:
	if _log_file == null:
		return
	_log_file.store_line("[%.3f] %s" % [run_elapsed(), line])
	_log_file.flush()


func _append_summary_csv(won: bool) -> void:
	var file_existed := FileAccess.file_exists(RUNS_SUMMARY_PATH)
	var f := FileAccess.open(RUNS_SUMMARY_PATH, FileAccess.READ_WRITE if file_existed else FileAccess.WRITE)
	if f == null:
		return
	if not file_existed:
		f.store_line("run,won,duration,kills,parry_attempts,parry_successes,parry_perfects,parry_success_pct,avg_hit_distance,avg_miss_distance,dashes,jumps,npc_dodges")
	f.seek_end()
	f.store_line("%d,%s,%.2f,%d,%d,%d,%d,%.1f,%.1f,%.1f,%d,%d,%d" % [
		run_count, won, run_elapsed(), kills,
		parry_attempts, parry_successes, parry_perfects, parry_success_pct(),
		average(hit_distances), average(miss_distances), dash_count, jumps, npc_dodges,
	])
	f.close()
