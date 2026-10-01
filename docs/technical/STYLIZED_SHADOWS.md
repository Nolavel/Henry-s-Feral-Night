# Stylized shadows

Status: production contract since 2026-10-01. Author decisions: stock Godot only
(no engine fork); stylize the shadows only, not the whole light ramp.

Reference: [Stylized shadows, not a post processing](https://godotshaders.com/shader/stylized-shadows-not-a-post-processing/)
(ShaderError, CC0, May 2023): cast shadows with a torn, noise-displaced
silhouette and a spray of mid-tone islands around a dark core.

## Model

Two stages, both in world space and both inside the material, so fog,
volumetrics and the colour grade apply after them unchanged.

1. **Torn lookup (all lights).** `fragment()` moves `LIGHT_VERTEX` by a
   three-octave value-noise vector projected into the surface plane
   (0.18 m, base 3 cycles/m). Godot copies `LIGHT_VERTEX` into the position
   used for every light and shadow lookup
   (`scene_forward_clustered.glsl`, `vertex = light_vertex`, 4.8-dev6
   `8898c2b`), so each fragment reads the shadow map at a nearby point and the
   cast silhouette tears. Projecting into the surface plane keeps walls from
   sampling inside themselves.
2. **Three tones (directional only).** `light()` cuts the directional shadow
   term into core 0, mid 0.45 and lit 1, with the two cuts (0.34, 0.66)
   jittered by a second noise (base 9 cycles/m, contrast 2.5, clamped to ±0.3).
   The jitter never reaches a fully lit or fully shadowed fragment, so only the
   penumbra breaks into islands. The sun's `shadow_blur = 3.3` widens that
   penumbra so the islands form a visible halo, and the directional soft-shadow
   filter runs at Soft High: at the default Soft Low the rotated PCF samples
   leave per-pixel dither in the penumbra, which the tone cut turns into speckle.
   Godot also scales the filter radius with quality (2.0 Low/Medium, 3.0 High,
   4.0 Ultra), so blur × radius is held at ~10. At that width, pixel-scale noise
   on the replica was 4.9 Low, 2.6 Medium, 1.8 High, 1.3 Ultra.

N·L stays physical, and so does everything that is not a shadow.

Noise octaves fade before they fall under ~3 px (`fwidth` of the world
position), so distant shadows settle to three clean tones rather than sub-pixel
noise. The noise is fixed to the world, so it does not swim with the camera.

### Local lights

In `light()` an omni or spot `ATTENUATION` is distance falloff × shadow, and
stock Godot exposes no light position to separate them. Local lights therefore
get the torn lookup but not the tone cut. The lookup offset also moves the
falloff sample slightly; measured on the lab omni with no shadow, the light pool
changes by ΔL\* 0.67 mean, 1.56 p95 (around the just-noticeable difference).

The shelter stove's room light (`Flame`) casts shadows; the firebox glow does not.

## Why the earlier contract never matched the reference

Measured on a replica of the reference scene (see Verification):

- It only edited `ATTENUATION` inside the physical penumbra. With a hard sun
  that band is a few centimetres wide, and darkening the core changes nothing
  because direct light there is already zero. The frame was visually the same
  as physical shadows.
- Its noise periods were 2–18 m against a 5–15 cm grain in the reference, and
  its warp was horizontal only, which pushes wall lookups into the wall.
- The shelter could not show it at all: the stove light cast no shadows, local
  lights were excluded, and the shelter materials opted out.

The engine patch (two lookups per light) was not the missing piece: the stock
`LIGHT_VERTEX` lookup reproduces the silhouette, and the mid-tone islands come
from the penumbra cut. The patch and its build tooling were removed.

## Colour grades

The tone cut happens before tonemapping and the LUT. All Cold Ash LUTs are
monotonic, so the three tones stay three distinct, ordered levels and the island
shapes do not change; a LUT only moves the spacing between tones. On the
replica, lit/shadow separation was ΔL\* 47–54 under all four LUTs (physical
48). In the shelter at night, the stove shadow measured ΔL\* 13–14 on the floor
and 20–21 on the wall under all four LUTs. Shadow readability is set by the
key/fill ratio (sun or stove against ambient), not by the grade. Inside, the
levers are the stove's room light (`StoveVisual.ROOM_LIGHT_ENERGY`) against
`DayNightManager.shelter_ambient_energy_cap`.

## Tuning

Constants at the top of `stylized_shadow.gdshaderinc`. One global,
`stylized_shadow_strength` (0 = physical), drives the A/B captures.
Light-side settings: `SunLight.shadow_blur` in `WorldEnvironmentSystem.tscn`,
`Flame.shadow_blur` in `first_exit_blockout.tscn`, and
`rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality`
(4, Soft High, 16 taps) in `project.godot`. Changing the quality changes the
penumbra width too; rescale `shadow_blur` with it. Its cost has only been seen
on lavapipe and needs a real-GPU check. A soft sun via
`light_angular_distance` (PCSS) was rejected: its sampling noise speckled
fully lit snow once cut into tones.

## Verification

`tools/runtime/capture_stylized_shadows.gd` writes matched physical/stylized
frames of Key West: outside at noon, inside the shelter at noon, by stove light
at night, and the stove frame under the Day, Dusk and Night LUTs.

On lavapipe, outside and in the shelter: no new boot-log errors, and the
stylized shelter frame at noon is brighter than physical by more than 10 L\* on
0.07 % of pixels, all along existing sunlit edges (no light leaking through
walls).

Not yet verified: frame cost and camera-motion stability on a real GPU.
Characters keep their own materials: Henry's cast shadow is stylized where it
lands, but shadows falling on Henry are physical.
