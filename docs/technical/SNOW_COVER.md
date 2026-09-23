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
| `snow_cover` | float | 0–1 | Settled snow on up-facing surfaces. From the active weather profile, blended with it. | 0.5 |
| `frost_amount` | float | 0–1 | Rime on steep and vertical surfaces. From outdoor air: 0 at −2 °C, 1 at −25 °C. | 0.3 |

Declared in `project.godot` under `[shader_globals]`. A shader that declares
`global uniform float snow_cover;` does not compile if the name is missing
there, so the declaration is part of the contract and is tested.

## Per-profile cover

| Profile | `snow_cover` |
|---|---|
| calm | 0.35 |
| windy | 0.50 |
| snowfall | 0.80 |
| blizzard | 1.00 |

Nothing is ever zero: the island is never bare.

## Rules

- **One writer.** Nothing else calls `global_shader_parameter_set` for these
  names. `SnowfallVFX` may *read* `snow_cover` in its own shader; it does not
  write it.
- **Write on change only**, with a 0.002 threshold. Never read back through
  `RenderingServer` at runtime — that stalls on the render thread. Tests read
  `get_written_snow_cover()` / `get_written_frost_amount()` instead.
- **Frost follows the air outside, not the felt temperature.** A warm shelter
  does not melt rime off the outside of its walls.

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

- **Contact rule.** The ball of the foot within 6 cm of the ground, after it
  has risen past 9 cm since the last print, with Henry on the floor and moving
  faster than 0.35 m/s. The ground is found by a short ray under the foot, so
  the rule works on any surface. The rule itself is a pure method
  (`update_foot`) and is tested without a scene.
- **Orientation.** The print image has the toe at the top, which a decal maps
  to its −Z; the decal's −Z is set to the heel→toe direction of the foot. Left
  and right prints are cropped from the ADT stamp `pin_step_walk.png`.
- **Terrain-agnostic.** Decals project onto whatever is below. Nothing is
  deformed; real depth belongs to a later local snow shell.
- **Fill.** A print lasts 240 s with no snow falling and 25 s in a whiteout,
  scaled by `WeatherController.get_snowfall_density()`. A pool of 64 reuses the
  oldest print first.
- **The sensor is the shared source** for anything that needs to know a foot
  landed: footstep audio and ice load can listen to the same signal.

### Known: stride length comes from the animation, not from here

Walking at `MovementController.walk_speed` (4 m/s) with the current walk clip
plants a foot roughly every 1.3–2.7 m. The prints are honest about that: the
clip's cadence is slow for the ground speed, so Henry glides. Tightening it is
an animation/locomotion blend change in `HenryUALAnimation`, not in this system.
