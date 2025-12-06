extends Node

const CURRENT_VERSION = "beta-1.0"
const VERSION_URL = "https://raw.githubusercontent.com/Aradhya-Shaswat/vulkan-hc/main/version.json"

var http_request: HTTPRequest
var update_available: bool = false
var update_info: Dictionary = {}

var loading_panel: Panel = null
var loading_label: Label = null
var spinner: Label = null
var spinner_chars: Array = ["◐", "◓", "◑", "◒"]
var spinner_index: int = 0
var is_loading: bool = false

func _ready() -> void:
	if not OS.has_feature("editor"):
		_check_for_updates()
	_connect_hover_sounds()
	SoundManager.start_menu_music()
	_create_loading_panel()

func _create_loading_panel():
	loading_panel = Panel.new()
	loading_panel.name = "LoadingPanel"
	loading_panel.visible = false
	loading_panel.anchors_preset = Control.PRESET_FULL_RECT
	loading_panel.anchor_right = 1.0
	loading_panel.anchor_bottom = 1.0
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	loading_panel.add_theme_stylebox_override("panel", style)
	add_child(loading_panel)
	
	spinner = Label.new()
	spinner.name = "Spinner"
	spinner.anchors_preset = Control.PRESET_CENTER
	spinner.anchor_left = 0.5
	spinner.anchor_top = 0.5
	spinner.anchor_right = 0.5
	spinner.anchor_bottom = 0.5
	spinner.offset_left = -30
	spinner.offset_top = -70
	spinner.offset_right = 30
	spinner.offset_bottom = -10
	spinner.pivot_offset = Vector2(30, 30)
	spinner.add_theme_color_override("font_color", Color(1, 1, 0.8235294, 1))
	spinner.add_theme_font_size_override("font_size", 40)
	spinner.text = "◐"
	spinner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spinner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading_panel.add_child(spinner)

	loading_label = Label.new()
	loading_label.name = "LoadingLabel"
	loading_label.anchors_preset = Control.PRESET_CENTER
	loading_label.anchor_left = 0.5
	loading_label.anchor_top = 0.5
	loading_label.anchor_right = 0.5
	loading_label.anchor_bottom = 0.5
	loading_label.offset_left = -150
	loading_label.offset_top = 10
	loading_label.offset_right = 150
	loading_label.offset_bottom = 50
	loading_label.add_theme_color_override("font_color", Color(1, 1, 0.8235294, 1))
	loading_label.add_theme_font_size_override("font_size", 20)
	loading_label.text = "Loading game..."
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading_panel.add_child(loading_label)

func _process(delta):
	if is_loading and spinner:
		spinner.rotation += delta * 5.0
		_check_scene_load_status()

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

func _check_for_updates():
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_version_check)
	http_request.request(VERSION_URL)

func _on_version_check(_result, code, _headers, body):
	http_request.queue_free()
	if code != 200:
		return
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json and json.has("version") and json.version != CURRENT_VERSION:
		update_available = true
		update_info = json
		_show_update_available()

func _show_update_available():
	if has_node("UpdateButton"):
		$UpdateButton.show()
		$UpdateButton.text = "Update Available (" + update_info.version + ")"

func _on_update_button_pressed():
	if update_info.has("download_url"):
		OS.shell_open(update_info.download_url)


func _on_play_button_pressed() -> void:
	SoundManager.play_ui_click()
	loading_panel.show()
	loading_label.text = "Loading game..."
	is_loading = true
	ResourceLoader.load_threaded_request("res://scenes/main_level.tscn")

func _check_scene_load_status():
	var progress = []
	var status = ResourceLoader.load_threaded_get_status("res://scenes/main_level.tscn", progress)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		is_loading = false
		var scene = ResourceLoader.load_threaded_get("res://scenes/main_level.tscn")
		get_tree().change_scene_to_packed(scene)
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		is_loading = false
		loading_label.text = "Failed to load!"
		await get_tree().create_timer(1.5).timeout
		loading_panel.hide()


func _on_options_button_pressed() -> void:
	SoundManager.play_ui_click()
	SceneTransition.change_scene("res://scenes/options.tscn")


func _on_credits_button_pressed() -> void:
	SoundManager.play_ui_click()
	SceneTransition.change_scene("res://scenes/credits.tscn")


func _on_quit_button_pressed() -> void:
	SoundManager.play_ui_click()
	get_tree().quit()
