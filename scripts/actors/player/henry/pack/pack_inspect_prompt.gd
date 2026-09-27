class_name PackInspectPrompt
extends InteractiveArea

## F on the pack while it is set down beside Henry: open it for full inspection.

const PROMPT_KEY: String = "PACK_INSPECT"


func _ready() -> void:
	if player_animation_action == &"":
		player_animation_action = &"none"
	super()
	set_item_name(tr(PROMPT_KEY))
	set_description("")


func _on_interaction_performed() -> void:
	var player: Node = get_tree().get_first_node_in_group(&"player")
	var hub := player.get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent if player != null else null
	if hub != null:
		hub.open_inspection()
