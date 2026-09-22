class_name IceGaitBinder
extends Node

## Translates how Henry is moving into the load he puts on the ice. Reads the
## movement controller rather than editing it, so ownership stays clean.

## Emitted when the reported gait changes, for audio and animation to follow.
signal gait_changed(gait: IceField.Gait)

@export_group("Wiring")
@export var ice_field: IceField
## Body supplying the velocity; usually Henry's CharacterBody3D.
@export var character_body: CharacterBody3D
## Optional. When set, its sprint state wins over the speed threshold.
@export var movement_controller: MovementController

@export_group("Thresholds")
## Horizontal speed below which Henry counts as standing still, in m/s.
@export var still_speed_mps: float = 0.35
## Horizontal speed at or above which he counts as sprinting, in m/s. Ignored
## when a movement controller is wired.
@export var sprint_speed_mps: float = 6.0

@export_group("Crouch")
## Input action for crouching. The project has no crouch yet, so this is empty
## by default and CROUCH is simply never reported.
@export var crouch_action: StringName = &""

var _gait: IceField.Gait = IceField.Gait.STILL


func _physics_process(_delta: float) -> void:
	if character_body == null:
		return
	apply(character_body.velocity)


## Classifies a velocity and pushes the result to the field.
func apply(velocity: Vector3) -> IceField.Gait:
	var gait: IceField.Gait = classify(velocity)
	if gait != _gait:
		_gait = gait
		gait_changed.emit(gait)
	if ice_field != null:
		ice_field.set_gait(gait)
	return gait


## Gait for a velocity, without touching the field. Public so the HUD and the
## tests can ask the same question the binder answers.
func classify(velocity: Vector3) -> IceField.Gait:
	var speed: float = Vector2(velocity.x, velocity.z).length()
	if speed < still_speed_mps:
		return IceField.Gait.CROUCH if _is_crouching() else IceField.Gait.STILL
	if _is_crouching():
		return IceField.Gait.CROUCH
	if _is_sprinting(velocity, speed):
		return IceField.Gait.SPRINT
	return IceField.Gait.WALK


## Last gait reported to the field.
func get_gait() -> IceField.Gait:
	return _gait


func _is_sprinting(velocity: Vector3, speed: float) -> bool:
	if movement_controller != null:
		return movement_controller.is_currently_sprinting(velocity)
	return speed >= sprint_speed_mps


func _is_crouching() -> bool:
	if crouch_action == &"" or not InputMap.has_action(crouch_action):
		return false
	return Input.is_action_pressed(crouch_action)
