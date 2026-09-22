# Changelog

All notable changes to Henry's Feral Night. Newest first.
Maintained per branch; entries are added by whoever makes the change.

## [Experiment] — `codex`

### 2026-09-23 — Freeman's Sky controlled island preview

Added
- Official CC0 full-resolution and quarter-resolution Freeman's Sky shaders from
  Niwl Games.
- A capture harness that renders the same Henry eye-line view at 06:15, 12:00,
  17:45 and 19:00 on the authored Graciosa island scene.
- Cold maritime parameter tuning lives in the harness, not gameplay code, so the
  experiment can be rejected without touching the current overcast day/night stack.

Performance choice
- The quarter-resolution variant is retained for the intended Forward+ runtime.
  The capture harness can use the full-resolution variant with its explicit
  manual-sun fallback when a headless runner cannot expose LIGHT0 correctly.
- No dedicated Freeman CI workflow is added; the project keeps the existing
  shared render/test pipeline.

## [Unreleased] — `claudeflow`

### 2026-09-22 (12) — Fix CI: the environment, not the code

The first CI run on PR #2 went red. Every cause was in the harness I wrote.

Fixed
- `setup_env.sh` was invoked as `sudo -E`, so the **whole** script ran as root
  and created `$HOME/.local` root-owned. Every later unprivileged step then
  failed to write `user://`, which is why the save tests could not create a
  slot. Root is needed for apt and nothing else, so the script now asks for it
  itself and the workflow calls it unprivileged.
- The artifact step ran `find` over a directory that does not exist when no
  render was produced, and `bash -e` turned that into a failed job even under
  `if: always()`. It tolerates a missing directory now.
- `HeatSource.get_offset_at()` read `global_position` without checking
  `is_inside_tree()`, flooding the log with engine errors on every headless
  temperature calculation. Guarded.
- Two suites dereferenced a null `FileAccess` when `user://` was unwritable, so
  a broken environment surfaced as a crash instead of a reason. They now report
  what could not be written and why.

Changed
- **All eight suites now run from the first frame** rather than `_initialize()`.
  Three of them had been relying on a node outside the tree returning a zero
  transform that happened to equal the origin — luck, not correctness. This is
  the same Godot trap recorded in `WORLD_ARCHITECTURE.md` §8, and it is now
  handled consistently everywhere. The engine-error flood in the logs is gone
  with it (from hundreds of lines to zero).

Verified
- Eight suites pass, `TestScene` renders, the workflow's step list is intact.


### 2026-09-22 (11) — ASCII filenames and the orphaned uid

Closes §3.10 of the commercial assessment.

Renamed
- `scenes/game/Сhunks/` → `scenes/game/chunks/` — the old directory began with
  **U+0421 CYRILLIC CAPITAL ES**, visually identical to a Latin `C` and quietly
  fatal to every grep, glob, path comparison and export filter written against
  it. Nine chunk scenes moved.
- `Warning sign101х86.png` / `Warning sign60х51.png` → `warning_sign_101x86.png`
  / `warning_sign_60x51.png`. Those `х` were Cyrillic too.
- The island scene's own node names with them: `FM_Сhunks` → `FM_Chunks`,
  `Сhunk_*` → `Chunk_*`.

Removed
- `scripts/systems/world/Debug_Accelerator.gd.uid`, orphaned when the script was
  renamed to `debug_accelerator.gd`. It kept handing out `uid://cjj38qmk6jo8p`,
  which `WorldEnvironmentSystem.tscn` still referenced — the scene loaded by
  text path with a warning on every boot. The scene now points at the real
  `uid://dgvkrwulefgho` and the warning is gone.

Added
- `tools/ci/check_filenames.sh`, wired into CI ahead of the tests: fails the
  build on any non-ASCII tracked path and on any `.uid` whose script is gone.
  Neither problem can come back silently.

Verified
- Eight suites pass; `data/world_data.tres` regenerated from the normalised
  scene (9 chunks, every content scene resolved); both the island and
  `TestScene` render; the gate reports clean.


### 2026-09-22 (10) — Data-driven streaming

Closes the last item `AGENTS.md` had against this project: chunk definitions
are data now, not code.

Added
- `core/world/resources/chunk_data.gd` and `world_data.gd` — mirroring ADT's
  `BlockData`/`WorldData`: id, display name, location, position, radius and the
  two ring scene paths.
- `tools/world/generate_world_data.gd` — **generates** `data/world_data.tres`
  from the authored island scene. Position comes from each `Area3D`, radius is
  measured from its `CollisionPolygon3D`, the display name from its `Label3D`,
  and content scenes are matched by naming convention rather than a table. Nine
  chunks came out with every content scene resolved and nothing re-authored by
  hand. It matches both spellings of `Chunk_`, so the Cyrillic homoglyph in the
  authored names is handled rather than tripped over.
- `core/world/streaming_system.gd` — the pipeline, reading the resource and
  nothing else. **No per-chunk variable and no per-chunk `match` arm exists in
  the file.** ADT's cell machine (`UNLOADED → QUEUED → LOADING → READY →
  ACTIVE`, with rollback), ADT's budgets (2 concurrent loads, 1 instantiation
  per frame), and its non-optional `_packed_cache`.
- `tests/systems/test_streaming.gd` — generated data, approach and activation,
  hysteresis, the instantiation budget, rollback, and reset.

Removed
- `experimental_location/scripts/WorldStreamManager.gd` (558 lines), replaced
  rather than patched. `CHUNK_DEFINITIONS` and `LOCATION_AREAS` go with it; the
  authored `Area3D` markers stay as the generator's source of truth.

Fixed (found by the new tests)
- A chunk whose background load landed **after** the player had walked away was
  still instantiated, because the pump activated anything `READY` without
  re-checking distance. Both the poll and the activation now re-check the band,
  and the packed scene stays cached for the next approach.

Deliberate difference from ADT
- The load band is **per chunk** — its own authored radius plus a margin — not
  one flat radius. Our chunks range from 190 m to 312 m across, so a single
  number would either thrash the small ones or load the big ones far too late.
- `StreamingSystem` is not an autoload. It has one owner and one lifetime, which
  is what `WORLD_SYSTEM_SCRIPTS` is for.

Open
- Ring 0 is built but empty: no silhouette scenes exist yet, so
  `silhouette_scene_path` is blank on every chunk. The island's terrain is the
  floor in the meantime, as in ADT after its own island move.

Verified
- Eight suites pass. The island boots through the composition root with the
  pipeline live (`[World] initialized with 3 systems`) and renders.


### 2026-09-22 (9) — Composition root, WorldContext and InputSystems, from ADT

Read `Nolavel/ADT` and ported its architectural spine. Details and the full
list of what was and was not taken: `docs/technical/WORLD_ARCHITECTURE.md`.

Added
- `world/world.gd` — the composition root. Three declarative lists
  (`WORLD_SYSTEM_SCRIPTS`, `WORLD_3D_ENTITY_SCENES`, `WORLD_UI_SCENES`) say what
  exists; the loops that build them are fixed, so **the file does not grow as
  systems are added**. Adding anything is one line.
- `core/world/world_context.gd` — `WorldContext`, the "almost DI": player,
  camera, stream container and the live systems, with `get_system(Class)`.
  Systems stop being hand-wired through `@export` NodePaths in the scene.
- `on_world_ready(context)` — duck-typed lifecycle hook, checked by
  `has_method()`. `SaveManager` adopts the systems list through it;
  `WeatherController` finds the day/night clock and loads its profiles.
- `core/input/input_systems.gd` — first autoload in this project, and the only
  file that reads `Input`. Edges come from events, levels come from polls, and
  `Input.is_action_just_pressed()` is banned outright.
- `tests/systems/test_world_composition.gd`.

Changed
- The island scene now carries `world.gd`, has a `StreamContainer`, and its root
  is `World`. `GameRouter.gd`'s one job — move the player to the marker and free
  it — is `_place_player()`.
- **Save contract converged on ADT's**, since two codebases by the same author
  should not disagree: `save_id()` → `get_save_key()`; partial implementations
  are now skipped all-or-nothing; and an unrecognised save version is **refused
  outright** rather than passed through with a warning. A half-applied save from
  a future build is worse than a refused one.

Fixed
- `WeatherController` dereferenced `get_tree()` without checking it, which is
  null outside the tree.

Recorded, not done
- By ADT's naming rule, `BioMonitorManager`, `StaminaManager`,
  `InventoryManager` and `ThermalManager` are all **Components** — attached to
  one owner, owning no collection. Renaming touches scenes as well as scripts,
  so it is written down rather than half-applied.
- The streaming port is specified in `WORLD_ARCHITECTURE.md` §6 as four concrete
  steps. `CHUNK_DEFINITIONS` being a hardcoded dictionary is the gap
  `AGENTS.md` already names; the generator and the rewrite land together or not
  at all.

Verified
- Seven suites pass; the island boots through the composition root and renders
  (`[World] initialized with 2 systems`).


### 2026-09-22 (8) — Gait wired to the ice

Added
- `scripts/systems/ice/ice_gait_binder.gd` — reads `MovementController` and the
  body's horizontal velocity and pushes the resulting gait into `IceField`, so
  sprinting across the bay now costs 3.2x what standing still does. Written as
  an adapter: `MovementController` is not edited and stays in nobody's way.
- Tests: gait classification (still / walk / sprint), that vertical velocity is
  not mistaken for movement, and that a sprint through the binder loads the ice
  harder than a walk.

Finding
- **The project has no crouch.** No input action, no controller state. The
  profile's 0.45 crouch multiplier is therefore unreachable, and the careful way
  across the ice does not exist — the player's only options today are walk or
  gamble. `IceGaitBinder` reports `CROUCH` only when someone binds
  `crouch_action`, and a test asserts it is never reported until then, so this
  cannot be forgotten silently.

Verified
- All six suites pass; `TestScene` still renders.


### 2026-09-22 (7) — The frozen sea

Added
- `scripts/systems/ice/ice_profile.gd` — all ice tuning as a Resource.
- `scripts/systems/ice/ice_field.gd` — the frozen sea. Sparse tile grid,
  thickness from distance to the island outline, gait-scaled load, recovery,
  and the creak → crack → break ladder.
- `scripts/systems/ice/cold_water_immersion.gd` — falling through soaks the
  player, drains body heat on the game clock, and refuses to let them climb out
  until they have thrashed. The trap is a story beat, not a reload.
- `ThermalManager.apply_body_temperature_delta()` — public seam for events the
  ambient model does not cover.
- `resources/ice/bay_ice.tres`, `tests/systems/test_ice_field.gd`,
  `tools/runtime/capture_ice_map.gd`, `docs/technical/ICE_SYSTEM.md`.

Guarantees the tests hold
- **Audio lands before visuals**: the first stage emitted walking a tile down is
  `CREAKING`, never `CRACKING`. The player always gets a warning they can act on
  before one they can only react to.
- **Cost is constant**: the active window stays 5×5 whether the player is 60 m
  or 4 km offshore.
- A tile breaks exactly once and stays broken; abandoned tiles recover but never
  past their natural thickness.

Level-design finding
- The map tool reports that on the illustrative bay the shortcut saves 54 % of
  the distance but **a sprinted crossing survives** — thinnest ice on the route
  is 0.74. The shortcut is free, so the ice mechanic would never fire. This is
  the risk `VERTICAL_SLICE.md` §4 predicted, now measured. Two levers are
  documented in `ICE_SYSTEM.md` §7; both are design decisions, not code ones.

Note
- GDScript lambdas capture local primitives **by value**, so a counter
  incremented inside a signal handler lambda silently stays zero. Cost one
  debugging round; the test now uses a reference type.


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
