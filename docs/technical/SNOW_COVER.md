# Snow cover — the contract between weather and snow shaders

Scope: `SnowPresentationSystem`, the `snow_cover` and `frost_amount` shader
globals, and every material that reads them. Decided in issue #16.

## The boundary

```
WeatherController (authority: profiles, blending)
ThermalManager    (authority: outdoor air)
        │  read-only
        ▼
SnowPresentationSystem   ← the only writer
        │  RenderingServer.global_shader_parameter_set, on change only
        ▼
shader globals: snow_cover, frost_amount
        │  `global uniform float …;`
        ▼
props / environment materials (via shaders/environment/snow/*.gdshaderinc)
```

**The snow layer does not know what the ground is made of.** Terrain3D is a
placeholder that may be replaced by a Blender mesh, so no snow work goes into
its shader and no terrain geometry is deformed. Ground snow, when it comes, is
its own layer on top: decals or a local snow shell around the player.

## Globals

| Name | Type | Range | Meaning | Default |
|---|---|---|---|---|
| `snow_cover` | float | 0–1 | **Settled** snow on up-facing surfaces — world state, not the weather. | 0.5 |
| `frost_amount` | float | 0–1 | Rime on steep faces, grown from edges inward. | 0.3 |

Declared in `project.godot` under `[shader_globals]`. A shader that declares
`global uniform float snow_cover;` does not compile if the name is missing
there, so the declaration is part of the contract and is tested.

## Settled snow is state, not a weather mirror

Each weather profile carries `snow_cover` — the level that weather *tends to
leave*. The global does not jump to it. `SnowPresentationSystem` owns a settled
value that moves with game time:

| Situation | Behaviour |
|---|---|
| Snow falling, weather's level above settled | builds at `build_per_hour` (0.6) × snowfall density |
| Weather's level below settled | settles at `settle_per_hour` (0.03): a blizzard's 1.0 takes about a day to settle to calm's 0.35 |
| Outdoor air above 0 °C | extra loss, `melt_per_hour_per_c` (0.02) per degree |
| Fresh world | starts at its weather's level, not bare |

Rime follows the outdoor air (0 at −2 °C, 1 at −25 °C) but moves at
`frost_per_hour` (0.25): it grows and sheds over hours, never snaps across a
threshold. Both values are saved under the `snow` key and restored on Continue.

| Profile | `snow_cover` target |
|---|---|
| calm | 0.35 |
| windy | 0.50 |
| snowfall | 0.80 |
| blizzard | 1.00 |

## Rime grows from edges

Rime needs something to grow from: corners, edges, the cold base of an object,
cavities. It does not appear as uniform noise across a face. `frost_weight()`
takes an `edge` factor, 1 on an edge and 0 mid-face; as `frost_amount` rises the
front moves inward, and noise only breaks up that front.

- **Real assets:** bake an edge/cavity (curvature + AO) mask and assign it to
  `edge_mask` on the material. White is where rime gathers.
- **Placeholder boxes:** set the per-instance `box_half_extents` and
  `box_center_offset` to **the whole surface the piece belongs to**, so seams
  between pieces of one wall do not read as edges. The test shelter does this.

## Rules

- **One writer.** Nothing else calls `global_shader_parameter_set` for these
  names. `SnowfallVFX` may *read* `snow_cover` in its own shader; it does not
  write it.
- **Write on change only**, with a 0.002 threshold. Never read back through
  `RenderingServer` at runtime — that stalls on the render thread. Tests read
  `get_written_snow_cover()` / `get_written_frost_amount()` instead.
- **Frost follows the air outside, not the felt temperature.** A warm shelter
  does not melt rime off the outside of its walls.
- **Readers are free.** `SnowfallVFX` or any shader may read `snow_cover`;
  nothing but `SnowPresentationSystem` writes it. `test_snow_presentation.gd`
  scans `scripts/`, `core/` and `world/` for other writers and fails on one.

## Quality tiers

| Tier | What runs |
|---|---|
| Low (HD 620 class) | cover + rime from the shared include, decal footprints, bounded snowfall particles. No compute, no POM. |
| High (Forward+) | the above, plus — later — a local L0 accumulation field, POM near the camera, compute evolution. |

Nobody enables compute on the low tier by default.

## Material checklist for the dressed slice

Snow reads as a world only when everything outside uses the same include.
Before the slice area is called done, each of these carries
`snow_surface.gdshaderinc` (through `snow_prop.gdshader` or its own material):

- [ ] Ground — a snow shell or decal layer over whatever the terrain becomes
- [x] Test shelter walls and roof
- [ ] Crates, barrels and other outdoor props
- [ ] Rocks and shore objects
- [ ] Dead trunks and vegetation that stands above the snow
- [ ] Path markers and signs
- [ ] Ice edge along the bay, where it meets snow — cover only; ice integrity
      and its crack visuals stay with `IceField`

## Footprints

```
HenryUALVisual skeleton (read only)
        │  foot_l / ball_l / ball_leaf_l, and _r
        ▼
FootContactSensor (on player.tscn)
        │  foot_planted(side, ground_point, heel→toe forward, speed)
        ▼
FootprintSystem (composition root) — pooled Decals
```

- **Signal.** `foot_planted(side, position, normal, forward, speed)`. The normal
  is the ground's, from the same ray; `forward` runs heel to toe *along* that
  ground, so a print on a slope lies on the slope instead of hovering flat.
- **Contact rule.** The ball of the foot within 6 cm of the sampled surface,
  with Henry on the floor and moving faster than 0.35 m/s. Contact distance is
  measured along the hit surface normal rather than world Y. A foot rearms
  either after an obvious 9 cm ground clearance or after its animated ball bone
  rises 4.5 cm relative to that foot's last planted pose in Player-local space.
  The animated phase is observed before the ground ray, so a brief Terrain3D /
  collider-seam probe miss cannot silently lose the next step. Small planted
  jitter remains below the rearm threshold. The contact rule itself remains
  testable without a scene.
- **Orientation.** The decal's +Y is the ground normal (it projects along −Y);
  the print image has the toe at the top, which a decal maps to its −Z, set to
  the heel→toe direction along the ground. Left
  and right prints are cropped from the ADT stamp `pin_step_walk.png`.
- **Terrain-agnostic.** Decals project onto whatever is below. Nothing is
  deformed; real depth belongs to a later local snow shell.
- **Fill.** A print lasts 240 s with no snow falling and 25 s in a whiteout,
  scaled by `WeatherController.get_snowfall_density()`. A pool of 64 reuses the
  oldest print first.
- **Decals are the low tier, not persistence.** Once walking cadence is fixed,
  64 prints recycle well before 240 s. Growing the pool is not the fix; the
  high-tier answer is a local L0 accumulation field that stamps write into.
- **The sensor is the shared source** for anything that needs to know a foot
  landed: footstep audio and ice load can listen to the same signal.

### Known: stride length comes from the animation, not from here

Walking at `MovementController.walk_speed` (4 m/s) with the current walk clip
plants a foot roughly every 1.3–2.7 m. The prints are honest about that: the
clip's cadence is slow for the ground speed, so Henry glides. Tightening it is
an animation/locomotion blend change in `HenryUALAnimation`, not in this system.
