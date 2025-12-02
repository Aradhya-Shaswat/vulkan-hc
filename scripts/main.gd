extends Node3D

var peer = ENetMultiplayerPeer.new()
@export var player_scene : PackedScene
var used_spawn_points = []

func _on_host_pressed() -> void:
	peer.create_server(1027)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	add_player(1)
	# temporary stuff
	$CanvasLayer/Host.hide()
	$CanvasLayer/Join.hide()


func _on_join_pressed() -> void:
	peer.create_client('127.0.0.1', 1027)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	$CanvasLayer/Host.hide()
	$CanvasLayer/Join.hide()

func _on_peer_connected(id):
	if multiplayer.is_server():
		add_player(id)

func _on_peer_disconnected(id):
	del_player(id)

func get_spawn_position() -> Vector3:
	var spawn_nodes = get_tree().get_nodes_in_group("spawn_points")
	for spawn in spawn_nodes:
		if spawn not in used_spawn_points:
			used_spawn_points.append(spawn)
			return spawn.global_position
	if spawn_nodes.size() > 0:
		return spawn_nodes[randi() % spawn_nodes.size()].global_position
	return Vector3(0, 0, 0)

func add_player(id):
	var player = player_scene.instantiate()
	player.name = str(id)
	var spawn_pos = get_spawn_position()
	player.position = spawn_pos
	player.sync_position = spawn_pos
	add_child(player)
	
func exit_game(id):
	del_player(id)

func del_player(id):
	var player_node = get_node_or_null(str(id))
	if player_node:
		player_node.queue_free()
	
	
	
	
	
	
