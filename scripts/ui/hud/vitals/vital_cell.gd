class_name VitalCell
extends RefCounted

## One pentagon of the vital cluster: level, threshold state and event motion.

enum Pulse { NONE, DRAIN, REFILL }
enum Severity { NORMAL, WARNING, CRITICAL }

const WARNING_LEVEL: float = 0.50
const CRITICAL_LEVEL: float = 0.10
const MORPH_REST_FRAME: float = 0.0
const MORPH_WARNING_FRAME: float = 3.0
const MORPH_CRITICAL_FRAME: float = 7.0

var id: StringName
## Unit vector from the cluster centre out to this cell.
var direction: Vector2
## Row in the shared HFN icon atlas: hunger, thirst, sleep, cold.
var icon_row: int
var level: float = 1.0
## Extra outward push in pixels, tweened on a drain.
var push: float = 0.0
## Scale over 1.0, tweened on a refill.
var grow: float = 0.0
## Edge flash strength and which colour it uses.
var flash: float = 0.0
var pulse: int = Pulse.NONE
var severity: int = Severity.NORMAL
var critical: bool = false
## Baked atlas frame, tweened only when severity crosses a threshold.
var morph_frame: float = MORPH_REST_FRAME
var tween: Tween
var morph_tween: Tween


func _init(cell_id: StringName, out_direction: Vector2, atlas_row: int) -> void:
	id = cell_id
	direction = out_direction.normalized()
	icon_row = atlas_row


## Records a new level and says how it moved: DRAIN, REFILL or NONE.
func set_level(value: float, threshold: float) -> int:
	var next: float = clampf(value, 0.0, 1.0)
	var moved: int = Pulse.NONE
	if next < level - threshold:
		moved = Pulse.DRAIN
	elif next > level + threshold:
		moved = Pulse.REFILL
	level = next
	severity = severity_for_level(level)
	critical = severity == Severity.CRITICAL
	return moved


func target_morph_frame() -> float:
	match severity:
		Severity.WARNING:
			return MORPH_WARNING_FRAME
		Severity.CRITICAL:
			return MORPH_CRITICAL_FRAME
		_:
			return MORPH_REST_FRAME


static func severity_for_level(value: float) -> int:
	if value < CRITICAL_LEVEL:
		return Severity.CRITICAL
	if value < WARNING_LEVEL:
		return Severity.WARNING
	return Severity.NORMAL


## Pentagon with its tip at the origin, the base away from it, in cell space.
static func pentagon(width: float, height: float, tip: float) -> PackedVector2Array:
	var half: float = width * 0.5
	return PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(half, -tip),
		Vector2(half, -height),
		Vector2(-half, -height),
		Vector2(-half, -tip),
	])
