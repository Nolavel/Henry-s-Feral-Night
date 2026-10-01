class_name NarrowPassage
extends Node3D

## Authored doorway or short gap for Henry's traversal and the camera. Origin on the
## floor in the middle of the opening; local Z points across the wall.

@export var clear_width: float = 1.5
@export var clear_height: float = 2.25
@export var wall_thickness: float = 0.2
## Shoulder the camera keeps while passing: the player's choice, or a forced side.
@export_enum("Player", "Left", "Right", "Centre") var shoulder: int = 0
## Optional camera overrides; zero or below derives them from the opening.
@export var yaw_limit_deg: float = 0.0
@export var camera_distance: float = 0.0
@export var fov_offset_deg: float = -1.0


func _ready() -> void:
	add_to_group(PassageInfo.GROUP)


func get_passage_info() -> PassageInfo:
	var info := PassageInfo.new()
	info.center = global_position
	var axis: Vector3 = global_basis.z
	axis.y = 0.0
	info.axis = axis.normalized() if axis.length_squared() > 1e-6 else Vector3.FORWARD
	info.clear_width = clear_width
	info.clear_height = clear_height
	info.wall_thickness = wall_thickness
	info.shoulder = shoulder
	info.yaw_limit_deg = yaw_limit_deg
	info.camera_distance = camera_distance
	info.fov_offset_deg = fov_offset_deg
	info.authored = true
	info.source_id = get_instance_id()
	return info
