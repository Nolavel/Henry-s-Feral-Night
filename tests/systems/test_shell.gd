extends SceneTree

## Covers the minimal shell: Continue restores the night Henry slept through —
## time, place, hunger, pack — and Esc pauses without saving anything.
## Run: godot --headless --script tests/systems/test_shell.gd

## A slot the game never writes, so the suite cannot clobber a real save.
const TEST_SLOT: int = 5

var _failures: int = 0
var _frame: int = 0
var _world: World


## Two frames: the pending load is deferred, so it only lands on the second.
func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_test_a_save_carries_the_whole_night()
		_test_the_pause_menu_pauses_and_resumes()
		_test_the_pause_menu_stays_out_of_the_sleep_dialog()
		_test_continue_needs_a_save()
		_begin_pending_load()
		return false
	_finish_pending_load()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.slot_path(TEST_SLOT)))
	if _failures > 0:
		push_error("shell: %d check(s) failed" % _failures)
		quit(1)
		return true
	print("shell: all checks passed")
	quit(0)
	return true


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("shell: %s" % message)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


## A world with the player-side nodes a real save touches.
func _make_world() -> World:
	var world := World.new()
	var player := CharacterBody3D.new()
	player.name = "Player"
	world.add_child(player)
	var camera := Camera3D.new()
	camera.name = "PlayerCamera"
	world.add_child(camera)

	var clock := DayNightManager.new()
	clock.name = "DayNightManager"
	player.add_child(clock)
	var bio := BioMonitorManager.new()
	bio.name = "BioMonitorManager"
	player.add_child(bio)
	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	player.add_child(inventory)

	root.add_child(world)
	world.initialize()
	return world


func _player(world: World) -> CharacterBody3D:
	return world.get_node("Player") as CharacterBody3D


func _node(world: World, name: String) -> Node:
	return _player(world).get_node(name)


func _save_manager(world: World) -> SaveManager:
	return world.get_context().get_system(SaveManager) as SaveManager


## Everything Continue promises in issue #7 — heat, time, pack — plus where he
## lay down, which a sleep save is worthless without.
func _test_a_save_carries_the_whole_night() -> void:
	var world := _make_world()
	var clock := _node(world, "DayNightManager") as DayNightManager
	var bio := _node(world, "BioMonitorManager") as BioMonitorManager
	var inventory := _node(world, "InventoryComponent") as InventoryComponent

	clock.total_game_time_hours = 51.5
	_player(world).global_position = Vector3(31.0, 2.0, -14.0)
	bio.current_calories = 640.0
	inventory.try_add(ItemCatalog.get_item(&"firewood"))

	var saves := _save_manager(world)
	_check(saves.save_to_slot(TEST_SLOT), "the save did not land: %s" % saves.get_last_error())

	clock.total_game_time_hours = 6.0
	_player(world).global_position = Vector3.ZERO
	bio.current_calories = 2500.0
	inventory.try_remove(&"firewood")

	_check(saves.load_from_slot(TEST_SLOT), "the load failed: %s" % saves.get_last_error())
	_check(
		is_equal_approx(clock.total_game_time_hours, 51.5),
		"the clock came back at %.2f h" % clock.total_game_time_hours
	)
	_check(
		_player(world).global_position.is_equal_approx(Vector3(31.0, 2.0, -14.0)),
		"Henry woke up at %s, not where he slept" % str(_player(world).global_position)
	)
	_check(is_equal_approx(bio.current_calories, 640.0), "hunger was not restored")
	_check(inventory.has_item(&"firewood"), "the pack came back empty")
	_dispose(world)


func _test_the_pause_menu_pauses_and_resumes() -> void:
	var menu := (load("res://scenes/ui/menu/pause_menu.tscn") as PackedScene).instantiate() as PauseMenu
	root.add_child(menu)
	menu.open()
	_check(menu.is_open(), "the pause menu did not open")
	_check(paused, "opening the pause menu did not pause the tree")
	menu.resume()
	_check(not menu.is_open(), "the pause menu did not close")
	_check(not paused, "resuming left the tree paused")
	_dispose(menu)


## Esc belongs to whichever modal is already up. The sleep dialog holds the
## menu mode while open, and Esc there must close it, not stack a pause on top.
func _test_the_pause_menu_stays_out_of_the_sleep_dialog() -> void:
	var state: Node = root.get_node_or_null(^"PlayerState")
	if state == null:
		return
	var menu := (load("res://scenes/ui/menu/pause_menu.tscn") as PackedScene).instantiate() as PauseMenu
	root.add_child(menu)
	state.call(&"open_menu")

	var esc := InputEventAction.new()
	esc.action = PauseMenu.PAUSE_ACTION
	esc.pressed = true
	menu._unhandled_input(esc)
	_check(not menu.is_open(), "Esc opened a pause menu on top of another modal")

	state.call(&"close_menu")
	menu._unhandled_input(esc)
	_check(menu.is_open(), "Esc did not open the pause menu with nothing else up")
	menu.resume()
	_dispose(menu)


func _test_continue_needs_a_save() -> void:
	## The real sleep slot is never touched by this suite; only the static
	## check that the title menu relies on is exercised here.
	_check(
		SaveManager.has_sleep_save() == FileAccess.file_exists(SaveManager.slot_path(SaveManager.SLEEP_SLOT)),
		"has_sleep_save() disagrees with the file on disk"
	)


## The title menu hands the slot over before the game scene exists; the world
## applies it only after every system has adopted its scene state.
func _begin_pending_load() -> void:
	var source := _make_world()
	(_node(source, "DayNightManager") as DayNightManager).total_game_time_hours = 77.0
	_save_manager(source).save_to_slot(TEST_SLOT)
	_dispose(source)

	SaveManager.pending_load_slot = TEST_SLOT
	_world = _make_world()
	_check(
		not is_equal_approx(
			(_node(_world, "DayNightManager") as DayNightManager).total_game_time_hours, 77.0
		),
		"the pending load landed synchronously, before later systems were ready"
	)


func _finish_pending_load() -> void:
	var clock := _node(_world, "DayNightManager") as DayNightManager
	## The clock has run for a frame since the load, so allow a sliver.
	_check(
		absf(clock.total_game_time_hours - 77.0) < 0.25,
		"Continue did not restore the saved night: clock at %.2f h" % clock.total_game_time_hours
	)
	_check(SaveManager.pending_load_slot == -1, "the pending slot was not cleared")
	_dispose(_world)
