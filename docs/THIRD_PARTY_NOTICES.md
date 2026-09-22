# Third-Party Notices

## Fade Volume

- Source: https://godotshaders.com/shader/fade-volume/
- Author: dairycultist
- Published: August 29, 2026
- License: CC0
- HFN changes: color/alpha control, numerical guards, reusable BoxMesh scene.

## Stylized shadows, not a post processing

- Source: https://godotshaders.com/shader/stylized-shadows-not-a-post-processing/
- Author: ShaderError
- Published: May 22, 2023
- License: CC0
- HFN changes: adapted for stock Godot without the source shader's custom
  `sample_directional_shadow()` engine-pipeline modification. The HFN version
  stylizes the built-in `ATTENUATION` shadow result inside `light()`.

## Freeman's Sky Shader

- Source: https://godotshaders.com/shader/freemans-sky-shader/
- Upstream: NiwlGames/GodotStarterAssets, shaders/sky_full.gdshader and
  shaders/sky_quarter.gdshader.
- Author: Niwl Games.
- Published: June 16, 2026.
- License: CC0-1.0.
- HFN experiment: official full-resolution and quarter-resolution variants are
  included. The capture harness may use the full-resolution variant with a
  capture-only manual sun-direction fallback on renderers that cannot expose
  LIGHT0 correctly; runtime Forward+ keeps the upstream LIGHT0 path.
  Island-specific atmospheric tuning is applied only by
  tools/runtime/capture_freemans_sky.gd.

