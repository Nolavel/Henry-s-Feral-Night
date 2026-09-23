# =============================================================================
# garment_data.gd — the facet that makes an item wearable.
#
# Attached to an ItemResource through its optional `garment` field. Null means
# "not a garment", and that is the ordinary case — a tin of food does not carry
# empty garment fields.
#
# A garment does two things: it occupies one body slot, and IT BRINGS ITS OWN
# POCKETS. The second is the load-bearing half — slot count belongs to the
# garment, not to the character. A coat with four pockets and a coat with none
# are both legitimate coats, and swapping one for the other changes what Henry
# can carry without touching Henry at all. Take the coat off and whatever was
# in its pockets goes with it.
#
# Ported from ADT, plus the one axis ADT does not have: insulation.
# =============================================================================
class_name GarmentData
extends Resource

## Which body slot this occupies, by the id the character's EquipmentLayout
## defines. An id no layout knows is refused at equip time, not ignored.
@export var body_slot_id: StringName = &""

## The pockets this garment brings. Empty is valid and means exactly that:
## a garment you cannot put anything into.
@export var pockets: Array[EquipmentSlotDefinition] = []

@export_group("Survival")
## Degrees of insulation this garment contributes while worn on the body.
## Summed by EquipmentComponent and read by ThermalManager — this is what
## makes clothing a survival item rather than a costume.
@export var insulation_c: float = 0.0

@export_group("Visuals")
## The skinned MeshInstance3D that IS this garment on screen, named rather
## than pathed so the name survives being read by a rig other than Henry's.
@export var mesh_node_name: StringName = &""
