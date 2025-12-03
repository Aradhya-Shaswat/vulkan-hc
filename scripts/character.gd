extends CharacterBody3D

var speed
const WALK_SPEED = 8.5
const SPRINT_SPEED = 10.0
const JUMP_VELOCITY = 6

const BOB_FREQ = 2.0
const BOB_AMP = 0.09
const TILT_MAX = 0.08
var t_bob = 0.0

const PUSH_FORCE = 1.0

var gravity = 15

var in_cart: bool = false
var current_cart: Node = null
var nearby_cart: Node = null

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var player_mesh = $MeshInstance3D
@onready var multiplayer_sync = $MultiplayerSynchronizer
@onready var cart_hint_label = $CanvasLayer/CartHint
@onready var nametag = $Nametag
var cam_default_pos: Vector3

const PLAYER_COLORS = [
	Color(0.83, 0.78, 1.0),    # Purple (default)
	Color(0.2, 0.8, 0.4),      # Green
	Color(0.9, 0.4, 0.3),      # Red
	Color(0.3, 0.6, 0.9),      # Blue
	Color(0.95, 0.75, 0.2),    # Yellow
	Color(0.95, 0.5, 0.8),     # Pink
	Color(0.4, 0.9, 0.9),      # Cyan
	Color(0.9, 0.6, 0.2),      # Orange
]

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
	
	var player_id = name.to_int()
	var color_index = player_id % PLAYER_COLORS.size()
	var player_color = PLAYER_COLORS[color_index]
	_set_player_color(player_color)
	
	call_deferred("_setup_nametag")
	
	if _is_local_authority():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		camera.current = true
		player_mesh.layers = 1 << 1
		camera.cull_mask &= ~(1 << 1)
		if nametag:
			nametag.visible = false
	else:
		camera.current = false
		player_mesh.layers = 1

func _set_player_color(color: Color):
	if player_mesh and player_mesh.mesh:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		player_mesh.mesh = player_mesh.mesh.duplicate()
		player_mesh.mesh.material = mat

func _setup_nametag():
	if not nametag:
		return
	
	var player_id = name.to_int()
	var main_node = get_parent()
	
	if main_node and main_node.has_node("../") == false:
		if main_node.get("player_list") != null:
			var player_list = main_node.player_list
			if player_list.has(player_id):
				nametag.text = player_list[player_id]
			else:
				nametag.text = "Player " + str(player_id)
		else:
			nametag.text = "Player " + str(player_id)
	else:
		nametag.text = "Player " + str(player_id)

func _unhandled_input(event):
	if not _is_local_authority():
		return
	if GameSettings.is_paused:
		return
	if event is InputEventMouseMotion:
		var sens = GameSettings.sensitivity
		head.rotate_y(-event.relative.x * sens)
		var new_x = camera.rotation.x - event.relative.y * sens
		new_x = clamp(new_x, deg_to_rad(-80), deg_to_rad(90))
		camera.rotation.x = new_x

func _physics_process(delta):
	if _is_local_authority():
		if GameSettings.is_paused:
			velocity.x = 0
			velocity.z = 0
			if not in_cart:
				move_and_slide()
			return
		
		_check_nearby_cart()
		
		if Input.is_action_just_pressed("interact"):
			_toggle_cart()
		
		if in_cart and current_cart:
			_handle_cart_driving()
			global_position = current_cart.get_seat_global_position()
			sync_position = global_position
			sync_rotation = rotation
			sync_head_rotation = head.rotation.y
			return
		
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
				var normal = collision.get_normal()
				if normal.y > 0.7:
					continue
				var push_dir = -normal
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

func _check_nearby_cart():
	nearby_cart = null
	var carts = get_tree().get_nodes_in_group("carts")
	
	for cart in carts:
		var dist = global_position.distance_to(cart.global_position)
		if dist < 3.0 and not cart.is_cart_occupied():
			nearby_cart = cart
			break
	
	if cart_hint_label:
		cart_hint_label.visible = nearby_cart != null and not in_cart

func _toggle_cart():
	if in_cart and current_cart:
		_exit_cart()
	elif nearby_cart:
		_enter_cart(nearby_cart)

func _enter_cart(cart: Node):
	if cart.is_cart_occupied():
		return
	
	current_cart = cart
	in_cart = true
	
	var peer_id = name.to_int()
	if multiplayer.is_server():
		cart._server_enter(peer_id)
	else:
		cart.request_enter.rpc_id(1, peer_id)
	
	player_mesh.visible = false
	$CollisionShape3D.disabled = true

func _exit_cart():
	if not current_cart:
		return
	
	var exit_pos = current_cart.global_position + current_cart.global_transform.basis.x * 2.5 + Vector3(0, 1, 0)
	
	var peer_id = name.to_int()
	if multiplayer.is_server():
		current_cart._server_exit(peer_id)
	else:
		current_cart.request_exit.rpc_id(1, peer_id)
	
	in_cart = false
	current_cart = null
	
	player_mesh.visible = true
	$CollisionShape3D.disabled = false
	global_position = exit_pos

func _handle_cart_driving():
	if not current_cart:
		return
	
	var input_dir = Vector2.ZERO
	input_dir.y = Input.get_axis("up", "down")
	input_dir.x = Input.get_axis("right", "left")
	var brake = Input.is_action_pressed("sprint")
	
	current_cart.set_input(input_dir, brake)
