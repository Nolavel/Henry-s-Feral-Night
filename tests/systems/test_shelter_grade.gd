extends SceneTree

## The real TestScene: at the noon start, outside uses Day, entering the test
## shelter switches to Shelter, leaving restores the current outdoor Day LUT.
## Run: godot --headless --script tests/systems/test_shelter_grade.gd

const TEST_SCENE: String = "res://tests/scenes/TestScene.tscn"
const INSIDE: Vector3 = Vector3(0.0, 1.0, 14.0)
const OUTSIDE: Vector3 = Vector3(10.0, 1.0, 0.0)

var _failures: int = 0
var _frame: int = 0
var _scene: Node
var _grade: ColorGradeController

func _physics_process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_scene = (load(TEST_SCENE) as PackedScene).instantiate()
			root.add_child(_scene)
		20:
			_grade = _scene.find_child("ColorGradeController", true, false) as ColorGradeController
			_check(_grade != null, "TestScene has no ColorGradeController")
			if _grade == null:
				_finish()
				return false
			_scene.get_node("Player").global_position = OUTSIDE
		40:
			_check(_grade.get_current_profile_id() == ColorGradeController.DAY_PROFILE_ID, "outside at noon is not Day")
			_scene.get_node("Player").global_position = INSIDE
		60:
			_check(_grade.get_current_profile_id() == ColorGradeController.SHELTER_PROFILE_ID, "inside the shelter is not Shelter")
			_scene.get_node("Player").global_position = OUTSIDE
		80:
			_check(_grade.get_current_profile_id() == ColorGradeController.DAY_PROFILE_ID, "leaving did not restore Day")
			_finish()
	return false

func _finish() -> void:
	if _failures > 0:
		push_error("shelter grade: %d check(s) failed" % _failures)
		quit(1)
		return
	print("shelter grade: Day / Shelter switching passed")
	quit(0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("shelter grade: %s" % message)
