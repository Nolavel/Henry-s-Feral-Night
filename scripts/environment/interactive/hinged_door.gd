class_name HingedDoor
extends InteractiveArea

## A full-size exterior door. The leaf and its StaticBody are children of the
## same hinge, so the visible swing and the passage collision cannot disagree.

signal door_toggled(open: bool)

const OPEN_KEY: String = "HOUSE_DOOR_OPEN"
const CLOSE_KEY: String = "HOUSE_DOOR_CLOSE"

@export_group("Door")
@export var door_hinge: Node3D
@export var open_angle_deg: float = 105.0
@export_range(0.0, 1.0, 0.05) var hand_delay: float = 0.2
@export_range(0.1, 1.5, 0.05) var swing_time: float = 0.45
@export var starts_open: bool = false
## The shelter's damaged doorway can still leak while the leaf is closed. Once
## it is boarded, the door closes and stops offering an interaction.
@export var breach: ShelterBreach

var _open: bool = false
var _tween: Tween


func _ready() -> void:
	interaction_type = InteractionType.DOOR
	_open = starts_open
	if door_hinge != null:
		door_hinge.rotation.y = deg_to_rad(open_angle_deg) if _open else 0.0
	if breach != null and not breach.boarded_changed.is_connected(_on_breach_boarded_changed):
		breach.boarded_changed.connect(_on_breach_boarded_changed)
	super()
	_refresh_prompt()
	call_deferred("_sync_breach")


func is_open() -> bool:
	return _open


func is_swinging() -> bool:
	return _tween != null and _tween.is_running()


func can_interact() -> bool:
	return (
		super()
		and door_hinge != null
		and not is_swinging()
		and (breach == null or not breach.is_boarded())
	)


func _on_interaction_performed() -> void:
	_open = not _open
	var target: float = deg_to_rad(open_angle_deg) if _open else 0.0
	_tween = create_tween()
	_tween.tween_interval(hand_delay)
	_tween.tween_property(door_hinge, ^"rotation:y", target, swing_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if _open else Tween.EASE_IN_OUT)
	_refresh_prompt()
	door_toggled.emit(_open)


func _get_interaction_text() -> String:
	return "[%s] %s" % [_interact_key_label(), tr(CLOSE_KEY if _open else OPEN_KEY)]


func _on_breach_boarded_changed(_boarded: bool) -> void:
	_sync_breach()


func _sync_breach() -> void:
	if breach == null or not breach.is_boarded():
		_refresh_prompt()
		return
	if _tween != null:
		_tween.kill()
	_open = false
	if door_hinge != null:
		door_hinge.rotation.y = 0.0
	_refresh_prompt()


func _refresh_prompt() -> void:
	set_item_name(tr(CLOSE_KEY if _open else OPEN_KEY))
	set_description("")
	if info_label != null and info_label.visible:
		info_label.text = _get_interaction_text()
