extends RigidBody3D

@export var sync_position: Vector3
@export var sync_rotation: Vector3
@export var sync_linear_velocity: Vector3
@export var sync_angular_velocity: Vector3

var is_held_by: int = 0
var held_target_pos: Vector3
var held_target_rot: Vector3

func _ready():
	sync_position = global_position
	sync_rotation = rotation
	sync_linear_velocity = linear_velocity
	sync_angular_velocity = angular_velocity
	held_target_pos = global_position
	held_target_rot = rotation

func _physics_process(delta):
	if multiplayer.multiplayer_peer == null:
		return
	if not multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return
	
	var my_id = multiplayer.get_unique_id()
	
	if multiplayer.is_server():
		if is_held_by != 0 and is_held_by != 1:
			global_position = global_position.lerp(held_target_pos, delta * 14.0)
			global_rotation = held_target_rot
		
		sync_position = global_position
		sync_rotation = rotation
		sync_linear_velocity = linear_velocity
		sync_angular_velocity = angular_velocity
	else:
		if is_held_by != my_id:
			global_position = global_position.lerp(sync_position, delta * 15.0)
			rotation = rotation.lerp(sync_rotation, delta * 15.0)
			linear_velocity = sync_linear_velocity
			angular_velocity = sync_angular_velocity

@rpc("any_peer", "call_local", "reliable")
func apply_push(push_velocity: Vector3):
	if multiplayer.is_server():
		linear_velocity += push_velocity

@rpc("any_peer", "call_local", "reliable")
func request_hold(peer_id: int):
	if multiplayer.is_server():
		if is_held_by == 0:
			is_held_by = peer_id
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

@rpc("any_peer", "call_local", "reliable")
func request_scale(mesh_scale: Vector3, shape_scale: Vector3, new_mass: float):
	if multiplayer.is_server():
		_apply_scale(mesh_scale, shape_scale, new_mass)
		_sync_scale.rpc(mesh_scale, shape_scale, new_mass)

func _apply_scale(mesh_scale: Vector3, shape_scale: Vector3, new_mass: float):
	var mesh = _find_mesh(self)
	var shape = _find_collision_shape(self)
	if mesh:
		mesh.scale = mesh_scale
	if shape:
		shape.scale = shape_scale
	mass = new_mass

func _find_mesh(obj: Node) -> MeshInstance3D:
	if obj is MeshInstance3D:
		return obj
	for c in obj.get_children():
		var m = _find_mesh(c)
		if m:
			return m
	return null

func _find_collision_shape(root: Node) -> CollisionShape3D:
	if root is CollisionShape3D:
		return root
	for c in root.get_children():
		var r = _find_collision_shape(c)
		if r:
			return r
	return null

@rpc("authority", "call_local", "reliable")
func _sync_scale(mesh_scale: Vector3, shape_scale: Vector3, new_mass: float):
	_apply_scale(mesh_scale, shape_scale, new_mass)

@rpc("authority", "call_local", "reliable")
func _sync_hold_state(holder_id: int, is_frozen: bool):
	is_held_by = holder_id
	freeze = is_frozen
	if is_frozen:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO

@rpc("any_peer", "call_local", "reliable")
func request_glue():
	if multiplayer.is_server():
		is_held_by = 0
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_sync_glue_state.rpc()

@rpc("authority", "call_local", "reliable")
func _sync_glue_state():
	is_held_by = 0
	freeze = true
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
