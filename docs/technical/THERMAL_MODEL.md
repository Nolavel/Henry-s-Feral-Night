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

effective = felt + clothing_insulation * (1 - wetness * wetness_penalty)

if effective < comfort:  body -= (comfort - effective) * cooling_coefficient * hours
else:                    body += (effective - comfort) * rewarm_coefficient * hours
```

Everything is billed **per in-game hour**, never per frame. The clock comes from
`DayNightManager.time_update`, funnelled through `GameHourTracker`, which handles
the wrap at midnight. This means the model behaves identically at 30 fps and
144 fps, and it stays correct when `TimeAccelerator` speeds the clock up.

Current tuning: roughly **1.3 °C of core temperature lost per hour** at -15 °C in
dry clothing — Henry reaches hypothermia in about 2.5 hours of exposure and dies
in about 6. Tuned to make one night the unit of tension. All of it lives in
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

## 6. Wiring it into a scene

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

## 7. Deliberately not built yet

- **Clothing as items.** `clothing_insulation_c` is one number today. It becomes
  a sum over equipped garments once the inventory carries wearables.
- **Wind direction.** Only speed is modelled. Directional shelter (a cliff that
  only helps from one side) needs the wind vector and a facing test.
- **Cold water.** Falling through the ice needs a hard body-temperature slam and
  a climb-out state; that lands with the ice system, and `add_wetness(1.0)` plus
  a large negative zone is already enough to prototype it.
- **Sleeping.** `restore_body_temperature()` and `reset_clock()` exist as the
  seam for it; the save system is what is actually missing.

## 8. Known test findings

The suites caught three real defects while this was written, all fixed:

1. `ThermalZone.priority` silently collided with the native `Area3D.priority`.
2. `HeatSource` kept freed instances in its static registry; one stale fire made
   *every* temperature calculation abort mid-way and silently freeze the felt
   temperature at its previous value.
3. `_ready()` does not run until the first frame, so anything constructed in a
   headless test was uninitialised. Each system now has a public `initialize()`
   that `_ready()` calls, which is also a better seam for save-game loading.
