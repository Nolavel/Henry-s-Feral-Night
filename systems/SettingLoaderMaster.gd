extends Node

const SETTINGS_PATH := "res://project_settings.json"
const FLAG_PATH := "res://settings_loaded.flag"

func _ready():
	# Проверяем флаг загрузки
	if FileAccess.file_exists(FLAG_PATH):
		return
	
	force_load_settings()
	create_loaded_flag()

func force_load_settings():
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file:
		return
	
	var json := JSON.new()
	var result := json.parse(file.get_as_text())
	file.close()
	
	if result != OK:
		return
	
	var settings_dict: Dictionary = json.data
	var applied_count = 0
	
	for key in settings_dict.keys():
		var value = settings_dict[key]
		if is_critical_setting(key):
			ProjectSettings.set_setting(key, value)
			applied_count += 1
	
	# КЛЮЧЕВОЕ ИЗМЕНЕНИЕ: сохраняем только если мы НЕ в редакторе
	if applied_count > 0 and not Engine.is_editor_hint():
		ProjectSettings.save()
	
	print("Применено настроек: " + str(applied_count))

func is_critical_setting(key: String) -> bool:
	var critical_prefixes = [
		"application/config/",
		"application/run/", 
		"display/window/",
		"input/",
		"autoload/",
		"layer_names/"
	]
	
	for prefix in critical_prefixes:
		if key.begins_with(prefix):
			return true
	return false

func create_loaded_flag():
	var flag_file = FileAccess.open(FLAG_PATH, FileAccess.WRITE)
	if flag_file:
		flag_file.store_string("loaded")
		flag_file.close()
