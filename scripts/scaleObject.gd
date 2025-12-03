extends Camera3D

@export var ray_length: float = 12.0
@export var hold_distance: float = 3.0
@export var max_drag_distance: float = 8.0
@export var pull_strength: float = 18.0
@export var scale_step := 1.1
@export var highlight_material: Material
@export var min_scale: float = 0.5
@export var max_scale: float = 2.0
@export var cooldown: float = 0.12
@export var player_node_path: NodePath
@export var max_impact_velocity: float = 8.0
@export var held_mass_multiplier: float = 0.3
@export var surface_offset: float = 0.15
@export var throw_min_power: float = 5.0
@export var throw_max_power: float = 30.0
@export var throw_charge_time: float = 1.5
@export var power_indicator_path: NodePath
@export var default_fov: float = 75.0
@export var zoom_fov: float = 30.0
@export var zoom_speed: float = 10.0

var hovered: Node3D = null
var previous: Node3D = null
var held: Node3D = null
var is_charging_throw: bool = false
var throw_charge: float = 0.0
var throw_target: Node3D = null
var is_zooming: bool = false

@onready var power_indicator: Control = null
var can_resize := true
var held_rot := 0.0
var held_rot_x := 0.0
var wheel_delta := 0.0
var held_prev_mass := 1.0
var last_frame_pos := Vector3.ZERO
var last_frame_dt := 0.0
var held_original_scale := Vector3.ONE
var object_scales: Dictionary = {}
var held_aabb_half_extents := Vector3.ZERO
var velocity_buffer: Array = []
var buffer_size: int = 5

@onready var player_node: Node = null

func _is_local_authority() -> bool:
	if not player_node:
		return true
	if player_node.has_method("_is_local_authority"):
		return player_node._is_local_authority()
	if multiplayer.multiplayer_peer == null:
		return true
	if not multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return true
	return player_node.is_multiplayer_authority()

func _ready():
	if player_node_path != NodePath("") and has_node(player_node_path):
		player_node = get_node(player_node_path)
	else:
		var current = get_parent()
		while current:
			if current is CharacterBody3D or current.name == "player":
				player_node = current
				break
			current = current.get_parent()
	if power_indicator_path != NodePath("") and has_node(power_indicator_path):
		power_indicator = get_node(power_indicator_path)
		power_indicator.visible = false
	#print("scaleObject ready, player_node: ", player_node, " is_local: ", _is_local_authority())
	set_process_input(true)

func _process(delta):
	if not _is_local_authority():
		return
	_update_hover()
	_handle_resize()
	_update_held_motion(delta)
	_update_throw_charge(delta)
	_update_zoom(delta)
	if held and wheel_delta != 0.0:
		if Input.is_key_pressed(KEY_CTRL):
			held_rot_x += wheel_delta * 0.2
		else:
			held_rot += wheel_delta * 0.2
		wheel_delta = 0.0
	elif not held:
		wheel_delta = 0.0

func _unhandled_input(event):
	if not _is_local_authority():
		#print("Not local authority, skipping input")
		return
	if event is InputEventMouseButton:
		#print("Mouse button event: ", event.button_index, " pressed: ", event.pressed)
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed: wheel_delta = 1.0
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed: wheel_delta = -1.0
			MOUSE_BUTTON_LEFT:
				if event.pressed: _try_start_hold()
				else: _release_hold()
			MOUSE_BUTTON_RIGHT:
				if event.pressed: _start_throw_charge()
				else: _execute_throw()
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_glue_object()
	if event is InputEventKey and event.keycode == KEY_C:
		is_zooming = event.pressed

func _is_player_grounded() -> bool:
	if player_node and player_node is CharacterBody3D:
		return player_node.is_on_floor()
	return true

func _get_exclusion_rids() -> Array[RID]:
	var excl: Array[RID] = []
	if player_node and player_node is CollisionObject3D:
		excl.append(player_node.get_rid())
		for child in player_node.get_children():
			if child is CollisionObject3D:
				excl.append(child.get_rid())
	return excl

func _is_static_surface(node: Node) -> bool:
	if node == null:
		return false
	if node.name == "ground" or node.is_in_group("ground"):
		return true
	if node.is_in_group("walls"):
		return true
	if node is StaticBody3D:
		var current = node
		while current:
			if current.name == "walls" or current.is_in_group("walls") or current.name == "ground" or current.is_in_group("ground"):
				return true
			current = current.get_parent()
		return true
	return false

func _update_hover():
	if held or not _is_player_grounded():
		if previous:
			_clear_highlight(previous)
		if hovered:
			_clear_highlight(hovered)
		hovered = null
		previous = null
		return
	
	var center = get_viewport().get_visible_rect().size * 0.5
	var origin = project_ray_origin(center)
	var dir = project_ray_normal(center)
	var params = PhysicsRayQueryParameters3D.create(origin, origin + dir * ray_length)
	params.exclude = _get_exclusion_rids()
	params.collide_with_bodies = true
	
	var res = get_world_3d().direct_space_state.intersect_ray(params)
	hovered = null
	
	if res:
		var c = res.collider
		if not _is_static_surface(c) and not _is_part_of_player(c):
			var root = _get_interactable_root(c)
			if root and not _is_static_surface(root) and not _is_part_of_player(root) and not _is_player_standing_on(root):
				hovered = root
	
	if hovered != previous:
		_clear_highlight(previous)
		_apply_highlight(hovered)
		previous = hovered

func _is_player_standing_on(obj: Node3D) -> bool:
	if not player_node or not player_node is CharacterBody3D:
		return false
	if not player_node.is_on_floor():
		return false
	var player_body = player_node as CharacterBody3D
	for i in range(player_body.get_slide_collision_count()):
		var collision = player_body.get_slide_collision(i)
		var collider = collision.get_collider()
		if collider == obj:
			return true
		var root = _get_interactable_root(collider)
		if root == obj:
			return true
	return false

func _try_start_hold():
	if not hovered or not _is_player_grounded():
		return
	if _is_player_standing_on(hovered):
		return
	_clear_highlight(hovered)
	held = hovered
	hovered = null
	previous = null
	var euler = held.global_transform.basis.get_euler()
	held_rot = euler.y
	held_rot_x = euler.x
	held_original_scale = held.scale
	last_frame_pos = held.global_transform.origin
	last_frame_dt = 0.0
	velocity_buffer.clear()
	held_aabb_half_extents = _get_object_half_extents(held)
	
	if held is RigidBody3D:
		held_prev_mass = held.mass
		held.mass *= held_mass_multiplier
		
		if held.has_method("request_hold") and _is_multiplayer_active():
			var my_id = held.multiplayer.get_unique_id()
			held.request_hold.rpc(my_id)
		else:
			held.freeze = true
			held.linear_velocity = Vector3.ZERO
			held.angular_velocity = Vector3.ZERO

func _release_hold():
	if not held:
		return
	if held is RigidBody3D:
		var velocity = _get_smoothed_velocity()
		if velocity.length() > max_impact_velocity:
			velocity = velocity.normalized() * max_impact_velocity
		held.mass = held_prev_mass
		
		if held.has_method("request_release") and _is_multiplayer_active():
			var my_id = held.multiplayer.get_unique_id()
			held.request_release.rpc(my_id, velocity)
		else:
			held.freeze = false
			held.sleeping = false
			held.linear_velocity = velocity
			held.angular_velocity = Vector3.ZERO
			if velocity.length() < 0.1:
				held.apply_central_impulse(Vector3(0, -0.05, 0))
	held = null
	last_frame_dt = 0.0
	velocity_buffer.clear()

func _glue_object():
	var target = held if held else hovered
	if not target:
		return
	if not target is RigidBody3D:
		return
	
	if held:
		held.mass = held_prev_mass
		held = null
		last_frame_dt = 0.0
		velocity_buffer.clear()
	
	target.freeze = true
	target.linear_velocity = Vector3.ZERO
	target.angular_velocity = Vector3.ZERO
	
	if target.has_method("request_glue") and _is_multiplayer_active():
		target.request_glue.rpc()

func _start_throw_charge():
	var target = held if held else hovered
	if not target or not target is RigidBody3D:
		return
	if not held and _is_player_standing_on(target):
		return
	is_charging_throw = true
	throw_charge = 0.0
	throw_target = target
	#print("Started charging throw on: ", throw_target.name)
	if power_indicator:
		power_indicator.visible = true
		_update_power_indicator(0.0)

func _update_throw_charge(delta):
	if not is_charging_throw:
		return
	if not throw_target or not is_instance_valid(throw_target):
		_cancel_throw()
		return
	throw_charge = min(throw_charge + delta / throw_charge_time, 1.0)
	if power_indicator:
		_update_power_indicator(throw_charge)

func _execute_throw():
	if not is_charging_throw:
		return
	#print("Executing throw with power: ", throw_charge)
	if throw_target and is_instance_valid(throw_target) and throw_target is RigidBody3D:
		var cam_forward = -global_transform.basis.z
		var power = lerp(throw_min_power, throw_max_power, throw_charge)
		var throw_velocity = cam_forward * power
		
		if throw_target == held:
			held.mass = held_prev_mass
			held = null
			velocity_buffer.clear()
		
		if throw_target.has_method("request_throw") and _is_multiplayer_active():
			throw_target.request_throw.rpc(throw_velocity)
		else:
			throw_target.freeze = false
			throw_target.sleeping = false
			throw_target.linear_velocity = throw_velocity
			throw_target.angular_velocity = Vector3.ZERO
	_cancel_throw()

func _cancel_throw():
	is_charging_throw = false
	throw_charge = 0.0
	throw_target = null
	if power_indicator:
		power_indicator.visible = false

func _update_power_indicator(power: float):
	if power_indicator and power_indicator.has_method("set_power"):
		power_indicator.set_power(power)

func _update_zoom(delta):
	var target_fov = zoom_fov if is_zooming else default_fov
	fov = lerp(fov, target_fov, delta * zoom_speed)

func _get_smoothed_velocity() -> Vector3:
	if velocity_buffer.is_empty():
		return Vector3.ZERO
	var sum = Vector3.ZERO
	for v in velocity_buffer:
		sum += v
	return sum / velocity_buffer.size()

func _is_multiplayer_active() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _get_object_half_extents(obj: Node3D) -> Vector3:
	var mesh = _find_mesh(obj)
	if mesh and mesh.mesh:
		var aabb = mesh.mesh.get_aabb()
		return aabb.size * 0.5 * mesh.global_transform.basis.get_scale()
	var shape = _find_collision_shape(obj)
	if shape and shape.shape:
		if shape.shape is BoxShape3D:
			return shape.shape.size * 0.5 * shape.global_transform.basis.get_scale()
		elif shape.shape is SphereShape3D:
			var r = shape.shape.radius
			return Vector3(r, r, r)
		elif shape.shape is CapsuleShape3D:
			var r = shape.shape.radius
			var h = shape.shape.height * 0.5
			return Vector3(r, h, r)
	return Vector3(0.3, 0.3, 0.3)

func _update_held_motion(delta):
	if not held:
		return
	
	var cam_pos = global_transform.origin
	var cam_forward = -global_transform.basis.z
	var cam_right = global_transform.basis.x
	var current_pos = held.global_transform.origin
	var player_pos = player_node.global_transform.origin if player_node else cam_pos
	var space_state = get_world_3d().direct_space_state
	
	if current_pos.distance_to(player_pos) > max_drag_distance + 2.0:
		_release_hold()
		return

	var excl: Array[RID] = [held.get_rid()]
	var player_excl = _get_exclusion_rids()
	for rid in player_excl:
		excl.append(rid)
	
	var horizontal_forward = Vector3(cam_forward.x, 0, cam_forward.z).normalized()
	if horizontal_forward.length() < 0.1:
		horizontal_forward = Vector3(cam_right.x, 0, cam_right.z).normalized().rotated(Vector3.UP, -PI/2)
	
	var target_pos = player_pos + horizontal_forward * hold_distance
	target_pos.y = cam_pos.y + cam_forward.y * hold_distance
	
	var ground_result = _check_ground_below(space_state, target_pos, excl)
	var ground_y = player_pos.y - 1.0 + held_aabb_half_extents.y + surface_offset
	if ground_result.hit:
		ground_y = ground_result.position.y + held_aabb_half_extents.y + surface_offset
	
	if target_pos.y < ground_y:
		target_pos.y = ground_y
	
	target_pos = _resolve_surface_collision(space_state, cam_pos, target_pos, excl)
	
	if target_pos.y < ground_y:
		target_pos.y = ground_y
	
	var max_move_speed = 15.0
	var move_delta = target_pos - current_pos
	if move_delta.length() > max_move_speed * delta:
		move_delta = move_delta.normalized() * max_move_speed * delta
	var new_pos = current_pos + move_delta
	var new_rot = Vector3(held_rot_x, held_rot, 0)
	
	var frame_velocity = move_delta / max(delta, 0.001)
	if frame_velocity.length() > max_impact_velocity:
		frame_velocity = frame_velocity.normalized() * max_impact_velocity
	velocity_buffer.append(frame_velocity)
	if velocity_buffer.size() > buffer_size:
		velocity_buffer.pop_front()
	
	if held.has_method("update_held_position") and _is_multiplayer_active():
		var my_id = held.multiplayer.get_unique_id()
		held.update_held_position.rpc(my_id, new_pos, new_rot)
	
	held.global_position = new_pos
	held.global_rotation = new_rot
	held.scale = held_original_scale
	last_frame_pos = new_pos
	last_frame_dt = delta

func _check_ground_below(space_state: PhysicsDirectSpaceState3D, pos: Vector3, excl: Array[RID]) -> Dictionary:
	var ray_start = pos + Vector3(0, held_aabb_half_extents.y + 0.5, 0)
	var ray_end = pos - Vector3(0, 20.0, 0)
	var params = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	params.exclude = excl
	params.collide_with_bodies = true
	var result = space_state.intersect_ray(params)
	if result and _is_static_surface(result.collider):
		return {"hit": true, "position": result.position, "normal": result.normal}
	return {"hit": false}

func _resolve_surface_collision(space_state: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, excl: Array[RID]) -> Vector3:
	var params = PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = excl
	params.collide_with_bodies = true
	var result = space_state.intersect_ray(params)
	
	if result:
		var offset = held_aabb_half_extents.length() * 0.5 + surface_offset
		if _is_static_surface(result.collider):
			return result.position + result.normal * offset
		elif result.collider is RigidBody3D:
			return result.position + result.normal * (offset + 0.2)
	
	var check_dist = max(held_aabb_half_extents.x, held_aabb_half_extents.z) + surface_offset + 0.1
	var directions = [
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1)
	]
	
	for dir in directions:
		var check_params = PhysicsRayQueryParameters3D.create(to, to + dir * check_dist)
		check_params.exclude = excl
		check_params.collide_with_bodies = true
		var check_result = space_state.intersect_ray(check_params)
		
		if check_result:
			var dist_to_surface = to.distance_to(check_result.position)
			if dist_to_surface < check_dist:
				var push_amount = check_dist - dist_to_surface + surface_offset
				to -= dir * push_amount
	
	return to

func _handle_resize():
	var target = held if held else hovered
	if not target or not can_resize:
		return
	if Input.is_action_just_pressed("ui_page_up") or (Input.is_action_pressed('expand') and can_resize):
		_scale_object(target, scale_step)
		_start_cooldown()
	elif Input.is_action_just_pressed("ui_page_down") or (Input.is_action_pressed('shrink') and can_resize):
		_scale_object(target, 1.0 / scale_step)
		_start_cooldown()

func _start_cooldown():
	can_resize = false
	await get_tree().create_timer(cooldown).timeout
	can_resize = true

func _scale_object(obj: Node3D, factor: float):
	var current = object_scales.get(obj, 1.0)
	var new_val = current * factor
	if new_val < min_scale or new_val > max_scale:
		return
	object_scales[obj] = new_val
	
	var was_frozen = obj is RigidBody3D and not obj.freeze
	if was_frozen:
		obj.freeze = true
	
	var original_pos = obj.global_transform.origin
	var mesh = _find_mesh(obj)
	var shape = _find_collision_shape(obj)
	
	var new_mesh_scale = mesh.scale * factor if mesh else Vector3.ONE
	var new_shape_scale = shape.scale * factor if shape else Vector3.ONE
	var new_mass = obj.mass * factor * factor * factor if obj is RigidBody3D else 1.0
	
	if obj is RigidBody3D and obj.has_method("request_scale") and _is_multiplayer_active():
		if obj.multiplayer.is_server():
			obj.request_scale(new_mesh_scale, new_shape_scale, new_mass)
		else:
			obj.request_scale.rpc_id(1, new_mesh_scale, new_shape_scale, new_mass)
	else:
		if mesh:
			mesh.scale = new_mesh_scale
		if shape:
			shape.scale = new_shape_scale
		if obj is RigidBody3D:
			obj.mass = new_mass
	
	obj.global_transform.origin = original_pos
	
	if obj == held:
		held_original_scale = obj.scale
		held_aabb_half_extents = _get_object_half_extents(obj)
		if obj is RigidBody3D:
			held_prev_mass = new_mass
	
	if was_frozen and not _is_multiplayer_active():
		await get_tree().process_frame
		await get_tree().process_frame
		if obj:
			obj.freeze = false
			obj.sleeping = false

func _apply_highlight(obj: Node3D):
	if obj and highlight_material:
		var mesh = _find_mesh(obj)
		if mesh: mesh.set_surface_override_material(0, highlight_material)

func _clear_highlight(obj: Node3D):
	if obj:
		var mesh = _find_mesh(obj)
		if mesh: mesh.set_surface_override_material(0, null)

func _get_interactable_root(node: Node) -> Node3D:
	var cur = node
	while cur:
		if cur is RigidBody3D or cur is StaticBody3D or cur is CharacterBody3D:
			return cur
		cur = cur.get_parent()
	return null

func _find_mesh(obj: Node) -> MeshInstance3D:
	if obj is MeshInstance3D: return obj
	for c in obj.get_children():
		var m = _find_mesh(c)
		if m: return m
	return null

func _find_collision_shape(root: Node) -> CollisionShape3D:
	if root is CollisionShape3D: return root
	for c in root.get_children():
		var r = _find_collision_shape(c)
		if r: return r
	return null

func _is_part_of_player(node: Node) -> bool:
	if node is CharacterBody3D:
		return true
	var current = node
	while current:
		if current is CharacterBody3D or current.is_in_group("player"):
			return true
		current = current.get_parent()
	return false
