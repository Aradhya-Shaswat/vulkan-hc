extends Node

const CURRENT_VERSION = "beta-0.7"
const VERSION_URL = "https://raw.githubusercontent.com/Aradhya-Shaswat/vulkan-hc/main/version.json"

var http_request: HTTPRequest
var download_request: HTTPRequest
var update_available: bool = false
var update_info: Dictionary = {}
var is_updating: bool = false

func _ready() -> void:
	if not OS.has_feature("editor"):
		_check_for_updates()

func _process(_delta):
	if is_updating and download_request:
		var downloaded = download_request.get_downloaded_bytes()
		var total = download_request.get_body_size()
		if total > 0:
			var percent = int((float(downloaded) / float(total)) * 100)
			if has_node("UpdateLabel"):
				$UpdateLabel.text = "Downloading update... " + str(percent) + "%"

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
		_start_auto_update()

func _start_auto_update():
	if not update_info.has("pck_url"):
		_show_manual_update()
		return
	
	is_updating = true
	if has_node("UpdateLabel"):
		$UpdateLabel.show()
		$UpdateLabel.text = "Update found! Downloading..."
	
	var exe_dir = OS.get_executable_path().get_base_dir()
	var update_path = exe_dir + "/game_update.pck"
	
	download_request = HTTPRequest.new()
	download_request.download_file = update_path
	add_child(download_request)
	download_request.request_completed.connect(_on_update_downloaded)
	download_request.request(update_info.pck_url)

func _on_update_downloaded(result, code, _headers, _body):
	is_updating = false
	download_request.queue_free()
	
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if has_node("UpdateLabel"):
			$UpdateLabel.text = "Update failed. Please restart."
		_show_manual_update()
		return
	
	if has_node("UpdateLabel"):
		$UpdateLabel.text = "Installing update..."
	
	await get_tree().create_timer(0.5).timeout
	_apply_update()

func _apply_update():
	var exe_path = OS.get_executable_path()
	var exe_dir = exe_path.get_base_dir()
	var exe_name = exe_path.get_file().get_basename()
	
	var old_pck = exe_dir + "/" + exe_name + ".pck"
	var new_pck = exe_dir + "/game_update.pck"
	var backup_pck = exe_dir + "/" + exe_name + "_backup.pck"
	
	var dir = DirAccess.open(exe_dir)
	if dir:
		if dir.file_exists(backup_pck):
			dir.remove(backup_pck)
		if dir.file_exists(old_pck):
			dir.rename(old_pck, backup_pck)
		dir.rename(new_pck, old_pck)
	
	if has_node("UpdateLabel"):
		$UpdateLabel.text = "Update complete! Restarting..."
	
	await get_tree().create_timer(1.0).timeout
	OS.create_process(exe_path, [])
	get_tree().quit()

func _show_manual_update():
	if has_node("UpdateButton"):
		$UpdateButton.show()
		$UpdateButton.text = "  Download Update (" + update_info.version + ")"

func _on_update_button_pressed():
	if update_info.has("download_url"):
		OS.shell_open(update_info.download_url)


func _on_play_button_pressed() -> void:
	SceneTransition.change_scene("res://scenes/main_level.tscn")


func _on_options_button_pressed() -> void:
	SceneTransition.change_scene("res://scenes/options.tscn")


func _on_credits_button_pressed() -> void:
	SceneTransition.change_scene("res://scenes/credits.tscn")


func _on_quit_button_pressed() -> void:
	get_tree().quit()
