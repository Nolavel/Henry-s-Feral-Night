# ✅ Script: PlayerSprintSystem.gd
# (Eng) Sprint system with stamina drain, speed transitions and all that movement clusterfuck bullshit
# (Rus) Система спринта с тратой выносливости, переходами скорости и всей этой движковой пиздой
# 🔧 WIP ⚡ Prototype 🐛 Not Optimized — raw, unfinished crap, demo mechanics, eats resources / сырая, незавершённая хуйня, демо-механика, жрёт ресурсы

extends Node
class_name PlayerSprintSystem

# (Eng) Event signals - notify other systems when sprint shit changes or player runs out of steam
# (Rus) Сигналы событий - уведомляют другие системы когда спринт меняется или у игрока кончается пар
signal sprint_state_changed(is_sprinting: bool)
signal stamina_state_changed(can_sprint: bool)

# (Eng) Sprint configuration - tweak these values because the current balance is probably broken as fuck
# (Rus) Конфигурация спринта - настраивай эти значения потому что текущий баланс наверняка сломан как хуй
@export_group("Sprint Settings")
@export var base_walk_speed: float = 8.0
@export var max_sprint_speed: float = 18.0
@export var sprint_acceleration: float = 12.0
@export var sprint_deceleration: float = 15.0
@export var min_stamina_to_sprint: float = 0.05

# (Eng) Sprint state tracking - keeps tabs on all this movement bullshit and whether player can run
# (Rus) Отслеживание состояния спринта - следит за всей этой движковой фигнёй и может ли игрок бежать
var current_sprint_speed: float = 0.0
var is_trying_to_sprint: bool = false
var can_sprint: bool = true
var is_sprinting: bool = false

var movement_controller: PlayerMovementController

func _ready():
	# (Eng) Initialize with zero sprint - start player walking like a normal person
	# (Rus) Инициализируем с нулевым спринтом - начинаем игрока идти как нормальный человек
	current_sprint_speed = 0.0

func setup(movement_controller_ref: PlayerMovementController):
	# (Eng) Component initialization - connect this sprint clusterfuck to movement controller
	# (Rus) Инициализация компонента - подключаем этот спринтовый пиздец к контроллеру движения
	movement_controller = movement_controller_ref
	
	if not movement_controller:
		push_error("PlayerSprintSystem: MovementController reference не установлен!")

func update_sprint(delta: float, trying_to_sprint: bool, player_is_moving: bool):
	# (Eng) Main sprint update clusterfuck - processes all sprint logic every fucking frame like an idiot
	# (Rus) Основной спринтовый пиздец обновления - процессит всю логику спринта каждый блядский кадр как дебил
	is_trying_to_sprint = trying_to_sprint
	
	# (Eng) Get stamina from MovementController - dependency hell at its finest
	# (Rus) Получаем выносливость из MovementController - ад зависимостей во всей красе
	var current_stamina = movement_controller.get_current_stamina() if movement_controller else 1.0
	
	update_stamina_state(current_stamina)
	
	# (Eng) Calculate target speed - fancy math for what should be simple as fuck
	# (Rus) Вычисляем целевую скорость - модная математика для того что должно быть простым как хуй
	var target_sprint_speed = calculate_target_sprint_speed(player_is_moving)
	
	# (Eng) Smooth speed transition - because instant changes look janky as shit
	# (Rus) Плавный переход скорости - потому что мгновенные изменения выглядят как дерьмо
	update_current_sprint_speed(delta, target_sprint_speed)
	
	# (Eng) Drain stamina while sprinting - burn that energy like there's no tomorrow
	# (Rus) Тратим выносливость во время спринта - жжём эту энергию как будто завтра не будет
	if is_sprinting and movement_controller:
		var stamina_drain = get_stamina_drain_rate() * delta
		movement_controller.drain_stamina(stamina_drain)
	
	# (Eng) Update movement speed - push new speed to controller every frame like a dumbass
	# (Rus) Обновляем скорость движения - пихаем новую скорость в контроллер каждый кадр как долбоёб
	if movement_controller:
		var total_speed = base_walk_speed + current_sprint_speed
		movement_controller.set_movement_speed(total_speed)
	
	check_sprint_state_change()

func update_stamina_state(current_stamina: float):
	# (Eng) Stamina state management - figure out if player can still run or is fucked
	# (Rus) Управление состоянием выносливости - выясняем может ли игрок ещё бежать или ему пизда
	var old_can_sprint = can_sprint
	
	# (Eng) Determine sprint eligibility - check if player has enough juice left
	# (Rus) Определяем право на спринт - проверяем хватает ли игроку сока
	can_sprint = current_stamina > min_stamina_to_sprint
	
	# (Eng) Force stop sprint when stamina runs out - harsh but necessary reality check
	# (Rus) Принудительно останавливаем спринт когда выносливость кончается - жёстко но необходимая проверка реальности
	if current_sprint_speed > 0.0 and current_stamina <= 0.0:
		can_sprint = false
		is_trying_to_sprint = false
	
	# (Eng) Emit signal spam - notify every fucking system that gives a shit about stamina
	# (Rus) Спамим сигналами - уведомляем каждую блядскую систему которой не похуй на выносливость
	if old_can_sprint != can_sprint:
		stamina_state_changed.emit(can_sprint)

func calculate_target_sprint_speed(player_is_moving: bool) -> float:
	# (Eng) Target speed calculation - determines what speed we should be going for this clusterfuck
	# (Rus) Расчёт целевой скорости - определяет какую скорость нам нужно получить для этого пиздеца
	if is_trying_to_sprint and can_sprint and player_is_moving:
		return max_sprint_speed - base_walk_speed
	else:
		return 0.0

func update_current_sprint_speed(delta: float, target_speed: float):
	# (Eng) Smooth speed interpolation - gradual speed changes because instant shit looks broken
	# (Rus) Плавная интерполяция скорости - постепенные изменения скорости потому что мгновенная хуйня выглядит сломанной
	if current_sprint_speed < target_speed:
		current_sprint_speed += sprint_acceleration * delta
		current_sprint_speed = min(current_sprint_speed, target_speed)
	elif current_sprint_speed > target_speed:
		current_sprint_speed -= sprint_deceleration * delta
		current_sprint_speed = max(current_sprint_speed, target_speed)

func check_sprint_state_change():
	# (Eng) Sprint state transition detection - check if we started or stopped sprinting like idiots
	# (Rus) Обнаружение перехода состояния спринта - проверяем начали или остановили спринт как дебилы
	var was_sprinting = is_sprinting
	is_sprinting = current_sprint_speed > 1.0
	
	if was_sprinting != is_sprinting:
		sprint_state_changed.emit(is_sprinting)

func get_current_speed() -> float:
	# (Eng) Current speed calculation - returns total movement speed for this broken ass system
	# (Rus) Расчёт текущей скорости - возвращает общую скорость движения для этой сломанной системы
	return base_walk_speed + current_sprint_speed

func get_sprint_intensity() -> float:
	# (Eng) Sprint intensity ratio - fancy percentage calculation for UI that probably doesn't work right
	# (Rus) Соотношение интенсивности спринта - модный расчёт процентов для UI которое наверняка работает неправильно
	if max_sprint_speed <= base_walk_speed:
		return 0.0
	return current_sprint_speed / (max_sprint_speed - base_walk_speed)

func get_speed_percentage() -> float:
	# (Eng) Speed percentage calculation - another percentage function because we love redundancy
	# (Rus) Расчёт процента скорости - ещё одна процентная функция потому что мы любим избыточность
	return (get_current_speed() / max_sprint_speed) * 100.0

func is_player_sprinting() -> bool:
	# (Eng) Sprint state check - simple boolean but we need a function for it apparently
	# (Rus) Проверка состояния спринта - простой булев но нам видимо нужна для него функция
	return is_sprinting

func can_start_sprint() -> bool:
	# (Eng) Sprint eligibility check - determines if player can start running or is too tired
	# (Rus) Проверка права на спринт - определяет может ли игрок начать бежать или слишком устал
	return can_sprint

func get_stamina_drain_rate() -> float:
	# (Eng) Stamina drain calculation - determines how fast we burn through player's energy like a gas guzzler
	# (Rus) Расчёт скорости траты выносливости - определяет как быстро мы жжём энергию игрока как прожорливая тачка
	if not movement_controller or not movement_controller.is_moving():
		return 0.0
	
	if is_sprinting:
		# (Eng) Aggressive stamina drain - burn energy faster when sprinting harder
		# (Rus) Агрессивная трата выносливости - жжём энергию быстрее когда спринтим жёстче
		var sprint_intensity = get_sprint_intensity()
		return 0.2 + (0.3 * sprint_intensity)  # От 0.2 до 0.5 в секунду
	else:
		return 0.0  # Стамина тратится только при спринте

func force_stop_sprint():
	# (Eng) Emergency sprint stop - kills sprint immediately when shit hits the fan
	# (Rus) Экстренная остановка спринта - убивает спринт немедленно когда всё идёт по пизде
	current_sprint_speed = 0.0
	is_trying_to_sprint = false
	is_sprinting = false
	
	if movement_controller:
		movement_controller.set_movement_speed(base_walk_speed)

func set_sprint_speeds(new_base: float, new_max: float):
	# (Eng) Speed configuration - adjust speed values because current ones are probably shit
	# (Rus) Конфигурация скорости - настраиваем значения скорости потому что текущие наверняка говно
	base_walk_speed = new_base
	max_sprint_speed = new_max
	
	if movement_controller:
		movement_controller.set_movement_speed(get_current_speed())

func set_sprint_acceleration(new_accel: float, new_decel: float = -1):
	# (Eng) Acceleration tuning - modify speed transition rates because they feel janky as fuck
	# (Rus) Настройка ускорения - модифицируем скорости переходов потому что они ощущаются как дерьмо
	sprint_acceleration = new_accel
	if new_decel >= 0:
		sprint_deceleration = new_decel

func set_stamina_threshold(new_threshold: float):
	# (Eng) Stamina threshold adjustment - change minimum energy needed to not feel like dying
	# (Rus) Настройка порога выносливости - меняем минимальную энергию нужную чтобы не чувствовать себя умирающим
	min_stamina_to_sprint = clamp(new_threshold, 0.0, 1.0)

func debug_info() -> Dictionary:
	# (Eng) Debug info dump - spits out all the internal bullshit for troubleshooting this broken system
	# (Rus) Дамп отладочной информации - выплёвывает всю внутреннюю фигню для траблшутинга этой сломанной системы
	var current_stamina = movement_controller.get_current_stamina() if movement_controller else 1.0
	
	return {
		"current_sprint_speed": current_sprint_speed,
		"is_trying_to_sprint": is_trying_to_sprint,
		"can_sprint": can_sprint,
		"is_sprinting": is_sprinting,
		"total_speed": get_current_speed(),
		"sprint_intensity": get_sprint_intensity(),
		"speed_percentage": get_speed_percentage(),
		"stamina": current_stamina,
		"stamina_drain_rate": get_stamina_drain_rate()
	}
