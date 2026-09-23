# Cold Ash color-grading previews

These images use the production 33^3 LUT textures committed under
`assets/textures/color_grading/` and the same clean `TestScene` source frame.

The current automation host does not expose a renderable Godot framebuffer, so
the checked-in previews were produced by trilinearly sampling the production
LUTs over an existing real `res://tests/scenes/TestScene.tscn` capture. They are
comparison references, not a replacement for an in-engine visual check.

Run `tools/runtime/capture_color_grading.gd` on a render-capable Godot 4.8 dev6
host to overwrite both files with fresh in-engine captures from the canonical
test scene.
