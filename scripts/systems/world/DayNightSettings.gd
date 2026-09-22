extends Node
class_name DayNightSettings

@export_group("Time Settings")
@export var day_duration: float = 720.0
@export var night_duration: float = 720.0

@export_group("Light Settings")
@export var day_light_energy: float = 1.0
@export var night_light_energy: float = 0.1

@export_group("Sun")
@export var sun_max_altitude: float = 60.0
@export var sun_color_sunrise: Color = Color(1.0, 0.6, 0.4)
@export var sun_color_noon: Color = Color(1.0, 0.98, 0.95)
@export var sun_color_sunset: Color = Color(1.0, 0.5, 0.3)

@export_group("Moon")
@export var moon_max_altitude: float = 40.0
@export var moon_color: Color = Color(0.7, 0.75, 0.85)

@export_group("Ambient")
@export var day_ambient_color: Color = Color(0.58, 0.64, 0.70)
@export var night_ambient_color: Color = Color(0.055, 0.065, 0.09)
@export var day_sky_energy: float = 0.75
@export var night_sky_energy: float = 0.18
@export var day_ground_color: Color = Color(0.22, 0.21, 0.20)
@export var night_ground_color: Color = Color(0.018, 0.021, 0.028)

@export_group("Overcast Sky")
@export var day_cloud_color: Color = Color(0.30, 0.39, 0.48)
@export var dawn_cloud_color: Color = Color(0.34, 0.30, 0.31)
@export var dusk_cloud_color: Color = Color(0.30, 0.24, 0.27)
@export var night_cloud_color: Color = Color(0.035, 0.050, 0.075)
@export_range(0.0, 128.0, 0.05) var day_overcast_exposure: float = 0.82
@export_range(0.0, 128.0, 0.05) var night_overcast_exposure: float = 0.24
@export_range(0.1, 12.0, 0.1) var cloud_density: float = 4.8
@export_range(0.0, 6.0, 0.1) var cloud_depth: float = 2.0
@export_range(0.25, 6.0, 0.05) var cloud_sag: float = 2.0
@export var cloud_tiling: Vector2 = Vector2(1.0, 1.0)
@export var cloud_wind_speed: Vector2 = Vector2(0.24, 0.08)
@export_range(0.1, 20.0, 0.1) var cloud_light_energy_scale: float = 5.0
@export_range(0.001, 0.2, 0.001) var ground_curve: float = 0.04

@export_group("Cloud Noise")
@export var cloud_noise_seed: int = 1731
@export_range(64, 1024, 64) var cloud_noise_size: int = 256
@export_range(0.0005, 0.1, 0.0005) var cloud_noise_frequency: float = 0.008
@export_range(1, 8, 1) var cloud_noise_octaves: int = 5

@export_group("Critical Night")
@export var critical_night_day: int = 3
@export_range(0.0, 1.0, 0.05) var critical_night_darkness_factor: float = 0.7
