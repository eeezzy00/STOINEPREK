extends CanvasLayer

## Player-child gameplay HUD: heart-based HP row, parry charges, and
## PERFECT-parry streak counter. Bottom-left corner -- top-left is already
## taken by DebugHUD's always-on stats panel (see debug_hud.gd), so this
## sits opposite it.
##
## Parry pips and the streak label are still placeholder chunky-pixel
## geometry (ColorRect/Label, no drawn art yet) -- same spirit as how
## samurai_npc.gd's blood effects started procedural and can gain real art
## later; the HP row already made that jump (see HEART_FULL/HEART_BROKEN).
##
## Polls player fields every frame rather than wiring new signals -- matches
## debug_hud.gd's own pattern (also a player-child CanvasLayer reading
## _player fields directly in _process), and player.gd has no single signal
## that covers every case that must update these (e.g. a parry MISS resets
## parry_streak but doesn't emit the "parried" signal).

const MARGIN := 20.0
const HEART_SIZE := 128.0
## Negative on purpose -- the heart art itself has a lot of transparent
## padding baked into its 64x64 canvas, so a small positive gap between the
## (now much bigger) TextureRect boxes still reads as a big empty gap
## between the visible heart shapes. Pulling the boxes into a slight overlap
## cancels that padding back out instead of shrinking HEART_SIZE.
const HEART_GAP := -60
const PIP_SIZE := 16.0
const PIP_GAP := 6.0
const ROW_GAP := 8.0

## Real pixel-art hearts (assets/MYASSETS/UI/hp/) -- one heart per whole
## point of max_hp, broken the instant that point takes any damage. Only two
## states exist (no half-heart art yet), so a heart is either fully intact
## or fully broken -- see _update_hp()'s floori() rounding for how a
## fractional current_hp (sweet-spot/late-hit multipliers make this the
## common case, not an edge case) maps onto that.
const HEART_FULL := preload("res://assets/MYASSETS/UI/hp/HEALTH.png")
const HEART_BROKEN := preload("res://assets/MYASSETS/UI/hp/BROKEN HEART.png")

## Matches level.gd's palette (ACCENT_COLOR / DEATH_COLOR / FLASH_TEXT_COLOR)
## so this reads as the same UI language as the rest of the game, not a
## mismatched new color scheme.
const PIP_FULL_COLOR := Color(1, 0.18, 0.66, 1)
const PIP_EMPTY_COLOR := Color(0.2, 0.16, 0.22, 0.9)
const STREAK_COLOR := Color(1, 0.85, 0.95, 1)
const STREAK_BONUS_COLOR := Color(1, 0.18, 0.66, 1)

const STREAK_POP_DURATION := 0.15

var _player: Node
var _font: Font

var _heart_row: HBoxContainer
var _hearts: Array[TextureRect] = []
var _pip_row: HBoxContainer
var _pips: Array[ColorRect] = []
var _streak_label: Label
var _streak_tween: Tween

var _last_heart_count := -1
var _last_max_charges := -1
var _last_streak := 0


func _ready() -> void:
	layer = 9
	_player = get_parent()
	_font = _make_font()
	_build_ui()


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_update_hp()
	_update_parry_pips()
	_update_streak()


func _make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "Courier New", "Lucida Console", "monospace"])
	return f


func _build_ui() -> void:
	var root := Control.new()
	root.anchor_left = 0.0
	root.anchor_top = 1.0
	root.anchor_right = 0.0
	root.anchor_bottom = 1.0
	root.offset_left = MARGIN
	root.offset_top = -(MARGIN + HEART_SIZE + ROW_GAP + PIP_SIZE)
	root.offset_right = MARGIN + 400.0
	root.offset_bottom = -MARGIN
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", ROW_GAP)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vbox)

	_build_hp_hearts(vbox)
	_build_bottom_row(vbox)


func _build_hp_hearts(parent: Control) -> void:
	_heart_row = HBoxContainer.new()
	_heart_row.add_theme_constant_override("separation", HEART_GAP)
	_heart_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_heart_row)


func _build_bottom_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)

	_pip_row = HBoxContainer.new()
	_pip_row.add_theme_constant_override("separation", PIP_GAP)
	_pip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_pip_row)

	_streak_label = Label.new()
	_streak_label.text = ""
	_streak_label.add_theme_font_override("font", _font)
	_streak_label.add_theme_font_size_override("font_size", 16)
	_streak_label.add_theme_color_override("font_color", STREAK_COLOR)
	_streak_label.add_theme_color_override("font_outline_color", Color(0.02, 0.01, 0.03, 0.95))
	_streak_label.add_theme_constant_override("outline_size", 5)
	_streak_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_streak_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_streak_label.pivot_offset = Vector2(0.0, PIP_SIZE * 0.5)
	row.add_child(_streak_label)


## Rebuilds the heart row only when the heart count (ceili(max_hp)) actually
## changes (e.g. via the admin panel's HP slider) -- same change-detection
## pattern as _update_parry_pips() below, not a queue_free()/re-add every frame.
func _update_hp() -> void:
	var heart_count: int = maxi(ceili(_player.max_hp), 0)
	if heart_count != _last_heart_count:
		_last_heart_count = heart_count
		for heart in _hearts:
			heart.queue_free()
		_hearts.clear()
		for i in heart_count:
			var heart := TextureRect.new()
			heart.custom_minimum_size = Vector2(HEART_SIZE, HEART_SIZE)
			# EXPAND_IGNORE_SIZE: without it, TextureRect's default
			# EXPAND_KEEP_SIZE draws the 64x64 source art at its native
			# size (just centered by stretch_mode below) regardless of how
			# big custom_minimum_size makes the control itself -- the exact
			# reason a 3x HEART_SIZE bump rendered as a barely-bigger box
			# around a still-tiny heart instead of an actually bigger heart.
			heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_heart_row.add_child(heart)
			_hearts.append(heart)

	# floori, not round/ceil: "take damage = a heart breaks" means the very
	# first hit should show up immediately, not stay hidden until an entire
	# point of HP is gone (there's no half-heart art) -- so 2.9/3 already
	# shows 1 broken heart, not 3 still-intact ones.
	var intact: int = clampi(floori(_player.current_hp), 0, heart_count)
	for i in _hearts.size():
		_hearts[i].texture = HEART_FULL if i < intact else HEART_BROKEN


## Rebuilds the pip row only when max_parry_charges actually changes (e.g.
## via the admin panel slider) -- not every frame, that'd be needless churn.
func _update_parry_pips() -> void:
	var max_charges: int = int(_player.max_parry_charges)
	if max_charges != _last_max_charges:
		_last_max_charges = max_charges
		for pip in _pips:
			pip.queue_free()
		_pips.clear()
		for i in max_charges:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(PIP_SIZE, PIP_SIZE)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_pip_row.add_child(pip)
			_pips.append(pip)

	var current: int = int(_player.parry_charges)
	for i in _pips.size():
		_pips[i].color = PIP_FULL_COLOR if i < current else PIP_EMPTY_COLOR


func _update_streak() -> void:
	var streak: int = int(_player.parry_streak)
	if streak == _last_streak:
		return
	_last_streak = streak

	if streak <= 0:
		_streak_label.text = ""
		return

	_streak_label.text = "PERFECT x%d" % streak
	var bonus_armed: bool = streak >= int(_player.perfect_streak_for_bonus)
	_streak_label.add_theme_color_override("font_color", STREAK_BONUS_COLOR if bonus_armed else STREAK_COLOR)

	if _streak_tween != null and _streak_tween.is_valid():
		_streak_tween.kill()
	_streak_label.scale = Vector2(1.4, 1.4)
	_streak_tween = create_tween()
	_streak_tween.tween_property(_streak_label, "scale", Vector2.ONE, STREAK_POP_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
