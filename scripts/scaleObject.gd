extends Camera3D

@export var ray_length: float = 12.0
@export var hold_distance: float = 3.0
@export var max_drag_distance: float = 6.0
@export var pull_strength: float = 14.0
@export var scale_step := 1.1
@export var highlight_material: Material
@export var min_scale: float = 0.5
@export var max_scale: float = 2.0
@export var cooldown: float = 0.12
@export var player_node_path: NodePath
@export var max_impact_velocity: float = 8.0
@export var held_mass_multiplier: float = 0.3
@export var wall_push_distance: float = 0.3

var hovered: Node3D = null
var previous: Node3D = null
var held: Node3D = null
var can_resize := true
var held_rot := 0.0
var held_rot_x := 0.0
var wheel_delta := 0.0
var held_prev_mass := 1.0
var last_frame_pos := Vector3.ZERO
var last_frame_dt := 0.0
var held_original_scale := Vector3.ONE
var object_scales: Dictionary = {}

@onready var player_node: Node = null

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

func _process(delta):
	_update_hover()
	_handle_resize()
	_update_held_motion(delta)
	if held and wheel_delta != 0.0:
		if Input.is_action_pressed("ui_focus_next"):
			held_rot_x += wheel_delta * 0.2
		else:
			held_rot += wheel_delta * 0.2
		wheel_delta = 0.0
	elif not held:
		wheel_delta = 0.0

func _physics_process(_delta):
	if held:
		_prevent_wall_clipping()

func _input(event):
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed: wheel_delta = 1.0
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed: wheel_delta = -1.0
			MOUSE_BUTTON_LEFT:
				if event.pressed: _try_start_hold()
				else: _release_hold()

func _is_player_grounded() -> bool:
	if player_node and player_node is CharacterBody3D:
		return player_node.is_on_floor()
	return true

func _get_exclusion_list() -> Array:
	var excl = []
	if player_node and player_node is CollisionObject3D:
		excl.append(player_node.get_rid())
		for child in player_node.get_children():
			if child is CollisionObject3D:
				excl.append(child.get_rid())
	return excl

func _is_wall_or_ground(node: Node) -> bool:
	if node.name == "ground" or node.is_in_group("walls"):
		return true
	var current = node
	while current:
		if current.name == "walls" or current.is_in_group("walls"):
			return true
		current = current.get_parent()
	return false

func _update_hover():
	if held or not _is_player_grounded():
		if hovered and hovered != previous:
			_clear_highlight(previous)
		if not _is_player_grounded() and hovered:
			_clear_highlight(hovered)
		hovered = null
		previous = null
		return
	
	var center = get_viewport().get_visible_rect().size * 0.5
	var origin = project_ray_origin(center)
	var dir = project_ray_normal(center)
	var params = PhysicsRayQueryParameters3D.create(origin, origin + dir * ray_length)
	params.exclude = _get_exclusion_list()
	params.collide_with_bodies = true
	
	var res = get_world_3d().direct_space_state.intersect_ray(params)
	hovered = null
	
	if res:
		var c = res.collider
		if not _is_wall_or_ground(c) and not _is_part_of_player(c):
			var root = _get_interactable_root(c)
			if root and not _is_wall_or_ground(root) and not _is_part_of_player(root):
				hovered = root
	
	if hovered != previous:
		_clear_highlight(previous)
		_apply_highlight(hovered)
		previous = hovered

func _try_start_hold():
	if not hovered or not _is_player_grounded():
		return
	held = hovered
	var euler = held.global_transform.basis.get_euler()
	held_rot = euler.y
	held_rot_x = euler.x
	held_original_scale = held.scale
	last_frame_pos = held.global_transform.origin
	last_frame_dt = 0.0
	
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
		var dt = max(last_frame_dt, 0.016)
		var velocity = (held.global_transform.origin - last_frame_pos) / dt
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
				held.apply_central_impulse(Vector3(0, -0.01, 0))
	held = null
	last_frame_dt = 0.0

func _is_multiplayer_active() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _update_held_motion(delta):
	if not held:
		return
	
	var cam_pos = global_transform.origin
	var cam_forward = -global_transform.basis.z
	var current_pos = held.global_transform.origin
	var player_pos = player_node.global_transform.origin if player_node else cam_pos
	var space_state = get_world_3d().direct_space_state
	var min_dist = hold_distance * 0.5
	
	if current_pos.distance_to(cam_pos) > max_drag_distance:
		_release_hold()
		return

	var target_pos = cam_pos + cam_forward * hold_distance
	var excl = [held.get_rid()]
	if player_node and player_node is CollisionObject3D:
		excl.append(player_node.get_rid())
	
	target_pos = _adjust_for_walls(space_state, cam_pos, target_pos, excl)
	target_pos = _adjust_for_walls(space_state, current_pos, target_pos, excl)
	
	if target_pos.distance_to(player_pos) < min_dist:
		var away = (target_pos - player_pos).normalized()
		if away.length() < 0.01:
			away = cam_forward
		target_pos = player_pos + away * min_dist
	
	target_pos = _check_wall_between_player(space_state, player_pos, target_pos, excl, min_dist)
	
	var new_pos = current_pos.lerp(target_pos, delta * pull_strength)
	var new_rot = Vector3(held_rot_x, held_rot, 0)
	
	if held.has_method("update_held_position") and _is_multiplayer_active():
		var my_id = held.multiplayer.get_unique_id()
		held.update_held_position.rpc(my_id, new_pos, new_rot)
	
	held.global_position = new_pos
	held.global_rotation = new_rot
	held.scale = held_original_scale
	last_frame_pos = current_pos
	last_frame_dt = delta

func _adjust_for_walls(space_state, from: Vector3, to: Vector3, excl: Array) -> Vector3:
	var params = PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = excl
	params.collide_with_bodies = true
	var result = space_state.intersect_ray(params)
	if result and _is_wall_or_ground(result.collider):
		return result.position + result.normal * (wall_push_distance + 0.3)
	return to

func _check_wall_between_player(space_state, player_pos: Vector3, target_pos: Vector3, excl: Array, min_dist: float) -> Vector3:
	if not player_node:
		return target_pos
	var dir = target_pos - player_pos
	dir.y = 0
	if dir.length() < 0.1:
		return target_pos
	var params = PhysicsRayQueryParameters3D.create(player_pos, player_pos + dir.normalized() * (dir.length() + 1.0))
	params.exclude = excl
	params.collide_with_bodies = true
	var result = space_state.intersect_ray(params)
	if result and _is_wall_or_ground(result.collider):
		var wall_dist = player_pos.distance_to(result.position)
		if player_pos.distance_to(target_pos) > wall_dist - 0.5:
			var new_pos = result.position + result.normal * (wall_push_distance + 0.8)
			if new_pos.distance_to(player_pos) < min_dist:
				new_pos = player_pos + result.normal * min_dist
			return new_pos
	return target_pos

func _prevent_wall_clipping():
	if not held:
		return
	var space_state = get_world_3d().direct_space_state
	var held_pos = held.global_transform.origin
	var cam_pos = global_transform.origin
	var player_pos = player_node.global_transform.origin if player_node else cam_pos
	var min_dist = hold_distance * 0.5
	var excl = [held.get_rid()]
	if player_node and player_node is CollisionObject3D:
		excl.append(player_node.get_rid())
	
	var dir = (held_pos - player_pos)
	dir.y = 0
	if dir.length() > 0.1:
		var params = PhysicsRayQueryParameters3D.create(held_pos, held_pos + dir.normalized())
		params.exclude = excl
		params.collide_with_bodies = true
		var result = space_state.intersect_ray(params)
		if result and _is_wall_or_ground(result.collider):
			held.global_position = result.position + result.normal * (wall_push_distance + 0.8)
			last_frame_pos = held.global_position
			if held.global_position.distance_to(player_pos) < min_dist:
				held.global_position = player_pos + result.normal * min_dist
				last_frame_pos = held.global_position
			return
	
	var params = PhysicsRayQueryParameters3D.create(cam_pos, held_pos)
	params.exclude = excl
	params.collide_with_bodies = true
	var result = space_state.intersect_ray(params)
	if result and _is_wall_or_ground(result.collider):
		held.global_position = result.position + result.normal * (wall_push_distance + 0.5)
		last_frame_pos = held.global_position
		return
	
	var shape_node = _find_collision_shape(held)
	if not shape_node or not shape_node.shape:
		return
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape_node.shape
	query.transform = Transform3D(Basis().scaled(shape_node.global_transform.basis.get_scale()), held_pos)
	query.collide_with_bodies = true
	query.exclude = excl
	
	for r in space_state.intersect_shape(query, 16):
		if _is_wall_or_ground(r.collider):
			var to_player = (player_pos - held_pos)
			to_player.y = 0
			to_player = to_player.normalized() if to_player.length() > 0.01 else (cam_pos - held_pos).normalized()
			held.global_position += to_player * wall_push_distance * 2.0
			last_frame_pos = held.global_position
			if held.global_position.distance_to(player_pos) < min_dist:
				held.global_position = player_pos - to_player * min_dist
				last_frame_pos = held.global_position
			break

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
	
	if mesh:
		mesh.scale = new_mesh_scale
	if shape:
		shape.scale = new_shape_scale
	obj.global_transform.origin = original_pos
	
	if obj == held:
		held_original_scale = obj.scale
	
	if obj is RigidBody3D:
		obj.mass = new_mass
		if obj == held:
			held_prev_mass = new_mass
		
		if obj.has_method("request_scale") and _is_multiplayer_active():
			obj.request_scale.rpc(new_mesh_scale, new_shape_scale, new_mass)
		
		if was_frozen:
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
	if not player_node: return false
	var current = node
	while current:
		if current == player_node or current.is_in_group("player"):
			return true
		current = current.get_parent()
	return false
