extends Control

@onready var sfx_slider = $SettingsContainer/SFXContainer/SFXSlider
@onready var music_slider = $SettingsContainer/MusicContainer/MusicSlider
@onready var sensitivity_slider = $SettingsContainer/SensitivityContainer/SensitivitySlider
@onready var crosshair_preview = $SettingsContainer/CrosshairContainer/CrosshairPreview

@onready var sfx_value_label = $SettingsContainer/SFXContainer/SFXValue
@onready var music_value_label = $SettingsContainer/MusicContainer/MusicValue
@onready var sensitivity_value_label = $SettingsContainer/SensitivityContainer/SensitivityValue

const COLOR_GREEN = Color(0.2, 0.92, 0, 1)
const COLOR_RED = Color(1, 0.2, 0.2, 1)
const COLOR_WHITE = Color(1, 1, 1, 1)

func _ready():
	sfx_slider.value = GameSettings.sfx_volume * 100
	music_slider.value = GameSettings.music_volume * 100
	sensitivity_slider.value = GameSettings.sensitivity * 1000
	crosshair_preview.modulate = GameSettings.crosshair_color
	
	_update_labels()

func _update_labels():
	sfx_value_label.text = str(int(sfx_slider.value)) + "%"
	music_value_label.text = str(int(music_slider.value)) + "%"
	sensitivity_value_label.text = str(snapped(sensitivity_slider.value / 1000.0, 0.001))

func _on_sfx_slider_value_changed(value: float) -> void:
	GameSettings.set_sfx_volume(value / 100.0)
	_update_labels()

func _on_music_slider_value_changed(value: float) -> void:
	GameSettings.set_music_volume(value / 100.0)
	_update_labels()

func _on_sensitivity_slider_value_changed(value: float) -> void:
	GameSettings.set_sensitivity(value / 1000.0)
	_update_labels()

func _set_crosshair_color(color: Color) -> void:
	GameSettings.set_crosshair_color(color)
	crosshair_preview.modulate = color

func _on_green_button_pressed() -> void:
	_set_crosshair_color(COLOR_GREEN)

func _on_red_button_pressed() -> void:
	_set_crosshair_color(COLOR_RED)

func _on_white_button_pressed() -> void:
	_set_crosshair_color(COLOR_WHITE)

func _on_back_button_pressed() -> void:
	GameSettings.save_settings()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
