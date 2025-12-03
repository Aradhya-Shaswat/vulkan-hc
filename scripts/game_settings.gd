extends Node

signal settings_changed

var sfx_volume: float = 1.0
var music_volume: float = 1.0
var sensitivity: float = 0.005
var crosshair_color: Color = Color(0.2087988, 0.92084754, 0, 1)
var is_paused: bool = false

func _ready():
	load_settings()

func save_settings():
	var config = ConfigFile.new()
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("controls", "sensitivity", sensitivity)
	config.set_value("visuals", "crosshair_color_r", crosshair_color.r)
	config.set_value("visuals", "crosshair_color_g", crosshair_color.g)
	config.set_value("visuals", "crosshair_color_b", crosshair_color.b)
	config.save("user://settings.cfg")

func load_settings():
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")
	if err != OK:
		return
	sfx_volume = config.get_value("audio", "sfx_volume", 1.0)
	music_volume = config.get_value("audio", "music_volume", 1.0)
	sensitivity = config.get_value("controls", "sensitivity", 0.005)
	var r = config.get_value("visuals", "crosshair_color_r", 0.2087988)
	var g = config.get_value("visuals", "crosshair_color_g", 0.92084754)
	var b = config.get_value("visuals", "crosshair_color_b", 0.0)
	crosshair_color = Color(r, g, b, 1.0)
	_apply_audio_settings()

func _apply_audio_settings():
	var sfx_bus = AudioServer.get_bus_index("SFX")
	var music_bus = AudioServer.get_bus_index("Music")
	var master_bus = AudioServer.get_bus_index("Master")
	if sfx_bus >= 0:
		AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(sfx_volume))
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, linear_to_db(music_volume))

func set_sfx_volume(value: float):
	sfx_volume = value
	_apply_audio_settings()
	settings_changed.emit()

func set_music_volume(value: float):
	music_volume = value
	_apply_audio_settings()
	settings_changed.emit()

func set_sensitivity(value: float):
	sensitivity = value
	settings_changed.emit()

func set_crosshair_color(color: Color):
	crosshair_color = color
	settings_changed.emit()
