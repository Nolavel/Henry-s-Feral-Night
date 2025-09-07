extends Node

func _ready():
	var categorized_settings := {}

	for property in ProjectSettings.get_property_list():
		var key: String = property.name
		if ProjectSettings.has_setting(key):
			var value = ProjectSettings.get_setting(key)

			var category := key.split("/")[0]
			if not categorized_settings.has(category):
				categorized_settings[category] = {}
			
			categorized_settings[category][key] = value

	var json := JSON.new()
	var json_text := json.stringify(categorized_settings, "\t")  # читаемый формат

	var file := FileAccess.open("res://project_settings_dump.json", FileAccess.WRITE)
	file.store_string(json_text)
	file.close()

	print("✅ Настройки проекта сгруппированы и сохранены в res://project_settings_dump.json")
