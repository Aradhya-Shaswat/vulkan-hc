extends Camera3D

@export var ray_length: float = 200.0
@export var scale_step := 1.1
@export var highlight_material: Material
@export var min_scale: float = .5
@export var max_scale: float = 2.0
@export var cooldown: float = 0.12

var hovered: Node3D = null
var previous: Node3D = null
var can_resize := true

func _process(delta):
	_update_hover()
	_handle_input()

func _update_hover():
	var screen_center = get_viewport().get_visible_rect().size * 0.5
	var origin = project_ray_origin(screen_center)
	var dir = project_ray_normal(screen_center)
	var to = origin + dir * ray_length

	var params = PhysicsRayQueryParameters3D.create(origin, to)
	params.exclude = [self]
	params.collide_with_bodies = true

	var res = get_world_3d().direct_space_state.intersect_ray(params)

	if res and res.has("collider"):
		var hit = res.collider

		# use ancestor-walk to detect anything under the 'walls' node
		if hit.name == "ground" or hit.name == "player":
			hovered = null
		else:
			hovered = hit
	else:
		hovered = null

	if hovered != previous:
		_clear_highlight(previous)
		_apply_highlight(hovered)
		previous = hovered

func _handle_input():
	if not hovered or not can_resize:
		return
		
	if Input.is_key_pressed(KEY_Q):
		_scale_object(hovered, scale_step)
		_start_cooldown()

	if Input.is_key_pressed(KEY_R):
		_scale_object(hovered, 1.0 / scale_step)
		_start_cooldown()

func _start_cooldown():
	can_resize = false
	await get_tree().create_timer(cooldown).timeout
	can_resize = true

func _scale_object(obj: Node3D, factor: float):
	var new_scale = obj.scale * factor

	if new_scale.x < min_scale or new_scale.x > max_scale:
		return

	obj.scale = new_scale

	var col = _find_collision_shape(obj)
	if col:
		_scale_collision(col, factor)

func _find_mesh(obj: Node) -> MeshInstance3D:
	if obj is MeshInstance3D:
		return obj
	for c in obj.get_children():
		var m = _find_mesh(c)
		if m:
			return m
	return null

func _apply_highlight(obj: Node3D):
	if not obj:
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

func _find_collision_shape(root: Node) -> CollisionShape3D:
	if root is CollisionShape3D:
		return root
	for c in root.get_children():
		var r = _find_collision_shape(c)
		if r:
			return r
	return null

func _scale_collision(col: CollisionShape3D, factor: float):
	var shape = col.shape
	if shape is BoxShape3D:
		shape.extents *= factor
	elif shape is SphereShape3D:
		shape.radius *= factor
	elif shape is CapsuleShape3D:
		shape.radius *= factor
		shape.height *= factor
	else:
		col.scale *= factor
	col.shape = shape
