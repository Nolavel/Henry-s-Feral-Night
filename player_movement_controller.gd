# ✅ Script: PlayerMovementController.gd
# (Eng) Movement controller with wall bouncing, stamina integration and all sorts of architectural clusterfuck bullshit
# (Rus) Контроллер движения с отскоками от стен, интеграцией выносливости и всякой архитектурной пиздой
# 🔧 WIP ⚡ Prototype 🐛 Not Optimized — raw, unfinished crap, demo mechanics, eats resources / сырая, незавершённая хуйня, демо-механика, жрёт ресурсы

extends Node
class_name PlayerMovementController

# (Eng) References - dependency hell because we need to access everything from everywhere like idiots
# (Rus) Ссылки - ад зависимостей потому что нам нужно получать доступ ко всему отовсюду как дебилам
var player: CharacterBody3D
var head: Node3D
@onready var survival_ui: SurvivalUI = $"../../UI/SurvivalUI"

# (Eng) Movement configuration - basic movement shit that should be simple but isn't
# (Rus) Конфигурация движения - базовая двигательная фигня которая должна быть простой но не является
@export var current_movement_speed: float = 8.0
@export var jump_velocity: float = 5.0
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# (Eng) Wall bounce settings - overcomplicated physics for what should be basic collision
# (Rus) Настройки отскока от стен - перекомплексная физика для того что должно быть базовой коллизией
@export var wall_bounce_initial_force: float = 15.0
@export var wall_bounce_duration: float = 0.2
@export var min_impact_speed_for_wall_bounce: float = 2.0

# (Eng) Speed multipliers - because apparently walking backwards is rocket science
# (Rus) Множители скорости - потому что видимо идти назад это блядь ракетостроение
@export var backward_speed_multiplier: float = 0.6
@export var strafe_speed_multiplier: float = 0.8

# (Eng) Knockback system - moved from Player because we love spreading shit around
# (Rus) Система отталкивания - перенесена из Player потому что мы любим размазывать дерьмо повсюду
@export var knockback_resistance: float = 0.3
@export var max_knockback_force: float = 50.0

# (Eng) State tracking - bunch of flags because proper state machine is apparently too hard
# (Rus) Отслеживание состояния - куча флагов потому что нормальная машина состояний видимо слишком сложна
var is_bouncing_from_wall: bool = false
var current_wall_bounce_timer: float = 0.0
var wall_bounce_direction_override: Vector3 = Vector3.ZERO
var is_checking_for_landing: bool = false
var _is_moving: bool = false


# (Eng) Event signals - spam other systems with movement updates every fucking frame
# (Rus) Сигналы событий - спамим другие системы обновлениями движения каждый блядский кадр
signal movement_state_changed(is_moving: bool)
signal wall_bounce_triggered(force: Vector3)

func setup(player_ref: CharacterBody3D, head_ref: Node3D):
	# (Eng) Component initialization - connect this movement mess to player references
	# (Rus) Инициализация компонента - подключаем этот движковый пиздец к ссылкам на игрока
	player = player_ref
	head = head_ref
	
	if not player:
		push_error("PlayerMovementController: Player reference не установлен!")
	if not head:
		push_error("PlayerMovementController: Head reference не установлен!")
	
	print("PlayerMovementController: Настроен успешно")

func handle_movement(delta: float, input_vector: Vector2):
	# (Eng) Main movement clusterfuck - processes everything every frame because optimization is for losers
	# (Rus) Основной движковый пиздец - процессит всё каждый кадр потому что оптимизация для лузеров
	if not player:
		return
	
	# (Eng) Wall bounce decay - interpolation hell that runs constantly
	# (Rus) Затухание отскока от стены - интерполяционный ад который работает постоянно
	_update_wall_bounce(delta)
	
	_apply_gravity(delta)
	_handle_jump()
	_handle_horizontal_movement(input_vector)
	_move_and_handle_collisions()
	_update_movement_state(input_vector)

func _update_wall_bounce(delta: float):
	# (Eng) Wall bounce decay system - lerp hell that could be handled by tweens but whatever
	# (Rus) Система затухания отскока от стены - лерповый ад который мог бы обрабатываться твинами но похуй
	if current_wall_bounce_timer > 0:
		current_wall_bounce_timer -= delta
		
		var decay_progress = (wall_bounce_duration - current_wall_bounce_timer) / wall_bounce_duration
		player.velocity.x = lerp(wall_bounce_direction_override.x, 0.0, decay_progress)
		player.velocity.z = lerp(wall_bounce_direction_override.z, 0.0, decay_progress)
		
		if current_wall_bounce_timer <= 0:
			is_bouncing_from_wall = false
			wall_bounce_direction_override = Vector3.ZERO
			player.velocity.x = move_toward(player.velocity.x, 0, current_movement_speed)
			player.velocity.z = move_toward(player.velocity.z, 0, current_movement_speed)

func _apply_gravity(delta: float):
	# (Eng) Gravity application - basic physics that somehow needs its own function
	# (Rus) Применение гравитации - базовая физика которой почему-то нужна своя функция
	if not player.is_on_floor():
		player.velocity.y -= gravity * delta

func _handle_jump():
	# (Eng) Jump handling - simple shit that triggers landing detection nightmare
	# (Rus) Обработка прыжка - простая фигня которая запускает кошмар определения приземления
	if Input.is_action_just_pressed("jump") and player.is_on_floor():
		player.velocity.y = jump_velocity
		player.jump_performed.emit()
		_start_landing_check()

func _handle_horizontal_movement(input_direction: Vector2):
	# (Eng) Stop movement entirely if a wall bounce is in effect to prevent conflicting forces.
	# (Rus) Полностью останавливаем движение, если активен отскок от стены, чтобы избежать конфликта сил.
	if is_bouncing_from_wall:
		return

	# (Eng) Handle player-controlled movement.
	# (Rus) Обработка движения, управляемого игроком.
	if input_direction != Vector2.ZERO:
		# (Eng) Calculate the direction relative to the camera's rotation.
		# (Rus) Вычисляем направление, относительно поворота камеры.
		var direction = (head.global_transform.basis * Vector3(input_direction.x, 0, input_direction.y)).normalized()

		# (Eng) Apply speed multipliers based on movement direction.
		# (Rus) Применяем множители скорости в зависимости от направления движения.
		var speed_to_apply = current_movement_speed
		if input_direction.y < 0: # Note: Godot's Z-axis is typically forward, so input_direction.y < 0 is for forward movement
			# No multiplier for forward movement, but can be added if needed
			pass
		elif input_direction.y > 0: # Moving backward
			speed_to_apply *= backward_speed_multiplier
		
		if input_direction.x != 0: # Strafing
			speed_to_apply *= strafe_speed_multiplier
		
		# (Eng) Smoothly transition velocity to the new target speed.
		# (Rus) Плавно переводим скорость к новой целевой.
		player.velocity.x = lerp(player.velocity.x, direction.x * speed_to_apply, 0.2)
		player.velocity.z = lerp(player.velocity.z, direction.z * speed_to_apply, 0.2)
	else:
		# (Eng) Smoothly decelerate to a stop when no input is detected.
		# (Rus) Плавно замедляемся до полной остановки, когда нет ввода.
		player.velocity.x = move_toward(player.velocity.x, 0, current_movement_speed)
		player.velocity.z = move_toward(player.velocity.z, 0, current_movement_speed)

func _move_and_handle_collisions():
	# (Eng) Collision nightmare - processes all collisions every frame and checks group membership like a maniac
	# (Rus) Коллизионный кошмар - обрабатывает все коллизии каждый кадр и проверяет принадлежность к группам как маньяк
	var velocity_before_slide_horizontal = Vector3(player.velocity.x, 0, player.velocity.z)
	
	player.move_and_slide()
	
	# (Eng) Collision processing hell - iterate through all collisions and do complex math for wall bouncing
	# (Rus) Ад обработки коллизий - итерируемся по всем коллизиям и делаем сложную математику для отскока от стен
	for i in range(player.get_slide_collision_count()):
		var collision = player.get_slide_collision(i)
		if not collision:
			continue
			
		var collider = collision.get_collider()
		var normal = collision.get_normal()
		
		var is_wall_surface = abs(normal.y) < 0.3
		
		# (Eng) Wall bounce calculation - overcomplicated physics for simple collision response
		# (Rus) Расчёт отскока от стены - перекомплексная физика для простого ответа на коллизию
		if collider.is_in_group("Walls") and is_wall_surface and not is_bouncing_from_wall:
			var impact_speed = velocity_before_slide_horizontal.length()
			
			if impact_speed > min_impact_speed_for_wall_bounce:
				var bounce_dir: Vector3
				if velocity_before_slide_horizontal.length_squared() > 0.01:
					bounce_dir = -velocity_before_slide_horizontal.normalized()
				else:
					bounce_dir = normal
				
				is_bouncing_from_wall = true
				current_wall_bounce_timer = wall_bounce_duration
				wall_bounce_direction_override = bounce_dir * wall_bounce_initial_force
				
				player.velocity.x = wall_bounce_direction_override.x
				player.velocity.z = wall_bounce_direction_override.z
				
				wall_bounce_triggered.emit(wall_bounce_direction_override)
				
				if player.has_method("trigger_camera_shake"):
					player.trigger_camera_shake(0.15, 0.3, 0.2)

		# (Eng) Hazard cube check - because apparently we need special handling for danger cubes
		# (Rus) Проверка опасных кубов - потому что видимо нам нужна специальная обработка для опасных кубиков
		if collider.is_in_group("HazardCubes"):
			if player.has_method("trigger_camera_shake"):
				player.trigger_camera_shake(0.8, 0.8, 0.8)

func _update_movement_state(input_vector: Vector2):
	# (Eng) Movement state spam - emit signals every frame because efficiency is overrated
	# (Rus) Спам состояния движения - испускаем сигналы каждый кадр потому что эффективность переоценена
	var was_moving = _is_moving
	_is_moving = input_vector.length() > 0.1 or player.velocity.length() > 0.1
	
	if was_moving != _is_moving:
		movement_state_changed.emit(_is_moving)

func _start_landing_check():
	# (Eng) Landing detection initiation - starts recursive timer hell for jump landing
	# (Rus) Инициация определения приземления - запускает рекурсивный таймерный ад для приземления прыжка
	if not is_checking_for_landing:
		is_checking_for_landing = true
		_check_for_landing()

func _check_for_landing():
	# (Eng) Recursive landing check - polls landing state with timers because signals are apparently too hard
	# (Rus) Рекурсивная проверка приземления - опрашивает состояние приземления таймерами потому что сигналы видимо слишком сложны
	if not is_checking_for_landing:
		return
		
	if player.velocity.y < -1.0:  # Все еще падаем
		await get_tree().create_timer(0.1).timeout
		_check_for_landing()
	elif player.is_on_floor():  # Приземлились!
		is_checking_for_landing = false
		_trigger_landing_shake()

func _trigger_landing_shake():
	# (Eng) Landing shake effect - camera shake based on fall speed because immersion matters more than performance
	# (Rus) Эффект тряски приземления - тряска камеры на основе скорости падения потому что погружение важнее производительности
	var fall_speed = abs(player.velocity.y)
	var shake_intensity = clamp(fall_speed / 10.0, 0.8, 2.2)
	var shake_duration = 0.2 + (shake_intensity * 0.1)
	
	if player.has_method("trigger_camera_shake"):
		player.trigger_camera_shake(shake_duration, shake_intensity, 1.0)

func get_current_stamina() -> float:
	# (Eng) Stamina access through UI - architectural nightmare where movement controller talks to UI directly
	# (Rus) Доступ к выносливости через UI - архитектурный кошмар где контроллер движения напрямую общается с UI
	if survival_ui:
		return survival_ui.stamina
	return 1.0  # По умолчанию полная стамина

func drain_stamina(amount: float):
	# (Eng) Stamina drain through UI - because proper data flow is for suckers
	# (Rus) Трата выносливости через UI - потому что нормальный поток данных для лохов
	if survival_ui:
		survival_ui.stamina = max(0.0, survival_ui.stamina - amount)

func is_sprinting() -> bool:
	# (Eng) Sprint detection through velocity comparison - hacky shit instead of proper state tracking
	# (Rus) Определение спринта через сравнение скорости - дерьмовый хак вместо нормального отслеживания состояния
	if player:
		var horizontal_velocity = Vector2(player.velocity.x, player.velocity.z).length()
		return horizontal_velocity > current_movement_speed * 1.2  # Спринт если скорость больше базовой на 20%
	return false

func set_movement_speed(new_speed: float):
	# (Eng) Speed setter - simple function that somehow needs documentation
	# (Rus) Установщик скорости - простая функция которой почему-то нужна документация
	current_movement_speed = new_speed

func is_moving() -> bool:
	# (Eng) Movement check - returns cached boolean because direct velocity check is too expensive apparently
	# (Rus) Проверка движения - возвращает кешированный булев потому что прямая проверка скорости видимо слишком дорогая
	return _is_moving

func get_movement_speed() -> float:
	# (Eng) Speed getter - another wrapper function for a simple variable
	# (Rus) Получатель скорости - ещё одна функция-обёртка для простой переменной
	return current_movement_speed

func get_velocity() -> Vector3:
	# (Eng) Velocity getter with null checks because proper initialization is apparently optional
	# (Rus) Получатель скорости с проверками на null потому что нормальная инициализация видимо опциональна
	return player.velocity if player else Vector3.ZERO

func is_on_floor() -> bool:
	# (Eng) Floor check wrapper - because accessing player.is_on_floor() directly would be too simple
	# (Rus) Обёртка проверки пола - потому что прямой доступ к player.is_on_floor() был бы слишком простым
	return player.is_on_floor() if player else false

func is_wall_bouncing() -> bool:
	# (Eng) Wall bounce state getter - simple boolean access disguised as a method
	# (Rus) Получатель состояния отскока от стены - простой доступ к булевой переменной замаскированный под метод
	return is_bouncing_from_wall

func set_wall_bounce_settings(force: float, duration: float, min_speed: float):
	# (Eng) Wall bounce configuration - adjust parameters because current ones are probably broken
	# (Rus) Конфигурация отскока от стены - настраиваем параметры потому что текущие наверняка сломаны
	wall_bounce_initial_force = force
	wall_bounce_duration = duration
	min_impact_speed_for_wall_bounce = min_speed

func set_speed_multipliers(backward: float, strafe: float):
	# (Eng) Speed multiplier configuration - tweak magical numbers that control movement feel
	# (Rus) Конфигурация множителей скорости - настраиваем магические числа которые контролируют ощущение движения
	backward_speed_multiplier = clamp(backward, 0.1, 1.0)
	strafe_speed_multiplier = clamp(strafe, 0.1, 1.0)

func set_jump_velocity(new_jump_velocity: float):
	# (Eng) Jump force setter - another simple assignment disguised as a method
	# (Rus) Установщик силы прыжка - ещё одно простое присваивание замаскированное под метод
	jump_velocity = new_jump_velocity

func apply_knockback(knockback_force: Vector3):
	# (Eng) Knockback application - moved from Player class because we love spreading responsibilities around
	# (Rus) Применение отталкивания - перенесено из класса Player потому что мы любим размазывать ответственности
	if not player:
		return
	
	# (Eng) Resistance calculation - reduce force based on player stats
	# (Rus) Расчёт сопротивления - уменьшаем силу на основе статов игрока
	var reduced_force = knockback_force * (1.0 - knockback_resistance)
	
	# (Eng) Force clamping - prevent excessive knockback that breaks the game
	# (Rus) Ограничение силы - предотвращаем чрезмерное отталкивание которое ломает игру
	if reduced_force.length() > max_knockback_force:
		reduced_force = reduced_force.normalized() * max_knockback_force
	
	player.velocity += reduced_force
	
	print("MovementController: Применено отталкивание: %s" % reduced_force)

func set_knockback_settings(resistance: float, max_force: float):
	# (Eng) Knockback configuration - adjust knockback parameters because balance is probably fucked
	# (Rus) Конфигурация отталкивания - настраиваем параметры отталкивания потому что баланс наверняка просран
	knockback_resistance = clamp(resistance, 0.0, 1.0)
	max_knockback_force = max(max_force, 0.0)

# В PlayerMovementController.gd, добавьте в функцию pickup_weapon или pickup_item:
func reset_movement_state():
	# Сбросить все движковые состояния
	is_bouncing_from_wall = false
	wall_bounce_direction_override = Vector3.ZERO
	current_wall_bounce_timer = 0.0
	
	# Принудительно сбросить velocity
	if player:
		player.velocity = Vector3.ZERO
		player.velocity.x = 0
		player.velocity.z = 0
	
	print("PlayerMovementController: Состояние движения сброшено")
