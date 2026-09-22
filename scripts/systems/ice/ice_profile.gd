class_name IceProfile
extends Resource

## Tuning for the frozen sea. Designers edit this as a .tres; nothing about
## the ice is a constant in code.

@export_group("Grid")
## Side of one ice tile in metres. Smaller reads better, costs more tiles.
@export var tile_size_m: float = 4.0
## Tiles simulated around the player on each axis; 2 gives a 5x5 window.
@export var active_radius_tiles: int = 2

@export_group("Thickness")
## Distance from shore, in metres, at which ice stops being fully solid.
@export var solid_until_m: float = 12.0
## Distance from shore, in metres, beyond which ice is at its thinnest.
@export var thinnest_from_m: float = 90.0
## Integrity of the thinnest ice, 0.0 to 1.0. Never zero, or the far sea is
## an invisible wall rather than a risk.
@export_range(0.0, 1.0) var minimum_thickness: float = 0.18

@export_group("Load")
## Integrity drained per second while standing still on a tile.
@export var drain_per_second: float = 0.055
## Multiplier applied while walking.
@export var walk_multiplier: float = 1.6
## Multiplier applied while sprinting. Running across thin ice is the gamble.
@export var sprint_multiplier: float = 3.2
## Multiplier applied while crouched; the careful way across.
@export var crouch_multiplier: float = 0.45
## Integrity restored per second once nothing stands on the tile.
@export var recovery_per_second: float = 0.02

@export_group("Feedback ladder")
## Integrity below which the ice creaks. Audio only, no visuals yet.
@export_range(0.0, 1.0) var creak_below: float = 0.62
## Integrity below which cracks appear and the camera shakes.
@export_range(0.0, 1.0) var crack_below: float = 0.32
## Integrity at or below which the tile gives way.
@export_range(0.0, 1.0) var break_at: float = 0.0

@export_group("Cold water")
## Degrees per in-game hour the body loses while in the water. Brutal by design.
@export var immersion_body_loss_per_hour: float = 14.0
## Seconds of thrashing before the player may climb out.
@export var climb_out_delay_s: float = 1.2
