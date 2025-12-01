extends Camera3D

const MODE_KINEMATIC = 3
const MODE_RIGID = 0

@export var ray_length: float = 12.0
@export var hold_distance: float = 3.0
@export var max_drag_distance: float = 6.0
@export var pull_strength: float = 14.0
@export var scale_step := 1.1
@export var highlight_material: Material
@export var min_scale: float = .5
@export var max_scale: float = 2.0
@export var cooldown: float = 0.12
@export var player_node_path: NodePath

var hovered: Node3D = null
var previous: Node3D = null
var held: Node3D = null
var can_resize := true
var held_rot: float = 0.0
var wheel_delta := 0.0
var held_prev_mode: int = 0
var held_prev_gravity: float = 1.0
var held_prev_linvel: Vector3 = Vector3.ZERO
var last_frame_pos: Vector3 = Vector3.ZERO
var last_frame_dt: float = 0.0
var held_original_scale: Vector3 = Vector3.ONE

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
	_handle_rotation()

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			wheel_delta = 1.0
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			wheel_delta = -1.0
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_try_start_hold()
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_release_hold()

func _update_hover():
	if held:
		hovered = null
		return
	
	var center = get_viewport().get_visible_rect().size * 0.5
	var origin = project_ray_origin(center)
	var dir = project_ray_normal(center)
	var to = origin + dir * ray_length
	var params = PhysicsRayQueryParameters3D.create(origin, to)
	
	var excl = []
	if player_node:
		if player_node is CollisionObject3D:
			excl.append(player_node.get_rid())
		for child in _get_all_children(player_node):
			if child is CollisionObject3D:
				excl.append(child.get_rid())
	
	params.exclude = excl
	params.collide_with_bodies = true
	params.collide_with_areas = false
	
	var res = get_world_3d().direct_space_state.intersect_ray(params)
	
	if res and res.has("collider"):
		var c = res.collider
		
		if _is_part_of_player(c):
			hovered = null
			if hovered != previous:
				_clear_highlight(previous)
				previous = hovered
			return
		
		if _is_part_of_walls(c):
			hovered = null
			if hovered != previous:
				_clear_highlight(previous)
				previous = hovered
			return
		
		var root = _get_interactable_root(c)
		
		if root and not _is_part_of_player(root) and not _is_part_of_walls(root):
			if not (root.name == "ground" or root.is_in_group("walls")):
				hovered = root
			else:
				hovered = null
		else:
			hovered = null
	else:
		hovered = null
	
	if hovered != previous:
		_clear_highlight(previous)
		_apply_highlight(hovered)
		previous = hovered

func _try_start_hold():
	if not hovered:
		return
	
	held = hovered
	held_rot = held.global_transform.basis.get_euler().y
	held_original_scale = held.scale
	last_frame_pos = held.global_transform.origin
	last_frame_dt = 0.0
	
	if held is RigidBody3D:
		held_prev_gravity = held.gravity_scale
		held_prev_linvel = held.linear_velocity
		
		held.freeze = true
		held.linear_velocity = Vector3.ZERO
		held.angular_velocity = Vector3.ZERO

func _release_hold():
	if not held:
		return
	
	if held is RigidBody3D:
		var dt = max(last_frame_dt, 0.016)
		var velocity = (held.global_transform.origin - last_frame_pos) / dt
		
		held.freeze = false
		held.sleeping = false
		held.linear_velocity = velocity
		held.angular_velocity = Vector3.ZERO
		
		if velocity.length() < 0.1:
			held.apply_central_impulse(Vector3(0, -0.01, 0))
	
	held = null
	last_frame_dt = 0.0

func _update_held_motion(delta):
	if not held:
		return
	
	var cam_pos = global_transform.origin
	var cam_forward = -global_transform.basis.z
	var target_pos = cam_pos + cam_forward * hold_distance
	var current_pos = held.global_transform.origin
	var dist = current_pos.distance_to(cam_pos)
	
	if dist > max_drag_distance:
		_release_hold()
		return
	
	var new_pos = current_pos.lerp(target_pos, delta * pull_strength)
	
	held.global_position = new_pos
	held.global_rotation = Vector3(0, held_rot, 0)
	held.scale = held_original_scale
	
	last_frame_pos = current_pos
	last_frame_dt = delta

func _handle_resize():
	var target = held if held else hovered
	
	if not target or not can_resize:
		return
	
	if Input.is_action_just_pressed("ui_page_up") or (Input.is_key_pressed(KEY_Q) and can_resize):
		_scale_object(target, scale_step)
		_start_cooldown()
	elif Input.is_action_just_pressed("ui_page_down") or (Input.is_key_pressed(KEY_R) and can_resize):
		_scale_object(target, 1.0 / scale_step)
		_start_cooldown()

func _start_cooldown():
	can_resize = false
	await get_tree().create_timer(cooldown).timeout
	can_resize = true

func _scale_object(obj: Node3D, factor: float):
	var current_scale = obj.scale.x
	var new_scale_value = current_scale * factor
	
	if new_scale_value < min_scale or new_scale_value > max_scale:
		return
	
	var was_frozen = false
	if obj is RigidBody3D and not obj.freeze:
		was_frozen = true
		obj.freeze = true
	
	var original_pos = obj.global_transform.origin
	
	var mesh = _find_mesh(obj)
	if mesh:
		mesh.scale *= factor
	
	var shape_node = _find_collision_shape(obj)
	if shape_node:
		shape_node.scale *= factor
	
	obj.global_transform.origin = original_pos
	
	if obj == held:
		held_original_scale = obj.scale
	
	if obj is RigidBody3D:
		obj.mass = obj.mass * (factor * factor * factor)
		
		if was_frozen:
			await get_tree().process_frame
			await get_tree().process_frame
			if obj:
				obj.freeze = false
				obj.sleeping = false
	
	print("mesh scale: ", mesh.scale if mesh else "none", " | collision scale: ", shape_node.scale if shape_node else "none")

func _handle_rotation():
	if not held:
		wheel_delta = 0.0
		return
	
	if wheel_delta != 0.0:
		held_rot += wheel_delta * 0.2
		wheel_delta = 0.0

func _apply_highlight(obj: Node3D):
	if not obj or not highlight_material:
		return
	var mesh = _find_mesh(obj)
	if mesh:
		mesh.set_surface_override_material(0, highlight_material)

func _clear_highlight(obj: Node3D):
	if not obj:
		return
	var mesh = _find_mesh(obj)
	if mesh:
		mesh.set_surface_override_material(0, null)

func _get_interactable_root(node: Node) -> Node3D:
	var cur = node
	while cur:
		if cur is RigidBody3D or cur is StaticBody3D or cur is CharacterBody3D:
			return cur
		cur = cur.get_parent()
	return null

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

func _get_all_children(node: Node) -> Array:
	var children = []
	for child in node.get_children():
		children.append(child)
		children.append_array(_get_all_children(child))
	return children

func _is_part_of_player(node: Node) -> bool:
	if not player_node:
		return false
	
	var current = node
	while current:
		if current == player_node:
			return true
		if current.is_in_group("player"):
			return true
		current = current.get_parent()
	
	return false

func _is_part_of_walls(node: Node) -> bool:
	var current = node
	while current:
		if current.name == "walls" or current.is_in_group("walls"):
			return true
		current = current.get_parent()
	
	return false
