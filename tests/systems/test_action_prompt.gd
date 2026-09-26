extends SceneTree

const PROMPT_SCENE := preload("res://scenes/ui/hud/action_prompt/action_prompt_3d.tscn")
var failures := 0


func _initialize() -> void:
	var prompt := PROMPT_SCENE.instantiate() as ActionPrompt3D
	_check(prompt != null, "ActionPrompt3D scene does not instantiate")
	if prompt == null:
		quit(1)
		return
	root.add_child(prompt)
	_check(prompt.is_in_group(&"action_prompt_3d"), "prompt did not register its lookup group")
	var billboard := prompt.get_node_or_null(^"Billboard") as Sprite3D
	var viewport := prompt.get_node_or_null(^"Face") as SubViewport
	_check(billboard != null and billboard.no_depth_test, "3D banner is not always-on-top")
	_check(viewport != null and viewport.size == Vector2i(384, 160), "prompt viewport size changed")
	_check(is_equal_approx(prompt.billboard_pixel_size, 0.0020), "prompt is no longer the smaller requested scale")

	var area := InteractiveArea.new()
	area.interaction_type = InteractiveArea.InteractionType.PICKUP
	area.item_name = "Firewood"
	area.description = "Dry fuel"
	root.add_child(area)
	var data := area.get_interaction_prompt_data()
	_check(String(data.get("key")) == "F", "prompt key is not resolved live from InputMap")
	_check(String(data.get("action")) == tr("INTERACT_PICKUP"), "pickup action text is wrong")
	_check(String(data.get("detail")) == "Dry fuel", "short description is not preserved")

	area.queue_free()
	prompt.queue_free()
	print("test_action_prompt: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


func _check(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error("action prompt: %s" % message)
