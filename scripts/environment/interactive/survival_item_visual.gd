class_name SurvivalItemVisual
extends RefCounted

## Shared readable props for world pickups and the meal table; no inventory state.
static func make(item_id: StringName) -> Node3D:
	var holder := Node3D.new()
	if String(item_id).begins_with("water_flask"):
		var body := BoxMesh.new()
		body.size = Vector3(0.12, 0.19, 0.07)
		_part(holder, body, Vector3(0, 0.105, 0), Color(0.20, 0.42, 0.43))
		var neck := CylinderMesh.new()
		neck.top_radius = 0.025
		neck.bottom_radius = 0.025
		neck.height = 0.04
		_part(holder, neck, Vector3(0, 0.215, 0), Color(0.18, 0.19, 0.20))
		var stripe := BoxMesh.new()
		stripe.size = Vector3(0.065, 0.035, 0.074)
		_part(holder, stripe, Vector3(0, 0.14, 0), Color(0.84, 0.87, 0.78))
	elif item_id == &"knife":
		var handle := BoxMesh.new()
		handle.size = Vector3(0.04, 0.03, 0.10)
		_part(holder, handle, Vector3(0, 0.025, 0.06), Color(0.28, 0.18, 0.11))
		var blade := PrismMesh.new()
		blade.size = Vector3(0.028, 0.012, 0.14)
		_part(holder, blade, Vector3(0, 0.025, -0.06), Color(0.72, 0.76, 0.78))
	else:
		var tin := CylinderMesh.new()
		tin.top_radius = 0.055
		tin.bottom_radius = 0.055
		tin.height = 0.10
		_part(holder, tin, Vector3(0, 0.055, 0), Color(0.64, 0.67, 0.66))
		var label := CylinderMesh.new()
		label.top_radius = 0.056
		label.bottom_radius = 0.056
		label.height = 0.062
		_part(holder, label, Vector3(0, 0.055, 0), Color(0.88, 0.67, 0.12) if item_id == &"tinned_pineapple" else Color(0.62, 0.18, 0.12))
	return holder


static func _part(holder: Node3D, mesh: PrimitiveMesh, at: Vector3, colour: Color) -> void:
	var part := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.65
	mesh.material = material
	part.mesh = mesh
	part.position = at
	holder.add_child(part)
