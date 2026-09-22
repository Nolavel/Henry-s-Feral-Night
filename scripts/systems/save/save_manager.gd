class_name SaveManager
extends Node

## Collects state from every registered participant and writes it atomically to
## a slot. Meant to be an autoload; sleeping is the only thing that calls save().

## Emitted after a slot is written successfully.
signal save_completed(slot: int)
## Emitted when a save could not be written, with a human-readable reason.
signal save_failed(slot: int, reason: String)
## Emitted after a slot has been applied to every participant.
signal load_completed(slot: int)
## Emitted when a slot could not be loaded, with a human-readable reason.
signal load_failed(slot: int, reason: String)

## Nodes in this group are asked for their state when a save is written.
const SAVEABLE_GROUP: StringName = &"saveable"
const SAVE_DIR: String = "user://saves"
## Bumped whenever the payload layout changes; older files are migrated.
const SAVE_VERSION: int = 1
## Slot used by the autosave that sleeping performs.
const SLEEP_SLOT: int = 0

@export_group("Slots")
## Highest slot index the game offers, beyond the sleep autosave.
@export var max_slot: int = 5

var _last_error: String = ""
var _registered: Array[Node] = []


## Registers a participant explicitly. Use this from _ready() when a system
## must be saved regardless of when the scene tree settles.
func register(node: Node) -> void:
	if node == null or _registered.has(node):
		return
	if not (node.has_method("get_save_data") and node.has_method("load_save_data")):
		push_warning("SaveManager: '%s' cannot be registered, it lacks the save methods" % node.name)
		return
	_registered.append(node)


## Drops a participant; freed nodes are pruned automatically as well.
func unregister(node: Node) -> void:
	_registered.erase(node)


## Human-readable reason for the most recent failure, empty when none.
func get_last_error() -> String:
	return _last_error


## Writes every participant's state to the given slot. Returns true on success.
func save_to_slot(slot: int, metadata: Dictionary = {}) -> bool:
	if not _is_valid_slot(slot):
		return _fail_save(slot, "slot %d is out of range" % slot)

	var participants: Array[Node] = _get_participants()
	if participants.is_empty():
		return _fail_save(slot, "no save participants; refusing to write an empty save")

	var payload: Dictionary = {}
	for node: Node in participants:
		var id: String = _resolve_id(node)
		if payload.has(id):
			return _fail_save(slot, "duplicate save id '%s'" % id)
		var data: Variant = node.call("get_save_data")
		if typeof(data) != TYPE_DICTIONARY:
			return _fail_save(slot, "participant '%s' did not return a Dictionary" % id)
		payload[id] = data

	var document: Dictionary = {
		"version": SAVE_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"metadata": metadata,
		"payload": payload,
	}
	if not _write_atomically(_slot_path(slot), JSON.stringify(document, "\t")):
		return _fail_save(slot, _last_error)

	_last_error = ""
	save_completed.emit(slot)
	return true


## Applies a slot to every participant. Returns true when the slot was applied.
func load_from_slot(slot: int) -> bool:
	var document: Dictionary = read_slot(slot)
	if document.is_empty():
		load_failed.emit(slot, _last_error)
		return false

	var payload: Dictionary = document.get("payload", {})
	for node: Node in _get_participants():
		var id: String = _resolve_id(node)
		if payload.has(id):
			node.call("load_save_data", payload[id])

	_last_error = ""
	load_completed.emit(slot)
	return true


## Reads and migrates a slot without applying it; empty means unreadable.
func read_slot(slot: int) -> Dictionary:
	if not _is_valid_slot(slot):
		_last_error = "slot %d is out of range" % slot
		return {}
	var path: String = _slot_path(slot)
	if not FileAccess.file_exists(path):
		_last_error = "slot %d is empty" % slot
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_last_error = "cannot open slot %d (error %d)" % [slot, FileAccess.get_open_error()]
		return {}
	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_last_error = "slot %d is corrupt" % slot
		return {}
	return _migrate(parsed as Dictionary)


## True when the slot holds a readable save.
func has_slot(slot: int) -> bool:
	return _is_valid_slot(slot) and FileAccess.file_exists(_slot_path(slot))


## Deletes a slot. Returns true when the slot is gone afterwards.
func delete_slot(slot: int) -> bool:
	if not has_slot(slot):
		return true
	var error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(_slot_path(slot)))
	if error != OK:
		_last_error = "cannot delete slot %d (error %d)" % [slot, error]
		return false
	return true


## Metadata for every populated slot, for a load menu. Corrupt slots are
## reported with `corrupt = true` rather than hidden.
func list_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for slot: int in range(0, max_slot + 1):
		if not has_slot(slot):
			continue
		var document: Dictionary = read_slot(slot)
		if document.is_empty():
			slots.append({"slot": slot, "corrupt": true})
			continue
		slots.append({
			"slot": slot,
			"corrupt": false,
			"saved_at_unix": int(document.get("saved_at_unix", 0)),
			"metadata": document.get("metadata", {}),
		})
	return slots


## Every node that opted in, whether by group membership or explicit
## registration. Duplicates and freed nodes are dropped.
func _get_participants() -> Array[Node]:
	var participants: Array[Node] = []
	var live: Array[Node] = []
	for node: Node in _registered:
		if is_instance_valid(node):
			live.append(node)
			participants.append(node)
	if live.size() != _registered.size():
		_registered = live

	if is_inside_tree():
		for node: Node in get_tree().get_nodes_in_group(SAVEABLE_GROUP):
			if participants.has(node):
				continue
			if node.has_method("get_save_data") and node.has_method("load_save_data"):
				participants.append(node)
			else:
				push_warning(
					"SaveManager: '%s' is saveable but lacks the save methods" % node.name
				)
	return participants


## Participants may declare a stable id; otherwise the node name is used.
func _resolve_id(node: Node) -> String:
	if node.has_method("save_id"):
		return String(node.call("save_id"))
	return node.name


## Writes via a temporary file and renames, so a crash cannot leave a half save.
func _write_atomically(path: String, text: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(path)
	var error: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK and error != ERR_ALREADY_EXISTS:
		_last_error = "cannot create the save directory (error %d)" % error
		return false

	var temporary: String = path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		_last_error = "cannot open the save file (error %d)" % FileAccess.get_open_error()
		return false
	file.store_string(text)
	file.close()

	var dir := DirAccess.open(absolute.get_base_dir())
	if dir == null:
		_last_error = "cannot open the save directory"
		return false
	if FileAccess.file_exists(path):
		dir.remove(path.get_file())
	error = dir.rename(temporary.get_file(), path.get_file())
	if error != OK:
		_last_error = "cannot finalise the save file (error %d)" % error
		return false
	return true


## Upgrades an older document to the current layout. Unknown future versions
## are passed through untouched rather than silently mangled.
func _migrate(document: Dictionary) -> Dictionary:
	var version: int = int(document.get("version", 0))
	if version == SAVE_VERSION:
		return document
	if version > SAVE_VERSION:
		push_warning("SaveManager: slot was written by a newer build (v%d)" % version)
		return document
	if version < 1:
		document["payload"] = document.get("payload", {})
		document["metadata"] = document.get("metadata", {})
		document["version"] = SAVE_VERSION
	return document


func _slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


func _is_valid_slot(slot: int) -> bool:
	return slot >= 0 and slot <= max_slot


func _fail_save(slot: int, reason: String) -> bool:
	_last_error = reason
	push_warning("SaveManager: save to slot %d failed: %s" % [slot, reason])
	save_failed.emit(slot, reason)
	return false
