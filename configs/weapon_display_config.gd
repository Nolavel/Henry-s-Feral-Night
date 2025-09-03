# WeaponDisplayConfig.gd - Ресурс конфигурации отображения оружия
extends Resource
class_name WeaponDisplayConfig

# === НАСТРОЙКИ ОРУЖИЯ ===
@export var weapon_settings: Dictionary = {}

# Класс для настроек отдельного оружия
class WeaponDisplaySettings:
	var position: Vector3
	var rotation_degrees: Vector3
	var scale: Vector3
	
	func _init(pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE):
		position = pos
		rotation_degrees = rot
		scale = scl

func _init():
	"""Инициализация с настройками по умолчанию"""
	setup_default_settings()

func setup_default_settings():
	"""Настраивает конфигурацию по умолчанию"""
	weapon_settings = {
		"Wasteland Eagle": WeaponDisplaySettings.new(
			Vector3(0.4, 0, -0.75),
			Vector3(0, 0, 0),
			Vector3(1, 1, 1)
		),
		"Enforcer 12-Gauge": WeaponDisplaySettings.new(
			Vector3(0.5, 0, -0.75),
			Vector3(0, 0, 0),
			Vector3(1, 1, 1)
		),
		"Trail Boss Shotgun": WeaponDisplaySettings.new(
			Vector3(0.5, 0, -0.75),
			Vector3(0, 0, 0),
			Vector3(1, 1, 1)
		),
		"Assault Auto-Rifle": WeaponDisplaySettings.new(
			Vector3(0.5, 0, -0.75),
			Vector3(0, 0, 0),
			Vector3(1, 1, 1)
		)
	}

func get_weapon_settings(weapon_type: String) -> WeaponDisplaySettings:
	"""Возвращает настройки для указанного оружия"""
	if weapon_settings.has(weapon_type):
		return weapon_settings[weapon_type]
	else:
		print("WeaponDisplayConfig: Настройки для '%s' не найдены, используем по умолчанию" % weapon_type)
		return WeaponDisplaySettings.new()

func add_weapon_settings(weapon_type: String, settings: WeaponDisplaySettings):
	"""Добавляет настройки для нового оружия"""
	weapon_settings[weapon_type] = settings

func remove_weapon_settings(weapon_type: String):
	"""Удаляет настройки оружия"""
	weapon_settings.erase(weapon_type)

func has_weapon_settings(weapon_type: String) -> bool:
	"""Проверяет наличие настроек для оружия"""
	return weapon_settings.has(weapon_type)

func get_all_weapon_types() -> Array:
	"""Возвращает список всех типов оружия"""
	return weapon_settings.keys()
