class_name AfflictionDefinition
extends Resource

## Static, shared definition. Runtime state must never be written back here.

@export var id: StringName = &""
@export var display_key: String = ""
@export var stackable: bool = false
@export_range(0.01, 10.0, 0.01) var max_severity: float = 1.0
## Named multiplier at max severity. Runtime interpolates from 1.0 by severity.
@export var modifiers: Dictionary = {}
@export var recovery_key: String = ""
