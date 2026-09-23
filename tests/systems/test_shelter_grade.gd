extends SceneTree

## The real TestScene: walking into the test shelter switches the colour grade
## to Shelter, walking out brings Night back (#31).
## Run: godot --headless --script tests/systems/test_shelter_grade.gd

const TEST_SCENE: String = "res://tests/scenes/TestScene.tscn"
## Inside the test shelter at (0, 0, 14), and open ground away from it.
const INSIDE: Vector3 = Vector3(0.0, 1.0, 14.0)
const OUTSIDE: Vector3 = Vector3(10.0, 1.0, 0.0)

var _failures: int = 0
var _frame: int = 0
var _scene: Node
var _grade: ColorGradeController


## Stages step on physics frames, where area overlaps update.
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
			_check(_grade.get_current_profile_id() == ColorGradeController.OUTDOOR_PROFILE_ID, "outside is not Night")
			_scene.get_node("Player").global_position = INSIDE
		60:
			_check(_grade.get_current_profile_id() == ColorGradeController.SHELTER_PROFILE_ID, "inside the shelter is not Shelter")
			_scene.get_node("Player").global_position = OUTSIDE
		80:
			_check(_grade.get_current_profile_id() == ColorGradeController.OUTDOOR_PROFILE_ID, "leaving did not bring Night back")
			_finish()
	return false


func _finish() -> void:
	if _failures > 0:
		push_error("shelter grade: %d check(s) failed" % _failures)
		quit(1)
		return
	print("shelter grade: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("shelter grade: %s" % message)
