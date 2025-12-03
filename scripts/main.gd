extends Node3D

var peer = ENetMultiplayerPeer.new()
@export var player_scene : PackedScene
var used_spawn_points = []
var local_username = ""
var player_list = {}
var player_list_visible = false
var player_list_tween: Tween

func _ready():
	$MultiplayerSpawner.spawn_function = custom_spawn
	$CanvasLayer/Host.disabled = true
	$CanvasLayer/Join.disabled = true
	$CanvasLayer/PlayerList.modulate.a = 0.0
	$CanvasLayer/PlayerList.position.x = -200
	$CanvasLayer/PlayerList.hide()

func _unhandled_input(event):
	if event.is_action_pressed("ui_focus_next"):
		get_viewport().set_input_as_handled()
		if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_toggle_player_list()

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

func _on_username_text_changed(new_text: String) -> void:
	local_username = new_text.strip_edges()
	var is_valid = local_username.length() >= 1
	$CanvasLayer/Host.disabled = not is_valid
	$CanvasLayer/Join.disabled = not is_valid

func _on_host_pressed() -> void:
	peer.create_server(1027)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	player_list[1] = local_username
	add_player(1)
	_update_player_list_ui()
	_hide_menu()

func _on_join_pressed() -> void:
	peer.create_client('127.0.0.1', 1027)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	_hide_menu()

func _hide_menu():
	$CanvasLayer/Host.hide()
	$CanvasLayer/Join.hide()
	$CanvasLayer/Back.hide()
	$CanvasLayer/title.hide()
	$CanvasLayer/hackclub.hide()
	$CanvasLayer/hackclub2.hide()
	$CanvasLayer/SelectionUI.hide()
	$CanvasLayer/UsernameEdit.hide()
	$CanvasLayer/CenterContainer/Crosshair.show()
	$CanvasLayer/guide.show()
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
