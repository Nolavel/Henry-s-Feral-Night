extends Node

## Makes the production StartupTitleCard believe this lightweight wrapper is
## the active project scene, so the existing screenshot harness can capture it.
func _ready() -> void:
	get_tree().current_scene = self
