extends RigidBody3D

@export var sync_position: Vector3
@export var sync_rotation: Vector3
@export var sync_linear_velocity: Vector3
@export var sync_angular_velocity: Vector3

var is_held_by: int = 0
var held_target_pos: Vector3
var held_target_rot: Vector3
var is_dynamic_spawn: bool = false
var sync_timer: float = 0.0
var last_thrower_id: int = 0
var throw_velocity_magnitude: float = 0.0
var has_exploded: bool = false

const EXPLOSION_RADIUS: float = 8.0
const EXPLOSION_FORCE: float = 25.0
const EXPLOSION_DAMAGE: float = 40.0
const EXPLOSION_UPWARD_BIAS: float = 0.4
const MIN_IMPACT_VELOCITY: float = 5.0

func _get_scale_factor() -> float:
	var mesh = _find_mesh(self)
	if mesh:
		return mesh.scale.x
	return 1.0

func _ready():
	if sync_position != Vector3.ZERO:
		global_position = sync_position
		rotation = sync_rotation
		is_dynamic_spawn = true
	else:
		sync_position = global_position
		sync_rotation = rotation
	sync_linear_velocity = linear_velocity
	sync_angular_velocity = angular_velocity
	held_target_pos = global_position
	held_target_rot = rotation
	
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	if multiplayer.multiplayer_peer == null:
		return
	if not multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return
	
	if has_exploded:
		return
	
	var my_id = multiplayer.get_unique_id()
	
	if multiplayer.is_server():
		if is_held_by != 0 and is_held_by != 1:
			global_position = global_position.lerp(held_target_pos, delta * 14.0)
			global_rotation = held_target_rot
		
		sync_position = global_position
		sync_rotation = rotation
		sync_linear_velocity = linear_velocity
		sync_angular_velocity = angular_velocity
		
		if is_dynamic_spawn:
			sync_timer += delta
			if sync_timer >= 0.05:
				sync_timer = 0.0
				_rpc_sync_state.rpc(sync_position, sync_rotation, sync_linear_velocity, sync_angular_velocity)
	else:
		if is_held_by != my_id:
			global_position = global_position.lerp(sync_position, delta * 15.0)
			rotation = rotation.lerp(sync_rotation, delta * 15.0)
			linear_velocity = sync_linear_velocity
			angular_velocity = sync_angular_velocity

@rpc("authority", "unreliable_ordered", "call_remote")
func _rpc_sync_state(pos: Vector3, rot: Vector3, lin_vel: Vector3, ang_vel: Vector3):
	sync_position = pos
	sync_rotation = rot
	sync_linear_velocity = lin_vel
	sync_angular_velocity = ang_vel

@rpc("any_peer", "call_local", "reliable")
func apply_push(push_velocity: Vector3):
	if multiplayer.is_server():
		linear_velocity += push_velocity

@rpc("any_peer", "call_local", "reliable")
func request_hold(peer_id: int):
	if multiplayer.is_server():
		if is_held_by == 0 and not has_exploded:
			is_held_by = peer_id
			freeze = true
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			held_target_pos = global_position
			held_target_rot = rotation
			if peer_id != 1:
				_sync_hold_state.rpc(peer_id, true)

@rpc("any_peer", "call_local", "reliable")
func request_release(peer_id: int, release_velocity: Vector3):
	if multiplayer.is_server():
		if is_held_by == peer_id:
			last_thrower_id = peer_id
			throw_velocity_magnitude = release_velocity.length()
			is_held_by = 0
			freeze = false
			sleeping = false
			linear_velocity = release_velocity
			angular_velocity = Vector3.ZERO
			if release_velocity.length() < 0.1:
				apply_central_impulse(Vector3(0, -0.01, 0))
			_sync_hold_state.rpc(0, false)

@rpc("any_peer", "unreliable_ordered")
func update_held_position(peer_id: int, pos: Vector3, rot: Vector3):
	if multiplayer.is_server():
		if is_held_by == peer_id:
			held_target_pos = pos
			held_target_rot = rot
			if peer_id == 1:
				global_position = pos
				global_rotation = rot

@rpc("authority", "call_local", "reliable")
func _sync_hold_state(holder_id: int, is_frozen: bool):
	is_held_by = holder_id
	freeze = is_frozen
	if is_frozen:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO

@rpc("any_peer", "call_local", "reliable")
func request_throw(throw_velocity: Vector3):
	if multiplayer.is_server():
		last_thrower_id = is_held_by
		throw_velocity_magnitude = throw_velocity.length()
		is_held_by = 0
		freeze = false
		sleeping = false
		linear_velocity = throw_velocity
		angular_velocity = Vector3.ZERO
		_sync_throw.rpc(throw_velocity)

@rpc("authority", "call_local", "reliable")
func _sync_throw(throw_velocity: Vector3):
	is_held_by = 0
	freeze = false
	sleeping = false
	linear_velocity = throw_velocity
	angular_velocity = Vector3.ZERO
	SoundManager.play_throw()

func _on_body_entered(body: Node):
	if not multiplayer.is_server():
		return
	
	if has_exploded:
		return
	
	var impact_velocity = linear_velocity.length()
	if impact_velocity < MIN_IMPACT_VELOCITY and throw_velocity_magnitude < MIN_IMPACT_VELOCITY:
		return
	
	_explode()

func _explode():
	if has_exploded:
		return
	has_exploded = true
	
	var explosion_pos = global_position
	var scale_factor = _get_scale_factor()
	var scaled_radius = EXPLOSION_RADIUS * scale_factor
	var scaled_force = EXPLOSION_FORCE * scale_factor * scale_factor
	var scaled_damage = EXPLOSION_DAMAGE * scale_factor
	
	var _space_state = get_world_3d().direct_space_state
	
	for body in get_tree().get_nodes_in_group("players"):
		if body is CharacterBody3D:
			var dir = body.global_position - explosion_pos
			var dist = dir.length()
			if dist < scaled_radius and dist > 0.1:
				var force_mult = 1.0 - (dist / scaled_radius)
				var push_dir = dir.normalized()
				push_dir.y += EXPLOSION_UPWARD_BIAS
				push_dir = push_dir.normalized()
				
				var damage = scaled_damage * force_mult
				if body.has_method("request_damage"):
					body.request_damage(damage, last_thrower_id)
				if body.has_method("apply_explosion_force"):
					body.apply_explosion_force(push_dir * scaled_force * force_mult)
	
	for obj in get_tree().get_nodes_in_group("physics_objects"):
		if obj == self:
			continue
		if obj is RigidBody3D:
			var dir = obj.global_position - explosion_pos
			var dist = dir.length()
			if dist < scaled_radius and dist > 0.1:
				var force_mult = 1.0 - (dist / scaled_radius)
				var push_dir = dir.normalized()
				push_dir.y += EXPLOSION_UPWARD_BIAS
				push_dir = push_dir.normalized()
				
				if obj.has_method("apply_push"):
					obj.apply_push.rpc(push_dir * scaled_force * force_mult * 2.0)
	
	_sync_explode.rpc(explosion_pos)

@rpc("authority", "reliable", "call_local")
func _sync_explode(pos: Vector3):
	has_exploded = true
	_create_explosion_effect(pos)
	SoundManager.play_explosion()
	
	visible = false
	for child in get_children():
		if child is CollisionShape3D:
			child.disabled = true
		if child is MeshInstance3D:
			child.visible = false
	
	await get_tree().create_timer(0.1).timeout
	queue_free()

func _create_explosion_effect(pos: Vector3):
	var particles = GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 32
	particles.lifetime = 0.5
	
	var material = ParticleProcessMaterial.new()
	material.direction = Vector3(0, 1, 0)
	material.spread = 180.0
	material.initial_velocity_min = 5.0
	material.initial_velocity_max = 15.0
	material.gravity = Vector3(0, -10, 0)
	material.scale_min = 0.3
	material.scale_max = 0.8
	material.color = Color(1.0, 0.5, 0.1, 1.0)
	
	particles.process_material = material
	
	var mesh = SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	var mesh_mat = StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(1.0, 0.6, 0.2)
	mesh_mat.emission_enabled = true
	mesh_mat.emission = Color(1.0, 0.4, 0.0)
	mesh_mat.emission_energy_multiplier = 2.0
	mesh.material = mesh_mat
	particles.draw_pass_1 = mesh
	
	get_tree().current_scene.add_child(particles)
	particles.global_position = pos
	
	await get_tree().create_timer(1.0).timeout
	particles.queue_free()

@rpc("any_peer", "reliable")
func request_scale(mesh_scale: Vector3, shape_scale: Vector3, new_mass: float):
	if multiplayer.is_server():
		_apply_scale(mesh_scale, shape_scale, new_mass)
		_sync_scale.rpc(mesh_scale, shape_scale, new_mass)

@rpc("authority", "reliable", "call_local")
func _sync_scale(mesh_scale: Vector3, shape_scale: Vector3, new_mass: float):
	_apply_scale(mesh_scale, shape_scale, new_mass)

func _apply_scale(mesh_scale: Vector3, shape_scale: Vector3, new_mass: float):
	var mesh = _find_mesh(self)
	var shape = _find_collision_shape(self)
	if mesh:
		mesh.scale = mesh_scale
	if shape:
		shape.scale = shape_scale
	mass = new_mass

func _find_mesh(obj: Node) -> MeshInstance3D:
	if obj is MeshInstance3D:
		return obj
	for c in obj.get_children():
		var m = _find_mesh(c)
		if m:
			return m
	return null

func _find_collision_shape(obj: Node) -> CollisionShape3D:
	if obj is CollisionShape3D:
		return obj
	for c in obj.get_children():
		var s = _find_collision_shape(c)
		if s:
			return s
	return null
