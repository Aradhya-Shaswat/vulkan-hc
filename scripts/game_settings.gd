extends Node

signal settings_changed

var sfx_volume: float = 1.0
var music_volume: float = 1.0
var sensitivity: float = 0.005
var crosshair_color: Color = Color(0.2087988, 0.92084754, 0, 1)
var is_paused: bool = false
var saved_nickname: String = ""

var window_mode: int = DisplayServer.WINDOW_MODE_FULLSCREEN
var resolution_index: int = 0
var vsync_enabled: bool = true
var show_fps: bool = false
var render_scale: float = 1.0

const RESOLUTIONS = [
	Vector2i(1920, 1080),
	Vector2i(1600, 900),
	Vector2i(1366, 768),
	Vector2i(1280, 720),
	Vector2i(1024, 576),
]

var _profanity_cache: Dictionary = {}
var _http_request: HTTPRequest

func _ready():
	load_settings()

func check_profanity(text: String, callback: Callable):
	var lower = text.to_lower().strip_edges()
	
	if lower in _profanity_cache:
		callback.call(_profanity_cache[lower])
		return
	
	if lower.length() < 1:
		callback.call(false)
		return
	
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result, code, headers, body):
		var is_profane = false
		if code == 200:
			var response = body.get_string_from_utf8().strip_edges().to_lower()
			is_profane = response == "true"
		_profanity_cache[lower] = is_profane
		callback.call(is_profane)
		http.queue_free()
	)
	
	var url = "https://www.purgomalum.com/service/containsprofanity?text=" + lower.uri_encode()
	http.request(url)

func is_nickname_offensive(nickname: String) -> bool:
	var lower = nickname.to_lower().strip_edges()
	return _profanity_cache.get(lower, false)

func sanitize_nickname(nickname: String) -> String:
	var result = nickname.strip_edges()
	if result.length() < 1:
		return "Player"
	if result.length() > 16:
		result = result.substr(0, 16)
	if is_nickname_offensive(result):
		return "Player"
	return result

func save_settings():
	var config = ConfigFile.new()
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("controls", "sensitivity", sensitivity)
	config.set_value("visuals", "crosshair_color_r", crosshair_color.r)
	config.set_value("visuals", "crosshair_color_g", crosshair_color.g)
	config.set_value("visuals", "crosshair_color_b", crosshair_color.b)
	config.set_value("graphics", "window_mode", window_mode)
	config.set_value("graphics", "resolution_index", resolution_index)
	config.set_value("graphics", "vsync_enabled", vsync_enabled)
	config.set_value("graphics", "show_fps", show_fps)
	config.set_value("graphics", "render_scale", render_scale)
	config.set_value("player", "nickname", saved_nickname)
	config.save("user://settings.cfg")

func load_settings():
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")
	if err != OK:
		_apply_graphics_settings()
		return
	sfx_volume = config.get_value("audio", "sfx_volume", 1.0)
	music_volume = config.get_value("audio", "music_volume", 1.0)
	sensitivity = config.get_value("controls", "sensitivity", 0.005)
	var r = config.get_value("visuals", "crosshair_color_r", 0.2087988)
	var g = config.get_value("visuals", "crosshair_color_g", 0.92084754)
	var b = config.get_value("visuals", "crosshair_color_b", 0.0)
	crosshair_color = Color(r, g, b, 1.0)
	window_mode = config.get_value("graphics", "window_mode", DisplayServer.WINDOW_MODE_FULLSCREEN)
	resolution_index = config.get_value("graphics", "resolution_index", 0)
	vsync_enabled = config.get_value("graphics", "vsync_enabled", true)
	show_fps = config.get_value("graphics", "show_fps", false)
	render_scale = config.get_value("graphics", "render_scale", 1.0)
	saved_nickname = config.get_value("player", "nickname", "")
	_apply_audio_settings()
	_apply_graphics_settings()

func _apply_audio_settings():
	var sfx_bus = AudioServer.get_bus_index("SFX")
	var music_bus = AudioServer.get_bus_index("Music")
	if sfx_bus >= 0:
		if sfx_volume <= 0.0:
			AudioServer.set_bus_mute(sfx_bus, true)
		else:
			AudioServer.set_bus_mute(sfx_bus, false)
			AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(sfx_volume))
	if music_bus >= 0:
		if music_volume <= 0.0:
			AudioServer.set_bus_mute(music_bus, true)
		else:
			AudioServer.set_bus_mute(music_bus, false)
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

func _apply_graphics_settings():
	DisplayServer.window_set_mode(window_mode)
	if window_mode == DisplayServer.WINDOW_MODE_WINDOWED:
		if resolution_index >= 0 and resolution_index < RESOLUTIONS.size():
			var res = RESOLUTIONS[resolution_index]
			DisplayServer.window_set_size(res)
			var screen_size = DisplayServer.screen_get_size()
			var window_pos = Vector2i((screen_size.x - res.x) / 2, (screen_size.y - res.y) / 2)
			DisplayServer.window_set_position(window_pos)
	
	if vsync_enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	
	get_viewport().scaling_3d_scale = render_scale

func set_window_mode(mode: int):
	window_mode = mode
	_apply_graphics_settings()
	settings_changed.emit()

func set_resolution(index: int):
	resolution_index = index
	_apply_graphics_settings()
	settings_changed.emit()

func set_vsync(enabled: bool):
	vsync_enabled = enabled
	_apply_graphics_settings()
	settings_changed.emit()

func set_show_fps(enabled: bool):
	show_fps = enabled
	settings_changed.emit()

func set_render_scale(scale: float):
	render_scale = scale
	_apply_graphics_settings()
	settings_changed.emit()
