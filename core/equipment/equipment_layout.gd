# =============================================================================
# equipment_layout.gd — which body slots a character has.
#
# A Resource assigned on the character rather than constants inside the
# component, so a different character, or a different build of the same one,
# is data rather than an edit.
#
# It describes the BODY only. Pockets are NOT here: slot count is a property
# of the garment, and a garment brings its own (see GarmentData). That split
# is what makes clothing replaceable without changing the character.
# =============================================================================
class_name EquipmentLayout
extends Resource

## The fixed places on this character that hold a garment or a piece of kit.
## Order is presentation only; lookup is by EquipmentSlotDefinition.id.
@export var body_slots: Array[EquipmentSlotDefinition] = []


## The slot with this id, or null. Silent — "is there such a slot" is a
## legitimate question with a legitimate no.
func find_slot(slot_id: StringName) -> EquipmentSlotDefinition:
	for slot: EquipmentSlotDefinition in body_slots:
		if slot != null and slot.id == slot_id:
			return slot
	return null
