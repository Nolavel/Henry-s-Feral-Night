# The frozen sea — architecture

Status: **implemented** (`scripts/systems/ice/`)
Tests: `tests/systems/test_ice_field.gd` — run via `tools/ci/run_tests.sh`
Tool: `tools/runtime/capture_ice_map.gd`

---

## 1. What it is

The sea around the island is ice, not water. Walking out from shore it thins,
creaks, cracks and gives way, and falling through is a survival emergency
rather than a death. It is the slice's signature moment.

## 2. Cost: constant, whatever the bay's size

The sea is a grid of tiles, but **only the tiles around the player are ever
touched**. `active_radius_tiles = 2` gives a 5×5 window — twenty-five tiles,
regardless of whether the bay is one hectare or twenty. A test asserts the
window does not grow when the player is four kilometres offshore.

Tiles are stored sparsely: a tile that has never been walked on has no entry at
all, and reports its base thickness computed from geometry. Memory tracks where
the player has actually been, not the size of the map.

## 3. Thickness

Base integrity comes from distance to the island outline:

```
distance <= solid_until_m (12 m)   ->  1.0, fully solid
distance >= thinnest_from_m (90 m) ->  minimum_thickness (0.18)
between                            ->  linear interpolation
```

The outline is a `shore_polygon` on the XZ plane, so it reuses the same kind of
polygon data `locations_data.json` already stores for zones. `distance_to_shore()`
returns negative on land, which is also how the field knows where ice is not.

`minimum_thickness` is deliberately not zero. Ice that is 0.0 far out is an
invisible wall; ice at 0.18 is a risk the player can choose to take.

## 4. The ladder

Integrity drives four stages, and **the order is a guarantee, not a
convention**:

| Stage | Integrity | Feedback |
|---|---|---|
| `SOLID` | above 0.62 | nothing |
| `CREAKING` | below 0.62 | **audio only** — "you can still turn back" |
| `CRACKING` | below 0.32 | cracks, camera shake, faster creaking — "turn back now" |
| `BROKEN` | 0.0 | the tile gives way |

A test walks a tile all the way down and asserts the first warning emitted is
`CREAKING`, not `CRACKING`. The player always gets a warning they can act on
before they get one they can only react to. If a future change reorders these,
the suite fails.

`stage_changed` fires only on transitions; `load_tile_changed` fires every step
for the loaded tile, which is what a shader mask and a creak loop want.

## 5. Load and recovery

Standing on a tile drains it; gait scales how hard:

| Gait | Multiplier |
|---|---|
| Crouch | 0.45 — the careful way across |
| Still | 1.0 |
| Walk | 1.6 |
| Sprint | 3.2 — running the bay is the gamble |

Stepping off lets a tile recover at `recovery_per_second`, capped at its natural
thickness, so a bay can be crossed repeatedly but not carelessly. Broken tiles
never come back: the hole stays in the world.

## 6. Falling through

`ColdWaterImmersion` listens for `tile_broke`. Going under:

1. Soaks clothing to 1.0 immediately — which strips most of the clothing
   insulation in the thermal model, so the cold bites long after climbing out.
2. Drains body temperature at `immersion_body_loss_per_hour` (14 °C/h), billed
   in game hours like every other survival rate.
3. Stops the ice simulating until the player is out.
4. Refuses to let the player climb out for `climb_out_delay_s`. The thrash is
   the beat; an instant exit would make the whole thing a stumble.

This is the *Long Dark* lesson: the trap is a story, not a reload. The player
survives the water and then has to solve the cold.

`ThermalManager.apply_body_temperature_delta()` is the seam this uses — a public
method for events the ambient model does not cover, rather than the immersion
reaching into private state.

## 7. What the map tool is for, and what it already found

`tools/runtime/capture_ice_map.gd` draws the bay top-down: thickness shading,
the shore route against the ice shortcut with both distances, and a simulated
sprinted crossing. It prints a verdict.

On the illustrative bay it currently reports:

> shore 193 m, ice 90 m, saves 103 m (54 %)
> **a sprinted crossing survives (thinnest ice on the route 0.74): this shortcut
> is free, so the mechanic never fires here**

That is the exact risk `VERTICAL_SLICE.md` §4 flagged, now measured. The
shortcut is attractive — 54 % shorter is a real temptation — but the bay is so
close to shore that the ice never thins enough to matter. A player would take it
every time and never learn the ice is dangerous.

Two levers, and this is a **level-design decision, not a code one**:

- **Widen the bay** so the crossing runs further offshore. The route needs to
  spend real time beyond roughly 45–50 m out for a sprint to be a gamble.
- **Retune the falloff** for a tight bay: drop `solid_until_m` and
  `thinnest_from_m` so thinning starts closer in. Cheap, but it also makes every
  other stretch of coast dangerous, which may not be wanted.

Run the tool after either change; it re-reports the verdict for whatever route
and tuning it is given.

## 8. Not built yet

- **No visuals or audio.** The field emits everything a shader mask and a
  three-layer creak/crack bus need (`load_tile_changed`, `stage_changed`,
  `tile_broke`); nothing consumes them. Per `THERMAL_MODEL.md` §5, that is the
  expensive half and it is deliberately last.
- **No swim state.** `ColdWaterImmersion` owns the timing and the cold, but the
  character controller has no in-water movement, and `climb_out()` does not yet
  place the player at the hole's edge — `get_entry_position()` is there for
  whoever wires it.
- **Broken tiles do not persist.** The ice is not a save participant yet, so
  holes vanish on load. `IceField` needs the save contract.
- **Gait is not wired.** `set_gait()` exists; nothing calls it from
  `MovementController` yet.
- **No wind direction or snow cover.** Thin ice hidden under fresh snow is the
  obvious next twist, and the weather profiles already carry snowfall density.
