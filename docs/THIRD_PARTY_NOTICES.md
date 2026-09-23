# Third-Party Notices

## Licensing of this project itself

`/LICENSE` holds Henry's Feral Night's own terms: copyright reserved, not open
source. Until 2026-09-23 that path held an unrelated third party's MIT licence
(`Copyright (c) 2023 mohsenph69`, author of the Godot-MTerrain addon), which
arrived in commit `5496269` with terrain experiments and was never replaced —
so the project was formally published as MIT by someone unconnected to it. That
was never an intentional grant. See issue #5.

## Code ported from Nolavel/ADT

Parts of the body and interaction layer (items, catalog, garments, equipment,
inventory, interaction, hold prompt, input claim, player state) are ported from
`Nolavel/ADT` — *Vertical Trespass* / *Another Digital Thriller*.

ADT's licence reserves all rights and forbids reuse of its source in another
project **without prior written permission from the copyright holder**. Both
projects are owned by the same copyright holder, who granted that permission for
this port on 2026-09-23. What was taken, and what changed on the way across, is
recorded in [`technical/PORTED_FROM_ADT.md`](technical/PORTED_FROM_ADT.md).

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

## Simple Overcast cloud layer

- Source: https://godotshaders.com/shader/simple-overcast/
- Author: tentabrobpy
- License: CC0
- HFN changes: multi-layer angular parallax, depth sampling, wind, cloud-shape
  contrast and integration into the combined Freeman atmosphere shader.

## Freeman's Sky Shader

- Source: https://godotshaders.com/shader/freemans-sky-shader/
- Upstream: NiwlGames/GodotStarterAssets, shaders/sky_full.gdshader and
  shaders/sky_quarter.gdshader.
- Author: Niwl Games.
- Published: June 16, 2026.
- License: CC0-1.0.
- HFN integration: official full-resolution and quarter-resolution variants are
  retained for reference. Production uses
  shaders/environment/freemans_parallax_clouds.gdshader, which combines the
  Freeman atmosphere with HFN's CC0 Simple Overcast-derived parallax cloud layer.
  The atmosphere receives a dedicated solar direction from DayNightManager,
  while scene LIGHT0 continues to illuminate clouds as sun or moon.

## Wind Driven Falling Particles

- Source: https://godotshaders.com/shader/wind-driven-falling-particles-leaves-petals-feathers/
- Author: ProfesorShader
- Published: July 12, 2026
- License: CC0
- HFN production adaptation: procedural snowflake geometry, WeatherController-
  driven wind/gusts, live steering of airborne flakes, Terrain3D HeightField
  collision, rare foreground flakes and render-only high-wind velocity stretch.
  The source shader's autonomous wind range/change and vortex are not used.

