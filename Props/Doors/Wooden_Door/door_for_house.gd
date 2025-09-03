extends Node3D

# Состояние двери
var is_open = false

# Ссылка на UI
var hint_ui: InteractionHintUI
# === STATE VARIABLES ===
var player_in_range: bool = false
var player_reference: Node3D = null
# Зона для определения, что игрок рядом

func _ready():
	# Получаем UI по группе
	var ui_nodes = get_tree().get_nodes_in_group("InteractionHintUI")
	if ui_nodes.size() > 0:
		hint_ui = ui_nodes[0]

	# Скрываем подсказку при старте
	if hint_ui:
		hint_ui.hide_prompt()

func _on_body_entered(body):
	if body.is_in_group("Player") and hint_ui:
		if is_open:
			hint_ui.show_prompt(InteractionHintUI.ActionType.CLOSE)
		else:
			hint_ui.show_prompt(InteractionHintUI.ActionType.OPEN)

func _on_body_exited(body):
	if body.is_in_group("Player") and hint_ui:
		hint_ui.hide_prompt()

func _input(event):
	if event.is_action_pressed("interact"): # "interact" = клавиша E
		if hint_ui and not hint_ui.is_hidden():
			_toggle_door()

func _toggle_door():
	is_open = !is_open
	if is_open:
		print("Дверь открыта")
		if hint_ui:
			hint_ui.show_prompt(InteractionHintUI.ActionType.CLOSE)
	else:
		print("Дверь закрыта")
		if hint_ui:
			hint_ui.show_prompt(InteractionHintUI.ActionType.OPEN)


func _on_collision_shape_3d_visibility_changed() -> void:
	pass # Replace with function body.

func interaction_triggered(source: Node3D):
	print("BackpackPickup: Interaction triggered by ShapeCast from %s" % source.name)
	player_reference = source
	player_in_range = true

	if source is ShapeCast3D:
			print("Door opened")
	else:
		print("Door Closed")
