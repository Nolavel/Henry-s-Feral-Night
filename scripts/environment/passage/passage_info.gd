class_name PassageInfo
extends RefCounted

## One narrow passage in world space: authored by a NarrowPassage or a HingedDoor,
## or guessed from raycasts for unmarked geometry. Henry and the camera read the same data.

## Shoulder the camera keeps while passing.
enum Shoulder { PLAYER, LEFT, RIGHT, CENTRE }

## Group of nodes that author passages; each has get_passage_info() -> PassageInfo.
const GROUP: StringName = &"narrow_passages"

## Door plane centre at floor height.
var center: Vector3 = Vector3.ZERO
## Horizontal unit across the door plane; its sign carries no meaning.
var axis: Vector3 = Vector3.FORWARD
var clear_width: float = 1.5
var clear_height: float = 2.25
var wall_thickness: float = 0.2
var shoulder: int = Shoulder.PLAYER
## Authored camera overrides; zero or below keeps the camera's derived value.
var yaw_limit_deg: float = 0.0
var camera_distance: float = 0.0
var fov_offset_deg: float = -1.0
## False for a raycast guess, whose depth and height are estimates.
var authored: bool = false
## Instance id of the node that authored it; 0 for a guess.
var source_id: int = 0


## Horizontal unit along the door plane, right of `axis`.
func across() -> Vector3:
	return axis.cross(Vector3.UP).normalized()


## Signed horizontal distance of `point` past the door plane along `axis`.
func along_of(point: Vector3) -> float:
	return Vector3(point.x - center.x, 0.0, point.z - center.z).dot(axis)


## Signed horizontal distance of `point` from the centre line along across().
func lateral_of(point: Vector3) -> float:
	return Vector3(point.x - center.x, 0.0, point.z - center.z).dot(across())


func half_depth() -> float:
	return wall_thickness * 0.5


func same_passage(other: PassageInfo) -> bool:
	if other == null:
		return false
	if authored and other.authored:
		return source_id == other.source_id
	return center.distance_to(other.center) < 0.3 and absf(axis.dot(other.axis)) > 0.95
