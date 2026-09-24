# Changelog

All notable changes to Henry's Feral Night. Newest first.
Maintained per branch; entries are added by whoever makes the change.

## [Unreleased] — `codex`

### 2026-09-24 — Terrain stage 3: the main scene runs on IslandTerrain (claudeflow)

Changed
- Graciosa's main scene uses `IslandTerrain` in place of `NavigationRegion3D`
  and Terrain3D; the nav mesh was empty and unused. It follows the Player,
  which now starts at the spawner. The lavapipe crash is gone: 600 frames of
  the main scene, and full-scene captures in 2 of 2 runs.
- The blockout builder samples the heightmap instead of Terrain3D.
- `capture_first_exit.gd` renders the mesh terrain by default.

Fixed
- Generated interactives (pickups, board-up and stove prompts) saved their
  body signals twice and logged "already connected" at load. The route test
  now checks for exactly one connection.

### 2026-09-24 — Terrain stage 2: IslandTerrain from the heightmap (claudeflow)

Added
- `IslandTerrain` + `IslandHeightmap`: the island ground built from the
  heightmap. It has 128 m chunks with 1/4/16 m levels of detail, skirts, and
  HeightMapShape3D collision near the focus; `get_height` matches the Python
  tools exactly. The terrain shader colours by height and slope, with the
  shared snow cover on top.
- `tools/world/bake_terrain.py` writes `world/terrain/graciosa_height_la8.png`,
  the game-readable copy of the source (Godot drops 16-bit PNGs to 8-bit).
- `test_island_terrain.gd`.

Changed
- Heightmap export adds a sea bed that shelves from the coast instead of
  Terrain3D's flat 0 m plane. The source PNG was re-exported.

Found
- The full Graciosa scene no longer crashes under lavapipe once Terrain3D is
  swapped for IslandTerrain (3 of 3 runs, 7 shots each).

### 2026-09-24 — Terrain heightmap becomes the source of truth, stage 1 (claudeflow)

Added
- `world/terrain/source/graciosa_height.png` (+ `.json`): the island as a
  16-bit 1 m heightmap, −16…+48 m, exported from Terrain3D with at most
  0.5 mm error (8 MB against 25 MB of Terrain3D regions).
- `tools/blender/heightmap_import.py` / `heightmap_export.py`: Blender round
  trip. Import the whole island or a window as a grid, sculpt, and write back
  only the changed heights. Verified headless with `bpy`.
- `tools/world/heightmap.py`; `island_report.py` and `route_metrics.py` read
  the PNG directly. See `docs/world/TERRAIN_HEIGHTMAP.md`.

Fixed
- `route_metrics.py` crashed drawing pickups (no footprint size).

### 2026-09-24 — First Exit: the working loop moved into the route (claudeflow)

Added
- The shelter lot now carries the TestScene loop: an interior ThermalZone,
  five ShelterBreach openings with board-up prompts, and a stove (HeatSource +
  feed). Sleep and save work there through the existing SleepController.
- Layout `pickups`: boards, tinder, firewood and food placed per route with
  deliberate scarcity (5 openings, 3 boards; tinder only at the fort or in the
  collapsed house). `test_first_exit_route.gd` guards the loop and the
  scarcity.

### 2026-09-24 — First Exit: route clutter, Kenny on the pack, visible clothes (claudeflow)

Added
- Visible greybox clothes. Hat, coat with sleeves, trousers and boots are
  built on the UAL bones and shown per equipment slot through the garments'
  `mesh_node_name`. They darken with the thermal model's wetness
  (`HenryUALAnimation.set_wetness`, wired in `Player.on_world_ready`).
- Route clutter from the layout: cars, pickups, a van and a bus (overturned,
  sunk in drift, doors open), bins and dumpsters. Placed per route to break
  sprint lines and create choke points (Grok, #42).
- Kenny: item `kenny` (3 kg) on the back fixture from the start, with a plush
  silhouette strapped to the pack. Carried non-garments now count toward the
  carry weight (`EquipmentComponent.get_carried_weight`).
- `ItemResource.attached_mesh_node_name` shows a mesh on Henry for a
  non-garment in a body slot. `EquipmentComponent.starter_slot_items` places
  non-garments at start.

### 2026-09-24 — First Exit: suburb on the old road, human speeds (claudeflow)

Changed
- Greybox reworked per the author (PR #43). It is now an old coast road with
  a gravel bed, shoulders, ditches, broken asphalt, a junction and a lane to
  the jetty, and leaning or broken street lamps. Eleven lots face the road,
  each with a driveway, a fenced plot with a gate, a shed, a water tank, and
  winter retrofits (boarded, vestibule, stovepipe, insulation, snow fence).
  Some lots are roofless or collapsed. Houses have gable roofs. Resolved
  footprints are written to `docs/world/first_exit_resolved.json`.
- Walk 4 → 1.5 m/s, sprint 8 → 4.5 m/s. Locomotion blend points follow.
  The ice drain and sprint multiplier are rescaled so per-tile damage is
  unchanged.

Removed
- The inland salt lagoon proposal. Ice moves to the real coast later.

### 2026-09-24 — First Exit: island analysis and greybox (claudeflow)

Added
- `docs/world/FIRST_EXIT.md`: where the game starts on Graciosa, island
  metrics, buildable sites, measured routes, tropical reference typology and
  the author decisions the milestone needs (lagoon, walk speed, distance).
- `tools/world/dump_island_heights.gd`, `island_report.py`, `route_metrics.py`:
  heightfield dump, height/slope maps with buildable sites, route length /
  ice / coast-exposure metrics and landmark visibility.
- `data/world/first_exit_layout.json` and `tools/world/build_first_exit_blockout.gd`:
  data-driven greybox (bunker door, redoubt, battery, sheds, bus stop,
  bungalows, water tower, church, jetty, 36 dead palms) placed on terrain
  heights; instanced in the main scene.
- `tools/runtime/capture_first_exit.gd`: greybox renders.

Changed
- `FirstSpawner` faces the water tower; `World` now applies the spawner's yaw.

### 2026-09-24 — Dead player layer removed (claudeflow)

Removed
- The hidden Genesis8 Henry (skeleton, meshes, materials) embedded in
  `player.tscn`: 1.7 MB -> 4 KB. The UAL mannequin is the only body.
- Old HUD: `InGameUI`, `vital_signs.gd`, `CombatHUD` and its weapon slots, debug
  labels; `BioMonitorManager` no longer pokes a UI.
- Gizmo (the pre-Kenny robot): scene, scripts, the C# flashlight duplicate,
  test model and icons.

### 2026-09-24 — Audio system and a cheaper CI gate (claudeflow)

Added
- `SoundSystem` autoload with `SoundEvent` (variations, jitter, voice limits,
  cooldown) and `SoundLayer` (parameter-driven loops); bus layout with an
  interior low-pass. `WorldAudioBinder` feeds wind, shelter and footsteps.
  See `docs/technical/AUDIO.md`.

Changed
- CI is one `checks` workflow on pull requests to `main`: import, filename
  check, headless suites. The lavapipe render and both visual-FX preview
  workflows are gone; render locally with `tools/ci/render.sh`.
- `run_tests.sh` kills a hung suite after `SUITE_TIMEOUT` seconds (180) and
  counts it as failed.

### 2026-09-24 — Solid vital cells, a quiet figure, and a compile fix (claudeflow)

Changed
- Vital pentagons are a solid translucent backing; the level fill is gone.
- A plain grey standing figure sits between the top cells, above the health bar.

Fixed
- `VitalCluster` failed to compile on `main`: `draw_texture_rect_region` arguments
  were swapped and the glyph atlas SVG had no `.import`, so the HUD never loaded.

### 2026-09-24 — Original HFN vital glyphs and threshold morphs

Changed
- Replaced the four legacy bitmap glyphs inside `VitalCluster` with one original
  HFN SVG atlas: stomach, droplet, closing eye and falling thermometer.
- Each glyph has eight baked frames. A 0.35 s morph plays only when the value
  crosses 50% or 10%, reverses on recovery and never loops while idle.
- At 50% and above indicators stay off-white; below 50% the icon, outline and
  level fill turn muted yellow; below 10% they turn muted red.
- The always-running critical breathing was removed. Critical cells retain a
  static inset and stronger opacity, so danger remains legible without motion.
- Glyphs render at 30 px with a dark keyline for both snow and dark interiors.

Tests
- `test_vital_cluster.gd` now locks the exact 50% and 10% boundaries and the
  final critical morph frame.

### 2026-09-24 — Remove legacy map and portrait cameras

Removed
- The Graciosa island debug minimap pipeline: its SubViewport, regional overhead
  camera, MapDebug UI and inline minimap script.
- Henry's old front-face HUD camera pipeline: its SubViewport, CameraFaceHenry,
  portrait UI subtree and dedicated controller script.

Kept
- The gameplay TPS PlayerCamera, survival HUD, combat HUD, StatsDisplay and the
  remaining island debug labels.



### 2026-09-23 — Cold Ash color grading profiles

Added
- Two weak 33×33×33 display LUTs: `HFN_ColdAsh_Night` for the outdoor default
  and `HFN_ColdAsh_Shelter` for safe interiors.
- `ColorGradeController` owns only the existing Environment adjustments and
  exposes explicit outdoor, shelter and interior-initialization entry points.
- A deterministic standard-library LUT generator, a focused headless test and
  a same-camera TestScene capture tool.

Kept
- Day/night, weather, Freeman sky and parallax clouds retain their existing
  ownership. Automatic shelter detection is deliberately deferred until the
  gameplay system has one authoritative interior-state hook.

### 2026-09-23 — Weather-driven snowfall promoted to production

Added
- Production `SnowfallVFX` as a Node3D world-system under
  `scripts/systems/world/weather/`, registered next to WeatherController in
  `WORLD_SYSTEM_SCRIPTS`. Headless runs skip GPU VFX construction entirely.
- The VFX resolves the authoritative WeatherController from WorldContext; it
  does not create or own a second weather state.
- Local `SnowHeightFieldService` follows Henry by coarse 8 m cells, using a
  48×24×48 m / 256² GPUParticles height field only while snow is active.
- World snow is fixed at 3072 particles and 30 Hz simulation; foreground snow
  is capped at 32 rare flakes. Validated flake sizes and streak strength are
  frozen for this production pass.
- High-wind velocity stretch is render-only on the small world flakes; it does
  not add another emitter and does not enlarge particle collision.
- One island regression capture remains under `tools/runtime/`; the synthetic
  experimental snow scene, production-scene detour and old capture harness are removed.

Performance
- HeightField no longer follows the camera every frame.
- The validated llvmpipe preview showed no meaningful frame-time difference
  between snowfall, windy and blizzard stages; absolute llvmpipe FPS is not a
  target-GPU measurement.

### 2026-09-23 — Freeman atmosphere + parallax clouds promoted to runtime

Changed
- `WorldEnvironmentSystem` now assigns the combined Freeman + HFN parallax-cloud
  shader to `DayNightManager`; it is no longer capture-only.
- Cloud volume is slightly heavier: depth 2.35, coverage threshold 0.34 and
  opacity 0.92, while retaining the existing noise, wind and parallax controls.
- Freeman's physical sun direction is now independent from the scene's
  `DirectionalLight`. The latter can continue to become moonlight at night
  without being interpreted as the atmospheric sun.
- Runtime atmosphere uses the cold maritime tuning validated in the preview and
  12/4 view/sun samples to keep the production path bounded.

Kept
- `simple_overcast.gdshader` remains in the repository as the old implementation;
  the production scene no longer selects it.
- The existing shared CI/render workflow is unchanged.

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

### 2026-09-23 — Vital HUD: X layout, quieter cells

Changed
- Cells turned 45° into an X with a wider centre; the health band starts from
  the centre of the X and runs right beneath the cells.
- No coloured fill at rest: neutral translucent level, rust only when low.
  Cells sit at 45% opacity and go opaque while draining, refilling or critical.
- A drain now draws the cell toward the centre instead of pushing it out.

### 2026-09-23 — Experimental vital HUD: pentagon diamond and health band

Added
- `VitalCluster`: four pentagons in a diamond, tips to the centre — warmth top,
  water left, food right, sleep bottom. Level fills from the outer edge; a drain
  nudges the cell out and flashes it dull red, a refill grows it for ~2 s with a
  green-gold edge, under 15% it breathes and sits out. Warmth has its own
  cold scale. Procedural, all sizes/colours/timings exported.
- `HealthStrip`: the old red HUD band, smaller, as the health bar — same
  `BG_indicatorSURV` shader and fade, cut to current health, with a pale damage
  trail that catches up.

Changed
- The old vital icons (`vital_signs_enabled = false`) and the wide red band are
  hidden, not deleted, for easy rollback.

### 2026-09-23 — Colour grade follows the shelter; Cold Ash LUTs retuned

Added
- `ShelterGradeBinder` world system: `ThermalManager.sheltered_changed` drives
  `ColorGradeController.initialize_for_interior()`; the grade module still knows
  nothing about shelters. `test_shelter_grade.gd` walks Henry in and out of
  the real test shelter.

Changed
- Cold Ash LUTs regenerated from `generate_cold_ash_luts.py`. Night no longer
  darkens the frame (−5% instead of −18%) and puts the cold where #31 asked:
  shadows go from warm to graphite-teal, highlights and snow stay neutral, warm
  sources keep their colour. Shelter warms darks and mids and keeps bright
  openings cool.
- Preview PNGs are now live in-engine captures, not LUTs sampled over an old
  screenshot.

### 2026-09-23 — ADT head look; shelter edge signal for the colour grade

Added
- ADT's procedural head look on the UAL mannequin: standing, the `Head` bone
  eases toward where the camera looks (up to 55° each way); walking, the clips
  own the head and the look fades out. The UAL head rests ~13° off the body,
  so the limits are asymmetric to make the turn equal both ways.
  `test_head_look.gd` measures the turn through a BoneAttachment3D.
- `ThermalManager.sheltered_changed(is_sheltered)`: one edge per real change
  of being inside an interior zone, for #31's LUT switch.

### 2026-09-23 — Smart camera against walls

Fixed
- With Henry's back to a wall, turning the camera into it put the camera
  through the wall: the ADT 0.7 m minimum boom overrode the wall probe.

Added
- Wall assist in `TpsCamera`: when the boom behind Henry lacks ~0.9 m, it
  searches angles along the wall (up to 90°) and a little above (up to 30°),
  judging each by where the camera would really sit (shoulder shift and wall
  clearance included), and glides there; it glides back once the mouse angle
  has room. It keeps the side it chose so it does not flip.
- The camera goal is cleared of walls before the follow, and the post-contact
  restore is faster (5.0), so a sweep along a wall does not leave the camera
  hugging the head. As a last resort only, the main camera stops drawing the
  body when closer than 0.3 m to the eyes (the HUD portrait is unaffected).
- `test_tps_camera_orbit.gd`: back to a wall, a full 360° mouse sweep never
  enters the wall, never settles closer than 0.55 m and never hides Henry.

### 2026-09-23 — Camera in tight spaces; the backpack is an item

Changed
- `TpsCamera`: the shoulder offset shrinks with the boom (to 20% in the
  tightest space), a side sphere cast keeps the shoulder/lean shift out of a
  wall beside Henry, the near boom is 0.95 m and closing in is softer (2.5).

Added
- `backpack` item: a garment for the `pack` slot with a BULKY main
  compartment and a lid pocket, worn from the start. `GarmentData.mesh_node_name`
  now drives the body: the pack box shows only while the backpack is worn.

Fixed
- Interaction and camera tests stepped on idle frames and could miss physics
  ticks under load; they now step on physics frames.

### 2026-09-23 — Cursor ring carries stamina again

Fixed
- The ADT ring port had dropped this project's movement dot, stamina-coloured
  sprint arcs and jump-charge arc; they are back around the centre ring.

### 2026-09-23 — Interaction ported from ADT; cursor ring back

Added
- `InteractComponent` (ADT): a focus cast ahead, then a 2.5 m / 240° intent
  cone pick the target; F acts within 0.9 m, otherwise Henry walks over and
  acts on arrival (WASD cancels). Replaces `InteractionManager`.
- `Player.move_to_position()` / `stop_moving()` / `movement_stopped`.
- ADT's dynamic cursor ring at screen centre, brightening over interactables.
- Refusals are said on the object: no boards, no firewood/tinder, too heavy.

Changed
- `InteractiveArea` visuals are driven by the component: marker when targeted
  far, prompt and ground ring within 2 m. `can_interact()` now means only
  "offers itself"; the stove stays targetable while it can take fuel.
- Prompt text is localised and shows the bound key.

### 2026-09-23 — TPS camera: the rest of ADT's framing; ADT key layout

Added
- Over-the-shoulder framing from ADT: 0.85 m shoulder offset split 60/40
  between lens shift and camera move, Z swaps shoulders (`TpsShoulderState`).
- Q/E lean of the camera, breathing sway on pitch, ADT lead smoothing and
  start pitch. Pivot and probes use ADT body ratios from the feet, not the
  capsule centre (the old pivot sat a metre too high).

Changed
- Keys follow ADT: interact F, lean Q/E, shoulder Z; flashlight moved to L;
  unused `use_ability_henry` action removed.

### 2026-09-23 — Grey UAL mannequin, backpack placeholder, fonts, menu pointer

Changed
- Player visual is the Quaternius UAL mannequin from `UAL1_Standard.glb`,
  painted flat grey; UAL2 clips are added as library `UAL2`. The Henry glbs
  (`henry_ual`, `henry_test_model`) and their hidden nodes are removed.
- A box on `spine_03` stands in for the backpack.

Added
- CGF Locust Resistance font from ADT with its licence note; font table in
  `docs/THIRD_PARTY_NOTICES.md`. BlackRock stays ADT-only.

Fixed
- Quitting to the title left the mouse captured: releasing look capture now
  always shows the pointer, and the title menu releases it on open.

### 2026-09-23 — Debugger warnings cleaned

Changed
- Triple-quoted "docstrings" in `BioMonitorManager` and `vital_signs.gd`
  (standalone-expression warnings) became `##` doc comments in English.
- Unused parameters prefixed with `_`; `load_profiles_from` no longer shadows
  the `profiles` export; dead `shake_intensity` local removed.

### 2026-09-23 — Picked-up items no longer crash the interaction scan

Fixed
- `InteractionManager` kept a freed pickup in `detected_areas` and errored
  every physics frame after a pickup; freed areas are now dropped first.

### 2026-09-23 — TPS camera replaces the cursor camera; pickups fixed

Added
- `TpsCamera` (`scripts/systems/camera/tps_camera.gd`), ported from ADT's
  on-foot camera without view toggle, lock-on, aim or lean: captured mouse
  look, follow smoothing, sprint pull-back, movement lead, sphere-cast wall
  clamp. New: eight rods plus a ceiling ray judge how open the space is and
  ease the boom between 1.2 m (doorways, rooms) and 3 m (open ground).
- `InputSystems.get_look_delta()` / `set_look_capture()`; pause frees the mouse.

Changed
- Movement is camera-relative and Henry turns to face where he walks.
  `RotationController` and `MouseCursorUI` are removed from the player scene
  (files kept for reference). `PlayerCamera.gd` deleted; the scene is now
  `tps_camera.tscn` (node name `PlayerCamera` kept for `World`).

Fixed
- Interact (E) never reached placeholder pickups, board-up or stove feed: the
  shape cast hit the `InteractiveArea` itself, which was not counted.

### 2026-09-23 — #24: existing systems start costing each other

Added
- `IceField` save contract (key `ice`, group `saveable`): holes survive
  sleep-save; loading never emits `tile_broke`.
- Carry weight has a cost: `IceGaitBinder` scales ice drain by pack load,
  `BioMonitorManager` raises fatigue above half load.
  `InventoryComponent.get_load_fraction()` / `find_in()` are shared hooks.
- `ThermalManager` dries clothes by felt temperature (0 °C none, 25 °C full)
  anywhere out of precipitation.

Changed
- `VERTICAL_SLICE.md` now describes the route experience; stale pillar table removed.

### 2026-09-23 (15) — Snow A+: rime from edges, settled snow as state, prints on slopes

From the author's review and the Grok and Codex reviews in #16.

Changed
- **Rime grows from edges, corners and the cold base of an object**, not as
  uniform noise across a face. The author called the old spread amateurish, and
  it was. `frost_weight()` takes an edge factor; as `frost_amount` rises the
  front moves inward, and noise only breaks up that front. Real assets bake an
  `edge_mask`; placeholder boxes set `box_half_extents` / `box_center_offset`
  for the **whole surface**, so seams between pieces of one wall do not read as
  edges.
- **Settled snow is world state, not a weather mirror.** `snow_cover` used to
  jump to the active profile's level; a blizzard's 1.0 fell to calm's 0.35 the
  moment it stopped. It now builds with snowfall, settles slowly (about a day
  from blizzard to calm), melts above 0 °C, and is saved under `snow`.
- **Rime grows and sheds over hours** instead of snapping across a threshold.
- **`foot_planted` carries the ground normal**, and prints lie along it: on a
  slope a print sits on the slope instead of hovering flat above it or cutting
  into it. Heel-to-toe runs along the ground.

Added
- A test that fails if anything but `SnowPresentationSystem` writes the snow
  globals.
- `SNOW_COVER.md`: the settled-snow model, rime from edges, quality tiers, a
  material checklist for the slice, and why decals are the low tier rather than
  persistence.
- `THIRD_PARTY_NOTICES.md`: the ADT foot-print asset, alongside the code port.

### 2026-09-23 (14) — Pickups you can see, prompts that highlight

Fixed
- Every pickup and shelter prompt from #17 logged "interactive_mesh не
  назначен". Not only noise: `InteractiveArea` sizes its highlight ring from
  that mesh, so none of them highlighted, and pickups had no body in the world
  at all — only a floating icon.
  - `ItemPickup` builds a small placeholder crate until items have meshes.
  - `BreachBoardUp` rings under the breach's boards; `HeatSourceFeed` under the
    stove's body.
  - The base class is untouched; each subclass supplies its mesh before
    `super()._ready()`.

### 2026-09-23 (13) — Snow step 3: foot contact and footprints

Added
- **`FootContactSensor`** on `player.tscn` reads Henry's animated `foot_*`,
  `ball_*` and `ball_leaf_*` bones and emits `foot_planted(side, point, forward,
  speed)` each time a foot lands: the ball of the foot within 6 cm of the ground
  after lifting past 9 cm, on the floor, moving. The ground is found by a short
  ray, so any surface works. The shared source for footprints, and later for
  footstep audio and ice load.
- **`FootprintSystem`** in the composition root stamps pooled decals: the left
  or right print cropped from the ADT stamp, toe along heel→toe, tinted as
  compressed snow. Snowfall buries them — 240 s calm, 25 s in a whiteout. No
  geometry is deformed; terrain stays untouched.
- `assets/textures/snow/footprint_left.png` / `_right.png`.

Found
- Henry's walk clip plants a foot every 1.3–2.7 m at 4 m/s, so he glides. That
  is a locomotion blend matter in `HenryUALAnimation`, documented in
  `SNOW_COVER.md`, not patched here.

Tests
- `tests/systems/test_footprints.gd`: one print per stride; none standing still
  or in the air; the real rig has every bone; the toe points where the foot
  points; each foot leaves its own print; a full pool reuses the oldest; a
  blizzard buries a trail a calm minute keeps.

### 2026-09-23 (12) — Snow step 2: the shared snow and rime surface

Added
- `shaders/environment/snow/snow_surface.gdshaderinc` — the terrain-agnostic
  response any spatial material includes. Settled snow on up-facing surfaces,
  reaching steeper slopes as `snow_cover` rises; rime on steep and vertical
  faces, patchy, grown by `frost_amount`. Edges are broken up with cheap
  world-space value noise, so no texture is required.
- `shaders/environment/snow/snow_prop.gdshader` — a plain base (colour,
  texture, roughness, metallic) with snow and rime on top, for placeholder
  geometry now; real assets include the `.gdshaderinc` in their own material.
- The test shelter's walls and roof use it, so `TestScene` shows the weather.

Fixed along the way
- Rime first came out as vertical stripes: world XZ noise only varies along one
  axis on a wall. Frost now samples noise in the wall's own plane.

Tests
- `test_shelter_scene.gd` checks the shelter carries the snow shader.

### 2026-09-23 (11) — Snow step 1: the weather → shader contract

Issue #16, Phase A, reassigned to `claudeflow` by the author. Terrain3D is a
placeholder, so the snow layer is terrain-agnostic from the start.

Added
- `WeatherProfile.snow_cover` (calm 0.35 → blizzard 1.0), blended by
  `WeatherController` like every other field; `get_snow_cover()`.
- `ThermalManager.get_outdoor_air_c()` — the air outside, before wind, shelter
  or fires, which is what frost on the world responds to.
- **`SnowPresentationSystem`**, one more line in the composition root and the
  only writer of the `snow_cover` and `frost_amount` shader globals. Writes on
  change only, never reads back.
- `[shader_globals]` declared in `project.godot`.
- `docs/technical/SNOW_COVER.md` — names, ranges, the one-writer rule.

Tests
- `tests/systems/test_snow_presentation.gd`: every profile has sane cover and a
  blizzard beats calm; cover follows a profile switch; frost is zero above
  freezing, partial at −14 °C, full in deep cold; both globals are declared;
  the composition root builds the system.

Fixed
- `test_streaming.gd` failed once in a full run and passed alone. Chunks load
  on a worker thread and the test pumped 200–400 times back to back with no
  wall time, so on a busy machine it could finish before the thread did.
  `_settle()` now pumps with real time between calls, up to a deadline, and
  stops once the states stop changing. Verified green under CPU load.

### 2026-09-23 (10) — A test shelter: the whole loop by hand in TestScene

Every slice system was in `main`, yet no scene let anyone play the loop.

Added
- `scenes/environment/shelter/test_shelter.tscn` — placeholder-box shelter:
  a west window facing into the blizzard (a `ShelterBreach` with a board-up
  prompt), a door in the lee, a `ThermalZone` interior, and a stove that starts
  cold with a feed prompt and a flame light.
- **`ItemPickup`**, the third `InteractiveArea` subclass. No pickup in the game
  put anything into the pack before; firewood and boards could not be had.
  All or nothing: a stack too heavy for the pack stays on the ground.
- `HeatSource.flame_light` and `ShelterBreach.boarded_visual`, so a lit stove
  and a boarded window read at a glance and on a render.
- `World.streaming_enabled`. Off in a scene that brings its own floor, so the
  island's chunks do not stream on top of it.
- Interaction prompts on the new interactables go through localisation.

Changed
- **`TestScene` is now a `World`** (streaming off), with the shelter at
  (0, 0, 14) and firewood ×2, tinder, boards and a tin on the path to it. The
  cold, sleep, save, pause and weather all run there now.

Tests
- `tests/systems/test_shelter_scene.gd` loads the real scene and checks its
  wiring, not the classes alone: prompts find their breach and stove, the
  window faces the blizzard, boarding and lighting spend real items and flip
  the visuals, pickups go into the pack or refuse. It caught the window facing
  downwind on the first draft.
- `test_world_composition.gd`: streaming off means no chunks.

### 2026-09-23 (9) — Minimal shell: title, Continue, pause

The last non-content item on #7's must-have list: title → New / Continue →
Quit, and a pause with Resume / Quit to title.

Added
- `scenes/ui/menu/title_menu.tscn` — New game, Continue from last sleep
  (disabled with a note when no sleep is saved), Quit. Bare on purpose; how it
  looks is the author's call.
- `scenes/ui/menu/pause_menu.tscn`, one more line in `WORLD_UI_SCENES`. Esc
  pauses through `PlayerState`. No save here: the game saves only when Henry
  sleeps, and the pause menu says so.
- `localization/strings.csv` (English + Russian), registered in
  `project.godot`. The project had **no translation table at all** — every
  refusal key (`SLEEP_REFUSED_TOO_COLD` and the rest) would have shown raw.

Fixed — Continue would have been a lie
- A sleep save held weather, body temperature and shelter state, and nothing
  else. **Time of day, where Henry lay down, hunger/thirst/energy and the pack
  were not saved.** Loading would have put him at the spawn marker at dawn,
  fed and empty-handed.
  - `SessionState` (composition root): game clock and player position; resets
    the thermal and weather hour trackers so a loaded clock jump is not billed
    as time spent in the cold.
  - `BioMonitorManager` implements the save contract.
  - `SaveManager` adopts contract implementers inside the player, so inventory
    and equipment are saved at last.
- `SaveManager.pending_load_slot` carries Continue from the title scene into
  the world; applied deferred, after every system adopted its scene state.

Not changed
- `run/main_scene` is still `TestScene`, per the author's convention. Point it
  at `res://scenes/ui/menu/title_menu.tscn` when the slice should boot to the
  title.

Tests
- `tests/systems/test_shell.gd`: a save round trip restores clock, position,
  hunger and pack; the pending load lands on the next frame, not before; Esc
  pauses and resumes; Esc does not stack a pause over the sleep dialog.

### 2026-09-23 (8) — Ice retune: sprinting the bay is a real gamble

Author's decision in issue #7: thinner ice and a heavier sprint, no crouch.

Fixed
- **Sprinting was never riskier than walking.** Sprint moves twice as fast and
  had exactly twice the load multiplier, so both put the same load on every
  metre of ice. `sprint_multiplier` 3.2 → 8.0.
- **Mid-bay ice could not break at all.** At 0.18 it was thicker than a sprint
  drains from one tile. Bay profile: `solid_until_m` 12 → 8,
  `thinnest_from_m` 90 → 26, `minimum_thickness` 0.18 → 0.11,
  `drain_per_second` 0.055 → 0.0375 (so walking keeps a margin).
- **Thin ice sat cracked before anyone stepped on it.** The creak/crack ladder
  compared absolute integrity, so 0.11 ice started below the crack threshold and
  the warning that must come first never sounded. Stages are now a share of the
  tile's own natural thickness.
- `capture_ice_map.gd` simulated a 5.5 m/s sprint; the controller runs at 8.

Tests
- `test_ice_field.gd` crosses the bay at both gaits: a sprint breaks through
  mid-bay (more than 20 m in), a walk does not.

### 2026-09-23 (7) — Phase B step 3: a fire you have to light and feed

`HeatSource.refuel()` had no caller anywhere — the same shape `add_calories`
had before Phase A. Fuel did burn on the game clock, and `burn_duration_h` is
deliberately shorter than a night, so every fire went out and nothing the
player did could stop it. The sleep prompt already warned about it; now the
warning has an answer.

Added
- Items `firewood` (bulky, heavy — carrying it should cost space) and `tinder`
  (spent only to start a dead fire).
- **`HeatSourceFeed`** — the second `InteractiveArea` subclass that does
  something. A dead fire costs tinder and wood; a burning one costs wood. A full
  fire refuses, and nothing is spent on any refusal.
- `HeatSource.can_refuel()` and `restore_fuel(hours, burning)` — the second for
  saves only; gameplay goes through the capped `refuel()`.
- **`ShelterState` remembers fires** next to boards, so sleeping beside a
  half-burnt stove does not wake up to a full one. Fires are found under their
  zone in the scene; no new system.

Not done, deliberately
- A placeable stove. Free placement is a new system, and #7's scope lock says
  no new systems. An authored stove that starts unlit gives the same verb.

Tests
- `tests/systems/test_fire.gd`: tinder only for a dead fire, a full fire spends
  nothing, feeding carries a fire past its own burn duration, a dead fire stops
  warming the room, and fuel survives a save round trip at the exact level.

### 2026-09-23 (6) — Phase B step 2: a shelter you have to prepare

A shelter was a flat safe zone: step inside and the wind stopped, and a fire
warmed a holed ruin exactly as well as a sealed cabin. This is the mechanism
behind the core verb in issue #4 — preparing shelter rather than finding it —
and the one item on #7's must-have list that is not content.

Added
- **Wind has a direction.** `WeatherProfile.wind_direction_deg` plus a jitter
  angle, and `WeatherController.get_wind_direction()`. Bearings blend as
  vectors, so crossing 0/360 turns the short way instead of sweeping back
  through every intermediate quarter; the wander is sampled from the gust noise
  at an offset, so direction and speed are not the same number twice.
- **`ShelterBreach`** — a hole in a shelter, child of the `ThermalZone` it lets
  the weather into. Severity, a facing taken from the node's own basis (the
  author turns it in the editor; nobody fills in a vector), and
  `board_up()` / `tear_open()`.
- **`ThermalZone` derives its protection from its breaches.** `wind_exposure`
  is now the base leak of a sealed shelter, not the final number.
  `get_wind_exposure(wind_direction)` adds each unboarded hole weighted by how
  squarely it faces the wind — a hole in the lee costs almost nothing, the same
  hole turned windward costs its full severity.
- **A fire cannot heat a hole.** `get_sealed_fraction()` scales
  `max_heated_offset_c`, so a holed room never reaches a useful temperature
  however long it burns, and tearing boards off mid-night drops the warmth
  already stored. That is what makes boarding up worth the trouble.
- **`ShelterState`** — a composition-root system remembering which breaches are
  boarded, keyed by zone and breach name. Shelters live in streamed chunks, so
  the state cannot live in the zone.
- **`BreachBoardUp`** — the first `InteractiveArea` subclass in the project that
  does anything. Spends one `boards` item and closes the hole; refuses rather
  than boarding for free.

Fixed
- **Confirming sleep also triggered whatever you were standing next to.**
  `InteractionManager._input()` read `"interact"` raw, bypassing `InputSystems`,
  and the sleep dialog confirms with the same key. The prompt now claims the key
  while it is open and the manager honours the claim — which is what the claim
  contract was ported from ADT for.
- `test_world_composition.gd`'s new check was aborting on a null `world.player`
  before asserting anything, so the suite passed without running it. The player
  export is only resolved by `initialize()`; the scene node is the handle that
  early.
- `vital_signs.gd` connected the thermal signals twice when the scene had
  already wired a manager.

Tests
- `tests/systems/test_shelter.gd`: a breachless zone behaves exactly as before,
  a windward hole costs more than the same hole in the lee, boarding restores
  the base leak, a fire cannot pass a holed room's ceiling, boards cost an item,
  the state survives a save round trip, and a night in a holed shelter ends
  colder than the same night sealed.
- Thirteen suites green. `TestScene` and the island both render with no warnings
  from the survival systems.

Known, not mine
- `test_ice_field.gd` prints a duplicate `tile_broke` connection error. It
  predates this branch's changes; left alone rather than widened into here.

### 2026-09-23 (5) — Phase B step 1: the cold actually runs

The thermal stack was built, tested and driven by nothing. It is in the
composition root now, which means the survival simulation runs in the game
rather than only in the suites.

Added
- `ThermalManager` and `SleepController` are two more lines in
  `WORLD_SYSTEM_SCRIPTS`, as the composition root promised. Both implement
  `on_world_ready(context)` and find what they need — clock, weather, equipment,
  biomonitor, save manager — so no scene wires them by hand.
- `ThermalManager` rides with the player and builds its own `ZoneProbe` when
  the scene supplies none. Without a probe no shelter ever counted, so sleep
  would have refused everywhere.
- `WorldContext.find_in_scene()` — one scene-tree search shared by every
  system, searching the world root first. A headless harness that adds a scene
  to the SceneTree root leaves `current_scene` null, which the bespoke search in
  `WeatherController` could not survive; that copy is deleted.
- `_notify` now offers the hook to a node **and its subtree**, so a HUD
  indicator inside `player.tscn` can ask for what it needs. `vital_signs.gd` and
  `sleep_prompt.gd` use it: the thermometer and the S-hold dialog find the live
  systems themselves.

Fixed
- **The starting weather profile was never activated.** `WeatherController._ready()`
  ran `initialize()` before the world handed over clock and profiles; it returned
  early at the empty-profiles check, and the later call no-opped on the
  `_gust_noise` guard. `initialize()` is now idempotent *per concern* rather than
  gated by one boolean, in both `WeatherController` and `ThermalManager`.
- Same class of bug in `ThermalManager`: the clock was never connected, so body
  temperature never ticked in a real scene.
- Awaiting `process_frame` to defer past `_ready` does not work here — a
  coroutine resumed by that signal and a node connecting to it during the same
  emission both run in one pass. Both systems are structurally correct instead.

Tests
- `test_world_composition.gd` gains the check that would have caught all of
  this: both systems present, each reference resolved, a probe built, and the
  thermal model following the player rather than sitting at the origin.
- Twelve suites green. `TestScene` and the island both render with **no warnings
  from the survival systems at all**, which has not been true before.

### 2026-09-23 (4) — Phase A step 3: the survival loop closes

Closes issue #6. The two ends of the loop that were stubs now meet.

Added
- `BioMonitorManager.rest_sleep()` is no longer a `pass`. A night restores
  energy, charges its own metabolism (the clock jump skips the hourly tick),
  and rests worse on an empty stomach — `get_rest_quality()` takes the worse of
  hunger and thirst and never drops below a floor.
- `ConsumptionController` — eating reaches the body at last. Finds the item in
  the inventory or in a garment pocket, spends one, pushes calories, hydration
  and energy onto the biomonitor, charges `body_heat_cost_c` to the thermal
  model, and puts whatever is left behind back where it fits.
- Items `empty_tin` and `snow_handful`. Snow is water bought with body heat,
  which is the first content that exercises the heat cost.
- `EquipmentComponent`, `InventoryComponent` and `ConsumptionController` are
  now nodes on `player.tscn`, wired to the existing `BioMonitorManager`, so the
  loop runs in game and not only in tests.

Tests
- `tests/systems/test_survival_loop.gd` — eight checks: sleep restores, sleep
  costs, a starved night restores less, eating from the inventory and from a
  pocket, the empty tin, snow costing heat, and the four refusals.
- Eleven suites green; `TestScene` renders with no new errors.

Not done here
- `ThermalManager` and `SleepController` are still not in the composition root,
  so nothing yet drives them at runtime. That is the head of Phase B.

### 2026-09-23 (3) — Phase A step 2: items, equipment, inventory, and clothing that matters

Ported from ADT with permission; the full record of what crossed over, what was
dropped and what was added is in `docs/technical/PORTED_FROM_ADT.md`.

Added
- `core/items/` — `ItemTraits`, `GarmentData`, `ItemResource`, `ConsumableData`,
  `ItemCatalog`. Items are Resources authored as `.tres` now, not an inner class
  that could never be edited. The catalog loads **by path, never by scanning**:
  an exported build hides `.tres` behind a `.remap` and a `DirAccess` scan finds
  nothing.
- `core/equipment/` — `EquipmentSlotDefinition`, `EquipmentLayout`.
- `scripts/actors/player/henry/components/equipment_component.gd` — body slots
  are fixed by a layout resource, **pockets are brought by the garment**. Take
  the coat off and its pockets, and their contents, go with it. `equip()` into an
  occupied slot refuses rather than swapping; `unequip()` refuses while the
  garment's own pockets hold anything.
- `.../inventory_component.gd` — loose carry, gated by weight.
- `data/items/` and `data/equipment/player_layout.tres` — a worn coat, knit hat,
  work trousers, worn boots and a tin of stew; slots `head`, `torso`, `legs`,
  `feet`, `pack` and `back_fixture` (Kenny's, excluded from auto-stow).
- `tests/systems/test_equipment.gd`.

**The point of the exercise**
- `GarmentData.insulation_c` and `EquipmentComponent.get_total_insulation_c()`
  — the axis ADT's garments do not have. `ThermalManager` now reads what Henry
  is actually wearing, falling back to its exported constant when no equipment
  is wired, so every earlier test kept passing untouched. Fully dressed is about
  11 °C against the old flat 6 °C, and a test asserts a dressed Henry cools
  measurably slower than a bare one and that removing the coat is felt at once.

Removed
- `InventoryManager.gd` and its node in `player.tscn`. It was never wired
  (`setup()` had no callers), `Item` was an inner class that could not be
  authored, `_create_item_by_id()` returned null so loading restored nothing,
  and `_input()` read raw keycodes including `KEY_E`, colliding with `interact`.

Verified
- Ten suites pass; `TestScene` and the island both render after the removal;
  the filename gate is clean.

### 2026-09-23 (2) — Phase A step 1: player state and the interact claim

Both ported from ADT with permission; see `docs/THIRD_PARTY_NOTICES.md`.

Added
- `core/player_state/player_state.gd` — autoload, the single source of truth for
  what the player is doing: `ON_FOOT`, `WORKING`, `SWIMMING`, `SLEEPING`, `MENU`.
  **`MENU` is reachable only through `open_menu()`/`close_menu()`**; `set_mode(MENU)`
  push_errors, and so does any mode change while a menu is open, so pause and
  mode can never diverge. Pause is set **before** the signal fires, so every
  listener sees a consistent tree. A menu opened while swimming returns to
  swimming.
- The **interact claim** in `InputSystems`. While a claim is held the key
  belongs entirely to the claimant and `interact_pressed/held/released` stay
  silent — one owner decides what the key means instead of subscribers racing.
  The claimant duck-types `on_interact_claimed()` plus optional
  `on_interact_held(duration)` / `on_interact_released(duration)`. This is what
  Phase B's "hold to seal a breach" will use.
- `tests/systems/test_player_state.gd` — the pause coupling, mode restoration,
  movement blocking, and the claim taking and returning the key.

Changed
- `InputSystems` now gates on `PlayerState`: `get_move_axis()` returns zero and
  `is_sprinting()` returns false whenever the mode holds the player still, so
  no caller has to check. Gameplay edges are suppressed in `MENU`, except the
  cancel key, which must still reach the menu that is open.
- `SleepPrompt` no longer sets `get_tree().paused` itself — it calls
  `PlayerState.open_menu()`/`close_menu()`. Pause has one owner now.

Notes
- `_tick_interact()` level-polls `Input` as a safety net: if the release event
  never arrives (a Control ate it, focus was lost, the claimant was freed) the
  key would otherwise read as held forever. The test presses the key for real
  rather than working around that net.

Verified
- Nine suites pass; `TestScene` renders; the filename gate is clean.

### 2026-09-23 (1) — The project's own licence

Fixed
- **`/LICENSE` was an unrelated third party's MIT** — `Copyright (c) 2023
  mohsenph69`, the author of the Godot-MTerrain addon. It arrived in commit
  `5496269` alongside terrain experiments and was never replaced, so the whole
  game was formally published under MIT, granting everyone the right to copy,
  modify, sublicense and sell it, attributed to someone unconnected to the
  project. Not Terrain3D's licence either — that one ships separately at
  `addons/terrain_3d/LICENSE.txt`. Replaced with the project's own terms,
  modelled on ADT's. See issue #5.

Added
- `docs/THIRD_PARTY_NOTICES.md` now records the licensing history, so the change
  is explained rather than silently rewritten, and the author's permission to
  port code from `Nolavel/ADT` (whose licence requires written permission from
  the copyright holder, who owns both projects and granted it).


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
