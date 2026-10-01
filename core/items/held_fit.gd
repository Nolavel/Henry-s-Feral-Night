class_name HeldFit
extends Resource

## Per-item hand pose, ported from ADT's item_fitter contract.
## Values are local to Henry's BoneAttachment3D socket.
enum Hand {
	LEFT,
	RIGHT,
}

@export var hand: Hand = Hand.LEFT
@export var offset: Vector3 = Vector3.ZERO
@export var rotation_deg: Vector3 = Vector3.ZERO
@export var scale: Vector3 = Vector3.ONE


func apply_to(prop: Node3D) -> void:
	if prop == null:
		return
	prop.position = offset
	prop.rotation_degrees = rotation_deg
	prop.scale = scale


static func apply_legacy_adjustment(prop: Node3D, item_id: StringName) -> void:
	## Exact pre-fitter Hoarbound pose. Kept only as a null-HeldFit fallback so
	## introducing the authoring tool does not visually move existing items.
	if prop == null:
		return
	prop.rotate_object_local(Vector3.BACK, PI)
	prop.rotate_object_local(Vector3.RIGHT, deg_to_rad(33.0))
	if item_id == &"knife":
		prop.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		return
	var grip_height: float = 0.08 if String(item_id).begins_with("water_flask") or item_id == &"axe" else 0.04
	prop.position -= prop.basis.y * grip_height
