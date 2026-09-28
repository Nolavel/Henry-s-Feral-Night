class_name HungerComponent
extends Node

signal level_changed(progress: float)
signal critical_reached
signal recovered

var max_calories: float = 2500.0
var base_rate_per_hour: float = 100.0
var critical_threshold_percent: float = 0.0
var current_calories: float = 2500.0
var previous_calories: float = 2500.0
var is_critical: bool = false
var recently_replenished: bool = false


func configure(maximum: float, initial_percent: float, hourly_rate: float, critical_percent: float) -> void:
	max_calories = maxf(maximum, 0.001)
	base_rate_per_hour = maxf(hourly_rate, 0.0)
	critical_threshold_percent = clampf(critical_percent, 0.0, 100.0)
	current_calories = clampf(initial_percent / 100.0 * max_calories, 0.0, max_calories)
	previous_calories = current_calories
	is_critical = _critical_now()
	recently_replenished = false


func progress() -> float:
	return clampf(current_calories / max_calories, 0.0, 1.0)


func consume(hours: float, multiplier: float = 1.0) -> void:
	if hours <= 0.0:
		return
	previous_calories = current_calories
	current_calories = maxf(0.0, current_calories - base_rate_per_hour * maxf(multiplier, 0.0) * hours)


func add(amount: float) -> void:
	var was_critical: bool = is_critical
	previous_calories = current_calories
	current_calories = clampf(current_calories + amount, 0.0, max_calories)
	recently_replenished = true
	level_changed.emit(progress())
	_refresh_critical(was_critical)


func set_current(value: float) -> void:
	current_calories = clampf(value, 0.0, max_calories)


func emit_level() -> void:
	level_changed.emit(progress())


func refresh_critical() -> void:
	_refresh_critical(is_critical)


func reset_recent() -> void:
	recently_replenished = false


func _critical_now() -> bool:
	return current_calories <= max_calories * (critical_threshold_percent / 100.0)


func _refresh_critical(old_state: bool) -> void:
	var next: bool = _critical_now()
	is_critical = next
	if next and not old_state:
		critical_reached.emit()
	elif old_state and not next:
		recovered.emit()
