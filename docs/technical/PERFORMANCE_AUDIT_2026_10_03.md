# HD 620 performance audit — 2026-10-03

Related: #173 and #174. Status: measured diagnosis, not visual acceptance or a
completed optimization epic. Work was explicitly authorized in local `main`.

Published summary: [issue #173 comment](https://github.com/Nolavel/Hoarbound/issues/173#issuecomment-5969706720).

## Post-audit cleanup

The author subsequently requested removal of the diagnostic tools before commit
preparation. The capture scripts, C# prototype, CPU scopes, A/B controller and
console/city-statistics paths have been removed from the working source tree.
The lightweight FPS panel remains. Reproduction sources and their UIDs are
preserved locally under `shots/issue173_audit/retired_diagnostics/`, alongside
the original raw evidence. The C# source has a `.cs.txt` suffix so MSBuild does
not compile the archived experiment; Godot ignores the entire audit folder.
Tool paths and diagnostic flags below describe the
measured historical revision, not active production entry points. No new game
run was made for this cleanup, so its resulting FPS is not claimed as measured.

## Evidence and scope

- Godot 4.8-dev6 mono, Vulkan Forward+, Intel HD Graphics 620.
- Actual `scenes/world/key_west/key_west.tscn`, 1920x1080 window, 3D scale 0.77,
  MSAA disabled, high snow quality, VSync enabled.
- Main at `ffef61c` plus the existing uncommitted city/snow/sky changes. A copy
  of 257 modified/untracked files was saved before this pass under
  `shots/issue173_audit/pre_pass/`. No user edits were reset or committed.
- Two graphical game launches: initial observation, then an instrumented A/B
  sequence in one process. Each second-run stage had 8 seconds of settling and
  at least 30 seconds measured by wall time, after a 60-second initial warmup.
- PNG readback and JSON serialization happened after each measured interval.
  The C# experiment ran before the stage sequence, outside FPS samples.
- Raw evidence: `shots/issue173_audit/baseline/`,
  `shots/issue173_audit/diagnostic/`, `summary.json`, and `scopes.json` under
  `shots/issue173_audit/`. These are local ignored artifacts, not uploaded assets.
- Existing editor remained open; this was not a clean-room hardware benchmark.
  Power/clock telemetry was not recorded. Small single-stage differences must
  not be treated as accepted production gains.

### Important limitations

The capture harness placed Henry only 0.15 m above the sampled terrain. He did
not establish floor contact: every second-run stage reported `floor=false` and
six contacts with `IslandTerrain/Collision_12_18`. The initial forward-input
segment did not move him. Existing project capture tools use a 1 m lift.
This invalidates the intended walking/footprint-transition acceptance, and the
airborne pose in these images must not be reported as a newly proven gameplay
regression. Stationary render comparisons within the second run retain the same
pose and scene. The first and second launch are not a strict camera-matched pair.

DayNightManager processing was frozen after setting 12.85 hours. The sky result
therefore does not measure normal continuously updated day/night radiance work.
Weather/VFX still vary. No claim is made about all viewpoints, night, occlusion
pop-through, or the author's intermittent square seam during walking.

## Stationary A/B results

`quiet` disables StatsDisplay console snapshots and the performance policy's
city diagnostics, while retaining its streaming/camera/sky policy updates.
All exclusion stages start from this quiet control; settings are restored
between stages. Exclusions are diagnostic only and never saved into scenes.

| Stage | Wall FPS | Root GPU mean, ms | Wall frame p95, ms | Mean draw calls |
|---|---:|---:|---:|---:|
| Current diagnostics on | 3.676 | 132.98 | 724.58 | 491 |
| Quiet control | 5.758 | 132.89 | 217.57 | 492 |
| 3D scale 0.50 | 7.276 | 92.75 | 182.50 | 492 |
| Three SnowShape viewports off | 6.090 | 132.17 | 205.05 | 489 |
| Full local SnowShell off | 9.578 | 86.32 | 140.60 | 441 |
| Directional shadows off | 5.827 | 125.43 | 197.64 | 424 |
| Flat background / sky resource removed | 6.031 | 121.66 | 211.92 | 493 |
| City geometry hidden | 6.324 | 120.15 | 194.00 | 389 |
| Most scene script subtrees paused, SnowShell retained | 6.072 | 134.80 | 174.87 | 496 |
| Quiet control repeated | 5.625 | 133.48 | 220.82 | 492 |
| Diagnostics on repeated | 3.367 | 130.77 | 765.37 | 490 |

FPS is frames divided by the actual sample duration, not an average of rounded
HUD FPS. Percentiles use sorted frame durations at `floor(n * percentile)`.
GPU numbers are asynchronous viewport measurements. Root GPU excludes auxiliary
snow viewports. Disabled viewports can retain their last GPU measurement, so the
raw sum of all viewport times is **not** used to compare exclusion stages. CPU
process time includes engine/server waits and is not equivalent to script time.

The initial uninstrumented launch produced approximately 3.37 wall FPS in its
30-second stationary interval. It is observational context, not the paired
control for the table.

## Confirmed causes

### 1. City diagnostics impose a recurring blocking cost

`StatsDisplay._estimate_mesh_triangle_primitives()` calls
`RenderingServer.mesh_get_surface()` for each visible city mesh surface on every
console snapshot. It requests surface data to obtain only vertex/index counts.
The enclosing city walk measured:

- first baseline: 27 calls, 13,306 ms total, 493 ms mean, 639 ms maximum;
- repeated baseline: 28 calls, 14,855 ms total, 531 ms mean, 764 ms maximum.

Disabling diagnostic output raised FPS from 3.68 to 5.76 and the repeated control
from 3.37 to 5.63 without reducing root GPU work. The expensive mesh traversal
accounts for almost all measured console snapshot time. This is a concrete
instrumentation regression, including server synchronization/data extraction,
not evidence that gameplay arithmetic needs a language rewrite.

Next correction: use CPU-side ArrayMesh surface count metadata, and a properly
invalidated bounded count cache or explicit unsupported-type accounting for
other mesh resources. Do not retrieve full render buffers every second merely
to count triangles. Keep diagnostic flags independent of production policy.

### 2. The local snow render path is a major remaining GPU cost

Quiet root rendering still takes about 133 ms. Removing the local snow path
cuts root GPU time by about 46.6 ms (35%) and raises FPS by about 66% in this
view. Removing the three shaping passes alone leaves root cost almost unchanged.
Snow contact capture is another approximately 11 ms auxiliary viewport in the
quiet sample. SnowPacked/SnowShape timestamps require care because UPDATE_ONCE
and disabled targets may expose stale values.

The 0.50 resolution experiment cuts root GPU cost by about 40 ms without reducing
draw calls. This supports a substantial pixel/shader/bandwidth component, but
does not distinguish those hardware mechanisms by itself. Full SnowShell off
also removes geometry, shaders, viewports and script callbacks: it cannot assign
the entire gain to any one shader loop. A density/material/contact-pass split
is the next targeted GPU investigation.

Even the full-shell exclusion leaves an 86 ms root GPU pass. Neither a C# port
nor removing one script loop can turn this measured configuration into 30/60 FPS.
The result establishes a rendering-budget mismatch for this HD 620 setup; it
does not establish that Henry's model or the entire game concept is unsuitable.

### 3. Snow generation causes separate multi-second streaming stalls

During warmup, inclusive activation scopes measured:

- `kw_city_-7_2`: 12,172 ms activation; snow face clipping 9,836 ms;
- `kw_city_-7_3`: 11,418 ms activation; snow face clipping 8,727 ms;
- `kw_city_-8_3`: 4,506 ms activation; snow face clipping 2,645 ms.

Snow height sampling cost another 1.05–1.22 seconds per example chunk. Initial
local SnowField grid rebuilding cost 1.62–2.36 seconds; depth assembly itself
was only about 29 ms. These scopes are nested: do not add them to their parents.

`ChunkedCityMassing._start_snow()` performs a synchronous whole-chunk build near
Henry. `_process()` also finishes nearby jobs with a `1 << 40` microsecond budget.
The new exact footprint clipping in `SnowChunkCover._shade_row()` therefore runs
thousands of polygon operations on the main thread before a frame can complete.
This explains startup/arrival stalls, separately from steady-state GPU pressure.
Near-window GPU track readback was 21 ms in one observed transition; it is not
the measured 9-second clipping cause.

Next correction: precompute stable terrain/footprint topology, or finish it
under an actual preload budget before activation. Retain a single consistent
near/far snow-height and coverage contract. Increasing a distance or restoring
an unlimited synchronous budget alone cannot make a several-second build
invisible while walking.

## C# experiment: useful, but not a game-wide FPS result

`tools/performance/SnowDepthAudit.cs` computes baked settled depth using actual
SnowField ground, prevailing-wind and storm arrays. Four warmup calls preceded
20 measured calls. Caller timing includes marshalling arrays into C# and
returning the result. The .NET build used the project's Debug configuration.

| Work | Median | Mean |
|---|---:|---:|
| Existing GDScript `_begin_assemble` + 130 `_assemble_row` calls | 28.825 ms | 30.511 ms |
| Batched C# depth-output prototype, 16,900 cells | 0.888 ms | 1.825 ms |

Maximum depth-output difference was zero for these inputs. This is approximately
32.5x by median for the compared paths, **not an isolated language-speed ratio**:
the C# prototype returns only depth, while the existing GDScript path also sets
up/fills weights and evaluates auxiliary values unused by its baked branch.
Batching/removing redundant work contributes to the difference. It is not a
complete SnowField replacement or a measured production C# integration.

Crucially, the quiet 30-second stationary sample had no field rebuild. SnowShell
CPU callbacks totaled about 982 ms over the entire 30 seconds (inclusive physics
and process), while GPU rendering remained expensive every frame. Replacing the
depth calculation thus offers approximately zero direct steady-state benefit
in that sample, though it could shorten future rebuilds. The expensive polygon
clipping and terrain/physics sampling were **not** ported or benchmarked in C#.

Pausing most scene scripts while retaining SnowShell produced only 6.07 FPS.
This is an exclusion bound with changed simulation, not a prediction for a
semantically equivalent port. It gives no evidence for a large broad C# FPS gain.
Prioritize bulk CPU geometry kernels if profiling still identifies them after
prebaking/scheduling. Native engine calls and GPU shader work do not become
cheaper merely because their caller changes language.

## Visual review and issue status

- Clouds, building shadows and local snow rendered in both launches; no shader
  compilation error occurred. The reported scattered dark snow patches did not
  reproduce in the inspected views after the earlier caster restoration.
- The character remains in an airborne pose because the audit spawn never
  established floor contact. The walk and moving snow seam are unverified.
- A large soft black patch under the lower-right controls remains visible in
  both launches. Its owner/cause was not isolated; it should not be called a
  terrain shadow fix or attributed to SnowShell without a separate check.
- Shell-off visibly removes close snow relief; city-off removes buildings.
  These screenshots are exclusions, not acceptable production configurations.
- Logs show four active detailed city chunks, seven local massing chunks and
  52 resident far sectors at this position. That is not all 148 detailed chunks,
  but the far-sector residency still deserves a budget review.
- #173 remains open: the expensive main snow path, near/far seam and moving
  transitions are not accepted; all requested reference conditions are not met.
- #174 remains open: this pass did not toggle occlusion or verify moving-camera
  false occlusion. City-off is not an occlusion acceptance test.
- Existing warnings remain for stale stamina/speed debug-label paths, raw PNG
  loading that is unsafe for export, an obsolete expected 148-chunk count after
  far-sector registration, and Control anchor sizing.

## Changes made in this pass

Added opt-in `HFN_PERF_SCOPES=1` timing for snow rebuild phases, track readback,
stream activation, and console diagnostics. Added render-scale/MSAA metadata,
per-frame audit output, restored A/B stages, and an isolated C# comparison tool.
Added a diagnostic-output switch to RuntimePerformancePolicy without disabling
its actual policies. No diagnostic exclusion was saved as a production setting.

Validation: C# build completed with zero warnings/errors; diagnostic controller
passed `--check-only`; both graphical processes exited with code 0, and no script
or shader error occurred in their logs. Parser validation is not visual acceptance.

## Sources

- [Godot CPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html): profile first, native engine functions do not change speed with the caller's language.
- [Godot C# basics](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_basics.html): native interop and collection conversion costs matter.
- [ArrayMesh metadata methods](https://docs.godotengine.org/en/latest/classes/class_arraymesh.html): surface vertex/index lengths without requesting the entire surface payload.
- [PrimitiveMesh implementation](https://github.com/godotengine/godot/blob/master/scene/resources/3d/primitive_meshes.cpp): `get_mesh_arrays()` is also a render-server array retrieval, not a cheap count replacement.
