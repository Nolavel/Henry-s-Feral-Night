# ✅ Script: WorldEnvironmentController.gd  - Master Controller
extends Node3D

class_name WorldEnvironmentController

@export_group ("WorldSystems")
@export var day_night_manager: DayNightManager
@export var weather_controller: WeatherController 
@export var time_accelerator: TimeAccelerator
@export var world_environment: WorldEnvironment
@export var sun_light: DirectionalLight3D
@export var color_grade_controller: ColorGradeController
#@export var moon_light: DirectionalLight3D
