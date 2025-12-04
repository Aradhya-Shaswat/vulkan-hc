extends Control

@onready var sfx_slider = $SettingsContainer/SFXContainer/SFXSlider
@onready var music_slider = $SettingsContainer/MusicContainer/MusicSlider
@onready var sensitivity_slider = $SettingsContainer/SensitivityContainer/SensitivitySlider
@onready var crosshair_preview = $SettingsContainer/CrosshairContainer/CrosshairPreview

@onready var sfx_value_label = $SettingsContainer/SFXContainer/SFXValue
@onready var music_value_label = $SettingsContainer/MusicContainer/MusicValue
@onready var sensitivity_value_label = $SettingsContainer/SensitivityContainer/SensitivityValue

@onready var window_mode_option = $GraphicsContainer/WindowModeContainer/WindowModeOption
@onready var resolution_option = $GraphicsContainer/ResolutionContainer/ResolutionOption
@onready var vsync_check = $GraphicsContainer/VSyncContainer/VSyncCheck
@onready var fps_check = $GraphicsContainer/FPSContainer/FPSCheck
@onready var render_scale_slider = $GraphicsContainer/RenderScaleContainer/RenderScaleSlider
@onready var render_scale_value = $GraphicsContainer/RenderScaleContainer/RenderScaleValue
#@onready var fps_label = $FPSLabel

const COLOR_GREEN = Color(0.2, 0.92, 0, 1)
const COLOR_RED = Color(1, 0.2, 0.2, 1)
const COLOR_WHITE = Color(1, 1, 1, 1)

func _ready():
	sfx_slider.value = GameSettings.sfx_volume * 100
	music_slider.value = GameSettings.music_volume * 100
	sensitivity_slider.value = GameSettings.sensitivity * 1000
	crosshair_preview.modulate = GameSettings.crosshair_color
	
	_setup_graphics_options()
	_update_labels()
	_connect_hover_sounds()
	SoundManager.start_menu_music()

func _process(_delta):
	#if GameSettings.show_fps and fps_label:
		#fps_label.visible = true
		#fps_label.text = "FPS: " + str(Engine.get_frames_per_second())
	#elif fps_label:
		#fps_label.visible = false
	pass

func _setup_graphics_options():
	window_mode_option.clear()
	window_mode_option.add_item("Fullscreen", 0)
	window_mode_option.add_item("Windowed", 1)
	window_mode_option.add_item("Borderless", 2)
	
	match GameSettings.window_mode:
		DisplayServer.WINDOW_MODE_FULLSCREEN:
			window_mode_option.select(0)
		DisplayServer.WINDOW_MODE_WINDOWED:
			window_mode_option.select(1)
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			window_mode_option.select(2)
		_:
			window_mode_option.select(0)
	
	resolution_option.clear()
	for res in GameSettings.RESOLUTIONS:
		resolution_option.add_item(str(res.x) + " x " + str(res.y))
	resolution_option.select(GameSettings.resolution_index)
	resolution_option.disabled = GameSettings.window_mode != DisplayServer.WINDOW_MODE_WINDOWED
	
	vsync_check.button_pressed = GameSettings.vsync_enabled
	fps_check.button_pressed = GameSettings.show_fps
	render_scale_slider.value = GameSettings.render_scale * 100

func _connect_hover_sounds():
	_connect_buttons_recursive(self)

func _connect_buttons_recursive(node: Node):
	if node is Button:
		if not node.mouse_entered.is_connected(_on_button_hover):
			node.mouse_entered.connect(_on_button_hover)
	for child in node.get_children():
		_connect_buttons_recursive(child)

func _on_button_hover():
	SoundManager.play_ui_hover()

func _update_labels():
	sfx_value_label.text = str(int(sfx_slider.value)) + "%"
	music_value_label.text = str(int(music_slider.value)) + "%"
	sensitivity_value_label.text = str(snapped(sensitivity_slider.value / 1000.0, 0.001))
	if render_scale_value:
		render_scale_value.text = str(int(render_scale_slider.value)) + "%"

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
	SoundManager.play_ui_click()
	_set_crosshair_color(COLOR_GREEN)

func _on_red_button_pressed() -> void:
	SoundManager.play_ui_click()
	_set_crosshair_color(COLOR_RED)

func _on_white_button_pressed() -> void:
	SoundManager.play_ui_click()
	_set_crosshair_color(COLOR_WHITE)

func _on_back_button_pressed() -> void:
	SoundManager.play_ui_back()
	GameSettings.save_settings()
	SceneTransition.change_scene("res://scenes/main_menu.tscn")

func _on_window_mode_option_item_selected(index: int) -> void:
	SoundManager.play_ui_click()
	var mode: int
	match index:
		0: mode = DisplayServer.WINDOW_MODE_FULLSCREEN
		1: mode = DisplayServer.WINDOW_MODE_WINDOWED
		2: mode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		_: mode = DisplayServer.WINDOW_MODE_FULLSCREEN
	GameSettings.set_window_mode(mode)
	resolution_option.disabled = mode != DisplayServer.WINDOW_MODE_WINDOWED

func _on_resolution_option_item_selected(index: int) -> void:
	SoundManager.play_ui_click()
	GameSettings.set_resolution(index)

func _on_vsync_check_toggled(toggled_on: bool) -> void:
	SoundManager.play_ui_click()
	GameSettings.set_vsync(toggled_on)

func _on_fps_check_toggled(toggled_on: bool) -> void:
	SoundManager.play_ui_click()
	GameSettings.set_show_fps(toggled_on)

func _on_render_scale_slider_value_changed(value: float) -> void:
	GameSettings.set_render_scale(value / 100.0)
	_update_labels()
