extends Node2D

const ROAD_MIN_X := -1440.0
const ROAD_MAX_X := 2880.0

const LAMP_Y := 745.0
const LAMP_SPACING := 420.0

const DASH_Y := 775.0
const DASH_SIZE := Vector2(36.0, 6.0)
const DASH_GAP := 36.0
const DASH_COLOR := Color(0.78, 0.74, 0.58, 0.9)

const SEAM_SPACING := 80.0
const SIDEWALK_TOP := 700.0
const SIDEWALK_BOTTOM := 745.0
const SEAM_COLOR := Color(0.16, 0.15, 0.19, 1.0)

@onready var road_details: Node2D = $RoadDetails
@onready var lamp_scene: PackedScene = preload("res://street_lamp.tscn")


func _ready() -> void:
	_spawn_lamps()
	_draw_road_dashes()
	_draw_sidewalk_seams()


func _spawn_lamps() -> void:
	var x := ROAD_MIN_X + 120.0
	while x <= ROAD_MAX_X:
		var lamp := lamp_scene.instantiate()
		lamp.position = Vector2(x, LAMP_Y)
		road_details.add_child(lamp)
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


func _draw_sidewalk_seams() -> void:
	var x := ROAD_MIN_X
	while x <= ROAD_MAX_X:
		var seam := ColorRect.new()
		seam.color = SEAM_COLOR
		seam.size = Vector2(2.0, SIDEWALK_BOTTOM - SIDEWALK_TOP)
		seam.position = Vector2(x, SIDEWALK_TOP)
		road_details.add_child(seam)
		x += SEAM_SPACING
