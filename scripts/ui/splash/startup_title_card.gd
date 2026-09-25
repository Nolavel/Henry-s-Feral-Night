class_name StartupTitleCard
extends CanvasLayer

## A restrained startup card displayed only when the island is the actual
## project scene. Runtime capture tools instantiate the island themselves, so
## they skip the card instead of recording a black frame.

@export_range(0.0, 2.0, 0.05) var fade_in_seconds: float = 0.35
@export_range(0.0, 5.0, 0.05) var hold_seconds: float = 1.35
@export_range(0.0, 2.0, 0.05) var fade_out_seconds: float = 0.65

@onready var _cover: Control = $Cover
@onready var _titles: VBoxContainer = $Cover/Center/Titles


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_titles.modulate.a = 0.0
	call_deferred("_play_if_project_scene")


func _play_if_project_scene() -> void:
	if get_tree().current_scene != get_parent():
		queue_free()
		return

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_titles, "modulate:a", 1.0, fade_in_seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold_seconds)
	tween.tween_property(_cover, "modulate:a", 0.0, fade_out_seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	queue_free()
