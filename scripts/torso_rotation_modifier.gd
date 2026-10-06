extends SkeletonModifier3D
class_name TorsoRotationModifier

@export var animation_tree_path: NodePath = NodePath("../../AnimationTree")
@export var player_controller_path: NodePath = NodePath("../../..")
@export var torso_bone_name: StringName = &"mixamorig_Spine"
@export_range(-45.0, 45.0, 0.5) var correction_degrees: float = 10.0
@export_range(0.0, 1.0, 0.05) var aim_pitch_influence: float = 0.35
@export_range(0.0, 45.0, 1.0) var max_aim_pitch_degrees: float = 18.0


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return

	var animation_tree := get_node_or_null(animation_tree_path) as AnimationTree
	if animation_tree == null:
		return

	var bone_index := skeleton.find_bone(torso_bone_name)
	if bone_index < 0 and torso_bone_name == &"mixamorig_Spine":
		bone_index = skeleton.find_bone(&"Chest")
	if bone_index < 0:
		return

	var rifle_blend := clampf(
		float(animation_tree.get("parameters/Blend2/blend_amount")),
		0.0,
		1.0
	)
	var current_rotation := skeleton.get_bone_pose_rotation(bone_index)
	var correction := Quaternion(
		Vector3.UP,
		deg_to_rad(correction_degrees * rifle_blend)
	)
	var aim_pitch := 0.0
	var player_controller := get_node_or_null(player_controller_path)
	if player_controller != null:
		aim_pitch = float(player_controller.get("replicated_camera_pitch"))
	var torso_pitch := clampf(
		-aim_pitch * aim_pitch_influence * rifle_blend,
		-deg_to_rad(max_aim_pitch_degrees),
		deg_to_rad(max_aim_pitch_degrees)
	)
	var aim_pitch_correction := Quaternion(Vector3.RIGHT, torso_pitch)
	skeleton.set_bone_pose_rotation(
		bone_index,
		correction * current_rotation * aim_pitch_correction
	)
