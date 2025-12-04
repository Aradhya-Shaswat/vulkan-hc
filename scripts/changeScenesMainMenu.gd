extends Node

const CURRENT_VERSION = "beta-0.9"
const VERSION_URL = "https://raw.githubusercontent.com/Aradhya-Shaswat/vulkan-hc/main/version.json"

var http_request: HTTPRequest
var update_available: bool = false
var update_info: Dictionary = {}

func _ready() -> void:
	if not OS.has_feature("editor"):
		_check_for_updates()
	_connect_hover_sounds()
	SoundManager.start_menu_music()

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
	SceneTransition.change_scene("res://scenes/main_level.tscn")


func _on_options_button_pressed() -> void:
	SoundManager.play_ui_click()
	SceneTransition.change_scene("res://scenes/options.tscn")


func _on_credits_button_pressed() -> void:
	SoundManager.play_ui_click()
	SceneTransition.change_scene("res://scenes/credits.tscn")


func _on_quit_button_pressed() -> void:
	SoundManager.play_ui_click()
	get_tree().quit()
