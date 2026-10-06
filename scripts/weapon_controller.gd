class_name WeaponController
extends Node

signal ammo_changed(current_ammo: int, magazine_capacity: int)
signal shot_fired(hit_position: Vector3, hit_target: Node)
signal weapon_changed(weapon_definition: WeaponDefinition)
signal reload_started
signal reloaded(current_ammo: int)
signal animation_requested(animation_name: StringName)

@export var fire_action: StringName = &"fire"
@export var reload_action: StringName = &"reload"
@export var switch_weapon_action: StringName = &"swap_weapon"

var definition: WeaponDefinition
var firing_camera: Camera3D
var instigator: CharacterBody3D
var current_ammo: int = 0
var active_weapon_index: int = 0
var _cooldown_remaining: float = 0.0
var _reload_remaining: float = 0.0
var _is_reloading: bool = false
var _weapon_definitions: Array[WeaponDefinition] = []
var _weapon_ammo: Dictionary = {}


func configure(
	weapon_definition: WeaponDefinition,
	camera: Camera3D,
	owner_character: CharacterBody3D,
	alternate_weapon: WeaponDefinition = null
) -> void:
	_weapon_definitions.clear()
	if weapon_definition != null:
		_weapon_definitions.append(weapon_definition)
	if alternate_weapon != null and alternate_weapon != weapon_definition:
		_weapon_definitions.append(alternate_weapon)
	active_weapon_index = 0
	definition = _weapon_definitions[0] if not _weapon_definitions.is_empty() else null
	firing_camera = camera
	instigator = owner_character
	current_ammo = definition.magazine_capacity if definition != null else 0
	ammo_changed.emit(current_ammo, definition.magazine_capacity if definition != null else 0)


func reset_for_respawn() -> void:
	_is_reloading = false
	_reload_remaining = 0.0
	_cooldown_remaining = 0.0
	_weapon_ammo.clear()
	current_ammo = definition.magazine_capacity if definition != null else 0
	if definition != null:
		ammo_changed.emit(current_ammo, definition.magazine_capacity)


func _process(delta: float) -> void:
	if definition == null or firing_camera == null or instigator == null:
		return

	if InputMap.has_action(switch_weapon_action) and Input.is_action_just_pressed(switch_weapon_action):
		_switch_weapon()
		return

	_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
	if _is_reloading:
		_reload_remaining -= delta
		if _reload_remaining <= 0.0:
			_finish_reload()
		return

	if InputMap.has_action(reload_action) and Input.is_action_just_pressed(reload_action):
		_start_reload()
		return

	if not InputMap.has_action(fire_action):
		return

	var should_fire := Input.is_action_just_pressed(fire_action)
	if definition.fire_mode == WeaponDefinition.FireMode.AUTOMATIC:
		should_fire = Input.is_action_pressed(fire_action)
	if should_fire:
		_try_fire()


func _switch_weapon() -> void:
	if _is_reloading or _weapon_definitions.size() < 2:
		return

	_weapon_ammo[definition.get_instance_id()] = current_ammo
	active_weapon_index = (active_weapon_index + 1) % _weapon_definitions.size()
	definition = _weapon_definitions[active_weapon_index]
	current_ammo = int(_weapon_ammo.get(definition.get_instance_id(), definition.magazine_capacity))
	_cooldown_remaining = 0.0
	ammo_changed.emit(current_ammo, definition.magazine_capacity)
	weapon_changed.emit(definition)


func get_weapon_definition_for_index(index: int) -> WeaponDefinition:
	if index < 0 or index >= _weapon_definitions.size():
		return null
	return _weapon_definitions[index]


func set_replicated_weapon_index(index: int) -> void:
	if index < 0 or index >= _weapon_definitions.size() or index == active_weapon_index:
		return
	_weapon_ammo[definition.get_instance_id()] = current_ammo
	active_weapon_index = index
	definition = _weapon_definitions[active_weapon_index]
	current_ammo = int(_weapon_ammo.get(definition.get_instance_id(), definition.magazine_capacity))
	weapon_changed.emit(definition)


func _try_fire() -> void:
	if _is_reloading or _cooldown_remaining > 0.0 or current_ammo <= 0:
		return

	current_ammo -= 1
	_cooldown_remaining = 60.0 / maxf(definition.rounds_per_minute, 1.0)
	ammo_changed.emit(current_ammo, definition.magazine_capacity)
	if not definition.fire_animation.is_empty():
		animation_requested.emit(definition.fire_animation)

	var network_session := get_tree().current_scene as NetworkSession
	if network_session != null and network_session.is_networked():
		if multiplayer.is_server():
			network_session.process_local_shot(active_weapon_index)
		else:
			network_session.request_shot.rpc_id(1, active_weapon_index)
		shot_fired.emit(Vector3.ZERO, null)
		return

	var shot_trace := trace_shot()
	var result: Dictionary = shot_trace.get("hit", {})
	var hit_position: Vector3 = result.get("position", shot_trace.get("end_position", Vector3.ZERO))
	var hit_target: Node = null
	if not result.is_empty():
		_spawn_impact_effect(hit_position, result.get("normal", Vector3.UP))
		hit_target = _find_damage_receiver(result.get("collider"))
		if hit_target != null:
			hit_target.call("take_damage", definition.damage, instigator)

	shot_fired.emit(hit_position, hit_target)


func trace_shot(weapon_definition: WeaponDefinition = null) -> Dictionary:
	var shot_definition := weapon_definition if weapon_definition != null else definition
	if shot_definition == null or firing_camera == null or instigator == null:
		return {}

	var ray_origin := firing_camera.global_position
	var ray_direction := -firing_camera.global_basis.z.normalized()
	if shot_definition.spread_degrees > 0.0:
		var spread := deg_to_rad(shot_definition.spread_degrees)
		var yaw_offset := randf_range(-spread, spread)
		var pitch_offset := randf_range(-spread, spread)
		ray_direction = (-firing_camera.global_basis.z).rotated(
			firing_camera.global_basis.x,
			pitch_offset
		).rotated(
			firing_camera.global_basis.y,
			yaw_offset
		).normalized()

	# The camera selects the aim point. The damage ray starts at the weapon so walls
	# between the muzzle and that point still block the shot.
	var camera_end := ray_origin + ray_direction * shot_definition.max_range
	var camera_query := PhysicsRayQueryParameters3D.create(ray_origin, camera_end)
	camera_query.exclude = [instigator.get_rid()]
	var space_state := firing_camera.get_world_3d().direct_space_state
	var camera_hit := space_state.intersect_ray(camera_query)
	var aim_point: Vector3 = camera_hit.get("position", camera_end)

	var shot_origin := _get_shot_origin()
	var muzzle_to_aim := aim_point - shot_origin
	var shot_direction: Vector3
	var shot_distance: float
	var character_forward := -instigator.global_basis.z.normalized()
	if muzzle_to_aim.length_squared() < 0.0001:
		return {"hit": {}, "end_position": shot_origin + ray_direction * shot_definition.max_range}
	if muzzle_to_aim.normalized().dot(character_forward) <= 0.0:
		# A target visible behind the character from the over-the-shoulder camera
		# cannot make the weapon fire backward through the player.
		return {"hit": {}, "end_position": shot_origin + character_forward * shot_definition.max_range}

	shot_distance = minf(muzzle_to_aim.length(), shot_definition.max_range)
	shot_direction = muzzle_to_aim.normalized()

	var shot_end := shot_origin + shot_direction * shot_distance
	var shot_query := PhysicsRayQueryParameters3D.create(shot_origin, shot_end)
	shot_query.exclude = [instigator.get_rid()]
	return {
		"hit": space_state.intersect_ray(shot_query),
		"end_position": shot_end,
	}


func _get_shot_origin() -> Vector3:
	var muzzle := instigator.find_child("Muzzle", true, false) as Node3D
	if muzzle != null:
		return muzzle.global_position
	var gun_socket := instigator.find_child("GunSocket", true, false) as Node3D
	if gun_socket != null:
		return gun_socket.global_position
	return instigator.global_position + Vector3.UP * 1.3


func _spawn_impact_effect(hit_position: Vector3, surface_normal: Vector3) -> void:
	var world_root := get_tree().current_scene
	if world_root == null:
		world_root = get_tree().root

	if definition.impact_effect_scene != null:
		var custom_effect := definition.impact_effect_scene.instantiate()
		world_root.add_child(custom_effect)
		if custom_effect is Node3D:
			custom_effect.global_position = hit_position + surface_normal * 0.02
		return

	var particles := GPUParticles3D.new()
	particles.name = "HitImpact"
	particles.amount = 12
	particles.lifetime = 0.3
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.local_coords = false
	particles.emitting = false

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 180.0
	process_material.initial_velocity_min = 1.0
	process_material.initial_velocity_max = 3.0
	process_material.gravity = Vector3(0.0, -3.0, 0.0)
	process_material.scale_min = 0.025
	process_material.scale_max = 0.06
	particles.process_material = process_material

	var particle_mesh := QuadMesh.new()
	particle_mesh.size = Vector2(0.06, 0.06)
	var particle_material := StandardMaterial3D.new()
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	particle_material.albedo_color = Color(1.0, 0.72, 0.28)
	particle_mesh.material = particle_material
	particles.draw_pass_1 = particle_mesh

	world_root.add_child(particles)
	particles.global_position = hit_position + surface_normal * 0.02
	particles.finished.connect(particles.queue_free)
	particles.emitting = true


func spawn_network_impact(hit_position: Vector3, surface_normal: Vector3) -> void:
	_spawn_impact_effect(hit_position, surface_normal)


func _start_reload() -> void:
	if _is_reloading or current_ammo >= definition.magazine_capacity:
		return

	_is_reloading = true
	_reload_remaining = definition.reload_duration
	reload_started.emit()
	if not definition.reload_animation.is_empty():
		animation_requested.emit(definition.reload_animation)


func _finish_reload() -> void:
	_is_reloading = false
	current_ammo = definition.magazine_capacity
	ammo_changed.emit(current_ammo, definition.magazine_capacity)
	reloaded.emit(current_ammo)


func _find_damage_receiver(hit_object: Object) -> Node:
	var candidate := hit_object as Node
	while candidate != null:
		if candidate.has_method("take_damage"):
			return candidate
		candidate = candidate.get_parent()
	return null
