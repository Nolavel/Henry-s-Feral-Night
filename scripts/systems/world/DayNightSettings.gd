# ============================================================================
# DayNightSettings.gd - Resource для хранения всех настроек
# ============================================================================
extends Node
class_name DayNightSettings

@export_group("Time Settings")
@export var day_duration: float = 720.0 # 12 минут в секундах
@export var night_duration: float = 720.0 # 12 минут в секундах

@export_group("Light Settings")
@export var day_light_energy: float = 1.0
@export var night_light_energy: float = 0.1

@export_group("Ambient Settings")
@export var day_ambient_color: Color = Color(0.7, 0.8, 1.0)
@export var night_ambient_color: Color = Color(0.1, 0.1, 0.2)
@export var day_sky_energy: float = 1.0
@export var night_sky_energy: float = 0.3

@export_group("Sky Colors - Day")
@export var day_sky_top_color: Color = Color(0.2, 0.4, 0.8)
@export var day_sky_horizon_color: Color = Color(0.6, 0.8, 1.0)
@export var day_ground_color: Color = Color(0.3, 0.25, 0.2)

@export_group("Sky Colors - Night")
@export var night_sky_top_color: Color = Color(0.05, 0.05, 0.15)
@export var night_sky_horizon_color: Color = Color(0.1, 0.1, 0.2)
@export var night_ground_color: Color = Color(0.05, 0.05, 0.1)

@export_group("Critical Night Settings")
@export var critical_night_day: int = 3
@export var critical_night_darkness_factor: float = 0.7
