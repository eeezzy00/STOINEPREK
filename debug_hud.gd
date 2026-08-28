extends CanvasLayer

@onready var label: Label = $Panel/Label

var _player: Node


func _ready() -> void:
	layer = 10
	_player = get_parent()


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var dash_cd: float = _player.get_dash_cooldown()
	var dash_status := "READY" if dash_cd <= 0.0 else "COOLDOWN"
	label.text = ("HP: %s / %s\nDMG: %s\nATK SPD: %.2fs\nMOVE SPD: %d px/s\nDASH CD: %.1fs [%s]\n" +
		"PARRIES: %d\nPARRY CHARGES: %d / %d\nPARRY STREAK: %d\nLAST PARRY: %s") % [
		_fmt(_player.current_hp),
		_fmt(_player.max_hp),
		_fmt(_player.attack_damage),
		_player.attack_speed,
		int(_player.move_speed),
		dash_cd,
		dash_status,
		_player.parries_count,
		_player.parry_charges,
		_player.max_parry_charges,
		_player.parry_streak,
		_player.last_parry_result,
	]


func _fmt(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(round(v)))
	return "%.1f" % v
