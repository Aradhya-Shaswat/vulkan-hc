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
@export var downforce: float = 60.0
@export var anti_roll: float = 15.0
@export var jump_force: float = 12.0
@export var coyote_time: float = 0.15

var current_speed: float = 0.0
var current_steering: float = 0.0
var driver_id: int = 0
var is_occupied: bool = false
var input_direction: Vector2 = Vector2.ZERO
var is_braking: bool = false
var is_drifting: bool = false
var throttle_input: float = 0.0
var steering_input: float = 0.0
var coyote_timer: float = 0.0
var was_grounded: bool = false

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

# Wheel animation
var wheel_rotation: float = 0.0
var steering_visual_angle: float = 0.0
@export var wheel_radius: float = 0.35
@export var max_steering_visual_angle: float = 30.0  # degrees

@onready var seat_position: Node3D = $SeatPosition
@onready var exit_position: Node3D = $ExitPosition
@onready var cart_model: Node3D = $"Sketchfab_Scene2/Sketchfab_model"

# Wheel nodes (will be found in _ready)
var front_left_wheel: Node3D = null
var front_right_wheel: Node3D = null
var rear_left_wheel: Node3D = null
var rear_right_wheel: Node3D = null
var steering_wheel: Node3D = null

func _ready():
	add_to_group("carts")
	add_to_group("physics_objects")
	spawn_position = global_position
	spawn_rotation = rotation
	sync_position = global_position
	sync_rotation = rotation
	prev_sync_position = sync_position
	prev_sync_rotation = sync_rotation
	
	# Find wheel nodes in the model
	call_deferred("_find_wheel_nodes")
	_update_freeze_state()

func _find_wheel_nodes():
	if not cart_model:
		return
	
	# Find nodes recursively in the model hierarchy
	# Based on the GLTF structure, wheels are named root.4_gameasset, root.5_gameasset, etc.
	var root_node = cart_model.get_node_or_null("RootNode")
	if root_node:
		# Try to find wheel nodes by name pattern
		for child in root_node.get_children():
			var node_name = child.name
			if "root_4" in node_name or "root.4" in node_name:
				front_left_wheel = child
			elif "root_5" in node_name or "root.5" in node_name:
				front_right_wheel = child
			elif "root_6" in node_name or "root.6" in node_name:
				rear_left_wheel = child
			elif "root_7" in node_name or "root.7" in node_name:
				rear_right_wheel = child
			elif "Steering" in node_name:
				steering_wheel = child

func _animate_wheels(delta: float):
	if not is_occupied:
		return
	
	# Calculate wheel rotation based on speed
	var forward = -global_transform.basis.z
	var forward_speed = linear_velocity.dot(forward)
	var rotation_speed = forward_speed / wheel_radius if wheel_radius > 0 else 0.0
	wheel_rotation += rotation_speed * delta
	
	# Animate steering visual
	var target_steering = current_steering * deg_to_rad(max_steering_visual_angle)
	steering_visual_angle = lerp(steering_visual_angle, target_steering, 10.0 * delta)
	
	# Apply rotation to wheels
	if front_left_wheel:
		front_left_wheel.rotation.x = wheel_rotation
	if front_right_wheel:
		front_right_wheel.rotation.x = wheel_rotation
	if rear_left_wheel:
		rear_left_wheel.rotation.x = wheel_rotation
	if rear_right_wheel:
		rear_right_wheel.rotation.x = wheel_rotation
	
	# Apply steering to steering wheel (rotate around z-axis)
	if steering_wheel:
		steering_wheel.rotation.z = steering_visual_angle * 2.0  # Exaggerate for visual effect

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
		# Update coyote timer for jump
		var grounded = _is_grounded()
		if grounded:
			coyote_timer = coyote_time
			was_grounded = true
		else:
			coyote_timer = max(0, coyote_timer - delta)
			if coyote_timer <= 0:
				was_grounded = false
		
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
	
	# Animate wheels on all clients for visual effect
	_animate_wheels(delta)

func _apply_movement(delta):
	var forward = -global_transform.basis.z
	var right = global_transform.basis.x
	var up = global_transform.basis.y
	
	var forward_speed = linear_velocity.dot(forward)
	var lateral_speed = linear_velocity.dot(right)
	current_speed = forward_speed
	
	var speed_factor = clamp(abs(forward_speed) / max_speed, 0.0, 1.0)
	var downforce_amount = downforce * (1.0 + speed_factor * 2.0)
	apply_central_force(-Vector3.UP * downforce_amount)
	
	angular_velocity.x *= (1.0 - anti_roll * delta)
	angular_velocity.z *= (1.0 - anti_roll * delta)
	
	var current_roll = global_transform.basis.get_euler().z
	var current_pitch = global_transform.basis.get_euler().x
	apply_torque(Vector3(-current_pitch * anti_roll * 5.0, 0, -current_roll * anti_roll * 5.0))
	
	throttle_input = input_direction.y
	steering_input = input_direction.x
	
	current_steering = lerp(current_steering, steering_input, steering_speed * delta)
	
	is_drifting = is_braking and abs(forward_speed) > 5.0
	
	if throttle_input > 0:
		if forward_speed < max_speed:
			var accel = engine_power * delta
			linear_velocity += forward * accel * throttle_input
	elif throttle_input < 0:
		if forward_speed > -max_reverse_speed:
			var accel = reverse_power * delta
			linear_velocity += forward * accel * throttle_input
	
	if is_braking and abs(forward_speed) > 0.5:
		var brake_amount = brake_strength * delta
		var brake_force = min(brake_amount, abs(forward_speed))
		linear_velocity -= forward * sign(forward_speed) * brake_force
	
	if throttle_input == 0 and not is_braking:
		var decel = coast_decel * delta
		if abs(forward_speed) > decel:
			linear_velocity -= forward * sign(forward_speed) * decel
		elif abs(forward_speed) > 0.1:
			linear_velocity -= forward * forward_speed * 0.5 * delta
	
	var grip = wheel_grip
	if is_drifting:
		grip = drift_grip
	elif is_braking:
		grip = handbrake_grip
	
	var lateral_reduction = lateral_speed * grip * delta
	if abs(lateral_reduction) > abs(lateral_speed):
		lateral_reduction = lateral_speed
	linear_velocity -= right * lateral_reduction
	
	if abs(forward_speed) > 0.5:
		var turn_speed_factor = clamp(abs(forward_speed) / 15.0, 0.2, 1.0)
		var turn_amount = current_steering * turn_speed * turn_speed_factor * delta
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
	
	if abs(forward_speed) > 0.5:
		var decel = coast_decel * 0.3 * delta
		linear_velocity -= forward * sign(forward_speed) * decel
	
	var right = global_transform.basis.x
	var lateral_speed = linear_velocity.dot(right)
	linear_velocity -= right * lateral_speed * wheel_grip * 0.5 * delta
	
	angular_velocity.y *= 0.95

func _is_grounded() -> bool:
	var space_state = get_world_3d().direct_space_state
	# Check multiple points like wheels - any wheel touching ground counts
	var check_points = [
		Vector3(0.5, 0, -0.6),  # Front right
		Vector3(-0.5, 0, -0.6), # Front left
		Vector3(0.5, 0, 0.6),   # Rear right
		Vector3(-0.5, 0, 0.6),  # Rear left
		Vector3.ZERO            # Center
	]
	for offset in check_points:
		var start = global_position + global_transform.basis * offset
		var end = start + Vector3(0, -1.2, 0)
		var query = PhysicsRayQueryParameters3D.create(start, end)
		query.exclude = [self]
		query.collision_mask = 1
		var result = space_state.intersect_ray(query)
		if result.size() > 0:
			return true
	return false

func _can_jump() -> bool:
	return coyote_timer > 0 or _is_grounded()

func jump():
	if multiplayer.is_server():
		if _can_jump():
			linear_velocity.y = jump_force
			coyote_timer = 0  # Consume coyote time on jump
	else:
		_request_jump.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_jump():
	if multiplayer.is_server() and is_occupied and _can_jump():
		linear_velocity.y = jump_force
		coyote_timer = 0

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
