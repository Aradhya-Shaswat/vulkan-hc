extends Node3D

var peer: ENetMultiplayerPeer
@export var player_scene : PackedScene
var used_spawn_points = []
var local_username = ""
var player_list = {}
var player_list_visible = false
var player_list_tween: Tween
var is_paused = false
var is_in_game = false
var in_options_menu = false
var server_ip: String = "127.0.0.1"
var server_port: int = 1027

const COLOR_GREEN = Color(0.2, 0.92, 0, 1)
const COLOR_RED = Color(1, 0.2, 0.2, 1)
const COLOR_WHITE = Color(1, 1, 1, 1)

func _ready():
	$MultiplayerSpawner.spawn_function = custom_spawn
	$CanvasLayer/Host.disabled = true
	$CanvasLayer/Join.disabled = true
	$CanvasLayer/PlayerList.modulate.a = 0.0
	$CanvasLayer/PlayerList.position.x = -200
	$CanvasLayer/PlayerList.hide()
	$CanvasLayer/PauseMenu.hide()
	$CanvasLayer/InGameOptions.hide()
	_apply_crosshair_color()
	GameSettings.settings_changed.connect(_on_settings_changed)

	GameSettings.is_paused = false

func _on_settings_changed():
	_apply_crosshair_color()

func _apply_crosshair_color():
	$CanvasLayer/CenterContainer/Crosshair.modulate = GameSettings.crosshair_color

func _unhandled_input(event):
	if event.is_action_pressed("ui_focus_next"):
		get_viewport().set_input_as_handled()
		if is_in_game and not is_paused and multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_toggle_player_list()
	
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
			if is_in_game:
				_toggle_pause()

func _toggle_player_list():
	player_list_visible = not player_list_visible
	if player_list_tween:
		player_list_tween.kill()
	player_list_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	if player_list_visible:
		$CanvasLayer/PlayerList.show()
		player_list_tween.set_parallel(true)
		player_list_tween.tween_property($CanvasLayer/PlayerList, "position:x", 0.0, 0.3)
		player_list_tween.tween_property($CanvasLayer/PlayerList, "modulate:a", 1.0, 0.2)
	else:
		player_list_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
		player_list_tween.set_parallel(true)
		player_list_tween.tween_property($CanvasLayer/PlayerList, "position:x", -200.0, 0.25)
		player_list_tween.tween_property($CanvasLayer/PlayerList, "modulate:a", 0.0, 0.2)
		player_list_tween.chain().tween_callback($CanvasLayer/PlayerList.hide)

func _toggle_pause():
	is_paused = not is_paused
	GameSettings.is_paused = is_paused
	$CanvasLayer/PauseMenu.visible = is_paused
	if not is_paused and in_options_menu:
		$CanvasLayer/InGameOptions.hide()
		in_options_menu = false
	if is_paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if multiplayer.is_server():
			$CanvasLayer/PauseMenu/PauseButtons/QuitButton.text = "End Session"
		else:
			$CanvasLayer/PauseMenu/PauseButtons/QuitButton.text = "Leave Game"
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_resume_pressed():
	_toggle_pause()

func _on_pause_options_pressed():
	$CanvasLayer/PauseMenu.hide()
	$CanvasLayer/InGameOptions.show()
	in_options_menu = true
	_load_options_values()

func _load_options_values():
	$CanvasLayer/InGameOptions/OptionsContainer/SFXContainer/SFXSlider.value = GameSettings.sfx_volume * 100
	$CanvasLayer/InGameOptions/OptionsContainer/MusicContainer/MusicSlider.value = GameSettings.music_volume * 100
	$CanvasLayer/InGameOptions/OptionsContainer/SensitivityContainer/SensitivitySlider.value = GameSettings.sensitivity * 1000
	$CanvasLayer/InGameOptions/OptionsContainer/CrosshairContainer/CrosshairPreview.modulate = GameSettings.crosshair_color
	_update_options_labels()

func _update_options_labels():
	var sfx_val = $CanvasLayer/InGameOptions/OptionsContainer/SFXContainer/SFXSlider.value
	var music_val = $CanvasLayer/InGameOptions/OptionsContainer/MusicContainer/MusicSlider.value
	var sens_val = $CanvasLayer/InGameOptions/OptionsContainer/SensitivityContainer/SensitivitySlider.value
	$CanvasLayer/InGameOptions/OptionsContainer/SFXContainer/SFXValue.text = str(int(sfx_val)) + "%"
	$CanvasLayer/InGameOptions/OptionsContainer/MusicContainer/MusicValue.text = str(int(music_val)) + "%"
	$CanvasLayer/InGameOptions/OptionsContainer/SensitivityContainer/SensitivityValue.text = str(snapped(sens_val / 1000.0, 0.001))

func _on_ingame_sfx_slider_value_changed(value: float):
	GameSettings.set_sfx_volume(value / 100.0)
	_update_options_labels()

func _on_ingame_music_slider_value_changed(value: float):
	GameSettings.set_music_volume(value / 100.0)
	_update_options_labels()

func _on_ingame_sensitivity_slider_value_changed(value: float):
	GameSettings.set_sensitivity(value / 1000.0)
	_update_options_labels()

func _set_ingame_crosshair_color(color: Color):
	GameSettings.set_crosshair_color(color)
	$CanvasLayer/InGameOptions/OptionsContainer/CrosshairContainer/CrosshairPreview.modulate = color

func _on_ingame_green_button_pressed():
	_set_ingame_crosshair_color(COLOR_GREEN)

func _on_ingame_red_button_pressed():
	_set_ingame_crosshair_color(COLOR_RED)

func _on_ingame_white_button_pressed():
	_set_ingame_crosshair_color(COLOR_WHITE)

func _on_ingame_options_back_pressed():
	GameSettings.save_settings()
	$CanvasLayer/InGameOptions.hide()
	$CanvasLayer/PauseMenu.show()
	in_options_menu = false

func _on_quit_to_menu_pressed():
	if multiplayer and multiplayer.is_server():
		_notify_session_ended.rpc()
		if get_tree():
			await get_tree().create_timer(0.1).timeout
	
	is_paused = false
	is_in_game = false
	GameSettings.is_paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if multiplayer and multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	if get_tree():
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

@rpc("authority", "reliable", "call_remote")
func _notify_session_ended():
	if not is_in_game:
		return 
	is_paused = false
	is_in_game = false
	GameSettings.is_paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if multiplayer and multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	if get_tree():
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_username_text_changed(new_text: String) -> void:
	local_username = new_text.strip_edges()
	var is_valid = local_username.length() >= 1
	$CanvasLayer/Host.disabled = not is_valid
	$CanvasLayer/Join.disabled = not is_valid

func _on_host_pressed() -> void:
	GameSettings.is_paused = false  
	peer = ENetMultiplayerPeer.new()
	var result = peer.create_server(server_port)
	if result != OK:
		print("Failed to create server: ", result)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	player_list[1] = local_username
	add_player(1)
	_update_player_list_ui()
	_hide_menu()
	is_in_game = true
	print("Server started on port ", server_port)

func _on_join_pressed() -> void:
	GameSettings.is_paused = false
	peer = ENetMultiplayerPeer.new()
	print("Connecting to: ", server_ip, ":", server_port)
	var result = peer.create_client(server_ip, server_port)
	if result != OK:
		print("Failed to create client: ", result)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_hide_menu()
	is_in_game = true

func _on_ip_text_changed(new_text: String) -> void:
	# Parse IP and optional port (format: ip:port or just ip)
	var text = new_text.strip_edges()
	if text.contains(":"):
		var parts = text.split(":")
		server_ip = parts[0]
		if parts.size() > 1 and parts[1].is_valid_int():
			server_port = int(parts[1])
	else:
		server_ip = text if text != "" else "127.0.0.1"
		server_port = 1027

func _on_server_disconnected():
	if not is_in_game:
		return
	is_paused = false
	is_in_game = false
	GameSettings.is_paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if multiplayer and multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	if get_tree():
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _hide_menu():
	$CanvasLayer/Host.hide()
	$CanvasLayer/Join.hide()
	$CanvasLayer/Back.hide()
	$CanvasLayer/title.hide()
	$CanvasLayer/hackclub.hide()
	$CanvasLayer/hackclub2.hide()
	$CanvasLayer/SelectionUI.hide()
	$CanvasLayer/UsernameEdit.hide()
	$CanvasLayer/IPEdit.hide()
	$CanvasLayer/CenterContainer/Crosshair.show()
	$CanvasLayer/version.show()

func _on_connected_to_server():
	var my_id = multiplayer.get_unique_id()
	player_list[my_id] = local_username
	_register_player_on_server.rpc_id(1, my_id, local_username)

@rpc("any_peer", "reliable")
func _register_player_on_server(id: int, username: String):
	if not multiplayer.is_server():
		return
	player_list[id] = username
	_sync_player_list.rpc(player_list)
	_update_player_list_ui()

@rpc("authority", "reliable", "call_local")
func _sync_player_list(list: Dictionary):
	player_list = list
	_update_player_list_ui()

func _update_player_list_ui():
	var container = $CanvasLayer/PlayerList/VBoxContainer
	if not is_instance_valid(container) or not container.is_inside_tree():
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	var sorted_ids = player_list.keys()
	sorted_ids.sort()
	for id in sorted_ids:
		var label = Label.new()
		label.text = player_list[id]
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color.WHITE)
		container.add_child(label)

func _on_peer_connected(id):
	if multiplayer.is_server():
		add_player(id)

func _on_peer_disconnected(id):
	del_player(id)
	if multiplayer.is_server():
		player_list.erase(id)
		_sync_player_list.rpc(player_list)
		_update_player_list_ui()

func get_spawn_position() -> Vector3:
	var spawn_nodes = get_tree().get_nodes_in_group("spawn_points")
	for spawn in spawn_nodes:
		if spawn not in used_spawn_points:
			used_spawn_points.append(spawn)
			return spawn.global_position
	if spawn_nodes.size() > 0:
		return spawn_nodes[randi() % spawn_nodes.size()].global_position
	return Vector3(0, 0, 0)

func custom_spawn(data):
	var player = player_scene.instantiate()
	player.name = str(data.id)
	player.position = data.pos
	player.sync_position = data.pos
	return player

func add_player(id):
	var spawn_pos = get_spawn_position()
	$MultiplayerSpawner.spawn({"id": id, "pos": spawn_pos})
	
func exit_game(id):
	del_player(id)

func del_player(id):
	var player_node = get_node_or_null(str(id))
	if player_node:
		player_node.queue_free()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file('res://scenes/main_menu.tscn')
