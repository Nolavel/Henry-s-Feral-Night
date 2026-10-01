# Visual FX shaders

## Fade Volume

Reusable scene: `res://scenes/environment/visual_fx/FadeVolume.tscn`

The scene contains a BoxMesh using `fade_volume.gdshader`. The fade axis is
the cube's local X axis. Keep `x_len` equal to the BoxMesh X size. Rotate the
node to choose the fade direction and scale/edit the BoxMesh for the target
space.

This is a local transparent volume, not a fullscreen post-process.

## Stylized Shadows

Production contract:
`res://shaders/environment/stylized_shadow.gdshaderinc`. Model, tuning and
verification: [`docs/technical/STYLIZED_SHADOWS.md`](technical/STYLIZED_SHADOWS.md).

Only the shadow term is stylized, on stock Godot: every light's shadow lookup
is moved by world-space noise (`LIGHT_VERTEX`), and the directional shadow is
cut into three tones with noise-jittered cuts. N·L stays physical. It is not a
fullscreen post-process and does not patch the engine.

It is consumed by `IslandTerrain`, local and chunk-wide snow, the frozen sea,
and every material made by `StylizedEnvironmentMaterial` (Key West buildings,
roads, street props, the shelter house, doors, boards and tables).

`StylizedEnvironmentMaterial` adapts ordinary opaque `StandardMaterial3D`
environment assets. Transparent and deliberately unshaded materials stay on
their original path because they are not shadow receivers.

`stylized_shadow_strength` (`[shader_globals]` in `project.godot`) set to 0
restores physical shadows without swapping materials.

Showcase material:
`res://scenes/environment/visual_fx/StylizedShadowMaterial.tres`

Visual regression:
`tools/runtime/capture_stylized_shadows.gd` captures matched physical/stylized
Key West frames outside at noon, inside the shelter at noon and by stove light
at night, and the stove frame under each outdoor LUT. It runs in the existing
`checks.yml` Key West render job with the `[stylized-shadows]` commit marker.
