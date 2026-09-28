# Shelter door and stove validation - 2026-09-28

Implemented on `codex`, Godot 4.8 dev6 .NET. No publication or main integration.

## Automated checks

All 58 `tests/systems/test_*.gd` suites returned zero and passed their assertions.
The full run report/logs are local under `.godot/codex-checks/`.
The ice suite still reports its unrelated duplicate `tile_broke` connections;
PlayerState/save suites deliberately exercise refusal diagnostics. These are not
new stove/door failures and the complete run is not described as diagnostic-free.

Focused coverage:

- `test_door_draft.gd`: actual four-window/one-door scene, narrow emitters outside
  the closed leaf, moving aperture at 30/60/105 degrees, snowfall absent, windward
  and leeward wind, particle blockers, and old boarded-door saves.
- Identical shelter/weather comparison after reaching the heat ceiling: sealed
  1.395 C, closed 0.973 C, open -7.035 C felt temperature. Extra closed-gap cooling
  is **0.422 C**, satisfying the <=1 C requirement in the existing blizzard.
- `test_stove_act.gd`: paired/single transfers, last-log fallback, full stove,
  carry capacity/occupied hands, atomic completion, cancellation, repeated latched
  retrieval, F mode exit, saved whole logs, forced misfires and guaranteed sixth
  strike, animation interval, non-accumulating holds, one-time tinder consumption,
  warmup save/restore, legacy burning saves, charred-log refusal and cooking/heat
  integration. New state labels are checked in English and Russian.
- `test_stove_world_time.gd`: actual Graciosa world initialization and canonical
  clock wiring; intensity 0.54 at 10 normal seconds and 1.0 at 20, 10x acceleration,
  sleeping through fuel exhaustion and temporary fine-step request release.
- `test_shelter_focus.gd` / `test_shelter_workflow.gd`: physical handle versus open
  firebox targeting, occlusion, real mouse events, carry visuals and hot refueling.
- Existing fire, stove visual/warmer, time-costed actions, save, sound, thermal,
  snow and world-composition regression suites also passed.

A full resource import passed. Running the shelter generator produced **4323 nodes
and 83 footprints**. The generated output passes the same door and route tests;
the committed scene retains a minimal semantic diff instead of regenerated IDs.

## Native rendering and audio

`tools/runtime/capture_stove_draft.gd` runs the production Graciosa scene with
Forward+ Vulkan on Intel HD Graphics 620 and the real **WASAPI** audio driver.
It uses the real player hand socket, lighter prop, SoundSystem and SFX bus.
The SFX recorder is downstream of the indoor low-pass filter (`interior = 1`).

Local output: `.godot/codex-checks/live-stove-final/`.

- `01_sparks.png`: visible failed-strike sparks and flash at the hand.
- `02_held_lighter.png` / `03_released.png`: held flame/light then extinguished
  lighter with the stove still cold; runtime telemetry also checks the flame node.
- `04_kindling.png` / `05_developed.png`: independent small-to-full stove growth.
- `06_door_closed_blizzard.png`, `06b_door_gap_detail.png`, `07_door_moving.png`,
  `08_door_open_blizzard.png`, `09_door_without_snow.png`: main-scene door states.
- `lighter-indoor.wav`: nonzero 48 kHz stereo SFX recording with no clipping.
  The final recorded peak was -24.0 dBFS; the companion
  `audio-level.txt` contains the measurement. This establishes actual
  playback through the indoor bus and audio driver, not a headless audibility claim.
- `control.mp4`: timestamped native frames with that indoor audio recording.

Frame readback/PNG encoding slows wall-clock capture. The canonical driver test,
rather than video duration, establishes the normal 3-second hold and 20-second
warmup. The ordinary game runtime contains no recording/readback work.
The native main-scene run retains two existing invalid optional debug-label warnings.

`tools/runtime/capture_door_barrier.gd` separately uses actual shelter geometry
and production particle shaders in a native renderer. Its output is under
`.godot/codex-checks/door-barrier/`:

- `01_actual_closed_gap.png` shows aperture snow originating at the narrow gap.
- `02_exterior_gap_stress.png` shows exterior snow crossing the gap.
- `03_exterior_leaf_blocked.png` shows the same exterior probe stopped by the leaf.
- `04_without_barrier_control.png` disables both shader and particle contacts and
  reproduces a dense stream through the leaf at the unchanged probe location.
- `05_leaf_at_45_degrees.png` restores contacts with the leaf rotated.

The exterior probe is a deliberately dense 512-particle test, not the production
snow budget. Native snapshots establish rendered behavior; headless geometry and
weather checks alone were not used as evidence of visible snow/sparks or audio.

## Replay

Use the repository's Godot 4.8 dev6 executable:

```text
godot --headless --editor --path . --import
godot --headless --path . --script res://tests/systems/test_stove_act.gd
godot --headless --path . --script res://tests/systems/test_stove_world_time.gd
godot --headless --path . --script res://tests/systems/test_door_draft.gd
godot --path . --script res://tools/runtime/capture_stove_draft.gd
godot --path . --script res://tools/runtime/capture_door_barrier.gd
```

The accepted CC0 recording, author/source/license links and SHA256 package receipt
are in `assets/audio/lighter/`. The original public OGG preview is unmodified;
playback gain/pitch are authored in `resources/audio/lighter_strike.tres`.
