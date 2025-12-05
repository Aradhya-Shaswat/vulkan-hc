extends CharacterBody3D

signal cart_entered()
signal cart_exited()

var speed
var WALK_SPEED = 8.5
var SPRINT_SPEED = 10.0
const JUMP_VELOCITY = 6

const BOB_FREQ = 2.0
const BOB_AMP = 0.09
const TILT_MAX = 0.08
var t_bob = 0.0

const PUSH_FORCE = 1.0

var gravity = 15
const FALL_THRESHOLD = -50.0
var spawn_position: Vector3 = Vector3.ZERO

const MAX_HEALTH = 100.0
var health: float = MAX_HEALTH
@export var sync_health: float = MAX_HEALTH
var is_dead: bool = false
var respawn_timer: float = 0.0
const RESPAWN_DELAY = 3.0
var health_regen_timer: float = 0.0
const HEALTH_REGEN_DELAY = 5.0
const HEALTH_REGEN_RATE = 10.0
var last_damage_time: float = 0.0
var last_attacker_id: int = 0

var in_cart: bool = false
var current_cart: Node = null
var nearby_cart: Node = null
var looking_behind: bool = false
var cart_look_timer: float = 0.0
const CART_LOOK_TIMEOUT: float = 1.5
const CART_LOOK_LIMIT: float = PI / 2.0

var noclip_enabled: bool = false
const NOCLIP_SPEED_MULT = 2.0

var is_crouching: bool = false
const CROUCH_SPEED = 4.0
const STAND_HEIGHT = 1.0
const CROUCH_HEIGHT = 0.5
const CROUCH_TRANSITION_SPEED = 10.0
@export var sync_crouch: bool = false
@export var sync_in_cart: bool = false

var footstep_timer: float = 0.0
const FOOTSTEP_INTERVAL = 0.4

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var player_mesh = $MeshInstance3D
@onready var multiplayer_sync = $MultiplayerSynchronizer
@onready var cart_hint_label = $CanvasLayer/CartHint
@onready var nametag = $Nametag
@onready var health_bar_3d = $HealthBar3D
@onready var health_bar_ui = $CanvasLayer/HealthBarUI
@onready var health_label = $CanvasLayer/HealthBarUI/HealthLabel
@onready var death_overlay = $CanvasLayer/DeathOverlay
var cam_default_pos: Vector3

const PLAYER_COLORS = [
	Color(0.83, 0.78, 1.0),
	Color(0.2, 0.8, 0.4),
	Color(0.9, 0.4, 0.3),
	Color(0.3, 0.6, 0.9),
	Color(0.95, 0.75, 0.2),
	Color(0.95, 0.5, 0.8),
	Color(0.4, 0.9, 0.9),
	Color(0.9, 0.6, 0.2),
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
	add_to_group("players")
	cam_default_pos = camera.transform.origin
	spawn_position = global_position
	
	health = MAX_HEALTH
	sync_health = MAX_HEALTH
	
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
		if health_bar_3d:
			health_bar_3d.visible = false
		if health_bar_ui:
			health_bar_ui.visible = false
	else:
		camera.current = false
		player_mesh.layers = 1
		if health_bar_ui:
			health_bar_ui.visible = false
		if health_bar_3d:
			health_bar_3d.visible = true
			_update_health_bar_3d()

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

func show_health_ui():
	if _is_local_authority() and health_bar_ui:
		health_bar_ui.visible = true
		_update_health_ui()

func _update_health_ui():
	if not health_bar_ui:
		return
	var health_bar = health_bar_ui.get_node_or_null("HealthBar")
	if health_bar:
		health_bar.value = health
	if health_label:
		health_label.text = str(int(health)) + "/" + str(int(MAX_HEALTH))

func _update_health_bar_3d():
	if not health_bar_3d:
		return
	var health_percent = health / MAX_HEALTH
	
	var mat = health_bar_3d.get_surface_override_material(0)
	if mat:
		if health_percent > 0.6:
			mat.albedo_color = Color(0.2, 0.9, 0.2)
		elif health_percent > 0.3:
			mat.albedo_color = Color(0.9, 0.9, 0.2)
		else:
			mat.albedo_color = Color(0.9, 0.2, 0.2)
	
	if health_bar_3d.mesh:
		var box_mesh = health_bar_3d.mesh as BoxMesh
		if box_mesh:
			box_mesh.size.x = 0.8 * max(health_percent, 0.01)

func _process(_delta):
	if health_bar_3d and health_bar_3d.visible:
		var cam = get_viewport().get_camera_3d()
		if cam:
			health_bar_3d.look_at(health_bar_3d.global_position + cam.global_transform.basis.z, Vector3.UP)
			health_bar_3d.global_position = global_position + Vector3(0, 1.55, 0)

func take_damage(amount: float, from_peer_id: int = 0):
	if is_dead:
		return
	
	health -= amount
	health = max(health, 0)
	sync_health = health
	last_damage_time = Time.get_ticks_msec() / 1000.0
	if from_peer_id != 0:
		last_attacker_id = from_peer_id
	
	if _is_local_authority():
		SoundManager.play_hit()
	
	_update_health_ui()
	_update_health_bar_3d()
	
	if _is_local_authority():
		_sync_health_update.rpc(health)
	
	if health <= 0:
		_die()

@rpc("any_peer", "reliable", "call_remote")
func apply_damage_from_server(amount: float, from_peer_id: int):
	if multiplayer.get_remote_sender_id() != 1:
		return
	take_damage(amount, from_peer_id)

@rpc("any_peer", "reliable", "call_local")
func request_damage(amount: float, from_peer_id: int):
	if not multiplayer.is_server():
		return
	var target_id = name.to_int()
	if target_id == 1:
		take_damage(amount, from_peer_id)
	else:
		apply_damage_from_server.rpc_id(target_id, amount, from_peer_id)

@rpc("authority", "reliable", "call_remote")
func _sync_health_update(new_health: float):
	health = new_health
	sync_health = new_health
	_update_health_ui()
	_update_health_bar_3d()

func _die():
	is_dead = true
	respawn_timer = RESPAWN_DELAY
	call_deferred("_disable_collision_shape")
	
	if multiplayer.is_server():
		_sync_death_state.rpc(true)
		if last_attacker_id != 0:
			var main = get_parent()
			if main and main.has_method("register_kill"):
				main.register_kill(last_attacker_id)
	
	if _is_local_authority():
		player_mesh.visible = false
		SoundManager.play_death()
		velocity = Vector3.ZERO
		if noclip_enabled:
			call_deferred("set_noclip", false)
			if Console:
				Console.disable_noclip()
		if death_overlay:
			death_overlay.visible = true

func _disable_collision_shape():
	$CollisionShape3D.disabled = true

func _respawn_after_death():
	is_dead = false
	health = MAX_HEALTH
	sync_health = MAX_HEALTH
	last_attacker_id = 0
	player_mesh.visible = true
	if death_overlay:
		death_overlay.visible = false
	respawn()
	call_deferred("_enable_collision_shape")
	_update_health_ui()
	_update_health_bar_3d()
	_sync_health_update.rpc(health)
	
	if multiplayer.is_server():
		_sync_death_state.rpc(false)

func _enable_collision_shape():
	$CollisionShape3D.disabled = false

func _unhandled_input(event):
	if not _is_local_authority():
		return
	if GameSettings.is_paused:
		return
	if Console.is_open:
		return
	if is_dead:
		return
	
	if event is InputEventKey:
		if event.keycode == KEY_ALT:
			looking_behind = event.pressed
	
	if event is InputEventMouseMotion:
		var sens = GameSettings.sensitivity
		var rotation_amount = -event.relative.x * sens
		
		if in_cart and current_cart and not looking_behind:
			cart_look_timer = 0.0
			var cart_forward_y = current_cart.global_rotation.y
			var current_head_y = head.global_rotation.y
			var current_diff = angle_difference(current_head_y, cart_forward_y)
			var new_head_y = current_head_y + rotation_amount
			var new_diff = angle_difference(new_head_y, cart_forward_y)
			
			if abs(new_diff) > CART_LOOK_LIMIT:
				if abs(current_diff) >= CART_LOOK_LIMIT - 0.01:
					rotation_amount = 0.0
				else:
					var max_rotation = CART_LOOK_LIMIT - abs(current_diff)
					rotation_amount = sign(rotation_amount) * min(abs(rotation_amount), max_rotation)
					if sign(new_diff) != sign(current_diff) and abs(current_diff) > 0.1:
						rotation_amount = 0.0
		
		head.rotate_y(rotation_amount)
		var new_x = camera.rotation.x - event.relative.y * sens
		new_x = clamp(new_x, deg_to_rad(-80), deg_to_rad(90))
		camera.rotation.x = new_x

func _physics_process(delta):
	if _is_local_authority():
		if is_dead:
			respawn_timer -= delta
			if respawn_timer <= 0:
				_respawn_after_death()
			return
		
		var current_time = Time.get_ticks_msec() / 1000.0
		
		if global_position.y < FALL_THRESHOLD:
			respawn()
			return
		
		if GameSettings.is_paused or Console.is_open:
			velocity.x = 0
			velocity.z = 0
			if not is_on_floor() and not in_cart:
				velocity.y -= gravity * delta
			if not in_cart:
				move_and_slide()
			return
		
		_check_nearby_cart()
		
		if Input.is_action_just_pressed("interact"):
			_toggle_cart()
		
		if in_cart and current_cart:
			_handle_cart_driving(delta)
			global_position = current_cart.get_seat_global_position()
			cart_look_timer += delta
			
			if looking_behind:
				var behind_y = current_cart.global_rotation.y + PI
				head.global_rotation.y = lerp_angle(head.global_rotation.y, behind_y, delta * 10.0)
				cart_look_timer = 0.0
			elif cart_look_timer >= CART_LOOK_TIMEOUT:
				var target_head_y = current_cart.global_rotation.y
				head.global_rotation.y = lerp_angle(head.global_rotation.y, target_head_y, delta * 5.0)
				camera.rotation.x = lerp(camera.rotation.x, 0.0, delta * 5.0)
			
			sync_position = global_position
			sync_rotation = rotation
			sync_head_rotation = head.rotation.y
			sync_crouch = is_crouching
			return
		
		if noclip_enabled:
			_handle_noclip_movement(delta)
			return
		
		if not is_on_floor():
			velocity.y -= gravity * delta

		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
			
		if Input.is_action_just_pressed('quit'):
			$'../'.exit_game(name.to_int())
			get_tree().quit()
		
		var wants_crouch = Input.is_action_pressed("crouch")
		if wants_crouch and not is_crouching:
			is_crouching = true
			sync_crouch = true
		elif not wants_crouch and is_crouching:
			is_crouching = false
			sync_crouch = false
		
		_update_crouch_visual(delta)
			
		if Input.is_action_pressed("sprint") and not is_crouching:
			speed = SPRINT_SPEED
		elif is_crouching:
			speed = CROUCH_SPEED
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
			footstep_timer += delta
			var step_interval = FOOTSTEP_INTERVAL if speed == WALK_SPEED else FOOTSTEP_INTERVAL * 0.7
			if footstep_timer >= step_interval:
				footstep_timer = 0.0
				SoundManager.play_footstep()
		else:
			target_pos = cam_default_pos
			t_bob = lerp(t_bob, 0.0, clamp(delta * 2.0, 0, 1))
			footstep_timer = 0.0

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
		sync_crouch = is_crouching
		
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
		
		is_crouching = sync_crouch
		_update_crouch_visual(delta)
		
		if $CollisionShape3D.disabled != sync_in_cart:
			$CollisionShape3D.disabled = sync_in_cart
			player_mesh.visible = not sync_in_cart
		
		if health != sync_health:
			health = sync_health
			_update_health_bar_3d()

func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * (BOB_FREQ / 2.0)) * (BOB_AMP * 0.3)
	return pos

func _update_crouch_visual(delta: float):
	var target_scale_y = CROUCH_HEIGHT if is_crouching else STAND_HEIGHT
	var current_scale = player_mesh.scale.y
	player_mesh.scale.y = lerp(current_scale, target_scale_y, delta * CROUCH_TRANSITION_SPEED)
	
	var target_y = -0.35 if is_crouching else 0.0
	player_mesh.position.y = lerp(player_mesh.position.y, target_y, delta * CROUCH_TRANSITION_SPEED)
	
	var target_head_y = 0.0 if is_crouching else 0.4069364
	head.position.y = lerp(head.position.y, target_head_y, delta * CROUCH_TRANSITION_SPEED)

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
	
	SoundManager.play_cart_enter()
	SoundManager.start_cart_loop()
	current_cart = cart
	in_cart = true
	
	var peer_id = name.to_int()
	if multiplayer.is_server():
		cart._server_enter(peer_id)
	else:
		cart.request_enter.rpc_id(1, peer_id)
	
	sync_in_cart = true
	player_mesh.visible = false
	$CollisionShape3D.disabled = true
	_sync_collision_state.rpc(true)
	cart_entered.emit()

func _exit_cart():
	if not current_cart:
		return
	
	SoundManager.play_cart_exit()
	SoundManager.stop_cart_loop()
	var exit_pos = _find_safe_exit_position()
	
	var peer_id = name.to_int()
	if multiplayer.is_server():
		current_cart._server_exit(peer_id)
	else:
		current_cart.request_exit.rpc_id(1, peer_id)
	
	in_cart = false
	current_cart = null
	sync_in_cart = false
	
	player_mesh.visible = true
	$CollisionShape3D.disabled = false
	_sync_collision_state.rpc(false)
	global_position = exit_pos
	cart_exited.emit()

func _find_safe_exit_position() -> Vector3:
	var cart_pos = current_cart.global_position
	var cart_basis = current_cart.global_transform.basis
	var space_state = get_world_3d().direct_space_state
	
	var exit_directions = [
		cart_basis.x * 2.5,
		-cart_basis.x * 2.5,
		cart_basis.z * 2.5,
		-cart_basis.z * 2.5,
		cart_basis.x * 1.5,
		-cart_basis.x * 1.5,
	]
	
	for dir in exit_directions:
		var test_pos = cart_pos + dir + Vector3(0, 1, 0)
		var query = PhysicsRayQueryParameters3D.create(cart_pos + Vector3(0, 1, 0), test_pos)
		query.exclude = [self, current_cart]
		var result = space_state.intersect_ray(query)
		
		if not result:
			var down_query = PhysicsRayQueryParameters3D.create(test_pos, test_pos - Vector3(0, 3, 0))
			down_query.exclude = [self, current_cart]
			var ground_result = space_state.intersect_ray(down_query)
			if ground_result:
				return ground_result.position + Vector3(0, 1, 0)
			return test_pos
	
	return cart_pos + Vector3(0, 2, 0)

func _handle_cart_driving(delta):
	if not current_cart:
		return
	
	var input_dir = Vector2.ZERO
	input_dir.y = Input.get_axis("down", "up")
	input_dir.x = Input.get_axis("left", "right")
	var brake = Input.is_action_pressed("sprint")
	
	current_cart.set_input(input_dir, brake)

func _handle_noclip_movement(delta: float):
	var fly_speed = WALK_SPEED * NOCLIP_SPEED_MULT
	if Input.is_action_pressed("sprint"):
		fly_speed = SPRINT_SPEED * NOCLIP_SPEED_MULT * 1.5
	
	var input_dir = Input.get_vector("left", "right", "up", "down")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var vertical = 0.0
	if Input.is_action_pressed("jump"):
		vertical = 1.0
	elif Input.is_action_pressed("crouch"):
		vertical = -1.0
	
	velocity.x = direction.x * fly_speed
	velocity.z = direction.z * fly_speed
	velocity.y = vertical * fly_speed
	
	global_position += velocity * delta
	
	sync_position = global_position
	sync_rotation = rotation
	sync_head_rotation = head.rotation.y
	sync_crouch = is_crouching

func set_noclip(enabled: bool):
	noclip_enabled = enabled
	velocity = Vector3.ZERO
	if has_node("CollisionShape3D"):
		$CollisionShape3D.disabled = enabled

func respawn():
	if in_cart and current_cart:
		_exit_cart()
	
	if noclip_enabled:
		set_noclip(false)
		if Console:
			Console.disable_noclip()
	
	global_position = spawn_position
	velocity = Vector3.ZERO
	sync_position = spawn_position
	head.rotation.y = 0
	camera.rotation.x = 0
	
	health = MAX_HEALTH
	sync_health = MAX_HEALTH
	is_dead = false
	_update_health_ui()
	_update_health_bar_3d()

func apply_explosion_force(force: Vector3):
	velocity += force
	if is_on_floor():
		velocity.y = max(velocity.y, force.y * 0.8)

func apply_launch_force(force: Vector3):
	velocity = force
	SoundManager.play_launch()

@rpc("authority", "reliable", "call_remote")
func _sync_death_state(dead: bool):
	is_dead = dead
	if dead:
		_show_dead_body()
	else:
		_show_alive_body()

func _show_dead_body():
	if _is_local_authority():
		return
	player_mesh.visible = true
	if player_mesh:
		player_mesh.rotation.x = -PI / 2
		player_mesh.rotation.z = randf_range(-0.3, 0.3)
		player_mesh.position.y = 0.3
		player_mesh.scale.y = STAND_HEIGHT

func _show_alive_body():
	player_mesh.visible = true
	if player_mesh:
		player_mesh.rotation.x = 0
		player_mesh.rotation.z = 0

@rpc("any_peer", "reliable", "call_remote")
func _sync_collision_state(in_cart_state: bool):
	$CollisionShape3D.disabled = in_cart_state
	player_mesh.visible = not in_cart_state
