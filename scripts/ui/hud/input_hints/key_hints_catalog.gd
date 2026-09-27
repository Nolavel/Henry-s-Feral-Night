class_name KeyHintsCatalog
extends Resource

@export var entries: Array[KeyHintEntry] = []


func get_active_entries(mode: int, context: int) -> Array[KeyHintEntry]:
	var active: Array[KeyHintEntry] = []
	for entry: KeyHintEntry in entries:
		if entry != null and entry.matches(mode, context):
			active.append(entry)
	active.sort_custom(func(a: KeyHintEntry, b: KeyHintEntry) -> bool:
		return a.sort_order < b.sort_order)
	return active
