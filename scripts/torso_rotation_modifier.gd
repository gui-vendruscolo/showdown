extends SkeletonModifier3D
class_name TorsoRotationModifier

@export var animation_tree_path: NodePath = NodePath("../../AnimationTree")
@export var torso_bone_name: StringName = &"mixamorig_Spine1"
@export_range(-45.0, 45.0, 0.5) var correction_degrees: float = 10.0


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return

	var animation_tree := get_node_or_null(animation_tree_path) as AnimationTree
	if animation_tree == null:
		return

	var bone_index := skeleton.find_bone(torso_bone_name)
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
	skeleton.set_bone_pose_rotation(bone_index, current_rotation * correction)
