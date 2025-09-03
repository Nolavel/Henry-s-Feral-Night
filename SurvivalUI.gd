# SurvivalUI.gd - Optimized survival needs management system
extends Control

class_name SurvivalUI

# ============================================================================
# SURVIVAL STATS (1.0 = good, 0.0 = critical)
# ============================================================================
@export var health: float = 1.0 : set = set_health
@export var hunger: float = 1.0 : set = set_hunger  
@export var thirst: float = 1.0 : set = set_thirst
@export var sleep: float = 1.0 : set = set_sleep
@export var stamina: float = 1.0 : set = set_stamina

# ============================================================================
# EXPORT GROUPS - Better organization
# ============================================================================
@export_group("Game Time Settings")
@export var day_cycle_duration: float = 24.0  # 24 real minutes = 1 game day
@export var hunger_duration: float = 20.0     # Full hunger lasts 20 minutes
@export var thirst_duration: float = 10.0     # Full thirst lasts 10 minutes

@export_group("Stamina Settings") 
@export var stamina_drain_run: float = 0.25    # Per second while running/sprinting ONLY
@export var stamina_drain_jump: float = 0.1    # Per jump
@export var stamina_regen_rate: float = 0.3    # Per second (recovery rate)
@export var stamina_regen_delay: float = 1.5   # Seconds before regen starts

@export_group("UI Bars")
@export var health_bar: Sprite2D
@export var hunger_bar: Sprite2D  
@export var thirst_bar: Sprite2D
@export var sleep_bar: Sprite2D
@export var stamina_bar: Sprite2D

@export_group("Performance Settings")
@export var critical_check_frequency: float = 2.0    # Check critical states every 2 seconds
@export var ui_update_frequency: float = 10.0        # Update UI bars 10 times per second
@export var status_print_frequency: float = 0.2      # Debug prints every 5 seconds

# ============================================================================
# SIGNALS
# ============================================================================
signal health_changed(current: float, max_val: float)
signal hunger_changed(current: float, max_val: float)
signal thirst_changed(current: float, max_val: float) 
signal sleep_changed(current: float, max_val: float)
signal stamina_changed(current: float, max_val: float)
signal jump_performed()

# Critical state signals
signal health_critical(level: float)
signal hunger_critical(level: float)
signal thirst_critical(level: float)
signal sleep_critical(level: float)
signal stamina_critical(level: float)

# Death/game over conditions
signal player_died(cause: String)
signal needs_warning(need_name: String, level: float)

# ============================================================================
# OPTIMIZED INTERNAL VARIABLES
# ============================================================================
# Cached calculations to avoid repeated math
var _hunger_drain_rate: float
var _thirst_drain_rate: float
var _sleep_drain_rate: float

# Performance timers
var _critical_check_timer: float = 0.0
var _ui_update_timer: float = 0.0
var _status_print_timer: float = 0.0
var _critical_check_interval: float
var _ui_update_interval: float
var _status_print_interval: float

# Stamina tracking (optimized)
var _stamina_regen_timer: float = 0.0
var _game_start_time: float = 0.0
var _last_activity_time: float = 0.0

# Player tracking (cached references)
var player_node: Node = null
var _player_is_moving: bool = false
var _player_is_sprinting: bool = false
var _cached_player_sprint_check: bool = false

# UI optimization flags
var _needs_ui_update: bool = true
var _needs_critical_check: bool = true

# Cached critical state to avoid redundant signals
var _last_critical_states: Dictionary = {
	"health": false,
	"hunger": false,
	"thirst": false,
	"sleep": false,
	"stamina": false
}

# Pre-calculated drain rates (calculated once in _ready)
var _physics_delta_multiplier: float = 1.0

# ============================================================================
# INITIALIZATION
# ============================================================================
func _ready():
	print("SurvivalUI: Initializing optimized survival system...")
	
	# Calculate update intervals
	_critical_check_interval = 1.0 / critical_check_frequency
	_ui_update_interval = 1.0 / ui_update_frequency
	_status_print_interval = 1.0 / status_print_frequency
	
	# Pre-calculate drain rates (performance optimization)
	_precalculate_drain_rates()
	
	# Cache game start time
	_game_start_time = Time.get_time_dict_from_system()["hour"] * 3600.0 + Time.get_time_dict_from_system()["minute"] * 60.0
	
	# Find and cache player node
	_initialize_player_reference()
	
	# Initialize UI
	_force_update_all_bars()
	
	print("SurvivalUI: ✅ Optimized system initialized successfully")

func _precalculate_drain_rates():
	"""Pre-calculate drain rates for better performance"""
	_sleep_drain_rate = 1.0 / (day_cycle_duration * 60.0)    # Per second
	_hunger_drain_rate = 1.0 / (hunger_duration * 60.0)      # Per second  
	_thirst_drain_rate = 1.0 / (thirst_duration * 60.0)      # Per second
	
	print("SurvivalUI: Drain rates calculated - Sleep: %.6f, Hunger: %.6f, Thirst: %.6f" % [_sleep_drain_rate, _hunger_drain_rate, _thirst_drain_rate])

func _initialize_player_reference():
	"""Find and cache player reference"""
	player_node = get_tree().get_first_node_in_group("player")
	if not player_node:
		print("SurvivalUI: Warning - Player node not found! Stamina tracking disabled.")
	else:
		print("SurvivalUI: ✅ Player node found: %s" % player_node.name)

# ============================================================================
# PHYSICS PROCESS - Main update loop moved to physics
# ============================================================================
func _physics_process(delta: float):
	# Core needs updates every physics frame (more consistent)
	_update_time_based_needs_physics(delta)
	_update_stamina_system_physics(delta)
	
	# UI updates with controlled frequency
	_ui_update_timer += delta
	if _ui_update_timer >= _ui_update_interval:
		if _needs_ui_update:
			_update_ui_bars_optimized()
			_needs_ui_update = false
		_ui_update_timer = 0.0
	
	# Critical state checks with lower frequency
	_critical_check_timer += delta
	if _critical_check_timer >= _critical_check_interval:
		_check_critical_states_optimized()
		_critical_check_timer = 0.0
	
	# Debug status (very low frequency)
	_status_print_timer += delta
	if _status_print_timer >= _status_print_interval:
		# Only print if debug mode or player is in critical state
		if OS.is_debug_build() and not get_critical_needs().is_empty():
			_debug_print_critical_only()
		_status_print_timer = 0.0

# ============================================================================
# OPTIMIZED PHYSICS UPDATES
# ============================================================================
func _update_time_based_needs_physics(delta: float):
	"""Physics-based time updates with pre-calculated rates"""
	var old_sleep = sleep
	var old_hunger = hunger
	var old_thirst = thirst
	
	# Apply pre-calculated drain rates
	sleep = max(0.0, sleep - _sleep_drain_rate * delta)
	hunger = max(0.0, hunger - _hunger_drain_rate * delta)
	thirst = max(0.0, thirst - _thirst_drain_rate * delta)
	
	# Only flag UI update if values actually changed significantly
	if abs(sleep - old_sleep) > 0.001 or abs(hunger - old_hunger) > 0.001 or abs(thirst - old_thirst) > 0.001:
		_needs_ui_update = true

func _update_stamina_system_physics(delta: float):
	"""Optimized stamina system with cached player state"""
	if not player_node:
		return
	
	var old_stamina = stamina
	
	# Check player sprint state (cached to reduce method calls)
	var is_sprinting = _get_cached_sprint_state()
	
	# Stamina drain logic
	if is_sprinting:
		stamina = max(0.0, stamina - stamina_drain_run * delta)
		_stamina_regen_timer = 0.0  # Reset regen timer
	else:
		# Regeneration timer
		_stamina_regen_timer += delta
		
		# Regenerate stamina after delay
		if _stamina_regen_timer >= stamina_regen_delay and stamina < 1.0:
			var regen_amount = stamina_regen_rate * delta
			stamina = min(1.0, stamina + regen_amount)
	
	# Flag UI update only if stamina changed significantly
	if abs(stamina - old_stamina) > 0.001:
		_needs_ui_update = true

func _get_cached_sprint_state() -> bool:
	"""Optimized sprint state checking with caching"""
	# Check sprint state less frequently to reduce method calls
	if int(_stamina_regen_timer * 10) % 3 == 0:  # Update every 0.3 seconds
		if player_node.has_method("is_sprinting"):
			_cached_player_sprint_check = player_node.is_sprinting()
		elif player_node.has_method("is_running"):
			_cached_player_sprint_check = player_node.is_running()
		elif "current_sprint_speed" in player_node:  # ✅ ПРАВИЛЬНО:
			_cached_player_sprint_check = player_node.current_sprint_speed > 1.0
		else:
			_cached_player_sprint_check = false
	
	return _cached_player_sprint_check

# ============================================================================
# OPTIMIZED UI UPDATES
# ============================================================================
func _update_ui_bars_optimized():
	"""Update only bars that have changed"""
	# Only update bars if their shaders exist and values changed
	_update_health_bar_optimized()
	_update_hunger_bar_optimized()
	_update_thirst_bar_optimized()
	_update_sleep_bar_optimized()
	_update_stamina_bar_optimized()

func _update_health_bar_optimized():
	if health_bar and health_bar.material:
		health_bar.material.set_shader_parameter("progress", health)

func _update_hunger_bar_optimized():
	if hunger_bar and hunger_bar.material:
		hunger_bar.material.set_shader_parameter("progress", hunger)

func _update_thirst_bar_optimized():
	if thirst_bar and thirst_bar.material:
		thirst_bar.material.set_shader_parameter("progress", thirst)

func _update_sleep_bar_optimized():
	if sleep_bar and sleep_bar.material:
		sleep_bar.material.set_shader_parameter("progress", sleep)

func _update_stamina_bar_optimized():
	if stamina_bar and stamina_bar.material:
		stamina_bar.material.set_shader_parameter("progress", stamina)

# ============================================================================
# OPTIMIZED CRITICAL STATE MONITORING
# ============================================================================
func _check_critical_states_optimized():
	"""Optimized critical state checking with caching"""
	var critical_threshold = 0.2
	var physics_delta = get_physics_process_delta_time()
	
	# Health critical (can cause death)
	if health <= 0.0:
		emit_signal("player_died", "health")
		return  # Exit early if player is dead
	
	var health_critical = health <= critical_threshold
	if health_critical != _last_critical_states.health:
		_last_critical_states.health = health_critical
		if health_critical:
			emit_signal("health_critical", health)
	
	# Hunger critical (affects health over time)
	if hunger <= 0.0:
		health = max(0.0, health - 0.01 * physics_delta)
		_needs_ui_update = true
		emit_signal("needs_warning", "hunger", 0.0)
	else:
		var hunger_critical = hunger <= critical_threshold
		if hunger_critical != _last_critical_states.hunger:
			_last_critical_states.hunger = hunger_critical
			if hunger_critical:
				emit_signal("hunger_critical", hunger)
	
	# Thirst critical (affects health quickly)
	if thirst <= 0.0:
		health = max(0.0, health - 0.02 * physics_delta)
		_needs_ui_update = true
		emit_signal("needs_warning", "thirst", 0.0)
	else:
		var thirst_critical = thirst <= critical_threshold
		if thirst_critical != _last_critical_states.thirst:
			_last_critical_states.thirst = thirst_critical
			if thirst_critical:
				emit_signal("thirst_critical", thirst)
	
	# Sleep critical (affects stamina regeneration)
	var sleep_critical = sleep <= critical_threshold
	if sleep_critical != _last_critical_states.sleep:
		_last_critical_states.sleep = sleep_critical
		if sleep_critical:
			emit_signal("sleep_critical", sleep)
			stamina_regen_rate = 0.05  # Much slower regen when exhausted
		else:
			stamina_regen_rate = 0.3   # Normal regen rate
	
	# Stamina critical
	var stamina_critical = stamina <= critical_threshold
	if stamina_critical != _last_critical_states.stamina:
		_last_critical_states.stamina = stamina_critical
		if stamina_critical:
			emit_signal("stamina_critical", stamina)

# ============================================================================
# SIGNAL HANDLERS (from Player) - Optimized
# ============================================================================
func _on_player_movement_changed(moving_state: bool):
	"""Optimized movement state handler"""
	if _player_is_moving != moving_state:
		_player_is_moving = moving_state
		if not moving_state:
			_stamina_regen_timer = 0.0

func _on_player_jumped():
	"""Optimized jump handler"""
	var old_stamina = stamina
	stamina = max(0.0, stamina - stamina_drain_jump)
	
	if abs(stamina - old_stamina) > 0.001:
		_needs_ui_update = true
		_stamina_regen_timer = 0.0
		jump_performed.emit()

func _on_player_health_changed(health_progress: float, max_val: float):
	"""Optimized health change handler"""
	var old_health = health
	health = health_progress
	
	if abs(health - old_health) > 0.001:
		_needs_ui_update = true

func _on_player_took_damage(amount: float, damage_type: String):
	"""Damage handler with optimization"""
	print("SurvivalUI: Player took %.2f damage (%s)" % [amount, damage_type])

# ============================================================================
# OPTIMIZED SETTERS
# ============================================================================
func set_health(value: float):
	var old_health = health
	health = clamp(value, 0.0, 1.0)
	if abs(health - old_health) > 0.001:
		_needs_ui_update = true
		emit_signal("health_changed", health, 1.0)

func set_hunger(value: float):
	var old_hunger = hunger
	hunger = clamp(value, 0.0, 1.0)
	if abs(hunger - old_hunger) > 0.001:
		_needs_ui_update = true
		emit_signal("hunger_changed", hunger, 1.0)

func set_thirst(value: float):
	var old_thirst = thirst
	thirst = clamp(value, 0.0, 1.0)
	if abs(thirst - old_thirst) > 0.001:
		_needs_ui_update = true
		emit_signal("thirst_changed", thirst, 1.0)

func set_sleep(value: float):
	var old_sleep = sleep
	sleep = clamp(value, 0.0, 1.0)
	if abs(sleep - old_sleep) > 0.001:
		_needs_ui_update = true
		emit_signal("sleep_changed", sleep, 1.0)

func set_stamina(value: float):
	var old_stamina = stamina
	stamina = clamp(value, 0.0, 1.0)
	if abs(stamina - old_stamina) > 0.001:
		_needs_ui_update = true
		emit_signal("stamina_changed", stamina, 1.0)

# ============================================================================
# PUBLIC METHODS - Optimized versions
# ============================================================================
func restore_health(amount: float):
	"""Optimized health restoration"""
	var old_health = health
	health = min(1.0, health + amount)
	if abs(health - old_health) > 0.001:
		print("SurvivalUI: Health restored by %.2f. New health: %.2f" % [amount, health])

func restore_hunger(amount: float):
	"""Optimized hunger restoration"""
	var old_hunger = hunger
	hunger = min(1.0, hunger + amount)
	if abs(hunger - old_hunger) > 0.001:
		print("SurvivalUI: Hunger restored by %.2f. New hunger: %.2f" % [amount, hunger])

func restore_thirst(amount: float):
	"""Optimized thirst restoration"""
	var old_thirst = thirst
	thirst = min(1.0, thirst + amount)
	if abs(thirst - old_thirst) > 0.001:
		print("SurvivalUI: Thirst restored by %.2f. New thirst: %.2f" % [amount, thirst])

func restore_sleep(amount: float):
	"""Optimized sleep restoration"""
	var old_sleep = sleep
	sleep = min(1.0, sleep + amount)
	if abs(sleep - old_sleep) > 0.001:
		print("SurvivalUI: Sleep restored by %.2f. New sleep: %.2f" % [amount, sleep])

func damage_health(amount: float, cause: String = "unknown"):
	"""Optimized health damage"""
	var old_health = health
	health = max(0.0, health - amount)
	
	if abs(health - old_health) > 0.001:
		print("SurvivalUI: Health damaged by %.2f (%s). New health: %.2f" % [amount, cause, health])
		
		if health <= 0.0:
			emit_signal("player_died", cause)

# ============================================================================
# UTILITY METHODS
# ============================================================================
func get_current_needs() -> Dictionary:
	"""Returns current state of all needs (cached)"""
	return {
		"health": health,
		"hunger": hunger, 
		"thirst": thirst,
		"sleep": sleep,
		"stamina": stamina
	}

func get_critical_needs() -> Array:
	"""Optimized critical needs check"""
	var critical_needs = []
	var threshold = 0.2
	
	if health <= threshold: critical_needs.append("health")
	if hunger <= threshold: critical_needs.append("hunger")
	if thirst <= threshold: critical_needs.append("thirst")
	if sleep <= threshold: critical_needs.append("sleep")
	if stamina <= threshold: critical_needs.append("stamina")
	
	return critical_needs

func is_player_alive() -> bool:
	"""Inline check for player alive state"""
	return health > 0.0

# ============================================================================
# LEGACY SUPPORT METHODS
# ============================================================================
func update_all_bars():
	"""Legacy method - forces UI update"""
	_force_update_all_bars()

func _force_update_all_bars():
	"""Force update all UI bars regardless of flags"""
	_update_health_bar_optimized()
	_update_hunger_bar_optimized()
	_update_thirst_bar_optimized()
	_update_sleep_bar_optimized()
	_update_stamina_bar_optimized()

# Individual bar update methods (legacy support)
func update_health_bar(): _update_health_bar_optimized()
func update_hunger_bar(): _update_hunger_bar_optimized()
func update_thirst_bar(): _update_thirst_bar_optimized()
func update_sleep_bar(): _update_sleep_bar_optimized()
func update_stamina_bar(): _update_stamina_bar_optimized()

# ============================================================================
# DEBUG METHODS - Optimized
# ============================================================================
func debug_print_status():
	"""Full status print for debugging"""
	print("=== SURVIVAL STATUS ===")
	print("Health: %.1f%%" % (health * 100))
	print("Hunger: %.1f%%" % (hunger * 100))
	print("Thirst: %.1f%%" % (thirst * 100))
	print("Sleep: %.1f%%" % (sleep * 100))
	print("Stamina: %.1f%%" % (stamina * 100))
	print("Critical needs: ", get_critical_needs())
	print("=======================")

func _debug_print_critical_only():
	"""Print only critical status for performance"""
	var critical = get_critical_needs()
	if not critical.is_empty():
		print("SurvivalUI: CRITICAL - ", critical, " | Health: %.1f%%, Stamina: %.1f%%" % [health * 100, stamina * 100])

# ============================================================================
# PERFORMANCE MONITORING
# ============================================================================
func get_performance_stats() -> Dictionary:
	"""Get performance statistics for debugging"""
	return {
		"ui_update_frequency": ui_update_frequency,
		"critical_check_frequency": critical_check_frequency,
		"cached_sprint_state": _cached_player_sprint_check,
		"needs_ui_update": _needs_ui_update,
		"critical_states": _last_critical_states
	}
