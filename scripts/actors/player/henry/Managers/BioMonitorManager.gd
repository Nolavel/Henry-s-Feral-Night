class_name BioMonitorManager
extends Node3D

## Compatibility facade and save adapter for Henry's three metabolic components.
## State lives in HungerComponent, HydrationComponent and FatigueComponent.

signal hunger_level_changed(progress: float)
signal critical_hunger_reached
signal not_critical_hunger

signal thirst_level_changed(progress: float)
signal critical_dehydration_reached
signal dehydration_recovered

signal energy_level_changed(progress: float)
signal critical_exhaustion_reached
signal exhaustion_recovered

@export_group("Initial Values")
@export var initial_hunger_percent: float = 100.0
@export var initial_thirst_percent: float = 100.0
@export var initial_energy_percent: float = 100.0

@export_group("Maximum Values")
@export var max_calories: float = 2500.0
@export var max_hydration: float = 100.0
@export var max_energy: float = 100.0

@export_group("Hourly Consumption")
@export var base_metabolism_rate: float = 100.0
@export var base_thirst_rate: float = 5.0
@export var base_energy_rate: float = 7.0

@export_group("Critical Thresholds")
@export var critical_hunger_threshold: float = 0.0
@export var critical_thirst_threshold: float = 10.0
@export var critical_energy_threshold: float = 10.0

@export_group("Sleep")
@export var energy_restored_per_hour: float = 12.5
@export_range(0.0, 1.0) var sleep_metabolism_factor: float = 0.65
@export_range(0.0, 1.0) var sleep_thirst_factor: float = 0.5
@export_range(0.0, 1.0) var minimum_rest_quality: float = 0.25

@export_group("Carry")
@export var carry_fatigue_factor: float = 0.6
@export var carry_inventory: InventoryComponent

var _hunger: HungerComponent
var _hydration: HydrationComponent
var _fatigue: FatigueComponent
var _configured: bool = false


## Legacy state properties remain source-compatible while delegating storage.
var current_calories: float:
	get:
		_ensure_components()
		return _hunger.current_calories
	set(value):
		_ensure_components()
		_hunger.set_current(value)


var current_hydration: float:
	get:
		_ensure_components()
		return _hydration.current_hydration
	set(value):
		_ensure_components()
		_hydration.set_current(value)


var current_energy: float:
	get:
		_ensure_components()
		return _fatigue.current_energy
	set(value):
		_ensure_components()
		_fatigue.set_current(value)


var previous_calories: float:
	get:
		_ensure_components()
		return _hunger.previous_calories
	set(value):
		_ensure_components()
		_hunger.previous_calories = value


var previous_hydration: float:
	get:
		_ensure_components()
		return _hydration.previous_hydration
	set(value):
		_ensure_components()
		_hydration.previous_hydration = value


var previous_energy: float:
	get:
		_ensure_components()
		return _fatigue.previous_energy
	set(value):
		_ensure_components()
		_fatigue.previous_energy = value


var is_currently_critically_hungry: bool:
	get:
		_ensure_components()
		return _hunger.is_critical
	set(value):
		_ensure_components()
		_hunger.is_critical = value


var is_currently_critically_thirsty: bool:
	get:
		_ensure_components()
		return _hydration.is_critical
	set(value):
		_ensure_components()
		_hydration.is_critical = value


var is_currently_critically_tired: bool:
	get:
		_ensure_components()
		return _fatigue.is_critical
	set(value):
		_ensure_components()
		_fatigue.is_critical = value


var has_recently_eaten: bool:
	get:
		_ensure_components()
		return _hunger.recently_replenished
	set(value):
		_ensure_components()
		_hunger.recently_replenished = value


var has_recently_drunk: bool:
	get:
		_ensure_components()
		return _hydration.recently_replenished
	set(value):
		_ensure_components()
		_hydration.recently_replenished = value


var has_recently_rested: bool:
	get:
		_ensure_components()
		return _fatigue.recently_replenished
	set(value):
		_ensure_components()
		_fatigue.recently_replenished = value


func _ready() -> void:
	_ensure_components()
	_configure_components()
	_connect_component_signals()
	call_deferred(&"emit_initial_progress")


func _ensure_components() -> void:
	if _hunger != null and _hydration != null and _fatigue != null:
		return
	var host: Node = get_parent()
	if host != null:
		_hunger = host.get_node_or_null(^"HungerComponent") as HungerComponent
		_hydration = host.get_node_or_null(^"HydrationComponent") as HydrationComponent
		_fatigue = host.get_node_or_null(^"FatigueComponent") as FatigueComponent
	if _hunger == null:
		_hunger = HungerComponent.new()
		_hunger.name = "HungerComponent"
		add_child(_hunger)
	if _hydration == null:
		_hydration = HydrationComponent.new()
		_hydration.name = "HydrationComponent"
		add_child(_hydration)
	if _fatigue == null:
		_fatigue = FatigueComponent.new()
		_fatigue.name = "FatigueComponent"
		add_child(_fatigue)


func _configure_components() -> void:
	if _configured:
		return
	_configured = true
	_hunger.configure(max_calories, initial_hunger_percent, base_metabolism_rate, critical_hunger_threshold)
	_hydration.configure(max_hydration, initial_thirst_percent, base_thirst_rate, critical_thirst_threshold)
	_fatigue.configure(
		max_energy,
		initial_energy_percent,
		base_energy_rate,
		critical_energy_threshold,
		energy_restored_per_hour,
		carry_fatigue_factor,
		carry_inventory
	)


func _connect_component_signals() -> void:
	if not _hunger.level_changed.is_connected(_on_hunger_level_changed):
		_hunger.level_changed.connect(_on_hunger_level_changed)
		_hunger.critical_reached.connect(_on_hunger_critical)
		_hunger.recovered.connect(_on_hunger_recovered)
	if not _hydration.level_changed.is_connected(_on_hydration_level_changed):
		_hydration.level_changed.connect(_on_hydration_level_changed)
		_hydration.critical_reached.connect(_on_hydration_critical)
		_hydration.recovered.connect(_on_hydration_recovered)
	if not _fatigue.level_changed.is_connected(_on_fatigue_level_changed):
		_fatigue.level_changed.connect(_on_fatigue_level_changed)
		_fatigue.critical_reached.connect(_on_fatigue_critical)
		_fatigue.recovered.connect(_on_fatigue_recovered)


func get_hunger_component() -> HungerComponent:
	_ensure_components()
	return _hunger


func get_hydration_component() -> HydrationComponent:
	_ensure_components()
	return _hydration


func get_fatigue_component() -> FatigueComponent:
	_ensure_components()
	return _fatigue


func emit_initial_progress() -> void:
	update_ui_signals()
	check_critical_states()


func get_simulation_priority() -> int:
	return 400


func advance_simulation(hours: float, context: SimulationStepContext) -> void:
	if hours <= 0.0:
		return
	if floori(context.end_total_hours) > floori(context.start_total_hours):
		_reset_recent()
	if context.reason == &"sleep":
		rest_sleep(hours)
	else:
		pass_awake_hours(hours)


## Mutates the three tracks once; UI/threshold emission is deliberately separate.
func process_hourly_consumption(fraction: float = 1.0) -> void:
	_ensure_components()
	_sync_runtime_dependencies()
	var hours: float = maxf(fraction, 0.0)
	var hunger_rate: float = apply_hunger_modifiers(base_metabolism_rate)
	var thirst_rate: float = apply_thirst_modifiers(base_thirst_rate)
	var hunger_multiplier: float = hunger_rate / maxf(base_metabolism_rate, 0.001)
	var thirst_multiplier: float = thirst_rate / maxf(base_thirst_rate, 0.001)
	_hunger.consume(hours, hunger_multiplier)
	_hydration.consume(hours, thirst_multiplier)
	_fatigue.consume(hours)


func update_ui_signals() -> void:
	_ensure_components()
	_hunger.emit_level()
	_hydration.emit_level()
	_fatigue.emit_level()


func check_critical_states() -> void:
	_ensure_components()
	_hunger.refresh_critical()
	_hydration.refresh_critical()
	_fatigue.refresh_critical()


func calculate_hunger_progress() -> float:
	_ensure_components()
	return _hunger.progress()


func calculate_thirst_progress() -> float:
	_ensure_components()
	return _hydration.progress()


func calculate_energy_progress() -> float:
	_ensure_components()
	return _fatigue.progress()


func add_calories(amount: float) -> void:
	_ensure_components()
	_hunger.add(amount)


func add_hydration(amount: float) -> void:
	_ensure_components()
	_hydration.add(amount)


func add_energy(amount: float) -> void:
	_ensure_components()
	_fatigue.add(amount)


func pass_awake_hours(hours: float) -> void:
	if hours <= 0.0:
		return
	process_hourly_consumption(hours)
	update_ui_signals()
	check_critical_states()


func rest_sleep(hours: float) -> void:
	if hours <= 0.0:
		return
	_ensure_components()
	_sync_runtime_dependencies()
	_hunger.consume(hours, sleep_metabolism_factor)
	_hydration.consume(hours, sleep_thirst_factor)
	_fatigue.restore_sleep(hours, get_rest_quality())
	update_ui_signals()
	check_critical_states()


func get_rest_quality() -> float:
	var worst: float = minf(calculate_hunger_progress(), calculate_thirst_progress())
	return clampf(worst * 2.0, minimum_rest_quality, 1.0)


func apply_hunger_modifiers(base_rate: float) -> float:
	return base_rate


func apply_thirst_modifiers(base_rate: float) -> float:
	return base_rate


func apply_energy_modifiers(base_rate: float) -> float:
	_ensure_components()
	_sync_runtime_dependencies()
	return base_rate * _fatigue.get_drain_multiplier()


func get_energy_drain_multiplier() -> float:
	_ensure_components()
	_sync_runtime_dependencies()
	return _fatigue.get_drain_multiplier()


func get_energy_drain_reason() -> StringName:
	_ensure_components()
	_sync_runtime_dependencies()
	return _fatigue.get_drain_reason()


func _carry_load_fraction() -> float:
	_ensure_components()
	_sync_runtime_dependencies()
	return _fatigue.get_load_fraction()


func _sync_runtime_dependencies() -> void:
	if _fatigue == null:
		return
	_fatigue.carry_fatigue_factor = carry_fatigue_factor
	if carry_inventory != null:
		_fatigue.carry_inventory = carry_inventory


func _reset_recent() -> void:
	_hunger.reset_recent()
	_hydration.reset_recent()
	_fatigue.reset_recent()


func is_currently_satiated_from_meal() -> bool:
	return has_recently_eaten


func is_currently_hydrated_from_drink() -> bool:
	return has_recently_drunk


func is_currently_rested_from_sleep() -> bool:
	return has_recently_rested


func get_save_key() -> StringName:
	return &"bio"


func get_save_data() -> Dictionary:
	return {
		"calories": current_calories,
		"hydration": current_hydration,
		"energy": current_energy,
	}


func load_save_data(data: Dictionary) -> void:
	_ensure_components()
	current_calories = float(data.get("calories", current_calories))
	current_hydration = float(data.get("hydration", current_hydration))
	current_energy = float(data.get("energy", current_energy))
	previous_calories = current_calories
	previous_hydration = current_hydration
	previous_energy = current_energy
	update_ui_signals()
	check_critical_states()


func _on_hunger_level_changed(progress: float) -> void:
	hunger_level_changed.emit(progress)


func _on_hunger_critical() -> void:
	critical_hunger_reached.emit()


func _on_hunger_recovered() -> void:
	not_critical_hunger.emit()


func _on_hydration_level_changed(progress: float) -> void:
	thirst_level_changed.emit(progress)


func _on_hydration_critical() -> void:
	critical_dehydration_reached.emit()


func _on_hydration_recovered() -> void:
	dehydration_recovered.emit()


func _on_fatigue_level_changed(progress: float) -> void:
	energy_level_changed.emit(progress)


func _on_fatigue_critical() -> void:
	critical_exhaustion_reached.emit()


func _on_fatigue_recovered() -> void:
	exhaustion_recovered.emit()
