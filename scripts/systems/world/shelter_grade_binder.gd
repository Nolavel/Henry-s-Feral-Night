class_name ShelterGradeBinder
extends Node

## Switches the colour grade on the shelter edge: ThermalManager owns "inside",
## ColorGradeController owns the grade; this only connects the two (#31).

const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const GRADE_SCRIPT: GDScript = preload("res://scripts/systems/world/ColorGradeController.gd")

var _thermal: ThermalManager
var _grade: ColorGradeController


func on_world_ready(context: WorldContext) -> void:
	_thermal = context.get_system(THERMAL_SCRIPT) as ThermalManager
	_grade = context.find_in_scene(GRADE_SCRIPT) as ColorGradeController
	if _thermal == null or _grade == null:
		push_warning("ShelterGradeBinder: thermal or colour grade missing, grade stays outdoor.")
		return
	if not _thermal.sheltered_changed.is_connected(_on_sheltered_changed):
		_thermal.sheltered_changed.connect(_on_sheltered_changed)
	_grade.initialize_for_interior(_thermal.is_sheltered())


func _on_sheltered_changed(is_sheltered: bool) -> void:
	if is_instance_valid(_grade):
		_grade.initialize_for_interior(is_sheltered)
