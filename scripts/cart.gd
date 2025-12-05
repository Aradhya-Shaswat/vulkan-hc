extends RigidBody3D

@export var engine_power: float = 25.0
@export var max_speed: float = 28.0
@export var reverse_power: float = 15.0
@export var max_reverse_speed: float = 12.0
@export var brake_strength: float = 40.0
@export var turn_speed: float = 3.2
@export var steering_speed: float = 5.0
@export var wheel_grip: float = 8.0
@export var drift_grip: float = 2.0
@export var rolling_resistance: float = 0.02
@export var air_resistance: float = 0.01
@export var coast_decel: float = 3.0
@export var handbrake_grip: float = 1.0

var current_speed: float = 0.0
var current_steering: float = 0.0
var driver_id: int = 0
var is_occupied: bool = false
var input_direction: Vector2 = Vector2.ZERO
var is_braking: bool = false
var is_drifting: bool = false
var throttle_input: float = 0.0
var steering_input: float = 0.0

@export var sync_position: Vector3
@export var sync_rotation: Vector3

var prev_sync_position: Vector3
var prev_sync_rotation: Vector3
var sync_lerp_factor: float = 0.0
var was_server_last_check: bool = false
var spawn_position: Vector3 = Vector3.ZERO
var spawn_rotation: Vector3 = Vector3.ZERO
var has_received_sync: bool = false
const FALL_THRESHOLD: float = -50.0
const FLIP_THRESHOLD: float = 0.5
var flip_timer: float = 0.0
const FLIP_RESPAWN_TIME: float = 2.0

@onready var seat_position: Node3D = $SeatPosition
@onready var exit_position: Node3D = $ExitPosition

func _ready():
	add_to_group("carts")
	add_to_group("physics_objects")
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
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

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
		
		var up_dot = global_transform.basis.y.dot(Vector3.UP)
		if up_dot < FLIP_THRESHOLD:
			flip_timer += delta
			if flip_timer >= FLIP_RESPAWN_TIME:
				_respawn_cart()
		else:
			flip_timer = 0.0
		
		if is_occupied and driver_id != 0:
			_apply_movement(delta)
		else:
			_apply_friction(delta)
		sync_position = global_position
		sync_rotation = rotation
	else:
		if not has_received_sync:
			if sync_position != Vector3.ZERO or sync_rotation != Vector3.ZERO:
				has_received_sync = true
				global_transform.origin = sync_position
				global_rotation = sync_rotation
				prev_sync_position = sync_position
				prev_sync_rotation = sync_rotation
			return
		
		if prev_sync_position != sync_position or prev_sync_rotation != sync_rotation:
			prev_sync_position = sync_position
			prev_sync_rotation = sync_rotation
			sync_lerp_factor = 0.0
		
		sync_lerp_factor = min(sync_lerp_factor + delta * 15.0, 1.0)
		var new_pos = global_position.lerp(sync_position, sync_lerp_factor)
		var new_rot = Vector3(
			lerp_angle(global_rotation.x, sync_rotation.x, sync_lerp_factor),
			lerp_angle(global_rotation.y, sync_rotation.y, sync_lerp_factor),
			lerp_angle(global_rotation.z, sync_rotation.z, sync_lerp_factor)
		)
		global_transform.origin = new_pos
		global_rotation = new_rot

func _apply_movement(delta):
	var forward = -global_transform.basis.z
	var right = global_transform.basis.x
	
	var forward_speed = linear_velocity.dot(forward)
	var lateral_speed = linear_velocity.dot(right)
	current_speed = forward_speed
	
	throttle_input = input_direction.y
	steering_input = input_direction.x
	
	current_steering = lerp(current_steering, steering_input, steering_speed * delta)
	
	is_drifting = is_braking and abs(forward_speed) > 5.0
	
	# Engine force - direct velocity manipulation for reliability
	if throttle_input > 0:
		if forward_speed < max_speed:
			var accel = engine_power * delta
			linear_velocity += forward * accel * throttle_input
	elif throttle_input < 0:
		if forward_speed > -max_reverse_speed:
			var accel = reverse_power * delta
			linear_velocity += forward * accel * throttle_input
	
	# Braking
	if is_braking and abs(forward_speed) > 0.5:
		var brake_amount = brake_strength * delta
		var brake_force = min(brake_amount, abs(forward_speed))
		linear_velocity -= forward * sign(forward_speed) * brake_force
	
	# Natural deceleration when coasting (gentle)
	if throttle_input == 0 and not is_braking:
		var decel = coast_decel * delta
		if abs(forward_speed) > decel:
			linear_velocity -= forward * sign(forward_speed) * decel
		elif abs(forward_speed) > 0.1:
			# Very slow - reduce more gently
			linear_velocity -= forward * forward_speed * 0.5 * delta
	
	# Lateral grip - prevent sliding sideways
	var grip = wheel_grip
	if is_drifting:
		grip = drift_grip
	elif is_braking:
		grip = handbrake_grip
	
	var lateral_reduction = lateral_speed * grip * delta
	if abs(lateral_reduction) > abs(lateral_speed):
		lateral_reduction = lateral_speed
	linear_velocity -= right * lateral_reduction
	
	# Steering
	if abs(forward_speed) > 0.5:
		var speed_factor = clamp(abs(forward_speed) / 15.0, 0.2, 1.0)
		var turn_amount = current_steering * turn_speed * speed_factor * delta
		if forward_speed < 0:
			turn_amount = -turn_amount
		if is_drifting:
			turn_amount *= 1.5
			angular_velocity.y += current_steering * 3.0 * delta
		rotate_y(-turn_amount)
	
	angular_velocity.y *= 0.92

func _apply_friction(delta):
	var forward = -global_transform.basis.z
	var forward_speed = linear_velocity.dot(forward)
	
	# Gentle coast when unoccupied
	if abs(forward_speed) > 0.5:
		var decel = coast_decel * 0.3 * delta
		linear_velocity -= forward * sign(forward_speed) * decel
	
	# Lateral grip
	var right = global_transform.basis.x
	var lateral_speed = linear_velocity.dot(right)
	linear_velocity -= right * lateral_speed * wheel_grip * 0.5 * delta
	
	angular_velocity.y *= 0.95

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
		current_steering = 0.0
		throttle_input = 0.0
		steering_input = 0.0
		_sync_driver.rpc(0)
		
func _respawn_cart():
	global_position = spawn_position
	global_rotation = spawn_rotation
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sync_position = spawn_position
	sync_rotation = spawn_rotation
	current_speed = 0.0
	flip_timer = 0.0

func get_speed() -> float:
	return current_speed

func get_speed_ratio() -> float:
	return clamp(abs(current_speed) / max_speed, 0.0, 1.0)

@rpc("authority", "reliable", "call_local")
func apply_push(force: Vector3):
	if multiplayer.is_server():
		linear_velocity += force
		angular_velocity += Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2))
