# =============================================================================
# item_traits.gd — the vocabulary an item and a slot both have to speak.
#
# One enum, no state, never instantiated. It lives here rather than on
# ItemResource for a concrete reason: EquipmentSlotDefinition has to name a
# size class, and ItemResource reaches GarmentData, which reaches slot
# definitions. Put the enum on ItemResource and that becomes a cycle GDScript
# resolves badly. A vocabulary nothing else depends on breaks it.
#
# Ported from ADT. Its second enum, Readability, was NOT taken: that axis is
# how an item reads to an observer, and this game has no observers.
# =============================================================================
class_name ItemTraits
extends RefCounted


## Does this fit that socket. Three steps, because three is what the rules
## need today; a fourth is added when something needs it, not ahead of time.
enum SizeClass {
	## Fits in a pocket: a tin, a lighter, a knife.
	POCKET,
	## Too big to pocket; carried, slung or strapped.
	CARRIED,
	## Needs the pack or both hands.
	BULKY,
}
