# Visual FX shaders

## Fade Volume

Reusable scene: `res://scenes/environment/visual_fx/FadeVolume.tscn`

The scene contains a BoxMesh using `fade_volume.gdshader`. The fade axis is
the cube's local X axis. Keep `x_len` equal to the BoxMesh X size. Rotate the
node to choose the fade direction and scale/edit the BoxMesh for the target
space.

This is a local transparent volume, not a fullscreen post-process.

## Stylized Shadows

Reusable material:
`res://scenes/environment/visual_fx/StylizedShadowMaterial.tres`

Shader:
`res://shaders/environment/stylized_shadows.gdshader`

Assign the material to an environment mesh or duplicate it and replace
`albedo_tint` / enable `use_albedo_texture`.

The original GodotShaders example requires a custom engine shader built-in.
HFN intentionally does not patch the engine. This adaptation uses Godot's
stock `ATTENUATION` value (which already contains distance/shadow attenuation)
then perturbs the real directional shadow transition with two world-space
triplanar noise bands.

Important: this material replaces the receiving mesh's normal PBR material.
For textured production assets, duplicate the material and provide the
asset's albedo texture or port the shadow-light function into that asset's
existing shader.
