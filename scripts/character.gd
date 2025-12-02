extends CharacterBody3D

var speed
const WALK_SPEED = 6.5
const SPRINT_SPEED = 8.0
const JUMP_VELOCITY = 6
const SENSITIVITY = 0.005

const BOB_FREQ = 2.0
const BOB_AMP = 0.09
const TILT_MAX = 0.08
var t_bob = 0.0

const PUSH_FORCE = 1.0

var gravity = 15

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var player_mesh = $MeshInstance3D
@onready var multiplayer_sync = $MultiplayerSynchronizer
var cam_default_pos: Vector3

@export var sync_position: Vector3
@export var sync_rotation: Vector3
@export var sync_head_rotation: float
	
func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _is_local_authority() -> bool:
	if multiplayer.multiplayer_peer == null:
		return true
	if not multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return true
	return is_multiplayer_authority()

func _ready():
	cam_default_pos = camera.transform.origin
	
	multiplayer_sync.set_multiplayer_authority(name.to_int())
	
	if _is_local_authority():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		camera.current = true
		player_mesh.layers = 1 << 1
		camera.cull_mask &= ~(1 << 1)
	else:
		camera.current = false
		player_mesh.layers = 1

func _unhandled_input(event):
	if not _is_local_authority():
		return
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		var new_x = camera.rotation.x - event.relative.y * SENSITIVITY
		new_x = clamp(new_x, deg_to_rad(-80), deg_to_rad(90))
		camera.rotation.x = new_x

func _physics_process(delta):
	if _is_local_authority():
		if not is_on_floor():
			velocity.y -= gravity * delta

		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
			
		if Input.is_action_just_pressed('quit'):
			$'../'.exit_game(name.to_int())
			get_tree().quit()
			
		if Input.is_action_pressed("sprint"):
			speed = SPRINT_SPEED
		else:
			speed = WALK_SPEED

		var input_dir = Input.get_vector("left", "right", "up", "down")
		var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

		if is_on_floor():
			if direction:
				velocity.x = direction.x * speed
				velocity.z = direction.z * speed
			else:
				velocity.x = 0.0
				velocity.z = 0.0
		else:
			velocity.x = lerp(velocity.x, direction.x * speed, delta * 2.0)
			velocity.z = lerp(velocity.z, direction.z * speed, delta * 2.0)

		var horiz_speed = Vector2(velocity.x, velocity.z).length()
		var target_pos: Vector3

		if is_on_floor() and horiz_speed > 0.01:
			t_bob += delta * horiz_speed
			target_pos = cam_default_pos + _headbob(t_bob)
		else:
			target_pos = cam_default_pos
			t_bob = lerp(t_bob, 0.0, clamp(delta * 2.0, 0, 1))

		var right_dir = head.transform.basis.x.normalized()
		var lateral_speed = right_dir.dot(Vector3(velocity.x, 0, velocity.z))
		var max_ref_speed = SPRINT_SPEED
		var lateral_factor = 0.0
		if max_ref_speed > 0.0:
			lateral_factor = clamp(lateral_speed / max_ref_speed, -1.0, 1.0)

		lateral_factor = -lateral_factor

		var target_roll = lateral_factor * TILT_MAX
		camera.rotation.z = lerp(camera.rotation.z, target_roll, clamp(delta * 8.0, 0, 1))

		camera.transform.origin = camera.transform.origin.lerp(target_pos, clamp(delta * 8.0, 0, 1))

		move_and_slide()
		
		sync_position = global_position
		sync_rotation = rotation
		sync_head_rotation = head.rotation.y
		
		for i in range(get_slide_collision_count()):
			var collision = get_slide_collision(i)
			var body = collision.get_collider()
			
			if body is RigidBody3D and body.has_method("apply_push"):
				var push_dir = -collision.get_normal()
				push_dir.y = 0
				if push_dir.length() > 0.01:
					push_dir = push_dir.normalized()
					var strength = PUSH_FORCE / max(body.mass, 0.1)
					body.apply_push.rpc(push_dir * strength)
	else:
		global_position = global_position.lerp(sync_position, delta * 15.0)
		rotation = rotation.lerp(sync_rotation, delta * 15.0)
		head.rotation.y = lerp_angle(head.rotation.y, sync_head_rotation, delta * 15.0)

func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * (BOB_FREQ / 2.0)) * (BOB_AMP * 0.3)
	return pos
	
