extends Node

const SETTINGS_PATH := "res://project_settings.json"

func _ready():
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file:
		push_error("❌ Не удалось открыть файл настроек: " + SETTINGS_PATH)
		return

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var result := json.parse(json_text)

	if result != OK:
		push_error("❌ Ошибка парсинга JSON: " + json.get_error_message())
		return

	var settings_dict: Dictionary = json.data
	for key in settings_dict.keys():
		var value = settings_dict[key]
		if ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, value)
		else:
			# Можно добавить новые настройки, если они допустимы
			ProjectSettings.set_setting(key, value)

	ProjectSettings.save()

	print("✅ Настройки проекта загружены из JSON и применены")
