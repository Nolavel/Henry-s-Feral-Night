# ✅ Script: PlayerHealthSystem.gd
# (Eng) Player health management with regeneration, damage effects, knockback and all that survival bullshit
# (Rus) Управление здоровьем игрока с регенерацией, эффектами урона, отталкиванием и всей этой фигнёй выживания
# 🔧 WIP ⚡ Prototype 🐛 Not Optimized — raw, unfinished crap, demo mechanics, eats resources / сырая, незавершённая фигня, демо-механика, жрёт ресурсы

extends Node
class_name PlayerHealthSystem

# (Eng) Event signals - notify other systems when health shit changes or player dies
# (Rus) Сигналы событий - уведомляют другие системы когда здоровье меняется или игрок умирает
signal health_changed(current: float, max_health: float)
signal player_took_damage(amount: float, damage_type: String)
signal player_died(cause: String)
signal player_healed(amount: float)

# (Eng) Health configuration - tweak these values to balance the health system
# (Rus) Конфигурация здоровья - настраиваем эти значения для баланса системы здоровья
@export_group("Health Settings")
@export var max_health: float = 100.0
@export var health_regeneration_rate: float = 2.0
@export var health_regen_delay: float = 3.0

# (Eng) Damage configuration - knockback and immunity settings to prevent spam damage
# (Rus) Конфигурация урона - настройки отталкивания и иммунитета чтобы предотвратить спам урона
@export_group("Damage Settings")
@export var knockback_resistance: float = 0.3
@export var max_knockback_force: float = 50.0
@export var damage_immunity_time: float = 0.1

# (Eng) Health state tracking - keeps tabs on current condition and damage status
# (Rus) Отслеживание состояния здоровья - следит за текущим состоянием и статусом урона
var current_health: float
var is_taking_damage: bool = false
var damage_timer: float = 0.0
var is_dead: bool = false

var player: CharacterBody3D

func _ready():
	# (Eng) Initialize with full health - start player at maximum health
	# (Rus) Инициализируем полным здоровьем - начинаем игрока с максимальным здоровьем
	current_health = max_health

func setup(player_ref: CharacterBody3D):
	# (Eng) Component initialization - connect this health system to actual player
	# (Rus) Инициализация компонента - подключаем эту систему здоровья к реальному игроку
	player = player_ref
	
	if not player:
		push_error("PlayerHealthSystem: Player reference не установлен!")

func handle_regeneration(delta: float):
	# (Eng) Regeneration logic - heals player over time but only if not recently damaged
	# (Rus) Логика регенерации - лечит игрока со временем но только если не получал недавно урон
	damage_timer += delta
	
	# (Eng) Auto-healing when out of combat - gradual health recovery after damage delay
	# (Rus) Автолечение когда не в бою - постепенное восстановление здоровья после задержки урона
	if current_health < max_health and not is_taking_damage and not is_dead:
		if damage_timer >= health_regen_delay:
			var regen_amount = health_regeneration_rate * delta
			heal(regen_amount, false)  # Тихое лечение без эффектов
	
	# (Eng) Clear damage flag after immunity period - allow new damage after brief invulnerability
	# (Rus) Очищаем флаг урона после периода иммунитета - разрешаем новый урон после краткой неуязвимости
	if is_taking_damage and damage_timer >= damage_immunity_time:
		is_taking_damage = false

func take_damage(amount: float, damage_position: Vector3 = Vector3.ZERO, damage_normal: Vector3 = Vector3.UP, damage_type: String = "unknown") -> bool:
	# (Eng) Main damage handler - processes incoming damage with position info and effects
	# (Rus) Главный обработчик урона - процессит входящий урон с информацией о позиции и эффектами
	if is_dead or current_health <= 0:
		return false
	
	# (Eng) Apply damage and clamp to zero - reduce health but don't go negative
	# (Rus) Применяем урон и ограничиваем нулём - уменьшаем здоровье но не уходим в минус
	current_health -= amount
	current_health = max(current_health, 0.0)
	
	# (Eng) Update damage state - reset timers and set damage flag for immunity period
	# (Rus) Обновляем состояние урона - сбрасываем таймеры и устанавливаем флаг урона для периода иммунитета
	damage_timer = 0.0
	is_taking_damage = true
	
	# (Eng) Notify systems about damage - emit signals for UI updates and other systems
	# (Rus) Уведомляем системы об уроне - испускаем сигналы для обновлений UI и других систем
	var health_progress = current_health / max_health
	health_changed.emit(health_progress, 1.0)
	player_took_damage.emit(amount, damage_type)
	
	# (Eng) Visual feedback - create damage effects like screen flash and camera shake
	# (Rus) Визуальная обратная связь - создаём эффекты урона типа мигания экрана и тряски камеры
	create_damage_effects(amount, damage_position, damage_type)
	
	# (Eng) Death check - handle player death if health reaches zero
	# (Rus) Проверка смерти - обрабатываем смерть игрока если здоровье достигает нуля
	if current_health <= 0:
		handle_death(damage_type)
	
	return true

func damage(amount: float) -> bool:
	# (Eng) Simplified damage method - legacy compatibility function for basic damage
	# (Rus) Упрощённый метод урона - функция совместимости для базового урона
	return take_damage(amount, player.global_transform.origin, Vector3.UP, "direct")

#func apply_knockback(knockback_force: Vector3):
	## (Eng) Knockback application - pushes player around when taking damage, with resistance
	## (Rus) Применение отталкивания - толкает игрока при получении урона, с сопротивлением
	#if is_dead:
		#return
	#
	## (Eng) Apply resistance factor - reduce knockback based on player's resistance stat
	## (Rus) Применяем фактор сопротивления - уменьшаем отталкивание на основе стата сопротивления игрока
	#var actual_force = knockback_force * (1.0 - knockback_resistance)
	#
	## (Eng) Clamp maximum force - prevent excessive knockback that breaks gameplay
	## (Rus) Ограничиваем максимальную силу - предотвращаем чрезмерное отталкивание которое ломает геймплей
	#if actual_force.length() > max_knockback_force:
		#actual_force = actual_force.normalized() * max_knockback_force
	#
	## (Eng) Apply to player velocity - directly modify player movement vector
	## (Rus) Применяем к скорости игрока - прямо модифицируем вектор движения игрока
	#player.velocity += actual_force
	#
	## (Eng) Camera shake on strong hits - bigger knockback = more screen shake
	## (Rus) Тряска камеры при сильных ударах - больше отталкивание = больше тряска экрана
	#var force_magnitude = actual_force.length()
	#if force_magnitude > 10.0:
		#var shake_strength = min(force_magnitude / max_knockback_force, 1.0)
		#trigger_camera_shake(shake_strength * 0.5, 8.0, 0.3)

func heal(amount: float, show_effects: bool = true) -> bool:
	# (Eng) Healing handler - restores player health with optional visual feedback
	# (Rus) Обработчик лечения - восстанавливает здоровье игрока с опциональной визуальной обратной связью
	if is_dead or current_health >= max_health:
		return false
	
	var old_health = current_health
	current_health += amount
	current_health = min(current_health, max_health)
	
	var actual_heal = current_health - old_health
	
	if actual_heal > 0:
		# (Eng) Notify systems about healing - update UI and other health-dependent systems
		# (Rus) Уведомляем системы о лечении - обновляем UI и другие системы зависящие от здоровья
		var health_progress = current_health / max_health
		health_changed.emit(health_progress, 1.0)
		player_healed.emit(actual_heal)
		
		if show_effects:
			create_heal_effects(actual_heal)
		
		return true
	
	return false

func restore_full_health():
	# (Eng) Full heal - instantly restores player to maximum health
	# (Rus) Полное лечение - мгновенно восстанавливает игрока до максимального здоровья
	heal(max_health - current_health)

func create_damage_effects(amount: float, position: Vector3, damage_type: String):
	# (Eng) Damage visual effects - creates screen shake, comic effects and visual feedback
	# (Rus) Визуальные эффекты урона - создаёт тряску экрана, комиксные эффекты и визуальную обратную связь
	
	# (Eng) Proportional camera shake - bigger damage = more intense screen shake
	# (Rus) Пропорциональная тряска камеры - больше урон = более интенсивная тряска экрана
	var shake_intensity = min(amount / max_health, 0.8)
	trigger_camera_shake(shake_intensity, 10.0, 0.4)
	
	# (Eng) Comic book style effects - show hit effects if comic system available
	# (Rus) Эффекты в стиле комиксов - показываем эффекты попадания если система комиксов доступна
	if has_comic_effects():
		ComicEffects.show_effect_on_node(player, ComicEffects.EffectType.PLAYER_HIT)
	
	flash_damage_screen()

func create_heal_effects(amount: float):
	pass
	# (Eng) Healing visual effects - placeholder for heal effect creation
	# (Rus) Визуальные эффекты лечения - заглушка для создания эффектов лечения
	#if has_comic_effects():
		#ComicEffects.show_effect_on_node(player, ComicEffects.EffectType.HEAL)

func flash_damage_screen():
	# (Eng) Red screen flash effect - creates red overlay when taking damage
	# (Rus) Эффект красного мигания экрана - создаёт красное наложение при получении урона
	# TODO: Можно добавить интеграцию с UI для красного мигания
	pass

func handle_death(cause: String):
	# (Eng) Death processing - handles player death with effects and auto-respawn
	# (Rus) Обработка смерти - обрабатывает смерть игрока с эффектами и авто-воскрешением
	if is_dead:
		return
	
	is_dead = true
	
	# (Eng) Death screen shake - intense camera shake when player dies
	# (Rus) Тряска экрана смерти - интенсивная тряска камеры когда игрок умирает
	trigger_camera_shake(1.0, 5.0, 1.0)
	
	# (Eng) Death effects - comic book style death animation
	# (Rus) Эффекты смерти - анимация смерти в стиле комиксов
	if has_comic_effects():
		ComicEffects.show_effect_on_node(player, ComicEffects.EffectType.PLAYER_DEATH)
	
	player_died.emit(cause)
	
	# (Eng) Stop player movement - prevent dead player from moving around
	# (Rus) Останавливаем движение игрока - предотвращаем движение мёртвого игрока
	if player:
		player.velocity = Vector3.ZERO
	
	# (Eng) Auto-respawn after delay - temporary solution for game continuity
	# (Rus) Авто-воскрешение после задержки - временное решение для непрерывности игры
	await get_tree().create_timer(2.0).timeout
	respawn()

func respawn():
	# (Eng) Player resurrection - resets all health state and brings player back to life
	# (Rus) Воскрешение игрока - сбрасывает всё состояние здоровья и возвращает игрока к жизни
	is_dead = false
	is_taking_damage = false
	current_health = max_health
	damage_timer = 0.0
	
	# (Eng) Full health signal - notify UI that player is at full health again
	# (Rus) Сигнал полного здоровья - уведомляем UI что игрок снова с полным здоровьем
	health_changed.emit(1.0, 1.0)
	
	if player:
		player.velocity = Vector3.ZERO

func trigger_camera_shake(magnitude: float, speed: float, duration: float):
	# (Eng) Camera shake activation - finds camera and triggers screen shake effect
	# (Rus) Активация тряски камеры - находит камеру и запускает эффект тряски экрана
	var camera_node = get_tree().get_first_node_in_group("game_camera_group")
	if camera_node and camera_node.has_method("start_shake"):
		camera_node.start_shake(magnitude, speed, duration)

func has_comic_effects() -> bool:
	# (Eng) Comic effects availability check - validates if comic effect system is loaded
	# (Rus) Проверка доступности комиксных эффектов - валидирует загружена ли система комиксных эффектов
	return get_tree().has_group("comic_effects") or (ComicEffects != null)

func get_health() -> float:
	# (Eng) Health accessor - returns current health value
	# (Rus) Аксессор здоровья - возвращает текущее значение здоровья
	return current_health

func get_max_health() -> float:
	# (Eng) Max health accessor - returns maximum health capacity
	# (Rus) Аксессор максимального здоровья - возвращает максимальную вместимость здоровья
	return max_health

func get_health_percentage() -> float:
	# (Eng) Health ratio calculation - returns health as 0.0-1.0 ratio for UI bars
	# (Rus) Расчёт соотношения здоровья - возвращает здоровье как соотношение 0.0-1.0 для UI полосок
	return current_health / max_health if max_health > 0 else 0.0

func is_player_dead() -> bool:
	# (Eng) Death state check - validates if player is currently dead
	# (Rus) Проверка состояния смерти - валидирует мёртв ли игрок в данный момент
	return is_dead

func is_full_health() -> bool:
	# (Eng) Full health check - determines if player is at maximum health
	# (Rus) Проверка полного здоровья - определяет находится ли игрок на максимальном здоровье
	return current_health >= max_health

func is_low_health(threshold: float = 0.25) -> bool:
	# (Eng) Low health warning check - triggers at 25% health by default for UI alerts
	# (Rus) Проверка предупреждения низкого здоровья - срабатывает на 25% здоровья по умолчанию для UI оповещений
	return get_health_percentage() <= threshold

func is_critical_health(threshold: float = 0.1) -> bool:
	# (Eng) Critical health check - triggers at 10% health for emergency systems
	# (Rus) Проверка критического здоровья - срабатывает на 10% здоровья для аварийных систем
	return get_health_percentage() <= threshold

func can_take_damage() -> bool:
	# (Eng) Damage eligibility check - determines if player can receive damage right now
	# (Rus) Проверка права получения урона - определяет может ли игрок получить урон прямо сейчас
	return not is_dead and not is_taking_damage

func set_max_health(new_max: float):
	# (Eng) Max health modification - changes maximum health and scales current health proportionally
	# (Rus) Модификация максимального здоровья - изменяет максимальное здоровье и масштабирует текущее пропорционально
	if new_max <= 0:
		push_error("PlayerHealthSystem: Максимальное здоровье должно быть больше 0")
		return
	
	var health_ratio = get_health_percentage()
	max_health = new_max
	current_health = max_health * health_ratio
	
	health_changed.emit(get_health_percentage(), 1.0)

func modify_regeneration(new_rate: float, new_delay: float = -1):
	# (Eng) Regeneration parameter modification - adjusts heal rate and delay for balance tweaking
	# (Rus) Модификация параметров регенерации - настраивает скорость лечения и задержку для балансировки
	health_regeneration_rate = new_rate
	if new_delay >= 0:
		health_regen_delay = new_delay

func debug_info() -> Dictionary:
	# (Eng) Debug information dump - returns all health system state for troubleshooting
	# (Rus) Дамп отладочной информации - возвращает всё состояние системы здоровья для траблшутинга
	return {
		"current_health": current_health,
		"max_health": max_health,
		"health_percentage": get_health_percentage(),
		"is_dead": is_dead,
		"is_taking_damage": is_taking_damage,
		"damage_timer": damage_timer,
		"health_regen_rate": health_regeneration_rate,
		"health_regen_delay": health_regen_delay
	}
