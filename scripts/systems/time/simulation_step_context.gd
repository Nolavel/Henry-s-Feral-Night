class_name SimulationStepContext
extends RefCounted

## Immutable description of one deterministic slice of game time.
var start_total_hours: float
var end_total_hours: float
var hours: float
var hour_of_day: float
var day_number: int
var reason: StringName


func _init(start_h: float, end_h: float, why: StringName) -> void:
	start_total_hours = start_h
	end_total_hours = end_h
	hours = maxf(0.0, end_h - start_h)
	hour_of_day = fmod(end_h, 24.0)
	day_number = floori(end_h / 24.0) + 1
	reason = why
