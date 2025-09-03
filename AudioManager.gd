# AudioManager.gd - Простой глобальный менеджер звука
extends Node

# ============================================================================
# НАСТРОЙКИ ГРОМКОСТИ
# ============================================================================
var master_volume: float = 1.0
var music_volume: float = 0.7
var sfx_volume: float = 0.8
var voice_volume: float = 0.9

# ============================================================================
# НАСТРОЙКИ ВКЛЮЧЕНИЯ/ВЫКЛЮЧЕНИЯ
# ============================================================================
var master_enabled: bool = true
var music_enabled: bool = true
var sfx_enabled: bool = true
var voice_enabled: bool = true

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================================================
func _ready():
	print("🔊 Simple AudioManager initialized")
	
	# Загружаем настройки
	load_audio_settings()
	
	# Применяем настройки к шинам
	apply_all_audio_settings()
	
	# Проверяем шины
	check_audio_buses()

func check_audio_buses():
	"""Проверяет существование audio buses"""
	var buses = ["Master", "Music", "SFX", "Voice"]
	
	for bus_name in buses:
		var bus_index = AudioServer.get_bus_index(bus_name)
		if bus_index >= 0:
			print("✅ Bus '%s' found" % bus_name)
		else:
			print("❌ Bus '%s' NOT FOUND!" % bus_name)

# ============================================================================
# УСТАНОВКА ГРОМКОСТИ
# ============================================================================
func set_master_volume(volume: float):
	master_volume = clamp(volume, 0.0, 1.0)
	update_bus_volume("Master", master_volume, master_enabled)
	save_audio_settings()

func set_music_volume(volume: float):
	music_volume = clamp(volume, 0.0, 1.0)
	update_bus_volume("Music", music_volume, music_enabled)
	save_audio_settings()

func set_sfx_volume(volume: float):
	sfx_volume = clamp(volume, 0.0, 1.0)
	update_bus_volume("SFX", sfx_volume, sfx_enabled)
	
	# Уведомляем все SFX объекты
	get_tree().call_group("flashlight_sounds", "set_sound_volume", sfx_volume)
	get_tree().call_group("weapon_sounds", "set_sound_volume", sfx_volume)
	get_tree().call_group("ui_sounds", "set_sound_volume", sfx_volume)
	
	save_audio_settings()

func set_voice_volume(volume: float):
	voice_volume = clamp(volume, 0.0, 1.0)
	update_bus_volume("Voice", voice_volume, voice_enabled)
	save_audio_settings()

# ============================================================================
# ВКЛЮЧЕНИЕ/ВЫКЛЮЧЕНИЕ
# ============================================================================
func set_master_enabled(enabled: bool):
	master_enabled = enabled
	update_bus_volume("Master", master_volume, master_enabled)
	save_audio_settings()

func set_music_enabled(enabled: bool):
	music_enabled = enabled
	update_bus_volume("Music", music_volume, music_enabled)
	save_audio_settings()

func set_sfx_enabled(enabled: bool):
	sfx_enabled = enabled
	update_bus_volume("SFX", sfx_volume, sfx_enabled)
	
	# Уведомляем все SFX объекты
	get_tree().call_group("flashlight_sounds", "set_sound_enabled", enabled)
	get_tree().call_group("weapon_sounds", "set_sound_enabled", enabled)
	get_tree().call_group("ui_sounds", "set_sound_enabled", enabled)
	
	save_audio_settings()

func set_voice_enabled(enabled: bool):
	voice_enabled = enabled
	update_bus_volume("Voice", voice_volume, voice_enabled)
	save_audio_settings()

# ============================================================================
# ВНУТРЕННИЕ ФУНКЦИИ
# ============================================================================
func update_bus_volume(bus_name: String, volume: float, enabled: bool):
	"""Обновляет громкость конкретной шины"""
	var bus_index = AudioServer.get_bus_index(bus_name)
	if bus_index >= 0:
		if enabled and volume > 0.0:
			var db_volume = linear_to_db(volume)
			AudioServer.set_bus_volume_db(bus_index, db_volume)
			print("🔊 %s: %.0f%%" % [bus_name, volume * 100])
		else:
			AudioServer.set_bus_volume_db(bus_index, -80.0)  # Выключено
			print("🔊 %s: OFF" % bus_name)
	else:
		print("⚠️ Bus '%s' не найдена!" % bus_name)

func apply_all_audio_settings():
	"""Применяет все настройки звука"""
	print("🔊 Applying audio settings...")
	
	update_bus_volume("Master", master_volume, master_enabled)
	update_bus_volume("Music", music_volume, music_enabled)
	update_bus_volume("SFX", sfx_volume, sfx_enabled)
	update_bus_volume("Voice", voice_volume, voice_enabled)

# ============================================================================
# СОХРАНЕНИЕ/ЗАГРУЗКА
# ============================================================================
func save_audio_settings():
	"""Сохраняет настройки в файл"""
	var config = ConfigFile.new()
	
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "voice_volume", voice_volume)
	
	config.set_value("audio", "master_enabled", master_enabled)
	config.set_value("audio", "music_enabled", music_enabled)
	config.set_value("audio", "sfx_enabled", sfx_enabled)
	config.set_value("audio", "voice_enabled", voice_enabled)
	
	config.save("user://audio_settings.cfg")

func load_audio_settings():
	"""Загружает настройки из файла"""
	var config = ConfigFile.new()
	if config.load("user://audio_settings.cfg") != OK:
		print("🔊 Using default audio settings")
		return
	
	master_volume = config.get_value("audio", "master_volume", 1.0)
	music_volume = config.get_value("audio", "music_volume", 0.7)
	sfx_volume = config.get_value("audio", "sfx_volume", 0.8)
	voice_volume = config.get_value("audio", "voice_volume", 0.9)
	
	master_enabled = config.get_value("audio", "master_enabled", true)
	music_enabled = config.get_value("audio", "music_enabled", true)
	sfx_enabled = config.get_value("audio", "sfx_enabled", true)
	voice_enabled = config.get_value("audio", "voice_enabled", true)

# ============================================================================
# API ДЛЯ МЕНЮ
# ============================================================================
func get_master_volume() -> float:
	return master_volume

func get_music_volume() -> float:
	return music_volume

func get_sfx_volume() -> float:
	return sfx_volume

func get_voice_volume() -> float:
	return voice_volume

func is_master_enabled() -> bool:
	return master_enabled

func is_music_enabled() -> bool:
	return music_enabled

func is_sfx_enabled() -> bool:
	return sfx_enabled

func is_voice_enabled() -> bool:
	return voice_enabled

# ============================================================================
# БЫСТРЫЕ ФУНКЦИИ
# ============================================================================
func mute_all():
	set_master_enabled(false)

func unmute_all():
	set_master_enabled(true)

func reset_to_defaults():
	master_volume = 1.0
	music_volume = 0.7
	sfx_volume = 0.8
	voice_volume = 0.9
	
	master_enabled = true
	music_enabled = true
	sfx_enabled = true
	voice_enabled = true
	
	apply_all_audio_settings()
	save_audio_settings()
	
	print("🔊 Reset to defaults")

# ============================================================================
# DEBUG
# ============================================================================
func print_status():
	print("\n=== 🔊 AUDIO STATUS ===")
	print("Master: %.0f%% %s" % [master_volume * 100, "ON" if master_enabled else "OFF"])
	print("Music: %.0f%% %s" % [music_volume * 100, "ON" if music_enabled else "OFF"])
	print("SFX: %.0f%% %s" % [sfx_volume * 100, "ON" if sfx_enabled else "OFF"])
	print("Voice: %.0f%% %s" % [voice_volume * 100, "ON" if voice_enabled else "OFF"])
	print("======================\n")
