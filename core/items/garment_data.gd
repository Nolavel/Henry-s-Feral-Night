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

enum Layer { BASE, MID, OUTER }

## Which body slot this occupies, by the id the character's EquipmentLayout
## defines. An id no layout knows is refused at equip time, not ignored.
@export var body_slot_id: StringName = &""

## Semantic body region independent of a concrete equipment slot id.
## The live EquipmentLayout remains authoritative for what slots exist.
@export var body_region: StringName = &""
## Layer occupied within the body region.
@export var layer: Layer = Layer.OUTER

## The pockets this garment brings. Empty is valid and means exactly that:
## a garment you cannot put anything into.
@export var pockets: Array[EquipmentSlotDefinition] = []

@export_group("Survival")
## Legacy authoring field kept so old .tres resources remain readable.
## New code calls get_base_insulation_c().
@export var insulation_c: float = 0.0
## New explicit definition-level insulation. Negative means "use legacy insulation_c".
@export var base_insulation_c: float = -1.0
## Fraction of wind blocked at full condition.
@export_range(0.0, 1.0, 0.01) var windproof: float = 0.0
## Fraction of incoming moisture rejected at full condition.
@export_range(0.0, 1.0, 0.01) var waterproof: float = 0.0
## Wetness fraction shed per game hour at full drying warmth.
@export_range(0.0, 2.0, 0.01) var drying_rate: float = 0.25
## Definition-level durability ceiling. Runtime state stores a normalised 0..1 fraction.
@export_range(0.01, 10.0, 0.01) var max_condition: float = 1.0


func get_base_insulation_c() -> float:
	return base_insulation_c if base_insulation_c >= 0.0 else insulation_c


func get_layer_id() -> StringName:
	match layer:
		Layer.BASE:
			return &"base"
		Layer.MID:
			return &"mid"
		_:
			return &"outer"

@export_group("Visuals")
## The skinned MeshInstance3D that IS this garment on screen, named rather
## than pathed so the name survives being read by a rig other than Henry's.
@export var mesh_node_name: StringName = &""
