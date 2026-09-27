# =============================================================================
# consumable_data.gd — the facet that makes an item edible or drinkable.
#
# Attached to an ItemResource through its optional `consumable` field. Null is
# the ordinary case. What it restores maps onto BioMonitorManager's three
# tracks, so eating is one call rather than a special case per item.
# =============================================================================
class_name ConsumableData
extends Resource

@export_group("Restores")
## Calories returned. BioMonitorManager tracks a 2500 kcal budget.
@export var calories: float = 0.0
## Hydration returned, in the same units the biomonitor uses.
@export var hydration: float = 0.0
## Energy returned, for anything that staves off tiredness rather than sleep.
@export var energy: float = 0.0

@export_group("Cost")
## Degrees of body heat this costs to consume. Snow and cold water take heat
## out of the body; a hot drink would carry a negative value here.
@export var body_heat_cost_c: float = 0.0

@export_group("Result")
## Item left behind after consuming, such as an empty tin. Empty leaves none.
@export var leaves_behind_id: StringName = &""
