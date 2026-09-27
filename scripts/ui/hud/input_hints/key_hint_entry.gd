class_name KeyHintEntry
extends Resource

## One row in the ADT-style controls blot. Labels are resolved live from InputMap.
enum Context { DEFAULT, HUB, SITTING }
enum Category { MOVEMENT, ACTION }

@export var action_name: StringName = &""
@export var action_names: Array[StringName] = []
@export var description: String = ""
@export var category: Category = Category.ACTION

@export_group("Visible when")
## PlayerState.Mode integer values. Empty = any.
@export var modes: Array[int] = []
## Context values. Empty = any.
@export var contexts: Array[int] = []

@export_group("Ordering")
@export var sort_order: int = 0


func matches(mode: int, context: int) -> bool:
	if not modes.is_empty() and not modes.has(mode):
		return false
	if not contexts.is_empty() and not contexts.has(context):
		return false
	return true


func get_action_names() -> Array[StringName]:
	if not action_names.is_empty():
		return action_names
	return [action_name]


func get_row_key() -> StringName:
	var names := get_action_names()
	if names.is_empty():
		return &""
	var joined := String(names[0])
	for i in range(1, names.size()):
		joined += "|" + String(names[i])
	return StringName(joined)
