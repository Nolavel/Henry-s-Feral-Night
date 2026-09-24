extends SceneTree

## Headless contract check for the flare's gameplay seam.
## GPU particle rendering is intentionally skipped in headless mode.

const FLARE_SCENE := preload("res://scenes/actors/player/held/HeldFlare.tscn")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var flare := FLARE_SCENE.instantiate() as HeldFlare
	root.add_child(flare)
	await process_frame

	_check(flare != null, "HeldFlare scene did not instantiate")
	if flare == null:
		_finish()
		return
	_check(flare.get_node_or_null("Body") != null, "flare body was not built")
	_check(flare.get_node_or_null("Tip/HotCore") != null, "hot core was not built")
	_check(flare.get_node_or_null("Tip/FlareLight") != null, "real light was not built")
	_check(flare.is_burning(), "auto_ignite did not light the flare")
	_check(flare.get_current_energy() > 0.0, "burning flare reports zero energy")
	_check(is_equal_approx(flare.base_light_energy, 2.8), "review-tuned base light energy regressed")
	_check(is_equal_approx(flare.light_range_m, 4.5), "review-tuned light range regressed")

	flare.extinguish()
	_check(not flare.is_burning(), "extinguish did not stop the flare")
	_check(is_zero_approx(flare.get_current_energy()), "extinguished flare still reports energy")

	flare.ignite()
	_check(flare.is_burning(), "ignite did not relight the flare")
	_check(flare.get_remaining_seconds() > 0.0, "relit flare has no burn time")
	_finish()


func _finish() -> void:
	if _failures > 0:
		push_error("held flare: %d check(s) failed" % _failures)
		quit(1)
		return
	print("held flare: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("held flare: %s" % message)
