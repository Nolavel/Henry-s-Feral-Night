# Changelog

All notable changes to Henry's Feral Night. Newest first.
Maintained per branch; entries are added by whoever makes the change.

## [Unreleased] — `claudeflow`

### 2026-09-22 (6) — Campfire fuel and the hold-to-sleep UI

Added
- `HeatSource` fuel now actually burns: `advance_all_fuel()` is ticked by
  `ThermalManager` on the game clock, `refuel()` feeds and relights a fire, and
  `heats_zone` links a source to its room so a fire going out stops heating it
  with no scene wiring. Default burn is six hours — deliberately less than a
  full night.
- `scripts/ui/hud/sleep_prompt.gd` + `scenes/ui/hud/sleep_prompt.tscn` — hold S
  for one second, A/D choose 1–8 hours, E sleeps and saves, Esc cancels.
- Input actions `sleep` (S), `sleep_hours_less` (A), `sleep_hours_more` (D),
  `sleep_cancel` (Esc).
- `tools/runtime/capture_sleep_prompt.gd` — renders both UI states for review.
- `tests/systems/test_sleep_prompt.gd` — fuel burn-down, a dead fire cooling its
  zone, refuel capping, the hold gate, hour clamping, and the fuel warning.

Key conflicts, resolved rather than fudged
- **S was already `move_backward`.** The hold only charges while sleeping is
  possible and no movement action is held, so walking backwards can never start
  it. A test asserts S does nothing in the open.
- **E was already `interact`.** Opening the dialog pauses the tree while the
  prompt runs with `PROCESS_MODE_ALWAYS`, so `InteractionManager` never sees the
  press. No edits to its file and no input-order guessing.

Fixed
- The fuel warning is real: `fire_outlasts_sleep()` checks every fire warming
  the spot against the chosen duration, so the player learns they will wake up
  cold before committing.
- **A node-reference `@export` on a scene root cannot resolve to its own
  children** — root properties are applied before children exist. This produced
  a dialog that never appeared. `resolve_nodes()` now fills in any widget the
  scene left null.

Closed
- The "shelter is too safe" tuning problem raised by the thermal chart: fuel
  running out during sleep is now the pressure that makes banking wood a real
  decision.

Verified
- All five suites pass via `tools/ci/run_tests.sh`.
- `TestScene` still imports and renders; both sleep UI states captured.


### 2026-09-22 (5) — Save system and sleep-to-save

Added
- `scripts/systems/save/save_manager.gd` — participant registry, atomic slot
  writes, slot metadata for a load menu, and a real version-migration seam.
- `scripts/systems/save/sleep_controller.gd` — the only path to a save. Gates on
  shelter, felt temperature and tiredness, returning a typed `Refusal` with a
  localisation key rather than a bare bool.
- `ThermalManager` and `WeatherController` now implement the save contract
  (`save_id` / `get_save_data` / `load_save_data`), matching the convention
  `DayNightManager` already used.
- `tests/systems/test_save_system.gd` — round trip, metadata, corrupt files,
  out-of-range slots, the sleep gate, and the two guarantees below.
- `docs/technical/SAVE_SYSTEM.md`.

Design decisions
- **Sleeping is not a free reset.** `try_sleep()` steps the thermal model
  through the night in quarter-hour increments, so a shelter that goes cold
  still costs body heat while asleep. A test asserts it. This is the hook the
  "shelter is too safe" problem needs.
- Saves are plain JSON while the project is in development: a save can be read
  and diffed. `metadata` sits outside `payload` so a load menu can list slots
  without deserialising game systems.
- Writes go to `slot_N.json.tmp` and are renamed, so a crash mid-write cannot
  corrupt an existing save.

Fixed (found by the new tests)
- `SaveManager` originally discovered participants only through the `saveable`
  group, which returns nothing until the scene tree settles — so it silently
  wrote an **empty save file** and reported success. A save that contains
  nothing is the worst failure a save system can have: the player believes they
  are safe. It now refuses to write an empty save, explains why, and offers
  explicit `register()` alongside the group.
- Corrupt slots are reported as `corrupt` in `list_slots()` rather than hidden,
  so a damaged save is visible to the player instead of vanishing.

Verified
- All four suites pass via `tools/ci/run_tests.sh`.
- `TestScene` still imports and renders.


### 2026-09-22 (4) — HUD thermometer bound to the model; metabolism fix

Added
- `vital_signs.gd` now drives the temperature indicators from `ThermalManager`:
  icon opacity tracks body temperature, the warning sign follows the hypothermia
  stage, and the upper/lower indicators flash on real change — the same pattern
  hunger and thirst already use. Assign `thermal_manager` on the HUD node.
- `tests/systems/test_vital_signs_binding.gd` — asserts the HUD follows the
  model and survives having no manager assigned.
- `tools/runtime/capture_thermal_debug.gd` — charts one worsening night twice,
  exposed and sheltered-at-hour-5, to a PNG. This is the tuning instrument.
- `ThermalManager.basal_heat_c` — metabolic heat production.
- A test asserting a lit shelter returns a chilled player to `NORMAL`.

Fixed
- **The survival loop could not close.** The model had no metabolic heat term,
  so `effective` temperature never beat bare-skin comfort: a lit shelter at
  -18 °C ambient slowed the cooling but never reversed it, and every run ended
  at the lethal floor. Found by the new debug chart, which showed both the
  exposed and the sheltered curve flatlining. `basal_heat_c` (12 °C) fixes it;
  `cooling_coefficient` retuned to 0.075 to keep the night's pace.
- `vital_signs.gd` seeded the thermometer inside `initialize_ui_state()`, which
  returns early when no `BioMonitorManager` is assigned — so the thermometer
  silently never seeded. Moved to `initialize_thermal_state()`.
- `vital_signs.gd` dereferenced unassigned `TextureRect` exports in its
  device-visibility loop; now null-guarded.

Open for the author
- With a lit fire the sheltered curve holds a flat 36.6 °C straight through a
  blizzard — shelter is currently too safe. `HeatSource.burn_duration_h` is the
  intended answer but is not used anywhere yet.

Verified
- All three suites pass via `tools/ci/run_tests.sh`.
- `TestScene` still imports and renders.


### 2026-09-22 (3) — Thermal model, weather state machine, first test suites

Added
- `scripts/systems/survival/thermal_manager.gd` — body temperature simulation:
  ambient curve, weather, wind chill, shelter zones, heat sources, exertion and
  clothing wetness, integrated per in-game hour into a hypothermia stage ladder
  (NORMAL → CHILLED → COLD → HYPOTHERMIC → CRITICAL → death).
- `scripts/systems/survival/thermal_zone.gd` — static Area3D volumes for
  interiors and wind shadows, with warmth the player accumulates by burning fuel.
- `scripts/systems/survival/heat_source.gd` — point heat with distance falloff
  and a fuel timer; sampled from a static registry, not via physics overlap.
- `scripts/systems/survival/weather_profile.gd` — Resource holding one weather
  state's tuning, so designers edit `.tres` rather than code.
- `scripts/systems/survival/game_hour_tracker.gd` — converts the day/night
  clock's hour-of-day into deltas, handling the midnight wrap.
- `resources/weather/{calm,snowfall,windy,blizzard}.tres` — the four states.
- `tests/systems/test_thermal_model.gd` and `tests/systems/test_weather_profiles.gd`
  — the project's first automated tests.
- `tools/ci/run_tests.sh`, wired into the CI workflow ahead of the render step.
- `docs/technical/THERMAL_MODEL.md` — architecture, the formula, the weather
  table, how interiors work, and an honest cost breakdown of the snow/ice
  presentation layer.

Changed
- `scripts/systems/world/WeatherController.gd` — was an empty stub, now the
  global weather state machine: weighted scheduling, blended transitions,
  seeded simplex gusts, and `conditions_updated` / `weather_changed` signals for
  VFX and audio to listen on.

Fixed (found by the new tests)
- `ThermalZone.priority` collided with the native `Area3D.priority`; renamed to
  `zone_priority`.
- `HeatSource` kept freed instances in its static registry. A single stale
  source aborted every subsequent temperature calculation and silently froze the
  felt temperature at its last value.
- `_ready()` does not run until the first frame, so headless-constructed systems
  stayed uninitialised. Each system now has a public `initialize()` that
  `_ready()` calls — also the seam save-game loading will need.

Verified
- `tools/ci/run_tests.sh`: both suites pass, exit code 0.
- `TestScene` still imports and renders after the change.


### 2026-09-22 (2) — Sync with main, Terrain3D provisioning, slice definition

Changed
- Merged `origin/main` (Codex HEAD `4ba97eb`) into `claudeflow`. Conflicts:
  `AGENTS.md` kept Claude's roles table on top of Codex's rules; `global.json`
  took `main`'s version (`8.0.400` + `rollForward` + `allowPrerelease`).
- `tools/ci/setup_env.sh` now fetches the pinned Terrain3D `v1.0.1-stable`
  GDExtension binaries. They are not vendored — `addons/terrain_3d/bin/` is
  gitignored — so a clean checkout is reproducible without adding 40 MB to a
  repository that already has no LFS.
- `CLAUDE.md`: single-branch rule made explicit, plus a "Staying in sync"
  protocol (fetch, merge `main`, re-render, report in issue #1) and the list of
  recurring conflict files.

Added
- `docs/game_design/VERTICAL_SLICE.md` — the agreed next target: a *Long Dark*-style
  night on the frozen island, with the breaking-ice mechanic specified (per-tile
  integrity, creak → crack → break, cold-water survival rather than instant death),
  a pillar-by-pillar cost table, an explicit out-of-scope list and open questions.

Findings
- `scenes/game/Сhunks/` uses a Cyrillic С homoglyph (U+0421), as do the node
  paths in `WorldStreamManager.gd`. Logged as §3.10 of the assessment.
- Body temperature is not simulated anywhere; `vital_signs.gd` only displays it.
  This is the slice's core pillar and is the first system to build.

Verified
- After the merge, `TestScene` imports and renders clean: Henry's UAL rig is
  textured and posed, the day/night HUD reports live values, Terrain3D loads.


### 2026-09-22 — Agent infrastructure and headless render pipeline

Added
- `CLAUDE.md` — Claude's charter as technical director: role, branch ownership,
  engine baseline, comment policy (English, `##`, max 2 lines), GDScript style.
- `AGENTS.md` — adopted from `codex`, extended with a roles table and handover rules.
- `CHANGELOG.md` — this file.
- `tools/ci/setup_env.sh` — provisions Godot 4.8-dev6 mono, Mesa/lavapipe,
  Xvfb and .NET 8 in a clean container.
- `tools/ci/screenshot.gd` — `SceneTree` harness: boots a scene, runs N frames,
  writes the viewport to PNG.
- `tools/ci/render.sh` — one-line CPU render of any scene to PNG.
- `tools/ci/render_smoke.tscn` — minimal lit scene proving the render path.
- `.github/workflows/render-smoke.yml` — CI job importing the project and
  rendering the smoke scene on every push.
- `docs/technical/COMMERCIAL_ASSESSMENT.md` — commercial-readiness review of the
  prototype with a prioritised backlog.

Changed
- `global.json` — SDK pin `8.0.407` relaxed to `8.0.0` + `rollForward: latestFeature`,
  so the project builds on any installed .NET 8 SDK instead of one exact patch.

Verified
- Godot 4.8-dev6 mono runs Forward+/Vulkan on lavapipe (llvmpipe) under Xvfb.
- `res://tests/scenes/TestScene.tscn` boots and renders a frame headlessly.
