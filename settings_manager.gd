extends Node

## Autoload. Applies saved audio settings at boot (regardless of which scene
## happens to load first) and gives settings.gd a place to read/write them.
## Values are linear (0..1, what a slider shows); AudioServer wants dB, so
## the conversion happens once, here.

const CONFIG_PATH := "user://settings.cfg"
const BUSES := ["Master", "Music", "SFX"]
const SECTION := "audio"


func _ready() -> void:
	_apply_all()


func get_volume(bus_name: String) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return 1.0
	return cfg.get_value(SECTION, bus_name, 1.0)


## Applies immediately to the live AudioServer bus AND persists to disk --
## callers (the settings screen sliders) don't need a separate save step.
func set_volume(bus_name: String, linear: float) -> void:
	linear = clampf(linear, 0.0, 1.0)
	_apply_bus_volume(bus_name, linear)
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)  # ok to ignore error -- ConfigFile starts empty either way
	cfg.set_value(SECTION, bus_name, linear)
	cfg.save(CONFIG_PATH)


func _apply_all() -> void:
	for bus_name in BUSES:
		_apply_bus_volume(bus_name, get_volume(bus_name))


func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear))
