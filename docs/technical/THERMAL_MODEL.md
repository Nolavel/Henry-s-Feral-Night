# Thermal model — architecture

Status: **implemented** (`scripts/systems/survival/`, `scripts/systems/world/WeatherController.gd`)
Tests: `tests/systems/test_thermal_model.gd`, `tests/systems/test_weather_profiles.gd`
Run them with `tools/ci/run_tests.sh`; CI runs them on every push.

---

## 1. Is weather an Area3D that follows Henry?

**No.** That was the right question to ask, and the answer is no — for a
concrete reason.

Weather on a 27-hectare island is *the same everywhere at the same moment*. A
volume that follows the player would be a moving container for a value that
never varies in space: all the cost of physics overlap checks, none of the
benefit. Worse, it makes the weather depend on the player existing, which breaks
the moment you want weather to run while the player is asleep or in a cutscene.

So the model is split by **what actually varies in space and what does not**:

| Layer | What it is | Spatial? | Node type |
|---|---|---|---|
| **Weather** | One global state: air temperature offset, wind speed, snowfall, visibility, soak rate | No — one value for the island | `WeatherController` (plain `Node`) |
| **Zones** | Shelter interiors, caves, wind shadows behind a cliff | Yes — but **static**, placed by hand in the level | `ThermalZone` (`Area3D`) |
| **Heat sources** | Fires, barrels, heaters | Yes — point sources with falloff | `HeatSource` (plain `Node3D`) |
| **Body** | Henry's core temperature, wetness, hypothermia stage | Follows the player | `ThermalManager` (`Node3D` on the player) |

**Exactly one Area3D moves with Henry**, and it is not a weather field — it is a
small *probe* (`zone_probe`) whose only job is to report which static zones he
is currently standing in. Detector, not simulation.

Heat sources deliberately do **not** use `Area3D`. A distance check against a
registry of at most a handful of live fires is cheaper than physics overlap, and
it gives a smooth falloff curve instead of a binary inside/outside — you feel a
fire get warmer as you walk toward it, which is the whole point.

## 2. The formula

```
felt  =  ambient(hour of day)          # curve, ambient_min_c .. ambient_max_c
       + weather.ambient_offset        # calm +2, snowfall 0, windy -1, blizzard -6
       + dominant_zone.total_offset    # interior warmth, including accumulated heating
       - wind_speed * chill_per_mps * zone.wind_exposure
       + Σ heat_source.offset_at(player)
       + exertion_bonus * exertion     # sprinting generates real warmth

effective = felt
          + clothing_insulation * (1 - wetness * wetness_penalty)
          + basal_heat_c                # metabolism: the body is not passive

if effective < comfort:  body -= (comfort - effective) * cooling_coefficient * hours
else:                    body += (effective - comfort) * rewarm_coefficient * hours
```

Everything is billed **per in-game hour**, never per frame. The clock comes from
`DayNightManager.time_update`, funnelled through `GameHourTracker`, which handles
the wrap at midnight. This means the model behaves identically at 30 fps and
144 fps, and it stays correct when `TimeAccelerator` speeds the clock up.

`basal_heat_c` is not cosmetic. Without it there is **no reachable configuration
in which the player rewarms**: a lit shelter at -18 °C ambient tops out around
+4 °C felt, which never beats bare-skin comfort, so the body cools forever and
the survival loop cannot close. The debug chart in §9 is what exposed this.

Current tuning: roughly **1.5 °C of core temperature lost per hour** exposed at
-18 °C in dry clothing — hypothermia in about 2.5 hours, death in about 5.5. A
shelter with a lit fire recovers a hypothermic player to normal in roughly two
hours. Tuned to make one night the unit of tension. All of it lives in
`@export` values, not constants.

## 3. The four weather states

`resources/weather/*.tres`, editable without touching code:

| Profile | Air | Wind | Gusts | Snow | Visibility | Soak/h | Duration |
|---|---|---|---|---|---|---|---|
| **Calm** | +2 °C | 0.5 m/s | 1.0 | — | — | — | 2–5 h |
| **Snowfall** | 0 °C | 2.5 m/s | 3.0 | 0.45 | 220 m | 0.18 | 1.5–4 h |
| **Windy** | -1 °C | 8 m/s | 6.0 | 0.15 | 400 m | 0.06 | 1–3 h |
| **Blizzard** | -6 °C | 17 m/s | 11.0 | 0.95 | 45 m | 0.55 | 0.75–2 h |

Note that the blizzard's danger is mostly **not** its -6 °C. At 17 m/s the wind
chill term alone removes about 9 °C from the felt temperature, and it soaks
clothing three times faster than snowfall, which then strips most of the
insulation. The cold, the wind and the wet compound — that is the design.

Transitions blend over each profile's `blend_time_s` (20–35 s), and gusts ride on
top as seeded simplex noise, so wind breathes instead of sitting at a constant.
The scheduler picks the next profile by weight; `scheduler_enabled = false` pins
one profile for testing or for a scripted story beat.

## 4. How indoor temperature works

An interior is a `ThermalZone` with `is_interior = true`, and it does three
distinct things:

1. **`wind_exposure = 0.0`** kills the wind chill term outright. This is the
   biggest single effect — in a blizzard, stepping inside is worth roughly +9 °C
   before any heating at all.
2. **`temperature_offset_c`** gives the structure's passive warmth: a ruin with
   a roof maybe +3, a sealed bunker +10.
3. **`max_heated_offset_c`** is the part the player earns. Light a `HeatSource`
   inside and the zone accumulates warmth at `heating_rate_c_per_hour` up to its
   cap, then bleeds it back at `cooling_rate_c_per_hour` once the fire dies.

That third point is the shelter gameplay verb: a shelter is not warm because you
walked into it, it is warm because you *made* it warm, and it goes cold if you
sleep too long without banking fuel. Being sheltered is also what lets wet
clothing dry.

Overlapping zones resolve by `zone_priority` (named that way because `Area3D`
already has a native `priority` — an actual collision found by the test suite).

## 5. The island is entirely snow and ice — the cost

You are right that this is not cheap, and it is worth being precise about *what*
is expensive, because the answer is reassuring:

**The simulation is cheap.** Everything above is scalar arithmetic on a handful
of floats, ticked once per in-game minute, plus one small `Area3D` probe. It
costs effectively nothing, and it does not get more expensive as the island
grows.

**The presentation is what costs.** Rough order, most to least expensive:

1. **Snow shader across the whole island** — Terrain3D already handles the
   terrain surface, so the cost sits in blending snow onto *props and meshes*
   (world-space triplanar snow on upward faces). Expensive to author, cheap at
   runtime if it is one shared material.
2. **Blizzard particles + visibility** — density and fog distance are already
   driven by the weather profile; the GPU cost is in particle count and in the
   volumetric fog the whiteout needs.
3. **Footprints and deformation** — a render-target snow deformation map is the
   single most expensive thing on this list and the most commonly cut. Treat it
   as a stretch goal, not a pillar.
4. **Wind and weather audio** — three-layer bus (ambient bed, wind loop pitched
   and filtered by `wind_speed_mps`, gust one-shots), plus a low-pass when
   `is_interior` is true. Cheap on CPU, significant in authoring time, and it
   carries more of the felt cold than the visuals do.

**The important architectural point:** none of that is a dependency of the
thermal model. `WeatherController` emits `conditions_updated(ambient_offset,
wind_speed, snowfall_density)` and `weather_changed(profile)`; VFX and audio are
listeners. You can ship the whole survival loop with placeholder visuals, tune
it until the night is fair, and drop the expensive presentation in later without
touching a line of the simulation. Do it in that order — tuning cold against
unfinished visuals is how projects burn months.

## 6. The HUD binding

`vital_signs.gd` now drives the thermometer from the model, following exactly
the pattern the other vital signs use:

- **Icon opacity** tracks normalised body temperature — colder means more opaque,
  same `ICON_MIN_ALPHA`/`ICON_MAX_ALPHA` ramp as hunger and thirst.
- **Warning sign** appears at `HYPOTHERMIC` and clears on recovery.
- **Upper/lower indicators** flash on a real change of `TEMPERATURE_ALERT_DELTA_C`
  (0.35 °C): lower when falling, upper when warming.
- **The red critical indicator** holds solid while freezing, matching hunger.

Assign `thermal_manager` on the HUD node. Without it the HUD pushes a warning
and the thermometer stays idle rather than showing a fabricated reading.

One defect was found and fixed while wiring this: the thermometer seeding had
been placed inside `initialize_ui_state()`, which returns early when no
`BioMonitorManager` is assigned — so the thermometer silently never seeded. It
now lives in its own `initialize_thermal_state()`.

## 7. Wiring it into a scene

```
Player (CharacterBody3D)
├── ThermalManager            weather_controller, day_night_manager, zone_probe, ambient_curve
│   └── ZoneProbe (Area3D)    a small sphere on collision layer "thermal"
└── ... existing managers

World
├── WeatherController         profiles = resources/weather/*.tres, day_night_manager
├── Shelter_Ruin (ThermalZone)  is_interior, offset +3, max_heated +12
│   └── Campfire (HeatSource)
└── ...
```

`ThermalManager` exposes `body_temperature_changed`, `felt_temperature_changed`,
`stage_changed`, `wetness_changed` and `freezing_death_reached` — the HUD hooks
onto these. `vital_signs.gd` currently only toggles thermometer visibility and
has no value behind it; connecting it is the next step.

## 8. Deliberately not built yet

- **Clothing as items.** `clothing_insulation_c` is one number today. It becomes
  a sum over equipped garments once the inventory carries wearables.
- **Wind direction.** Only speed is modelled. Directional shelter (a cliff that
  only helps from one side) needs the wind vector and a facing test.
- **Cold water.** Falling through the ice needs a hard body-temperature slam and
  a climb-out state; that lands with the ice system, and `add_wetness(1.0)` plus
  a large negative zone is already enough to prototype it.
- **Sleeping.** `restore_body_temperature()` and `reset_clock()` exist as the
  seam for it; the save system is what is actually missing.

## 9. The tuning chart

`tools/runtime/capture_thermal_debug.gd` simulates one worsening night twice —
exposed throughout, and reaching a lit shelter at hour 5 — and renders both
curves to a PNG. Run it the same way as any capture tool; the output lands in
`user://shots/thermal_debug.png`.

This is the instrument for tuning the night, and it earned its place
immediately: the first run showed **both** curves flatlining at the lethal
floor, which is how the missing metabolic term was found.

Open tuning question for the author: with a lit fire the sheltered curve now
holds a flat 36.6 °C straight through the blizzard — shelter is currently
*too* safe. `HeatSource.burn_duration_h` is the intended answer (fuel runs out,
the room cools, you wake up cold), but it is not yet used anywhere.

## 10. Known test findings

The suites caught three real defects while this was written, all fixed:

1. `ThermalZone.priority` silently collided with the native `Area3D.priority`.
2. `HeatSource` kept freed instances in its static registry; one stale fire made
   *every* temperature calculation abort mid-way and silently freeze the felt
   temperature at its previous value.
3. `_ready()` does not run until the first frame, so anything constructed in a
   headless test was uninitialised. Each system now has a public `initialize()`
   that `_ready()` calls, which is also a better seam for save-game loading.
4. The model had no metabolic heat term, so no shelter could ever rewarm the
   player. Found by the debug chart, now covered by a test asserting that a lit
   shelter returns a chilled player to `NORMAL`.
5. `vital_signs.gd` seeded the thermometer behind an unrelated early return.
6. The HUD's device-visibility loop dereferenced unassigned `TextureRect`
   exports; now null-guarded.
