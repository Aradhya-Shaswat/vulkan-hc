extends RigidBody3D

@export var acceleration: float = 15.0
@export var max_speed: float = 20.0
@export var turn_speed: float = 3.0
@export var brake_force: float = 20.0
@export var friction: float = 2.0

var driver_id: int = 0
var is_occupied: bool = false
var input_direction: Vector2 = Vector2.ZERO
var is_braking: bool = false

@onready var seat_position: Node3D = $SeatPosition
@onready var exit_position: Node3D = $ExitPosition

func _ready():
	add_to_group("carts")

func _physics_process(delta):
	if not multiplayer.is_server():
		return
	
	if is_occupied and driver_id != 0:
		_apply_movement(delta)
	else:
		_apply_friction(delta)

func _apply_movement(delta):
	var forward = -global_transform.basis.z
	var current_speed = linear_velocity.dot(forward)
	
	if is_braking:
		linear_velocity = linear_velocity.lerp(Vector3.ZERO, brake_force * delta)
	else:
		if input_direction.y != 0:
			var target_velocity = forward * input_direction.y * max_speed
			linear_velocity.x = lerp(linear_velocity.x, target_velocity.x, acceleration * delta * 0.1)
			linear_velocity.z = lerp(linear_velocity.z, target_velocity.z, acceleration * delta * 0.1)
		else:
			linear_velocity.x = lerp(linear_velocity.x, 0.0, friction * delta)
			linear_velocity.z = lerp(linear_velocity.z, 0.0, friction * delta)
	
	if abs(current_speed) > 0.5 and input_direction.x != 0:
		var turn_amount = input_direction.x * turn_speed * delta
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
