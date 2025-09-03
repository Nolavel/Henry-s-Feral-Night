extends Control # Или extends Control, в зависимости от вашего узла

@onready var time_label = $"TimeLabel"   # Убедитесь, что пути к узлам правильные
@onready var period_label = $"PeriodLabel"
@onready var day_label = $"DayLabel"

func _ready():
	# Убедимся, что DayNightManager загружен как Autoload
	if not DayNightManager:
		push_error("DayNightManager Autoload не найден! Убедитесь, что он добавлен в Project Settings -> Autoload.")
		return
		
	# Подписываемся на сигнал time_changed от DayNightManager
	# Это гарантирует, что наш UI будет обновляться при каждом изменении времени
	DayNightManager.time_changed.connect(on_time_changed)
	
	# Вызываем первое обновление, чтобы UI сразу показал правильные значения при старте
	update_ui_labels()

func on_time_changed(current_time_str: String, is_day_current: bool, day_num: int, time_of_day_description: String, game_hour_float_val: float):
	# Этот метод вызывается каждый раз, когда DayNightManager посылает сигнал time_changed.
	# Он просто вызывает функцию, которая обновляет все лейблы.
	update_ui_labels()

func update_ui_labels():
	# Обновляем лэйбл с часами (только часы, с AM/PM)
	if time_label:
		time_label.text = DayNightManager.get_formatted_hour_only()
	
	# Обновляем лэйбл с названием части дня на английском
	if period_label:
		period_label.text = DayNightManager.get_current_time_description_en()
	
	# Обновляем лэйбл с номером текущего дня
	if day_label:
		day_label.text = DayNightManager.get_current_day_number_string()
