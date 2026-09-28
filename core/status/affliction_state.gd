class_name AfflictionState
extends RefCounted

var id: StringName = &""
var active: bool = false
var severity: float = 0.0
var elapsed_hours: float = 0.0
var recovery_progress: float = 0.0
var source: StringName = &""


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"active": active,
		"severity": severity,
		"elapsed_hours": elapsed_hours,
		"recovery_progress": recovery_progress,
		"source": String(source),
	}


static func from_dict(data: Dictionary) -> AfflictionState:
	var state := AfflictionState.new()
	state.id = StringName(data.get("id", ""))
	state.active = bool(data.get("active", false))
	state.severity = maxf(float(data.get("severity", 0.0)), 0.0)
	state.elapsed_hours = maxf(float(data.get("elapsed_hours", 0.0)), 0.0)
	state.recovery_progress = clampf(float(data.get("recovery_progress", 0.0)), 0.0, 1.0)
	state.source = StringName(data.get("source", ""))
	return state
