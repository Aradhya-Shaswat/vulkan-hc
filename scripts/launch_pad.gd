extends RigidBody3D

@export var sync_position: Vector3
@export var sync_rotation: Vector3
@export var sync_linear_velocity: Vector3
@export var sync_angular_velocity: Vector3

var is_held_by: int = 0
var held_target_pos: Vector3
var held_target_rot: Vector3
var is_dynamic_spawn: bool = false
var sync_timer: float = 0.0
var is_placed: bool = false

var launch_force: float = 20.0
var cooldown_players: Dictionary = {}
const LAUNCH_COOLDOWN: float = 0.5

var detection_area: Area3D

func _ready():
	if sync_position != Vector3.ZERO:
		global_position = sync_position
		rotation = sync_rotation
		is_dynamic_spawn = true
	else:
		sync_position = global_position
		sync_rotation = rotation
	sync_linear_velocity = linear_velocity
	sync_angular_velocity = angular_velocity
	held_target_pos = global_position
	held_target_rot = rotation
	
	add_to_group("launch_pads")
	add_to_group("physics_objects")
	
	# Find detection area
	detection_area = get_node_or_null("DetectionArea")
	if detection_area:
		detection_area.body_entered.connect(_on_body_entered)

func _physics_process(delta):
	if multiplayer.multiplayer_peer == null:
		return
	if not multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return
	
	# Update cooldowns
	var to_remove = []
	for player_id in cooldown_players:
		cooldown_players[player_id] -= delta
		if cooldown_players[player_id] <= 0:
			to_remove.append(player_id)
	for id in to_remove:
		cooldown_players.erase(id)
	
	var my_id = multiplayer.get_unique_id()
	
	if multiplayer.is_server():
		if is_held_by != 0 and is_held_by != 1:
			global_position = global_position.lerp(held_target_pos, delta * 14.0)
			global_rotation = held_target_rot
		
		# Check if pad has settled on ground
		if not is_placed and not freeze and linear_velocity.length() < 0.3 and is_on_ground():
			_settle_on_ground()
		
		sync_position = global_position
		sync_rotation = rotation
		sync_linear_velocity = linear_velocity
		sync_angular_velocity = angular_velocity
		
		if is_dynamic_spawn:
			sync_timer += delta
			if sync_timer >= 0.05:
				sync_timer = 0.0
				_rpc_sync_state.rpc(sync_position, sync_rotation, sync_linear_velocity, sync_angular_velocity, is_placed)
	else:
		if is_held_by != my_id:
			global_position = global_position.lerp(sync_position, delta * 15.0)
			rotation = rotation.lerp(sync_rotation, delta * 15.0)
			linear_velocity = sync_linear_velocity
			angular_velocity = sync_angular_velocity

func is_on_ground() -> bool:
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3(0, -0.3, 0))
	query.exclude = [self]
	var result = space_state.intersect_ray(query)
	return result.size() > 0

func _settle_on_ground():
	is_placed = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	rotation.x = 0
	rotation.z = 0
	_sync_placed.rpc()

@rpc("authority", "reliable", "call_local")
func _sync_placed():
	is_placed = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	rotation.x = 0
	rotation.z = 0

@rpc("authority", "unreliable_ordered", "call_remote")
func _rpc_sync_state(pos: Vector3, rot: Vector3, lin_vel: Vector3, ang_vel: Vector3, placed: bool):
	sync_position = pos
	sync_rotation = rot
	sync_linear_velocity = lin_vel
	sync_angular_velocity = ang_vel
	if placed and not is_placed:
		is_placed = true
		freeze = true

@rpc("any_peer", "call_local", "reliable")
func apply_push(push_velocity: Vector3):
	if multiplayer.is_server() and not is_placed:
		linear_velocity += push_velocity

@rpc("any_peer", "call_local", "reliable")
func request_hold(peer_id: int):
	if multiplayer.is_server():
		if is_held_by == 0:
			is_held_by = peer_id
			is_placed = false
			freeze = true
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			held_target_pos = global_position
			held_target_rot = rotation
			if peer_id != 1:
				_sync_hold_state.rpc(peer_id, true)

@rpc("any_peer", "call_local", "reliable")
func request_release(peer_id: int, release_velocity: Vector3):
	if multiplayer.is_server():
		if is_held_by == peer_id:
			is_held_by = 0
			freeze = false
			sleeping = false
			linear_velocity = release_velocity
			angular_velocity = Vector3.ZERO
			if release_velocity.length() < 0.1:
				apply_central_impulse(Vector3(0, -0.01, 0))
			_sync_hold_state.rpc(0, false)

@rpc("any_peer", "unreliable_ordered")
func update_held_position(peer_id: int, pos: Vector3, rot: Vector3):
	if multiplayer.is_server():
		if is_held_by == peer_id:
			held_target_pos = pos
			held_target_rot = rot
			if peer_id == 1:
				global_position = pos
				global_rotation = rot

@rpc("authority", "call_local", "reliable")
func _sync_hold_state(holder_id: int, is_frozen: bool):
	is_held_by = holder_id
	freeze = is_frozen
	if is_frozen:
		is_placed = false
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO

@rpc("any_peer", "call_local", "reliable")
func request_throw(throw_velocity: Vector3):
	if multiplayer.is_server():
		is_held_by = 0
		freeze = false
		sleeping = false
		linear_velocity = throw_velocity
		angular_velocity = Vector3.ZERO
		_sync_throw.rpc(throw_velocity)

@rpc("authority", "call_local", "reliable")
func _sync_throw(throw_velocity: Vector3):
	is_held_by = 0
	freeze = false
	sleeping = false
	linear_velocity = throw_velocity
	angular_velocity = Vector3.ZERO
	SoundManager.play_throw()

func _on_body_entered(body: Node):
	if not is_placed:
		return
	
	if body == self:
		return
	
	if body is CharacterBody3D and body.has_method("apply_launch_force"):
		var player_id = body.name.to_int()
		if cooldown_players.has(player_id):
			return
		
		cooldown_players[player_id] = LAUNCH_COOLDOWN
		body.apply_launch_force(Vector3.UP * launch_force)
		_play_launch_effect()
	
	elif body is RigidBody3D and body != self:
		if body.has_method("apply_push"):
			body.apply_push.rpc(Vector3.UP * launch_force * 0.5)
		else:
			body.apply_central_impulse(Vector3.UP * launch_force * body.mass * 0.3)
		_play_launch_effect()

func _play_launch_effect():
	SoundManager.play_launch()
	
	var mesh = get_node_or_null("MeshInstance3D")
	if mesh and mesh.mesh and mesh.mesh.material:
		var mat = mesh.mesh.material as StandardMaterial3D
		if mat:
			var tween = create_tween()
			mat.emission_energy_multiplier = 3.0
			tween.tween_property(mat, "emission_energy_multiplier", 0.5, 0.3)
