extends RigidBody3D

@export var acceleration: float = 15.0
@export var max_speed: float = 30.0
@export var turn_speed: float = 3.0
@export var brake_force: float = 20.0
@export var friction: float = 2.0
@export var drift_factor: float = 0.95
@export var grip_factor: float = 0.7

var driver_id: int = 0
var is_occupied: bool = false
var input_direction: Vector2 = Vector2.ZERO
var is_braking: bool = false
var is_drifting: bool = false

@export var sync_position: Vector3
@export var sync_rotation: Vector3

var prev_sync_position: Vector3
var prev_sync_rotation: Vector3
var sync_lerp_factor: float = 0.0
var was_server_last_check: bool = false
var spawn_position: Vector3 = Vector3.ZERO
var spawn_rotation: Vector3 = Vector3.ZERO
const FALL_THRESHOLD: float = -50.0

@onready var seat_position: Node3D = $SeatPosition
@onready var exit_position: Node3D = $ExitPosition

func _ready():
	add_to_group("carts")
	spawn_position = global_position
	spawn_rotation = rotation
	sync_position = global_position
	sync_rotation = rotation
	prev_sync_position = sync_position
	prev_sync_rotation = sync_rotation
	
	_update_freeze_state()

func _update_freeze_state():
	if multiplayer.multiplayer_peer == null:
		freeze = false
		return
	if not multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		freeze = false
		return
	
	var is_server = multiplayer.is_server()
	if is_server:
		freeze = false
	else:
		freeze = true

func _physics_process(delta):
	if multiplayer.multiplayer_peer == null:
		return
	if not multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return
	
	var is_server = multiplayer.is_server()
	if is_server != was_server_last_check:
		was_server_last_check = is_server
		_update_freeze_state()
	
	if multiplayer.is_server():
		if global_position.y < FALL_THRESHOLD:
			_respawn_cart()
		
		if is_occupied and driver_id != 0:
			_apply_movement(delta)
		else:
			_apply_friction(delta)
		sync_position = global_position
		sync_rotation = rotation
	else:
		if prev_sync_position != sync_position or prev_sync_rotation != sync_rotation:
			prev_sync_position = sync_position
			prev_sync_rotation = sync_rotation
			sync_lerp_factor = 0.0
		
		sync_lerp_factor = min(sync_lerp_factor + delta * 10.0, 1.0)
		global_position = global_position.lerp(sync_position, sync_lerp_factor)
		global_rotation = global_rotation.lerp(sync_rotation, sync_lerp_factor)

func _apply_movement(delta):
	var forward = -global_transform.basis.z
	var right = global_transform.basis.x
	var current_speed = linear_velocity.dot(forward)
	var lateral_speed = linear_velocity.dot(right)
	
	is_drifting = is_braking and abs(current_speed) > 3.0
	
	if input_direction.y != 0:
		var target_velocity = forward * input_direction.y * max_speed
		linear_velocity.x = lerp(linear_velocity.x, target_velocity.x, acceleration * delta * 0.1)
		linear_velocity.z = lerp(linear_velocity.z, target_velocity.z, acceleration * delta * 0.1)
	elif not is_drifting:
		linear_velocity.x = lerp(linear_velocity.x, 0.0, friction * delta)
		linear_velocity.z = lerp(linear_velocity.z, 0.0, friction * delta)
	
	if is_drifting:
		var drift_grip = drift_factor
		linear_velocity -= right * lateral_speed * (1.0 - drift_grip) * delta * 2.0
	else:
		linear_velocity -= right * lateral_speed * grip_factor * delta * 3.0
	
	if abs(current_speed) > 0.5 and input_direction.x != 0:
		var turn_multiplier = 1.0
		if is_drifting:
			turn_multiplier = 1.8
		var turn_amount = input_direction.x * turn_speed * delta * turn_multiplier
		if current_speed < 0:
			turn_amount = -turn_amount
		rotate_y(-turn_amount)

func _apply_friction(delta):
	linear_velocity.x = lerp(linear_velocity.x, 0.0, friction * delta)
	linear_velocity.z = lerp(linear_velocity.z, 0.0, friction * delta)

@rpc("any_peer", "reliable")
func request_enter(peer_id: int):
	if multiplayer.is_server():
		if not is_occupied:
			is_occupied = true
			driver_id = peer_id
			_sync_driver.rpc(peer_id)

@rpc("any_peer", "reliable")
func request_exit(peer_id: int):
	if multiplayer.is_server():
		if is_occupied and driver_id == peer_id:
			is_occupied = false
			driver_id = 0
			input_direction = Vector2.ZERO
			is_braking = false
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			_sync_driver.rpc(0)

@rpc("any_peer", "unreliable")
func send_input(peer_id: int, direction: Vector2, braking: bool):
	if multiplayer.is_server():
		if driver_id == peer_id:
			input_direction = direction
			is_braking = braking

@rpc("authority", "reliable", "call_local")
func _sync_driver(new_driver_id: int):
	driver_id = new_driver_id
	is_occupied = new_driver_id != 0

func get_seat_global_position() -> Vector3:
	if seat_position:
		return seat_position.global_position
	return global_position + Vector3(0, 0.5, 0)

func get_exit_global_position() -> Vector3:
	if exit_position:
		return exit_position.global_position
	return global_position + global_transform.basis.x * 1.5

func is_cart_occupied() -> bool:
	return driver_id != 0

func set_input(direction: Vector2, braking: bool):
	var peer_id = multiplayer.get_unique_id()
	if multiplayer.is_server():
		if driver_id == peer_id:
			input_direction = direction
			is_braking = braking
	else:
		send_input.rpc_id(1, peer_id, direction, braking)

func _server_enter(peer_id: int):
	if not is_occupied:
		is_occupied = true
		driver_id = peer_id
		_sync_driver.rpc(peer_id)

func _server_exit(peer_id: int):
	if is_occupied and driver_id == peer_id:
		is_occupied = false
		driver_id = 0
		input_direction = Vector2.ZERO
		is_braking = false
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_sync_driver.rpc(0)

func _respawn_cart():
	global_position = spawn_position
	global_rotation = spawn_rotation
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sync_position = spawn_position
	sync_rotation = spawn_rotation
