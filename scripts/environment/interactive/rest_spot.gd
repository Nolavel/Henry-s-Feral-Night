class_name RestSpot
extends InteractiveArea

## A seat by the stove: a chair, a crate, the edge of a bed. F sits Henry down
## (RestComponent); the node's -Z is where he faces.

const PROMPT_KEY: String = "REST_PROMPT"


func _ready() -> void:
	if player_animation_action == &"":
		player_animation_action = &"none"  # the sit clip plays from the state machine
	super()
	set_item_name(tr(PROMPT_KEY))
	set_description("")


func _on_interaction_performed() -> void:
	var player: Node = get_tree().get_first_node_in_group(&"player")
	var rest: RestComponent = player.get_node_or_null(^"RestComponent") as RestComponent if player != null else null
	if rest != null:
		rest.sit(self)
