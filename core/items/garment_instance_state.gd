class_name GarmentInstanceState
extends RefCounted

## Runtime-only state for one physical garment instance.
## Shared GarmentData resources must never be mutated with these values.

var wetness: float = 0.0
var condition: float = 1.0


func _init(initial_wetness: float = 0.0, initial_condition: float = 1.0) -> void:
	wetness = clampf(initial_wetness, 0.0, 1.0)
	condition = clampf(initial_condition, 0.0, 1.0)


func set_wetness(value: float) -> void:
	wetness = clampf(value, 0.0, 1.0)


func add_wetness(amount: float) -> void:
	set_wetness(wetness + amount)


func dry(amount: float) -> void:
	set_wetness(wetness - maxf(amount, 0.0))


func damage(amount: float) -> void:
	condition = clampf(condition - maxf(amount, 0.0), 0.0, 1.0)


func repair(amount: float) -> void:
	condition = clampf(condition + maxf(amount, 0.0), 0.0, 1.0)


func to_dict() -> Dictionary:
	return {
		"wetness": wetness,
		"condition": condition,
	}


static func from_dict(data: Dictionary) -> GarmentInstanceState:
	return GarmentInstanceState.new(
		float(data.get("wetness", 0.0)),
		float(data.get("condition", 1.0))
	)
