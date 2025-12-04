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
var is_connecting = false
var connection_timeout = 10.0
var server_ip: String = "127.0.0.1"
var server_port: int = 1027
var server_password: String = ""
var client_password: String = ""
var pending_action: String = ""
var password_rejection_id: int = 0
var password_attempted: bool = false
var selected_hotbar_slot = 0
var next_object_id = 1000
var spawn_counts = {}
var spawned_objects = {}
const MAX_SPAWNS_PER_TYPE = 10

var game_time_limit: float = 300.0
var game_time_remaining: float = 300.0
var game_timer_active: bool = false
var kill_counts: Dictionary = {}
var game_ended: bool = false
var return_to_menu_timer: float = 10.0

const COLOR_GREEN = Color(0.2, 0.92, 0, 1)
const COLOR_RED = Color(1, 0.2, 0.2, 1)
const COLOR_WHITE = Color(1, 1, 1, 1)

const HOTBAR_ITEMS = ["cube", "sphere", "cylinder", "capsule"]

func _ready():
	$MultiplayerSpawner.spawn_function = custom_spawn
	$CanvasLayer/Host.disabled = true
	$CanvasLayer/Join.disabled = true
	$CanvasLayer/PlayerList.modulate.a = 0.0
	$CanvasLayer/PlayerList.position.x = -200
	$CanvasLayer/PlayerList.hide()
	$CanvasLayer/PauseMenu.hide()
	$CanvasLayer/InGameOptions.hide()
	$CanvasLayer/LoadingPanel.hide()
	$CanvasLayer/PasswordPanel.hide()
	$CanvasLayer/GameTimerLabel.hide()
	$CanvasLayer/GameEndOverlay.hide()
	if has_node("CanvasLayer/Hotbar"):
		$CanvasLayer/Hotbar.hide()
	_apply_crosshair_color()
	GameSettings.settings_changed.connect(_on_settings_changed)
	GameSettings.is_paused = false
	_connect_hover_sounds()
	SoundManager.start_menu_music()
	
	if GameSettings.saved_nickname != "":
		$CanvasLayer/UsernameEdit.text = GameSettings.saved_nickname
		local_username = GameSettings.saved_nickname
		$CanvasLayer/Host.disabled = false
		$CanvasLayer/Join.disabled = false

func _connect_hover_sounds():
	_connect_buttons_recursive($CanvasLayer)

func _connect_buttons_recursive(node: Node):
	if node is Button:
		if not node.mouse_entered.is_connected(_on_button_hover):
			node.mouse_entered.connect(_on_button_hover)
	for child in node.get_children():
		_connect_buttons_recursive(child)

func _on_button_hover():
	SoundManager.play_ui_hover()

var time_sync_timer: float = 0.0
var last_countdown_second: int = -1

func _process(delta):
	if game_timer_active and not game_ended:
		if multiplayer.is_server():
			game_time_remaining -= delta
			time_sync_timer += delta
			if time_sync_timer >= 1.0:
				time_sync_timer = 0.0
				_sync_game_time.rpc(game_time_remaining)
			if game_time_remaining <= 0:
				game_time_remaining = 0
				_end_game()
		_update_timer_display()
		
		var current_second = int(game_time_remaining)
		if game_time_remaining <= 10 and current_second != last_countdown_second and current_second > 0:
			last_countdown_second = current_second
			SoundManager.play_countdown_tick()
	
	if game_ended:
		return_to_menu_timer -= delta
		$CanvasLayer/GameEndOverlay/ReturnTimer.text = "Returning to menu in " + str(int(return_to_menu_timer)) + "..."
		if return_to_menu_timer <= 0:
			_return_to_menu()

func _update_timer_display():
	var minutes = int(game_time_remaining) / 60
	var seconds = int(game_time_remaining) % 60
	$CanvasLayer/GameTimerLabel.text = "%d:%02d" % [minutes, seconds]
	if game_time_remaining <= 30:
		$CanvasLayer/GameTimerLabel.modulate = Color(1, 0.3, 0.3, 1)
	elif game_time_remaining <= 60:
		$CanvasLayer/GameTimerLabel.modulate = Color(1, 0.7, 0.3, 1)
	else:
		$CanvasLayer/GameTimerLabel.modulate = Color(1, 1, 1, 1)

func _on_settings_changed():
	_apply_crosshair_color()

func _apply_crosshair_color():
	$CanvasLayer/CenterContainer/Crosshair.modulate = GameSettings.crosshair_color

func _unhandled_input(event):
	if event.is_action_pressed("ui_focus_next"):
		get_viewport().set_input_as_handled()
		if is_in_game and not is_paused and not Console.is_open and multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_toggle_player_list()
	
	if event is InputEventMouseButton and event.pressed:
		if is_in_game and not is_paused and not Console.is_open:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_select_hotbar_slot((selected_hotbar_slot - 1 + 4) % 4)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_select_hotbar_slot((selected_hotbar_slot + 1) % 4)
	
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if is_in_game and not Console.is_open:
				_toggle_pause()
		
		if event.keycode == KEY_P:
			if is_in_game and not Console.is_open:
				_toggle_pause()
		
		if is_in_game and not is_paused and not Console.is_open:
			if event.keycode == KEY_1:
				_select_hotbar_slot(0)
			elif event.keycode == KEY_2:
				_select_hotbar_slot(1)
			elif event.keycode == KEY_3:
				_select_hotbar_slot(2)
			elif event.keycode == KEY_4:
				_select_hotbar_slot(3)
			elif event.keycode == KEY_G:
				_spawn_selected_object()

func _select_hotbar_slot(slot: int):
	selected_hotbar_slot = slot
	_update_hotbar_selection()

func _update_hotbar_selection():
	if not has_node("CanvasLayer/Hotbar"):
		return
	for i in range(4):
		var slot_node = $CanvasLayer/Hotbar/HBoxContainer.get_child(i)
		if slot_node:
			if i == selected_hotbar_slot:
				slot_node.modulate = Color(1, 1, 0.5, 1)
			else:
				slot_node.modulate = Color(1, 1, 1, 1)

func _update_hotbar_counts():
	if not has_node("CanvasLayer/Hotbar"):
		return
	if not multiplayer or not multiplayer.multiplayer_peer:
		return
	var my_id = multiplayer.get_unique_id()
	for i in range(4):
		var slot_node = $CanvasLayer/Hotbar/HBoxContainer.get_child(i)
		if slot_node and slot_node.has_node("Count"):
			var shape = HOTBAR_ITEMS[i]
			var count = _get_spawn_count(my_id, shape)
			slot_node.get_node("Count").text = str(count) + "/" + str(MAX_SPAWNS_PER_TYPE)
			if count >= MAX_SPAWNS_PER_TYPE:
				slot_node.get_node("Count").modulate = Color(1, 0.3, 0.3, 1)
			else:
				slot_node.get_node("Count").modulate = Color(1, 1, 1, 1)

func _spawn_selected_object():
	if selected_hotbar_slot >= 0 and selected_hotbar_slot < HOTBAR_ITEMS.size():
		_spawn_object(HOTBAR_ITEMS[selected_hotbar_slot])

func _toggle_player_list():
	player_list_visible = not player_list_visible
	if player_list_tween:
		player_list_tween.kill()
	player_list_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	if player_list_visible:
		$CanvasLayer/PlayerList.show()
		player_list_tween.set_parallel(true)
		player_list_tween.tween_property($CanvasLayer/PlayerList, "position:x", 14, 0.3)
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
		if not Console.is_open:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_resume_pressed():
	SoundManager.play_ui_click()
	_toggle_pause()

func _on_reset_character_pressed():
	SoundManager.play_ui_click()
	var my_id = multiplayer.get_unique_id()
	var player_node = get_node_or_null(str(my_id))
	if player_node and player_node.has_method("respawn"):
		player_node.respawn()
	_toggle_pause()

func _on_pause_options_pressed():
	SoundManager.play_ui_click()
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
	SoundManager.play_ui_click()
	_set_ingame_crosshair_color(COLOR_GREEN)

func _on_ingame_red_button_pressed():
	SoundManager.play_ui_click()
	_set_ingame_crosshair_color(COLOR_RED)

func _on_ingame_white_button_pressed():
	SoundManager.play_ui_click()
	_set_ingame_crosshair_color(COLOR_WHITE)

func _on_ingame_options_back_pressed():
	SoundManager.play_ui_back()
	GameSettings.save_settings()
	$CanvasLayer/InGameOptions.hide()
	$CanvasLayer/PauseMenu.show()
	in_options_menu = false

func _on_quit_to_menu_pressed():
	SoundManager.play_ui_click()
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
		SceneTransition.change_scene("res://scenes/main_menu.tscn")

@rpc("authority", "reliable", "call_remote")
func _notify_session_ended():
	if not is_in_game:
		return 
	is_paused = false
	is_in_game = false
	GameSettings.is_paused = false
	
	if multiplayer and multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	
	$CanvasLayer/PauseMenu.hide()
	$CanvasLayer/InGameOptions.hide()
	$CanvasLayer/LoadingPanel/CancelButton.hide()
	$CanvasLayer/LoadingPanel/LoadingLabel.text = "Host ended the session"
	$CanvasLayer/LoadingPanel.show()
	
	await get_tree().create_timer(2.0).timeout
	
	$CanvasLayer/LoadingPanel.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if get_tree():
		SceneTransition.change_scene("res://scenes/main_menu.tscn")

func _on_username_text_changed(new_text: String) -> void:
	var text = new_text.strip_edges()
	if text.length() < 1:
		$CanvasLayer/Host.disabled = true
		$CanvasLayer/Join.disabled = true
		return
	
	GameSettings.check_profanity(text, func(is_profane):
		if is_profane:
			$CanvasLayer/Host.disabled = true
			$CanvasLayer/Join.disabled = true
		else:
			local_username = GameSettings.sanitize_nickname(text)
			$CanvasLayer/Host.disabled = false
			$CanvasLayer/Join.disabled = false
			GameSettings.saved_nickname = local_username
			GameSettings.save_settings()
	)

func _on_host_pressed() -> void:
	SoundManager.play_ui_click()
	pending_action = "host"
	$CanvasLayer/PasswordPanel/PasswordTitle.text = "Set Server Password"
	$CanvasLayer/PasswordPanel/PasswordHint.text = "Leave empty for public server"
	$CanvasLayer/PasswordPanel/PasswordInput.text = ""
	$CanvasLayer/PasswordPanel/PasswordInput.placeholder_text = "Password"
	$CanvasLayer/PasswordPanel/TimerContainer.show()
	$CanvasLayer/title.hide()
	$CanvasLayer/PasswordPanel.show()
	$CanvasLayer/PasswordPanel/PasswordInput.grab_focus()

func _on_join_pressed() -> void:
	SoundManager.play_ui_click()
	_start_joining("")

func _on_password_confirm_pressed() -> void:
	SoundManager.play_ui_click()
	var password = $CanvasLayer/PasswordPanel/PasswordInput.text.strip_edges()
	$CanvasLayer/PasswordPanel.hide()
	
	if pending_action == "host":
		_start_hosting(password)
	elif pending_action == "join" or pending_action == "retry_join":
		_start_joining(password)

func _on_password_cancel_pressed() -> void:
	SoundManager.play_ui_back()
	$CanvasLayer/PasswordPanel.hide()
	$CanvasLayer/title.show()
	pending_action = ""

func _start_hosting(password: String) -> void:
	GameSettings.is_paused = false
	server_password = password
	
	var timer_minutes = $CanvasLayer/PasswordPanel/TimerContainer/TimerInput.value
	game_time_limit = timer_minutes * 60.0
	game_time_remaining = game_time_limit
	game_ended = false
	kill_counts.clear()
	
	$CanvasLayer/LoadingPanel/CancelButton.hide()
	$CanvasLayer/LoadingPanel/LoadingLabel.text = "Starting server on port " + str(server_port) + "..."
	$CanvasLayer/LoadingPanel.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_start_loading_animation()
	
	await get_tree().create_timer(1.5).timeout
	
	peer = ENetMultiplayerPeer.new()
	var result = peer.create_server(server_port)
	if result != OK:
		$CanvasLayer/LoadingPanel/LoadingLabel.text = "Failed to start server!"
		await get_tree().create_timer(1.5).timeout
		$CanvasLayer/LoadingPanel.hide()
		$CanvasLayer/title.show()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	
	$CanvasLayer/LoadingPanel.hide()
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	player_list[1] = local_username
	add_player(1)
	_update_player_list_ui()
	_update_player_nametags()
	_hide_menu()
	is_in_game = true
	game_timer_active = true
	$CanvasLayer/GameTimerLabel.show()
	SoundManager.stop_menu_music()
	SoundManager.play_game_start()
	var host_player = get_node_or_null("1")
	if host_player and host_player.has_method("show_health_ui"):
		host_player.show_health_ui()
	if has_node("CanvasLayer/Hotbar"):
		$CanvasLayer/Hotbar.show()
		_update_hotbar_selection()
		_update_hotbar_counts()

func _start_joining(password: String) -> void:
	GameSettings.is_paused = false
	client_password = password
	password_attempted = password != ""
	password_rejection_id += 1
	peer = ENetMultiplayerPeer.new()
	var result = peer.create_client(server_ip, server_port)
	if result != OK:
		print("Failed to create client: ", result)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	
	is_connecting = true
	$CanvasLayer/LoadingPanel.show()
	$CanvasLayer/LoadingPanel/CancelButton.hide()
	$CanvasLayer/LoadingPanel/LoadingLabel.text = "Connecting to server..."
	$CanvasLayer/title.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_start_loading_animation()
	_start_connection_timeout()

func _on_ip_text_changed(new_text: String) -> void:
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
		SceneTransition.change_scene("res://scenes/main_menu.tscn")

func _hide_menu():
	$CanvasLayer/Host.hide()
	$CanvasLayer/Join.hide()
	$CanvasLayer/Back.hide()
	$CanvasLayer/title.hide()
	$CanvasLayer/hackclub.hide()
	$CanvasLayer/Axolotl.hide()
	$CanvasLayer/SelectionUI.hide()
	$CanvasLayer/UsernameEdit.hide()
	$CanvasLayer/IPEdit.hide()
	$CanvasLayer/PasswordPanel.hide()
	$CanvasLayer/CenterContainer/Crosshair.show()
	$CanvasLayer/version.show()

func _on_connected_to_server():
	is_connecting = false
	
	await get_tree().create_timer(1.0).timeout
	
	if is_in_game:
		return
	
	$CanvasLayer/LoadingPanel/LoadingLabel.text = "Verifying..."
	
	var my_id = multiplayer.get_unique_id()
	_verify_password.rpc_id(1, my_id, local_username, client_password)

func _on_connection_failed():
	is_connecting = false
	$CanvasLayer/LoadingPanel/LoadingLabel.text = "Connection failed!"
	await get_tree().create_timer(1.5).timeout
	$CanvasLayer/LoadingPanel.hide()
	$CanvasLayer/title.show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if multiplayer and multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()

func _on_cancel_connection_pressed():
	SoundManager.play_ui_back()
	is_connecting = false
	$CanvasLayer/LoadingPanel.hide()
	if multiplayer and multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()

func _start_loading_animation():
	var spinner = $CanvasLayer/LoadingPanel/Spinner
	var tween = create_tween().set_loops()
	tween.tween_property(spinner, "rotation", TAU, 1.0).from(0.0)

func _start_connection_timeout():
	await get_tree().create_timer(connection_timeout).timeout
	if is_connecting:
		is_connecting = false
		$CanvasLayer/LoadingPanel/LoadingLabel.text = "Connection timed out!"
		await get_tree().create_timer(1.5).timeout
		$CanvasLayer/LoadingPanel.hide()
		$CanvasLayer/title.show()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if multiplayer and multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.close()

@rpc("any_peer", "reliable")
func _register_player_on_server(id: int, username: String):
	if not multiplayer.is_server():
		return
	player_list[id] = username
	_sync_player_list.rpc(player_list)
	_update_player_list_ui()

@rpc("any_peer", "reliable")
func _verify_password(id: int, username: String, password: String):
	if not multiplayer.is_server():
		return
	
	if server_password != "" and password != server_password:
		_password_rejected.rpc_id(id)
		return
	
	var final_username = _get_unique_username(username)
	_password_accepted.rpc_id(id, final_username)
	_sync_game_time.rpc_id(id, game_time_remaining)
	_sync_kill_counts.rpc_id(id, kill_counts)
	game_timer_active = true
	player_list[id] = final_username
	_sync_player_list.rpc(player_list)
	_update_player_list_ui()

func _get_unique_username(username: String) -> String:
	var sanitized = GameSettings.sanitize_nickname(username)
	var final_name = sanitized
	var suffix = 1
	
	for existing_name in player_list.values():
		if existing_name == final_name:
			final_name = sanitized + "_" + str(suffix)
			suffix += 1
	
	while _username_exists(final_name):
		final_name = sanitized + "_" + str(suffix)
		suffix += 1
	
	return final_name

func _username_exists(username: String) -> bool:
	for existing_name in player_list.values():
		if existing_name == username:
			return true
	return false

@rpc("authority", "reliable")
func _password_accepted(final_username: String = ""):
	pending_action = ""
	$CanvasLayer/LoadingPanel.hide()
	$CanvasLayer/PasswordPanel.hide()
	_hide_menu()
	is_in_game = true
	game_ended = false
	SoundManager.stop_menu_music()
	$CanvasLayer/GameTimerLabel.show()
	if has_node("CanvasLayer/Hotbar"):
		$CanvasLayer/Hotbar.show()
		_update_hotbar_selection()
		_update_hotbar_counts()
	
	var my_id = multiplayer.get_unique_id()
	player_list[my_id] = local_username
	
	var my_player = get_node_or_null(str(my_id))
	if my_player and my_player.has_method("show_health_ui"):
		my_player.show_health_ui()

@rpc("authority", "reliable")
func _password_rejected():
	is_connecting = false
	var my_rejection_id = password_rejection_id
	var was_attempted = password_attempted
	
	if multiplayer and multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	
	if was_attempted:
		$CanvasLayer/LoadingPanel/LoadingLabel.text = "Wrong password!"
	else:
		$CanvasLayer/LoadingPanel/LoadingLabel.text = "Password required!"
	
	await get_tree().create_timer(1.5).timeout
	
	if is_in_game or my_rejection_id != password_rejection_id:
		return
	
	$CanvasLayer/LoadingPanel.hide()
	$CanvasLayer/PasswordPanel/PasswordTitle.text = "Password Required"
	if was_attempted:
		$CanvasLayer/PasswordPanel/PasswordHint.text = "Incorrect password, try again"
	else:
		$CanvasLayer/PasswordPanel/PasswordHint.text = "This server requires a password"
	$CanvasLayer/PasswordPanel/PasswordInput.text = ""
	$CanvasLayer/PasswordPanel/PasswordInput.placeholder_text = "Enter password"
	$CanvasLayer/PasswordPanel/TimerContainer.hide()
	pending_action = "retry_join"
	$CanvasLayer/PasswordPanel.show()
	$CanvasLayer/PasswordPanel/PasswordInput.grab_focus()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

@rpc("authority", "reliable", "call_local")
func _sync_player_list(list: Dictionary):
	player_list = list
	_update_player_list_ui()
	_update_player_nametags()

func _update_player_nametags():
	for id in player_list.keys():
		var player_node = get_node_or_null(str(id))
		if player_node and player_node.has_node("Nametag"):
			var nametag = player_node.get_node("Nametag")
			nametag.text = player_list[id]

func _update_player_list_ui():
	var container = $CanvasLayer/PlayerList/VBoxContainer
	if not is_instance_valid(container) or not container.is_inside_tree():
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	var sorted_ids = player_list.keys()
	sorted_ids.sort()
	var my_id = multiplayer.get_unique_id() if multiplayer and multiplayer.multiplayer_peer else 0
	for id in sorted_ids:
		var label = Label.new()
		if id == my_id:
			label.text = player_list[id] + " (you)"
			label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
		else:
			label.text = player_list[id]
			label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_font_size_override("font_size", 16)
		container.add_child(label)

func _on_peer_connected(id):
	if multiplayer.is_server():
		add_player(id)
		for obj_name in spawned_objects:
			var data = spawned_objects[obj_name]
			var obj = get_node_or_null("Objects/" + obj_name)
			if obj:
				var spawner_id = data.get("spawner", 1)
				_sync_spawn_object.rpc_id(id, obj_name, data.shape, obj.global_position, data.color, spawner_id)

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
	SoundManager.play_ui_back()
	SceneTransition.change_scene('res://scenes/main_menu.tscn')

func _get_spawn_count(player_id: int, shape: String) -> int:
	var key = str(player_id) + "_" + shape
	return spawn_counts.get(key, 0)

func _increment_spawn_count(player_id: int, shape: String):
	var key = str(player_id) + "_" + shape
	spawn_counts[key] = spawn_counts.get(key, 0) + 1

func _spawn_object(shape: String):
	if not multiplayer or not multiplayer.multiplayer_peer:
		return
	
	var my_id = multiplayer.get_unique_id()
	
	if _get_spawn_count(my_id, shape) >= MAX_SPAWNS_PER_TYPE:
		return
	
	var player_node = get_node_or_null(str(my_id))
	if not player_node:
		return
	
	var cam = player_node.get_node_or_null("Head/Camera3D")
	if not cam:
		return
	
	var spawn_dir = -cam.global_transform.basis.z
	var spawn_pos = cam.global_position + spawn_dir * 2.5 + Vector3(0, 0.5, 0)
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(spawn_pos, spawn_pos - Vector3(0, 2, 0))
	query.collision_mask = 1
	var result = space_state.intersect_ray(query)
	if result:
		spawn_pos.y = result.position.y + 1.0
	
	var color = Color(randf(), randf(), randf())
	
	SoundManager.play_spawn()
	
	if multiplayer.is_server():
		_request_spawn_object(shape, spawn_pos, color)
	else:
		_request_spawn_object.rpc_id(1, shape, spawn_pos, color)

@rpc("any_peer", "reliable")
func _request_spawn_object(shape: String, pos: Vector3, color: Color):
	if not multiplayer.is_server():
		return
	
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1
	
	if _get_spawn_count(sender_id, shape) >= MAX_SPAWNS_PER_TYPE:
		return
	
	var obj_name = "spawned_" + str(next_object_id)
	next_object_id += 1
	
	spawned_objects[obj_name] = {"shape": shape, "pos": pos, "color": color, "spawner": sender_id}
	_sync_spawn_object.rpc(obj_name, shape, pos, color, sender_id)

func _create_spawned_object(shape: String, pos: Vector3, color: Color, obj_name: String):
	if has_node("Objects/" + obj_name):
		return
	
	var obj = RigidBody3D.new()
	obj.name = obj_name
	obj.collision_layer = 2
	obj.collision_mask = 3
	
	var mesh = MeshInstance3D.new()
	var collision = CollisionShape3D.new()
	
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	
	match shape:
		"cube":
			mesh.mesh = BoxMesh.new()
			mesh.mesh.material = material
			collision.shape = BoxShape3D.new()
		"sphere":
			mesh.mesh = SphereMesh.new()
			mesh.mesh.material = material
			collision.shape = SphereShape3D.new()
		"cylinder":
			mesh.mesh = CylinderMesh.new()
			mesh.mesh.material = material
			collision.shape = CylinderShape3D.new()
		"capsule":
			mesh.mesh = CapsuleMesh.new()
			mesh.mesh.material = material
			collision.shape = CapsuleShape3D.new()
	
	obj.add_child(mesh)
	obj.add_child(collision)
	
	var script = load("res://scripts/synced_rigid_body.gd")
	obj.set_script(script)
	
	obj.sync_position = pos
	obj.sync_rotation = Vector3.ZERO
	
	$Objects.add_child(obj, true)
	obj.global_position = pos

@rpc("authority", "reliable", "call_local")
func _sync_spawn_object(obj_name: String, shape: String, pos: Vector3, color: Color, spawner_id: int = 1):
	_create_spawned_object(shape, pos, color, obj_name)
	_increment_spawn_count(spawner_id, shape)
	_update_hotbar_counts()

func register_kill(killer_id: int):
	if not multiplayer.is_server():
		return
	if killer_id == 0:
		return
	kill_counts[killer_id] = kill_counts.get(killer_id, 0) + 1
	_sync_kill_counts.rpc(kill_counts)
	_play_kill_sound.rpc_id(killer_id)

@rpc("authority", "reliable")
func _play_kill_sound():
	SoundManager.play_kill()

@rpc("authority", "reliable", "call_local")
func _sync_kill_counts(counts: Dictionary):
	kill_counts = counts

@rpc("authority", "reliable", "call_local")
func _sync_game_time(time_remaining: float):
	game_time_remaining = time_remaining
	if not game_ended:
		game_timer_active = true

func _end_game():
	if game_ended:
		return
	game_ended = true
	game_timer_active = false
	SoundManager.play_game_end()
	_show_game_end.rpc()

@rpc("authority", "reliable", "call_local")
func _show_game_end():
	game_ended = true
	game_timer_active = false
	return_to_menu_timer = 10.0
	
	$CanvasLayer/GameTimerLabel.hide()
	$CanvasLayer/GameEndOverlay.show()
	$CanvasLayer/PauseMenu.hide()
	if has_node("CanvasLayer/Hotbar"):
		$CanvasLayer/Hotbar.hide()
	
	var my_id = multiplayer.get_unique_id()
	var my_player = get_node_or_null(str(my_id))
	if my_player and my_player.has_node("CanvasLayer/HealthBarUI"):
		my_player.get_node("CanvasLayer/HealthBarUI").visible = false
	
	var container = $CanvasLayer/GameEndOverlay/LeaderboardContainer
	for child in container.get_children():
		child.queue_free()
	
	var sorted_players = []
	for id in player_list:
		sorted_players.append({
			"id": id,
			"name": player_list[id],
			"kills": kill_counts.get(id, 0)
		})
	sorted_players.sort_custom(func(a, b): return a.kills > b.kills)
	
	var header = Label.new()
	header.text = "LEADERBOARD"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 24)
	header.add_theme_color_override("font_color", Color(1, 1, 0.8, 1))
	container.add_child(header)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	container.add_child(spacer)
	
	var rank = 1
	for p in sorted_players:
		var row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		
		var rank_label = Label.new()
		var rank_color = Color(1, 1, 1, 1)
		if rank == 1:
			rank_color = Color(1, 0.85, 0.2, 1)
		elif rank == 2:
			rank_color = Color(0.75, 0.75, 0.75, 1)
		elif rank == 3:
			rank_color = Color(0.8, 0.5, 0.2, 1)
		rank_label.text = "#" + str(rank) + "  "
		rank_label.add_theme_font_size_override("font_size", 20)
		rank_label.add_theme_color_override("font_color", rank_color)
		row.add_child(rank_label)
		
		var name_label = Label.new()
		var display_name = p.name
		if p.id == multiplayer.get_unique_id():
			display_name += " (you)"
		name_label.text = display_name
		name_label.add_theme_font_size_override("font_size", 20)
		name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		name_label.custom_minimum_size.x = 150
		row.add_child(name_label)
		
		var kills_label = Label.new()
		kills_label.text = str(p.kills) + " kills"
		kills_label.add_theme_font_size_override("font_size", 20)
		kills_label.add_theme_color_override("font_color", Color(0.5, 1, 0.5, 1))
		row.add_child(kills_label)
		
		container.add_child(row)
		rank += 1
	
	if sorted_players.size() > 0 and sorted_players[0].kills > 0:
		$CanvasLayer/GameEndOverlay/Title.text = sorted_players[0].name + " WINS!"
	else:
		$CanvasLayer/GameEndOverlay/Title.text = "GAME OVER"
	
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _return_to_menu():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	SceneTransition.change_scene("res://scenes/main_menu.tscn")
