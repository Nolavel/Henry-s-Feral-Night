class_name StoveDoorControl
extends InteractiveArea

## A moving door target keeps F door control distinct from the firebox target.
var feed: HeatSourceFeed


func can_interact() -> bool:
	return is_instance_valid(feed)


func _on_interaction_performed() -> void:
	if feed != null:
		if feed.is_acting():
			feed.cancel_act()
		else:
			feed.toggle_door()


func _get_interaction_text() -> String:
	return "[%s] %s" % [_interact_key_label(), tr("STOVE_CLOSE" if feed != null and feed.is_door_open() else "STOVE_OPEN")]


func is_aim_on_door(from: Vector3, direction: Vector3) -> bool:
	var local_from: Vector3 = to_local(from)
	var local_direction: Vector3 = global_basis.inverse() * direction
	if absf(local_direction.x) < 0.0001:
		return false
	var distance: float = -local_from.x / local_direction.x
	var hit: Vector3 = local_from + local_direction * distance
	return distance >= 0.0 and absf(hit.y) <= StoveVisual.DOOR_H * 0.5 and absf(hit.z) <= StoveVisual.DOOR_W * 0.5


func _input(event: InputEvent) -> void:
	if not _targeted or not shape_cast_detected or (feed != null and feed.is_acting()):
		return
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		get_viewport().set_input_as_handled()
