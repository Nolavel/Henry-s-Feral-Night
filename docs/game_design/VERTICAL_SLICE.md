# Vertical slice — "One Night on the Ice"

Status: **target definition**, agreed with the author 2026-09-22.
Owner: author (design) / Claude (technical plan and cost).
Reference: *The Long Dark*, transposed into the nuclear-winter setting.

This document defines the one artifact the project needs next: five to ten
uninterrupted minutes that can be shown to a publisher, recorded for a store
page, and played by a stranger without a guide.

---

## 1. Player fantasy

You are alone on a frozen island. It is getting dark and it is getting colder.
You have to find somewhere warm enough to sleep before the cold takes you, and
something to eat on the way. The sea around the island is frozen — the ice is a
road and a trap at the same time.

## 2. The loop

```
spawn cold and hungry
  -> explore the island (cold pressure rises)
  -> find food / fuel / a light source
  -> read the ice: shortcut across the bay, or the safe long way round
  -> reach a shelter, make it warm
  -> sleep -> save -> wake to a harder night
```

Failure states: freeze to death; starve; fall through the ice.
Success state: waking up warm.

## 3. Pillars, and what each one costs

| Pillar | Exists today | Missing | Effort |
|---|---|---|---|
| **Cold / body temperature** | Nothing. `BioMonitorManager` has calories and hydration only; temperature appears in `vital_signs.gd` as a HUD readout with no simulation behind it. | A real thermal model: ambient temperature by time-of-day and weather, wind, shelter/indoor modifier, clothing insulation, heat sources, wetness. This is **the** pillar — the whole slice is a fight against this number. | **L** |
| **Hunger / thirst** | `BioMonitorManager` simulates both with hourly rates and critical thresholds. | Food items that actually restore calories; a reason to search. | **S** |
| **Shelter + sleep-to-save** | Nothing. Save/load does not exist. | Shelter volumes that modify the thermal model, a sleep interaction, a save system, a wake-up transition. Stated USP; currently absent. | **M** |
| **Breaking ice** | Nothing. | See §4. | **M** |
| **Island** | `experimental_location/` has a Terrain3D island (`Graciosa_Island_Terrain.tscn`) and `WorldStreamManager.gd` with 9 named chunks and polygon zones from `locations_data.json`. Conceptually the island is ready. | Dressing it for winter; picking one small playable sub-area rather than all 27 hectares. | **M** |
| **Day/night + weather** | `DayNightManager` runs (verified: "06:58 AM, Morning, Day 1, 72 sec day + 72 sec night"); `WeatherController` exists. | Wind as a gameplay input to the thermal model, not just a visual. | **S** |
| **Character + camera** | Works. Henry UAL rig renders and animates; the cursor-driven rotation/camera system is the project's signature. | Nothing blocking. | — |

## 4. The ice — design and technical note

The author's mechanic: **the sea around the island is ice, not water. Walking
away from the shore, the ice cracks and you can fall through into freezing
water.**

This is the slice's signature moment and it is cheap to make *readable*, which
matters more than making it simulation-accurate.

Recommended model — **per-tile ice integrity, distance-driven**:

- The frozen sea is a grid of ice tiles. Each tile has an `integrity` value
  seeded from distance to shore: thick near the island, thin far out.
- Standing on a tile drains its integrity over time; weight and movement speed
  (sprint > walk > crouch) scale the drain. Moving off restores it slowly.
- Integrity drives a three-stage feedback ladder, and **the audio stage must
  land before the visual one**:
  1. **Creak** — audio only. "You can still turn back."
  2. **Crack** — a decal/shader crack propagates from under the player, camera
     shake, faster creaking. "Turn back now."
  3. **Break** — the tile gives way; the player falls into water.
- Falling in is not instant death: a hypothermia timer starts, the player must
  reach shore and then a heat source. This turns the trap into a story beat
  instead of a reload — which is exactly what *The Long Dark* does right.

Technical notes:
- Do **not** simulate the whole sea. Simulate only tiles inside a radius around
  the player; everything else is static visual ice. A 3×3 or 5×5 active window
  is enough and keeps this O(1) regardless of map size.
- The ice surface is one mesh with a shader; cracks are a screen- or
  world-space mask written per active tile, not spawned geometry.
- Water entry needs: a cold-water volume that slams body temperature, a swim or
  flail state, and a climb-out interaction at a tile edge. The climb-out is the
  part that will feel bad if rushed — budget for it.
- Keep the ice grid data-driven (a `Resource`), consistent with the AGENTS.md
  rule against per-chunk hardcoding.

Risk: this mechanic is fun exactly once unless it is a *choice*. The bay
shortcut must be meaningfully faster than the shore route, or the player will
simply never step on ice and the whole system goes unseen.

## 5. Scope discipline

For the slice, explicitly **out**: combat, enemies, crafting trees, Gizmo's
ability set, inventory depth, dialogue, the second protagonist, multiple
locations, the full 27-hectare island.

In: one sub-area of the island, one shelter, one bay crossing, three or four
findable items, one night.

## 6. Technical order of work

1. **Thermal model** as a standalone, testable system (`ThermalManager`),
   feeding the existing biomonitor HUD. Nothing else can be tuned until the
   cold number is real.
2. **Shelter volumes + sleep interaction + save/load.** Sleep is the only save,
   so save must exist before the loop closes.
3. **Ice tile system** with the three-stage feedback ladder, then cold-water
   entry and climb-out.
4. **Dress one sub-area** for winter and place the item set.
5. **Tune the night** so a first-time player fails once and succeeds on the
   second try.

Each step lands on `claudeflow` with a `tools/ci/render.sh` frame attached to
the changelog entry, so progress is visible without anyone installing Godot.

## 7. Open questions for the author

1. Does Gizmo appear in the slice at all? He is a stated USP, but he has no
   mechanical verb yet — including him half-finished is worse than omitting him.
2. Is the first night scripted (a guaranteed-findable shelter) or systemic
   (find it or die)? Scripted demos better; systemic pitches better.
3. Wetness: does falling through the ice soak clothing and permanently worsen
   insulation until dried? That single rule adds most of *The Long Dark*'s
   tension, at a real cost in UI and item state.
