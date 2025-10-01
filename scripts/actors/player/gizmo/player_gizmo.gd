# 🐾 player -> gizmo (robot) - только обработка ввода
extends CharacterBody3D

@onready var flashlight = $Flashlight_Gizmo

@export var hold_time: float = 0.55

var hold_timer := 0.0
var holding := false

func _process(delta: float) -> void:
	# включение/выключение по удержанию
	if Input.is_action_pressed("toggle_flashlight"):
		hold_timer += delta
		if not holding and hold_timer >= hold_time:
			holding = true
			flashlight.call("Toggle")
	else:
		hold_timer = 0.0
		holding = false

	# переключение режима (только когда фонарь включён)
	if flashlight.call("IsOn") and Input.is_action_just_pressed("modify_option"):
		flashlight.call("ToggleMode")
