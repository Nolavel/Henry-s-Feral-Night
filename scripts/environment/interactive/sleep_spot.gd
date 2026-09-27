class_name SleepSpot
extends InteractiveArea

## A place Henry can sleep: a bed, mattress or bedroll. F opens the sleep dialog;
## there is no global sleep key. Whether sleep is safe is SleepController's call.

const PROMPT_KEY: String = "SLEEP_PROMPT"


func _ready() -> void:
	if player_animation_action == &"":
		player_animation_action = &"none"  # the dialog pauses the world at once
	super()
	set_item_name(tr(PROMPT_KEY))
	set_description("")


func _on_interaction_performed() -> void:
	var prompt := get_tree().get_first_node_in_group(SleepPrompt.GROUP) as SleepPrompt
	if prompt == null:
		return
	if not prompt.request_open():
		var refusal: SleepController.Refusal = prompt.sleep_controller.can_sleep() \
			if prompt.sleep_controller != null else SleepController.Refusal.NONE
		show_message(tr(SleepController.describe_refusal(refusal)))
