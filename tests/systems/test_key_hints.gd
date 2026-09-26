extends SceneTree

const PANEL_SCENE := preload("res://scenes/ui/hud/input_hints/key_hints_panel.tscn")
const CATALOG := preload("res://data/key_hints.tres")
const SHADER_PATH := "res://shaders/ui/key_hints_blot.gdshader"
var failures := 0


func _initialize() -> void:
	var panel := PANEL_SCENE.instantiate() as KeyHintsPanel
	_check(panel != null, "panel scene does not instantiate")
	if panel == null:
		quit(1)
		return
	root.add_child(panel)
	_check(is_equal_approx(panel.right_margin, 24.0), "ADT right margin changed")
	_check(is_equal_approx(panel.bottom_margin, 20.0), "ADT bottom margin changed")
	_check(is_equal_approx(panel.panel_scale, 0.82), "ADT panel scale changed")
	var blot := panel.get_node_or_null(^"BlotLayer") as ColorRect
	_check(blot != null, "blot layer missing")
	if blot != null:
		var material := blot.material as ShaderMaterial
		_check(material != null and material.shader != null and material.shader.resource_path == SHADER_PATH,
			"ADT blot shader is not wired")

	var normal := CATALOG.get_active_entries(PlayerState.Mode.ON_FOOT, KeyHintEntry.Context.DEFAULT)
	var hub := CATALOG.get_active_entries(PlayerState.Mode.ON_FOOT, KeyHintEntry.Context.HUB)
	var sitting := CATALOG.get_active_entries(PlayerState.Mode.ON_FOOT, KeyHintEntry.Context.SITTING)
	_check(normal.size() == 10, "normal gameplay catalog should have 10 concise rows")
	_check(hub.size() == 2, "Hub should replace gameplay controls with 2 rows")
	_check(sitting.size() == 4, "sitting should replace gameplay controls with 4 rows")
	_check(CATALOG.get_active_entries(PlayerState.Mode.SLEEPING, KeyHintEntry.Context.DEFAULT).is_empty(),
		"sleeping must hide controls")
	_check(String(panel.call(&"_resolve_key_label", &"interact")) == "F", "interact key is not resolved live as F")
	panel.queue_free()
	print("test_key_hints: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


func _check(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error("key hints: %s" % message)
