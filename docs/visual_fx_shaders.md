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
`res://shaders/environment/stylized_shadow.gdshaderinc`

The contract implements the **solid physical core + noise-broken perimeter**
look on top of stock Godot `ATTENUATION`. It does not patch the engine and is
not a fullscreen post-process.

It is currently consumed by:
- `IslandTerrain`;
- local and chunk-wide snow surfaces;
- Key West building, road, airport and street-prop material factories;
- the masked frozen sea;
- opaque static shelter meshes and runtime boards/door/table materials.

`StylizedEnvironmentMaterial` is the adapter for ordinary opaque
`StandardMaterial3D` environment assets. It preserves base colour, roughness,
metallic, albedo/normal textures, vertex colour, double-sided state and
emission. Transparent and deliberately unshaded materials stay on their
original path because their blend/preview/VFX semantics are not physical
shadow receivers.

Directional lights may tear the real cast-shadow penumbra while keeping a
solid dark core. Omni/Spot lights use the same world-space ink pattern at a
lower global strength; because Godot combines local-light distance falloff and
shadowing in `ATTENUATION`, the local path never brightens above the physical
falloff.

Global tuning lives in `project.godot` under `[shader_globals]`, headed by
`stylized_shadow_strength` and `stylized_shadow_local_strength`. Setting the
main strength to 0 restores physical attenuation without swapping materials.

Legacy showcase material:
`res://scenes/environment/visual_fx/StylizedShadowMaterial.tres`

CI visual regression:
`tools/runtime/capture_stylized_shadows.gd` captures three production Key West
views twice, with the global strength at 0 and 1, through the existing
`checks.yml` Key West render job using the `[stylized-shadows]` commit marker.
