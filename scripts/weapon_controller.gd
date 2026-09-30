class_name WeaponController
extends Node

signal ammo_changed(current_ammo: int, magazine_capacity: int)
signal shot_fired(hit_position: Vector3, hit_target: Node)
signal reload_started
signal reloaded(current_ammo: int)
signal animation_requested(animation_name: StringName)

@export var fire_action: StringName = &"fire"
@export var reload_action: StringName = &"reload"

var definition: WeaponDefinition
var firing_camera: Camera3D
var instigator: CharacterBody3D
var current_ammo: int = 0
var _cooldown_remaining: float = 0.0
var _reload_remaining: float = 0.0
var _is_reloading: bool = false


func configure(
	weapon_definition: WeaponDefinition,
	camera: Camera3D,
	owner_character: CharacterBody3D
) -> void:
	definition = weapon_definition
	firing_camera = camera
	instigator = owner_character
	current_ammo = definition.magazine_capacity if definition != null else 0
	ammo_changed.emit(current_ammo, definition.magazine_capacity if definition != null else 0)


func reset_for_respawn() -> void:
	_is_reloading = false
	_reload_remaining = 0.0
	_cooldown_remaining = 0.0
	current_ammo = definition.magazine_capacity if definition != null else 0
	if definition != null:
		ammo_changed.emit(current_ammo, definition.magazine_capacity)


func _process(delta: float) -> void:
	if definition == null or firing_camera == null or instigator == null:
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


func _try_fire() -> void:
	if _is_reloading or _cooldown_remaining > 0.0 or current_ammo <= 0:
		return

	current_ammo -= 1
	_cooldown_remaining = 60.0 / maxf(definition.rounds_per_minute, 1.0)
	ammo_changed.emit(current_ammo, definition.magazine_capacity)
	if not definition.fire_animation.is_empty():
		animation_requested.emit(definition.fire_animation)

	var ray_origin := firing_camera.global_position
	var ray_direction := -firing_camera.global_basis.z
	if definition.spread_degrees > 0.0:
		var spread := deg_to_rad(definition.spread_degrees)
		ray_direction = ray_direction.rotated(
			firing_camera.global_basis.x,
			randf_range(-spread, spread)
		)
		ray_direction = ray_direction.rotated(
			firing_camera.global_basis.y,
			randf_range(-spread, spread)
		).normalized()
	var ray_end := ray_origin + ray_direction * definition.max_range
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [instigator.get_rid()]

	var result := firing_camera.get_world_3d().direct_space_state.intersect_ray(query)
	var hit_position: Vector3 = result.get("position", ray_end)
	var hit_target: Node = null
	if not result.is_empty():
		_spawn_impact_effect(hit_position, result.get("normal", Vector3.UP))
		hit_target = _find_damage_receiver(result.get("collider"))
		if hit_target != null:
			hit_target.call("take_damage", definition.damage, instigator)

	shot_fired.emit(hit_position, hit_target)


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
