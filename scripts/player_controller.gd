extends CharacterBody3D

signal health_changed(current_health: float, maximum_health: float)
signal eliminated
signal respawned

@export_category("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var acceleration: float = 20.0
@export var jump_velocity: float = 4.5

@export_category("Camera")
@export var mouse_sensitivity: float = 0.0025
@export var controller_look_speed: float = 2.2
@export var controller_look_deadzone: float = 0.2
@export var camera_height: float = 1.45
@export var camera_distance: float = 3.2
@export var camera_shoulder_offset: float = 0.65
@export var shoulder_swap_action: StringName = &"swap_shoulder"
@export_range(1.0, 20.0, 0.5) var shoulder_swap_smoothing: float = 8.0
@export var camera_focus_distance: float = 12.0
@export var aim_action: StringName = &"aim"
@export_range(35.0, 75.0, 1.0) var aim_camera_fov: float = 66.0
@export_range(1.0, 120.0, 1.0) var aim_zoom_speed: float = 45.0
@export var visual_yaw_offset_degrees: float = 180.0
@export var min_camera_pitch_degrees: float = -50.0
@export var max_camera_pitch_degrees: float = 35.0
@export var starting_weapon: WeaponDefinition = preload("res://assets/weapons/prototype_rifle.tres")
@export var alternate_weapon: WeaponDefinition = preload("res://assets/weapons/standard_pistol.tres")
@export var replicated_animation_state: StringName = &"idle"
@export var replicated_camera_pitch: float = 0.0
@export_range(0, 1, 1) var replicated_weapon_index: int = 0

@export_category("Health")
@export_range(1.0, 1000.0, 1.0) var maximum_health: float = 100.0
@export_range(0.1, 30.0, 0.1) var respawn_delay: float = 3.0

@export_category("Crouch")
@export var crouch_action: StringName = &"crouch"
@export var crouch_speed: float = 2.5
@export var crouched_camera_height: float = 1.05
@export var crouched_collider_height: float = 1.2
@export var camera_height_transition_speed: float = 8.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var player_visuals: Node3D = $PlaceholderVisuals
@onready var player_collider: CollisionShape3D = $PlayerCollider
@onready var gun_socket: Node3D = $PlaceholderVisuals.find_child("GunSocket", true, false) as Node3D

var _camera_pitch: float = 0.0
var _is_local_player: bool = false
var _camera_shoulder_side: float = 1.0
var _default_camera_fov: float = 75.0
var _is_aiming: bool = false
var _crosshair: Control
var _animation_player: AnimationPlayer
var _animation_tree: AnimationTree
var _holding_animation_node: AnimationNodeAnimation
var _locomotion_playback: AnimationNodeStateMachinePlayback
var _current_animation: StringName = &""
var _weapon_controller: WeaponController
var _pause_options_menu: OptionsMenuController
var current_health: float = 100.0
var is_eliminated: bool = false
var is_crouching: bool = false
var _spawn_transform: Transform3D
var _capsule_shape: CapsuleShape3D
var _standing_collider_height: float = 1.9
var _collider_bottom: float = -0.05
var _crouch_transitioning: bool = false
var _crouch_transition_entering: bool = false
var _crouch_transition_elapsed: float = 0.0
var _crouch_transition_duration: float = 0.0

const WEAPON_CONTROLLER_SCRIPT = preload("res://scripts/weapon_controller.gd")
const PAUSE_OPTIONS_SCENE: PackedScene = preload("res://scenes/menu/options_menu.tscn")

const ANIMATION_LIBRARIES := {
	"walking_placeholder": "res://assets/animations/walking_placeholder.fbx",
	"running_placeholder": "res://assets/animations/running_placeholder.fbx",
	"jumping_placeholder": "res://assets/animations/jumping_placeholder.fbx",
	"crouching_to_standing": "res://assets/animations/crouching_to_standing.fbx",
	"crouch_walking_placeholder": "res://assets/animations/crouch_walking_placeholder.fbx",
	"idle_crouching_placeholder": "res://assets/animations/idle_crouching_placeholder.fbx",
	"rifle_holding_placeholder": "res://assets/animations/rifle_holding_placeholder.fbx",
}
const IDLE_ANIMATION: StringName = &"mixamo_com"
const WALKING_ANIMATION: StringName = &"walking_placeholder/mixamo_com"
const RUNNING_ANIMATION: StringName = &"running_placeholder/mixamo_com"
const JUMP_ANIMATION: StringName = &"jumping_placeholder/mixamo_com"
const CROUCH_TRANSITION_ANIMATION: StringName = &"crouching_to_standing/mixamo_com"
const CROUCH_WALK_ANIMATION: StringName = &"crouch_walking_placeholder/mixamo_com"
const CROUCH_IDLE_ANIMATION: StringName = &"idle_crouching_placeholder/mixamo_com"
const IDLE_STATE: StringName = &"idle"
const WALK_STATE: StringName = &"walking"
const RUN_STATE: StringName = &"running"
const JUMP_STATE: StringName = &"jumping"
const CROUCH_ENTER_STATE: StringName = &"crouch_enter"
const CROUCH_IDLE_STATE: StringName = &"crouch_idle"
const CROUCH_WALK_STATE: StringName = &"crouch_walking"
const STAND_UP_STATE: StringName = &"stand_up"
const ROOT_YAW_PRESERVE_ANIMATIONS := {
	"crouching_to_standing/mixamo_com": true,
	"crouch_walking_placeholder/mixamo_com": true,
	"idle_crouching_placeholder/mixamo_com": true,
}


func _ready() -> void:
	_is_local_player = is_multiplayer_authority()
	if _is_local_player:
		add_to_group("local_player")
	_spawn_transform = global_transform
	current_health = maximum_health
	health_changed.emit(current_health, maximum_health)
	camera_pivot.position.y = camera_height
	camera.position = Vector3(camera_shoulder_offset, 0.0, camera_distance)
	var focus_point := camera_pivot.global_position - camera_pivot.global_basis.z * camera_focus_distance
	camera.look_at(focus_point, Vector3.UP)
	camera.current = _is_local_player
	_default_camera_fov = camera.fov
	player_visuals.rotation.y = deg_to_rad(visual_yaw_offset_degrees)
	if _is_local_player:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_setup_animations()
	_setup_crouch()
	_setup_weapon()
	if not _is_local_player and _weapon_controller != null:
		_weapon_controller.set_process(false)
	if _is_local_player:
		call_deferred("_connect_hud")


func _process(delta: float) -> void:
	if not _is_local_player:
		camera_pivot.rotation.x = replicated_camera_pitch
		if replicated_animation_state != _current_animation:
			_play_animation(replicated_animation_state)
		if _weapon_controller != null and replicated_weapon_index != _weapon_controller.active_weapon_index:
			_weapon_controller.set_replicated_weapon_index(replicated_weapon_index)
		return
	if InputMap.has_action(shoulder_swap_action) and Input.is_action_just_pressed(shoulder_swap_action):
		_camera_shoulder_side *= -1.0

	var target_shoulder_offset := camera_shoulder_offset * _camera_shoulder_side
	var smoothing_weight := 1.0 - exp(-shoulder_swap_smoothing * delta)
	camera.position.x = lerpf(camera.position.x, target_shoulder_offset, smoothing_weight)

	_is_aiming = InputMap.has_action(aim_action) and Input.is_action_pressed(aim_action)
	var target_fov := aim_camera_fov if _is_aiming else _default_camera_fov
	camera.fov = move_toward(camera.fov, target_fov, aim_zoom_speed * delta)

	if _crosshair != null:
		_crosshair.call("set_aiming", _is_aiming)
		var horizontal_speed := Vector2(velocity.x, velocity.z).length()
		var maximum_gap := float(_crosshair.get("movement_gap"))
		var movement_amount := clampf(horizontal_speed / maxf(sprint_speed, 0.01), 0.0, 1.0)
		_crosshair.call("set_movement_gap", maximum_gap * movement_amount)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_local_player:
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_open_pause_options()
		return
	if is_eliminated:
		return

	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity_multiplier := GameSettings.mouse_sensitivity_multiplier
		rotate_y(-event.relative.x * mouse_sensitivity * sensitivity_multiplier)
		_camera_pitch = clamp(
			_camera_pitch - event.relative.y * mouse_sensitivity * sensitivity_multiplier,
			deg_to_rad(min_camera_pitch_degrees),
			deg_to_rad(max_camera_pitch_degrees)
		)
		camera_pivot.rotation.x = _camera_pitch
		replicated_camera_pitch = _camera_pitch


func _physics_process(delta: float) -> void:
	if not _is_local_player:
		return

	_update_crouch_input()
	_update_crouch_transition(delta)

	var input_2d := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	var input_direction := Vector3(input_2d.x, 0.0, input_2d.y)
	var move_direction := (global_basis * input_direction).normalized()
	var target_speed := crouch_speed if is_crouching else (
		sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	)
	var target_velocity := move_direction * target_speed

	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	var just_jumped := false
	if not is_on_floor():
		velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity")) * delta
	elif Input.is_action_just_pressed("jump") and not is_crouching and not _crouch_transitioning:
		velocity.y = jump_velocity
		just_jumped = true

	move_and_slide()
	_update_animation(just_jumped)
	_update_controller_look(delta)


func _setup_animations() -> void:
	_animation_player = $PlaceholderVisuals.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation_player == null:
		push_warning("Player model has no AnimationPlayer; locomotion animations are disabled.")
		return

	for library_name in ANIMATION_LIBRARIES:
		if _animation_player.has_animation_library(library_name):
			continue

		var animation_library := load(ANIMATION_LIBRARIES[library_name]) as AnimationLibrary
		if animation_library == null:
			push_warning("Could not load animation library: %s" % ANIMATION_LIBRARIES[library_name])
			continue

		var error := _animation_player.add_animation_library(library_name, animation_library)
		if error != OK:
			push_warning("Could not add animation library '%s'. Error: %s" % [library_name, error])

	_setup_animation_tree()


func _find_player_skeleton() -> Skeleton3D:
	if player_visuals == null:
		return null
	var skeletons := player_visuals.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return null
	return skeletons[0] as Skeleton3D


func _setup_animation_tree() -> void:
	_animation_tree = $PlaceholderVisuals.find_child("AnimationTree", true, false) as AnimationTree
	if _animation_tree == null:
		push_warning("Player model has no AnimationTree; locomotion animations are disabled.")
		return

	_animation_tree.active = true
	var animation_blend_tree := _animation_tree.tree_root as AnimationNodeBlendTree
	if animation_blend_tree != null:
		var holding_node_name: StringName = &"RifleHolding"
		if not animation_blend_tree.get_node_list().has(holding_node_name):
			holding_node_name = &"Animation 2"
		if animation_blend_tree.get_node_list().has(holding_node_name):
			_holding_animation_node = animation_blend_tree.get_node(holding_node_name) as AnimationNodeAnimation
	_locomotion_playback = _animation_tree.get("parameters/Locomotion/playback") as AnimationNodeStateMachinePlayback
	if _locomotion_playback == null:
		push_warning("AnimationTree is missing the Locomotion state machine playback parameter.")
		return

	_animation_tree.active = false
	_neutralize_root_rotation_in_all_animations()
	_configure_crouch_crossfades()

	_set_animation_loop(IDLE_ANIMATION, Animation.LOOP_LINEAR)
	_set_animation_loop(WALKING_ANIMATION, Animation.LOOP_LINEAR)
	_set_animation_loop(RUNNING_ANIMATION, Animation.LOOP_LINEAR)
	_set_animation_loop(JUMP_ANIMATION, Animation.LOOP_NONE)
	_set_animation_loop(CROUCH_TRANSITION_ANIMATION, Animation.LOOP_NONE)
	_set_animation_loop(CROUCH_WALK_ANIMATION, Animation.LOOP_LINEAR)
	_set_animation_loop(CROUCH_IDLE_ANIMATION, Animation.LOOP_LINEAR)
	_animation_tree.clear_caches()
	_animation_tree.active = true
	_play_animation(IDLE_STATE)


func _setup_crouch() -> void:
	_capsule_shape = player_collider.shape as CapsuleShape3D
	if _capsule_shape == null:
		push_warning("Crouch requires PlayerCollider to use a CapsuleShape3D.")
		return

	# Keep this player's collider independent when the player scene is instanced more than once.
	_capsule_shape = _capsule_shape.duplicate() as CapsuleShape3D
	player_collider.shape = _capsule_shape
	_standing_collider_height = _capsule_shape.height
	_collider_bottom = player_collider.position.y - _standing_collider_height * 0.5
	crouched_collider_height = clampf(
		crouched_collider_height,
		_capsule_shape.radius * 2.0,
		_standing_collider_height
	)


func _update_crouch_input() -> void:
	if _capsule_shape == null or not InputMap.has_action(crouch_action):
		return
	if _crouch_transitioning or not is_on_floor():
		return

	var wants_to_crouch := Input.is_action_pressed(crouch_action)
	if wants_to_crouch == is_crouching:
		return
	if not wants_to_crouch and not _can_stand_up():
		return

	is_crouching = wants_to_crouch
	var transition := _animation_player.get_animation(CROUCH_TRANSITION_ANIMATION)
	if _locomotion_playback == null or transition == null:
		return

	_crouch_transitioning = true
	_crouch_transition_entering = is_crouching
	_crouch_transition_elapsed = 0.0
	_crouch_transition_duration = maxf(transition.length, 0.01)
	_play_animation(CROUCH_ENTER_STATE if is_crouching else STAND_UP_STATE)


func _update_crouch_transition(delta: float) -> void:
	if _capsule_shape == null:
		return

	if _crouch_transitioning:
		_crouch_transition_elapsed = minf(
			_crouch_transition_elapsed + delta,
			_crouch_transition_duration
		)
		var progress := _crouch_transition_elapsed / _crouch_transition_duration
		var crouch_fraction := progress if _crouch_transition_entering else 1.0 - progress
		_apply_crouch_fraction(crouch_fraction)
		if is_equal_approx(_crouch_transition_elapsed, _crouch_transition_duration):
			_crouch_transitioning = false
			_apply_crouch_fraction(1.0 if is_crouching else 0.0)
		return

	var target_fraction := 1.0 if is_crouching else 0.0
	var current_fraction := inverse_lerp(
		_standing_collider_height,
		crouched_collider_height,
		_capsule_shape.height
	)
	var next_fraction := move_toward(
		current_fraction,
		target_fraction,
		camera_height_transition_speed * delta
	)
	_apply_crouch_fraction(next_fraction)


func _apply_crouch_fraction(crouch_fraction: float) -> void:
	if _capsule_shape == null:
		return
	var target_height := lerpf(_standing_collider_height, crouched_collider_height, crouch_fraction)
	_capsule_shape.height = target_height
	player_collider.position.y = _collider_bottom + target_height * 0.5
	camera_pivot.position.y = lerpf(camera_height, crouched_camera_height, crouch_fraction)


func _can_stand_up() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var standing_shape := _capsule_shape.duplicate() as CapsuleShape3D
	standing_shape.height = _standing_collider_height
	query.shape = standing_shape
	query.transform = player_collider.global_transform
	query.transform.origin += Vector3.UP * (
		(_standing_collider_height - _capsule_shape.height) * 0.5 + 0.08
	)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 8).is_empty()


func _setup_weapon() -> void:
	if starting_weapon == null:
		return
	if gun_socket == null:
		push_warning("PlaceholderVisuals has no GunSocket; weapon visuals cannot be attached.")
	else:
		var skeleton := _find_player_skeleton()
		if skeleton != null:
			var right_hand_index := skeleton.find_bone(&"mixamorig_RightHand")
			if right_hand_index < 0:
				right_hand_index = skeleton.find_bone(&"RightHand")
			if right_hand_index >= 0 and gun_socket is BoneAttachment3D:
				(gun_socket as BoneAttachment3D).bone_idx = right_hand_index

	_weapon_controller = WEAPON_CONTROLLER_SCRIPT.new() as WeaponController
	_weapon_controller.name = "WeaponController"
	_weapon_controller.configure(starting_weapon, camera, self, alternate_weapon)
	_weapon_controller.weapon_changed.connect(_on_weapon_changed)
	add_child(_weapon_controller)
	_apply_weapon_presentation(starting_weapon)


func _on_weapon_changed(weapon_definition: WeaponDefinition) -> void:
	if _weapon_controller != null:
		replicated_weapon_index = _weapon_controller.active_weapon_index
	_apply_weapon_presentation(weapon_definition)


func _apply_weapon_presentation(weapon_definition: WeaponDefinition) -> void:
	if weapon_definition == null:
		return
	if gun_socket == null:
		return

	var selected_visual_found := false
	for child in gun_socket.get_children():
		if child is Node3D:
			var is_selected_visual := child.name == weapon_definition.visual_node_name
			child.visible = is_selected_visual
			selected_visual_found = selected_visual_found or is_selected_visual

	if not selected_visual_found:
		push_warning("No weapon visual named '%s' found under GunSocket." % weapon_definition.visual_node_name)

	if _holding_animation_node != null and not weapon_definition.holding_animation.is_empty():
		_holding_animation_node.animation = weapon_definition.holding_animation
		_animation_tree.clear_caches()


func take_damage(amount: float, _attacker: Node = null) -> void:
	if is_eliminated or amount <= 0.0:
		return

	current_health = maxf(current_health - amount, 0.0)
	health_changed.emit(current_health, maximum_health)
	if current_health <= 0.0:
		_eliminate_and_respawn()


func _eliminate_and_respawn() -> void:
	is_eliminated = true
	eliminated.emit()
	velocity = Vector3.ZERO
	visible = false
	player_collider.set_deferred("disabled", true)
	set_process(false)
	set_physics_process(false)
	if _animation_tree != null:
		_animation_tree.active = false
	if _weapon_controller != null:
		_weapon_controller.set_process(false)

	await get_tree().create_timer(respawn_delay).timeout
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	_camera_pitch = 0.0
	camera_pivot.rotation = Vector3.ZERO
	camera_pivot.position.y = camera_height
	camera.fov = _default_camera_fov
	_is_aiming = false
	is_crouching = false
	_crouch_transitioning = false
	if _capsule_shape != null:
		_capsule_shape.height = _standing_collider_height
		player_collider.position.y = _collider_bottom + _standing_collider_height * 0.5
	current_health = maximum_health
	player_collider.set_deferred("disabled", false)
	visible = true
	_current_animation = &""
	if _animation_tree != null:
		_animation_tree.active = true
	_play_animation(IDLE_STATE)
	if _weapon_controller != null:
		_weapon_controller.reset_for_respawn()
		_weapon_controller.set_process(true)
	set_process(true)
	set_physics_process(true)
	is_eliminated = false
	health_changed.emit(current_health, maximum_health)
	respawned.emit()


func _connect_hud() -> void:
	if not _is_local_player:
		return
	_crosshair = get_tree().get_first_node_in_group("hud_crosshair") as Control
	if _crosshair == null:
		return

	_crosshair.call("set_aiming", _is_aiming)
	if _weapon_controller != null:
		_weapon_controller.shot_fired.connect(_on_weapon_shot_fired)


func _on_weapon_shot_fired(_hit_position: Vector3, _hit_target: Node) -> void:
	if _crosshair != null:
		_crosshair.call("add_shot_bloom")


func _update_animation(just_jumped: bool) -> void:
	if _locomotion_playback == null:
		return

	if just_jumped:
		_play_animation(JUMP_STATE)
		return
	if _crouch_transitioning:
		return

	if not is_on_floor():
		_play_animation(JUMP_STATE)
		return

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if is_crouching:
		if horizontal_speed < 0.15:
			_play_animation(CROUCH_IDLE_STATE)
			return

		_play_animation(CROUCH_WALK_STATE)
		return

	if horizontal_speed < 0.15:
		_play_animation(IDLE_STATE)
	elif Input.is_action_pressed("sprint"):
		_play_animation(RUN_STATE)
	else:
		_play_animation(WALK_STATE)


func _set_animation_loop(animation_name: StringName, loop_mode: Animation.LoopMode) -> void:
	if _animation_player == null:
		return
	var animation := _animation_player.get_animation(animation_name)
	if animation != null:
		animation.loop_mode = loop_mode


func _neutralize_root_rotation_in_all_animations() -> void:
	if _animation_player == null:
		return

	var adjusted_count := 0
	for library_name in _animation_player.get_animation_library_list():
		var source_library := _animation_player.get_animation_library(library_name)
		if source_library == null:
			continue

		var library_copy := source_library.duplicate(true) as AnimationLibrary
		var library_changed := false
		for clip_name in source_library.get_animation_list():
			var source_animation := source_library.get_animation(clip_name)
			if source_animation == null:
				continue
			var animation_key := "%s/%s" % [library_name, clip_name]
			if ROOT_YAW_PRESERVE_ANIMATIONS.has(animation_key):
				continue

			var animation_copy := source_animation.duplicate(true) as Animation
			if not _neutralize_root_yaw(animation_copy):
				continue

			library_copy.remove_animation(clip_name)
			var error := library_copy.add_animation(clip_name, animation_copy)
			if error != OK:
				push_warning("Could not replace animation '%s/%s'. Error: %s" % [library_name, clip_name, error])
				continue
			library_changed = true
			adjusted_count += 1

		if not library_changed:
			continue

		# Keep the imported source resources unchanged; only this AnimationPlayer gets adjusted copies.
		_animation_player.remove_animation_library(library_name)
		var error := _animation_player.add_animation_library(library_name, library_copy)
		if error != OK:
			push_warning("Could not install adjusted animation library '%s'. Error: %s" % [library_name, error])

	if adjusted_count == 0:
		push_warning("No mixamorig_Hips rotation tracks were found to neutralize.")


func _neutralize_root_yaw(animation: Animation) -> bool:
	var changed_track := false
	for track_index in range(animation.get_track_count() - 1, -1, -1):
		var track_path := String(animation.track_get_path(track_index))
		var is_root_rotation_track := (
			animation.track_get_type(track_index) == Animation.TYPE_ROTATION_3D
			and (track_path.ends_with(":mixamorig_Hips") or track_path.ends_with(":Hips"))
		)
		if not is_root_rotation_track:
			continue

		for key_index in range(animation.track_get_key_count(track_index)):
			var value: Variant = animation.track_get_key_value(track_index, key_index)
			if typeof(value) != TYPE_QUATERNION:
				continue

			var rotation: Quaternion = value
			rotation = rotation.normalized()
			# Strip only the Hips bone's twist around its Y axis. Keep its swing (pitch/roll),
			# which contributes to the animation's posture and was lost when deleting the track.
			var yaw_twist := Quaternion(0.0, rotation.y, 0.0, rotation.w)
			if yaw_twist.length_squared() < 0.000001:
				continue
			yaw_twist = yaw_twist.normalized()
			var posture_rotation := (rotation * yaw_twist.inverse()).normalized()
			animation.track_set_key_value(track_index, key_index, posture_rotation)
			changed_track = true
	return changed_track


func _configure_crouch_crossfades() -> void:
	var blend_tree := _animation_tree.tree_root as AnimationNodeBlendTree
	if blend_tree == null or not blend_tree.has_node(&"Locomotion"):
		return
	var locomotion := blend_tree.get_node(&"Locomotion") as AnimationNodeStateMachine
	if locomotion == null:
		return

	var crossfade_times := {
		"crouch_enter>crouch_idle": 0.2,
		"crouch_enter>crouch_walking": 0.2,
		"crouch_idle>crouch_walking": 0.2,
		"crouch_walking>crouch_idle": 0.2,
		"crouch_idle>stand_up": 0.12,
		"crouch_walking>stand_up": 0.12,
		"stand_up>idle": 0.18,
		"stand_up>walking": 0.18,
		"stand_up>running": 0.18,
	}
	for transition_index in range(locomotion.get_transition_count()):
		var transition := locomotion.get_transition(transition_index)
		transition.xfade_time = 0.15
		var transition_key := "%s>%s" % [
			locomotion.get_transition_from(transition_index),
			locomotion.get_transition_to(transition_index),
		]
		if crossfade_times.has(transition_key):
			transition.xfade_time = crossfade_times[transition_key]


func _play_animation(animation_name: StringName) -> void:
	if _locomotion_playback == null or _current_animation == animation_name:
		return
	_locomotion_playback.travel(animation_name)
	_current_animation = animation_name
	replicated_animation_state = animation_name


func refresh_multiplayer_role() -> void:
	var should_be_local := is_multiplayer_authority()
	if should_be_local == _is_local_player:
		return

	_is_local_player = should_be_local
	if _is_local_player:
		add_to_group("local_player")
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if _weapon_controller != null:
			_weapon_controller.set_process(true)
		call_deferred("_connect_hud")
	else:
		remove_from_group("local_player")
		camera.current = false
		if _weapon_controller != null:
			_weapon_controller.set_process(false)


func set_spawn_transform(spawn_transform: Transform3D) -> void:
	var adjusted_transform := spawn_transform
	var capsule := player_collider.shape as CapsuleShape3D
	if capsule != null:
		# The marker sits on the floor; compensate for the capsule's local vertical offset.
		adjusted_transform.origin.y += capsule.height * 0.5 - player_collider.position.y
	global_transform = adjusted_transform
	_spawn_transform = global_transform


func _open_pause_options() -> void:
	if _pause_options_menu != null:
		return
	var ui_layer := get_tree().current_scene.get_node_or_null("UI") as CanvasLayer
	if ui_layer == null:
		return
	_pause_options_menu = PAUSE_OPTIONS_SCENE.instantiate() as OptionsMenuController
	if _pause_options_menu == null:
		return
	_pause_options_menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	ui_layer.add_child(_pause_options_menu)
	_pause_options_menu.back_requested.connect(_close_pause_options)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_pause_options() -> void:
	get_tree().paused = false
	if _pause_options_menu != null:
		_pause_options_menu.queue_free()
		_pause_options_menu = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _update_controller_look(delta: float) -> void:
	var look_input := Input.get_vector(
		"look_left",
		"look_right",
		"look_up",
		"look_down",
		controller_look_deadzone
	)
	if look_input.is_zero_approx():
		return

	rotate_y(-look_input.x * controller_look_speed * delta)
	_camera_pitch = clamp(
		_camera_pitch - look_input.y * controller_look_speed * delta,
		deg_to_rad(min_camera_pitch_degrees),
		deg_to_rad(max_camera_pitch_degrees)
	)
	camera_pivot.rotation.x = _camera_pitch
	replicated_camera_pitch = _camera_pitch
