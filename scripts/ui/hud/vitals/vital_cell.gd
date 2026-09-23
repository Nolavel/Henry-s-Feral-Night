class_name VitalCell
extends RefCounted

## One pentagon of the vital cluster: level, the drain/refill pulse state and
## its geometry, pointing at the cluster centre along `direction`.

enum Pulse { NONE, DRAIN, REFILL }

## Share of the cell below which the vital reads as critical.
const CRITICAL_LEVEL: float = 0.15

var id: StringName
## Unit vector from the cluster centre out to this cell.
var direction: Vector2
var icon: Texture2D
var level: float = 1.0
## Extra outward push in pixels, tweened on a drain.
var push: float = 0.0
## Scale over 1.0, tweened on a refill.
var grow: float = 0.0
## Edge flash strength and which colour it uses.
var flash: float = 0.0
var pulse: int = Pulse.NONE
var critical: bool = false
var tween: Tween


func _init(cell_id: StringName, out_direction: Vector2, cell_icon: Texture2D) -> void:
	id = cell_id
	direction = out_direction.normalized()
	icon = cell_icon


## Records a new level and says how it moved: DRAIN, REFILL or NONE.
func set_level(value: float, threshold: float) -> int:
	var next: float = clampf(value, 0.0, 1.0)
	var moved: int = Pulse.NONE
	if next < level - threshold:
		moved = Pulse.DRAIN
	elif next > level + threshold:
		moved = Pulse.REFILL
	level = next
	critical = level < CRITICAL_LEVEL
	return moved


## Pentagon with its tip at the origin, the base away from it, in cell space
## where "out" is -Y; rotated into place by the cluster.
static func pentagon(width: float, height: float, tip: float) -> PackedVector2Array:
	var half: float = width * 0.5
	return PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(half, -tip),
		Vector2(half, -height),
		Vector2(-half, -height),
		Vector2(-half, -tip),
	])
