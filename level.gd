extends Node2D

const ROAD_MIN_X := -1440.0
const ROAD_MAX_X := 2880.0

const LAMP_Y := 745.0
const LAMP_SPACING := 420.0

const DASH_Y := 790.0
const DASH_SIZE := Vector2(40.0, 7.0)
const DASH_GAP := 30.0
const DASH_COLOR := Color(0.88, 0.85, 0.7, 0.95)

const SEAM_SPACING := 80.0
const SIDEWALK_TOP := 700.0
const SIDEWALK_BOTTOM := 745.0
const SEAM_COLOR := Color(0.16, 0.15, 0.19, 1.0)

const SIGN_Y := 745.0

const CROSSWALK_STRIPE := Vector2(90.0, 14.0)
const CROSSWALK_GAP := 16.0
const CROSSWALK_COLOR := Color(0.85, 0.85, 0.82, 0.85)

## mp3, not the original .wav -- the .wav (any compression mode, including
## uncompressed PCM) reported playing=true but produced no audible output
## in-editor; menu music (already mp3) was the only thing that ever
## actually played, so this swaps format to match what's proven to work.
const AMBIENCE_SOUND := preload("res://Audio/Ambience/CITY_SOUNDS_AMBIUNCE.mp3")
## Shared across every level (level.tscn, level2.tscn, ...) -- one generic
## "levels" track, distinct from the menu track, always playing while
## you're in a level.
const LEVEL_MUSIC := preload("res://Audio/Song for lvl1/LVL1NDLVL2SONG.mp3")

const ACCENT_COLOR := Color(1, 0.18, 0.66, 1)
const DEATH_COLOR := Color(0.92, 0.15, 0.15, 1)
const DIM_TEXT_COLOR := Color(0.62, 0.42, 0.62, 1)
const FLASH_TEXT_COLOR := Color(1, 0.85, 0.95, 1)

@export var next_level_path: String = ""
@export var lamps_lit: bool = true
## Top surface Y of the generated ground collider for road_details levels
## (level.tscn, level2.tscn) -- see _setup_ground_collision. Matches the old
## y_max standing depth those levels used before real gravity existed.
@export var ground_y: float = 724.0

## Camera2D.limit_* applied to the player's own camera in _setup_player() --
## keeps the view from following the player down into the void when they
## fall off the level, or past its sides/top. Defaults cover the road
## levels (level.tscn, level2.tscn); level3 overrides these to its own
## (much smaller) painted bounds.
@export var camera_limit_left: float = ROAD_MIN_X - 40.0
@export var camera_limit_right: float = ROAD_MAX_X + 40.0
@export var camera_limit_top: float = -600.0
@export var camera_limit_bottom: float = 900.0

## Y below which the player, and any enemy, has fallen off the level and
## dies instantly -- see player.gd/samurai_npc.gd. Comfortably below
## camera_limit_bottom so the fall is visible before it's fatal.
@export var death_y: float = 1400.0

## Parallel arrays: sign_x[i] is positioned at SIGN_Y with type sign_types[i]
## ("warning", "circle", or "bus"). Empty by default -- each level opts in.
@export var sign_x: PackedFloat32Array = []
@export var sign_types: PackedStringArray = []

## One crosswalk per entry in crosswalk_x, spanning crosswalk_top..crosswalk_bottom.
@export var crosswalk_x: PackedFloat32Array = []
@export var crosswalk_top: float = 749.0
@export var crosswalk_bottom: float = 950.0

## Null for tile-based levels (level3+) that don't use the procedural
## sidewalk/road decor at all -- _ready() skips that whole step when absent,
## since _spawn_lamps() etc. all assume this node exists.
@onready var road_details: Node2D = get_node_or_null("RoadDetails")
@onready var lamp_scene: PackedScene = preload("res://street_lamp.tscn")
@onready var sign_scene: PackedScene = preload("res://road_sign.tscn")
@onready var sign_warning_tex: Texture2D = preload("res://assets/textures/sign_warning.png")
@onready var sign_circle_tex: Texture2D = preload("res://assets/textures/sign_circle.png")
@onready var sign_bus_tex: Texture2D = preload("res://assets/textures/sign_bus.png")

var _enemies_alive := 0
var _victory_shown := false
var _defeat_shown := false


func _ready() -> void:
	add_to_group("level")
	TelemetryLogger.start_run()
	if road_details:
		_spawn_lamps()
		_draw_road_dashes()
		_draw_sidewalk_seams()
		_spawn_signs()
		_draw_crosswalks()
		_setup_ground_collision()
	_setup_enemies()
	_setup_player()
	_play_level_audio()


## Real floor for real gravity: level3+ paint their own tile collision, but
## the sidewalk levels (level.tscn, level2.tscn) only ever had the visual
## sidewalk texture plus a fake y_min/y_max depth clamp on each character --
## now that movement is real platformer physics, they need an actual
## collision body to land on. One flat StaticBody2D spanning the whole road.
func _setup_ground_collision() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 4  # Walls -- same layer level3's tile collision uses
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	var thickness := 200.0
	rect.size = Vector2(ROAD_MAX_X - ROAD_MIN_X, thickness)
	shape.shape = rect
	shape.position = Vector2((ROAD_MIN_X + ROAD_MAX_X) / 2.0, ground_y + thickness / 2.0)
	body.add_child(shape)
	add_child(body)


## Routed through MusicManager (an autoload, survives scene changes) rather
## than local AudioStreamPlayer children -- level.tscn/level2.tscn reload
## constantly (death, bot restarts, F5-panel level switch), and a
## scene-local player would restart music/ambience from 0 on every single
## one of those. MusicManager no-ops if the same stream is already playing,
## so both just keep going uninterrupted across reloads.
func _play_level_audio() -> void:
	MusicManager.play_ambience(AMBIENCE_SOUND)
	MusicManager.play_music(LEVEL_MUSIC)


func _spawn_lamps() -> void:
	var x := ROAD_MIN_X + 120.0
	while x <= ROAD_MAX_X:
		var lamp := lamp_scene.instantiate()
		lamp.position = Vector2(x, LAMP_Y)
		road_details.add_child(lamp)
		if not lamps_lit:
			lamp.get_node("Glow").visible = false
		x += LAMP_SPACING


func _draw_road_dashes() -> void:
	var x := ROAD_MIN_X
	while x <= ROAD_MAX_X:
		var dash := ColorRect.new()
		dash.color = DASH_COLOR
		dash.size = DASH_SIZE
		dash.position = Vector2(x, DASH_Y)
		road_details.add_child(dash)
		x += DASH_SIZE.x + DASH_GAP


func _spawn_signs() -> void:
	for i in range(sign_x.size()):
		var sign := sign_scene.instantiate()
		sign.position = Vector2(sign_x[i], SIGN_Y)
		var tex: Texture2D
		match sign_types[i]:
			"circle":
				tex = sign_circle_tex
			"bus":
				tex = sign_bus_tex
			_:
				tex = sign_warning_tex
		sign.get_node("Icon").texture = tex
		road_details.add_child(sign)


func _draw_crosswalks() -> void:
	for cx in crosswalk_x:
		var y := crosswalk_top
		while y <= crosswalk_bottom:
			var stripe := ColorRect.new()
			stripe.color = CROSSWALK_COLOR
			stripe.size = CROSSWALK_STRIPE
			stripe.position = Vector2(cx - CROSSWALK_STRIPE.x / 2.0, y)
			road_details.add_child(stripe)
			y += CROSSWALK_STRIPE.y + CROSSWALK_GAP


func _draw_sidewalk_seams() -> void:
	var x := ROAD_MIN_X
	while x <= ROAD_MAX_X:
		var seam := ColorRect.new()
		seam.color = SEAM_COLOR
		seam.size = Vector2(2.0, SIDEWALK_BOTTOM - SIDEWALK_TOP)
		seam.position = Vector2(x, SIDEWALK_TOP)
		road_details.add_child(seam)
		x += SEAM_SPACING


func _setup_enemies() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	_enemies_alive = enemies.size()
	for enemy in enemies:
		enemy.died.connect(_on_enemy_died)
		enemy.death_y = death_y


## Called by the admin panel when it spawns an extra Samurai NPC mid-run --
## without this, a spawned NPC's death wouldn't count toward the victory
## condition at all (or worse, could make _enemies_alive go negative).
func register_enemy(enemy: Node) -> void:
	_enemies_alive += 1
	enemy.died.connect(_on_enemy_died)
	enemy.death_y = death_y


func _on_enemy_died() -> void:
	TelemetryLogger.log_kill()
	_enemies_alive -= 1
	if _enemies_alive <= 0 and not _victory_shown and not _defeat_shown:
		_victory_shown = true
		TelemetryLogger.log_victory()
		RunAnalyzer.show_summary(true)
		if AutoPlayBot.active:
			# Skip the screen entirely -- the bot doesn't click NEXT/QUIT,
			# it just needs the next run started as fast as possible.
			AutoPlayBot.request_restart()
		else:
			_show_victory_screen()


func _setup_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.died.connect(_on_player_died)
		player.death_y = death_y
		player.camera.limit_left = int(camera_limit_left)
		player.camera.limit_right = int(camera_limit_right)
		player.camera.limit_top = int(camera_limit_top)
		player.camera.limit_bottom = int(camera_limit_bottom)


func _on_player_died() -> void:
	if _defeat_shown or _victory_shown:
		return
	_defeat_shown = true
	var player := get_tree().get_first_node_in_group("player")
	var hp_at_death: float = player.current_hp if player else 0.0
	var reason: String = player.death_reason if player else "defeated_by_enemy"
	TelemetryLogger.log_death(reason, hp_at_death)
	RunAnalyzer.show_summary(false)
	_show_death_screen()


func _show_victory_screen() -> void:
	var term_font := _make_term_font()
	var buttons: Array[Button] = []

	if next_level_path != "":
		var next_btn := _make_victory_button("NEXT", term_font)
		next_btn.pressed.connect(func(): get_tree().change_scene_to_file(next_level_path))
		buttons.append(next_btn)

	var quit_btn := _make_victory_button("QUIT", term_font)
	quit_btn.pressed.connect(func(): get_tree().quit())
	buttons.append(quit_btn)

	_show_end_screen("LEVEL CLEARED", ACCENT_COLOR, term_font, buttons)


func _show_death_screen() -> void:
	var term_font := _make_term_font()

	var restart_btn := _make_victory_button("RESTART", term_font)
	restart_btn.pressed.connect(func(): get_tree().reload_current_scene())

	var quit_btn := _make_victory_button("QUIT", term_font)
	quit_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://men.tscn"))

	_show_end_screen("YOU DIED", DEATH_COLOR, term_font, [restart_btn, quit_btn])


func _make_term_font() -> Font:
	var term_font := SystemFont.new()
	term_font.font_names = PackedStringArray(["Consolas", "Courier New", "Lucida Console", "monospace"])
	return term_font


func _show_end_screen(title_text: String, title_color: Color, term_font: Font, buttons: Array[Button]) -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.03, 0.82)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	canvas.add_child(dim)

	var title := Label.new()
	title.text = title_text
	title.anchor_right = 1.0
	title.anchor_top = 0.28
	title.anchor_bottom = 0.42
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", term_font)
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", title_color)
	canvas.add_child(title)

	var vbox := VBoxContainer.new()
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -110.0
	vbox.offset_right = 110.0
	vbox.offset_top = -30.0
	vbox.add_theme_constant_override("separation", 16)
	canvas.add_child(vbox)

	for button in buttons:
		vbox.add_child(button)
	if buttons.size() > 0:
		buttons[0].grab_focus()


func _make_victory_button(label: String, font: Font) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(220.0, 44.0)
	btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_color_override("font_color", DIM_TEXT_COLOR)
	btn.add_theme_color_override("font_hover_color", ACCENT_COLOR)
	btn.add_theme_color_override("font_focus_color", ACCENT_COLOR)
	btn.add_theme_color_override("font_pressed_color", FLASH_TEXT_COLOR)
	var empty_style := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty_style)
	btn.add_theme_stylebox_override("hover", empty_style)
	btn.add_theme_stylebox_override("pressed", empty_style)
	btn.add_theme_stylebox_override("focus", empty_style)
	btn.add_theme_stylebox_override("disabled", empty_style)
	return btn
