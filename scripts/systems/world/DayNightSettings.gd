extends Node
class_name DayNightSettings

@export_group("Time Settings")
@export var day_duration: float = 720.0 # 12 минут в секундах
@export var night_duration: float = 720.0 # 12 минут в секундах

@export_group("Light Settings")
@export var day_light_energy: float = 1.0
@export var night_light_energy: float = 0.1

@export_group("Realistic Lighting (NEW)")
@export var enable_realistic_lighting: bool = true
@export_subgroup("Sun Settings")
@export var sun_max_altitude: float = 60.0  # Максимальная высота солнца в полдень (градусы)
@export var sun_color_sunrise: Color = Color(1.0, 0.6, 0.4)  # Оранжевый рассвет
@export var sun_color_noon: Color = Color(1.0, 0.98, 0.95)   # Теплый белый
@export var sun_color_sunset: Color = Color(1.0, 0.5, 0.3)   # Красный закат

@export_subgroup("Moon Settings")
@export var moon_max_altitude: float = 40.0  # Максимальная высота луны (градусы)
@export var moon_color: Color = Color(0.7, 0.75, 0.85)      # Холодный голубоватый

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
