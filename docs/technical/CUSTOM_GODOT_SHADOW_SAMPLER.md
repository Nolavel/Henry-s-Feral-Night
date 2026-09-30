# HFN custom directional-shadow sampler

Optional. The project runs on stock Godot 4.8-dev6 (CLAUDE.md engine baseline):
the default stylized-shadow path warps LIGHT_VERTEX and tears ATTENUATION into
ink. This patch is an opt-in upgrade for a local editor build; enable it by
uncommenting `#define HFN_PATCHED_SHADOW_SAMPLER` in
`shaders/environment/stylized_shadow.gdshaderinc`. Never commit it enabled:
CI, other machines and export templates run stock Godot.

## Engine base

The patch is pinned to the exact upstream commit used by the official Godot **4.8-dev6** build:

`8898c2b3db32adf6f92c694ffb6dac19af672e5f`

Do not apply it to a different Godot revision without rebasing the patch against that revision.

## What the patch adds

The patch introduces two shader-language features for spatial `light()`:

- `LIGHT_INDEX : uint`
- `float sample_directional_shadow(uint light_index, vec3 vertex)`

The custom sampler accepts a **view-space** position and samples the current Forward+ directional shadow map at that position using Godot 4.8's PSSM/PCF data. This is what the original ShaderError reference needs in order to make two independently displaced shadow lookups.

Forward Mobile is kept buildable but deliberately returns `1.0` from the custom sampler. HFN production rendering is Forward+.

## Build on Windows (.NET)

Prerequisites:

- Git
- Python + SCons
- Visual Studio C++ build tools or another supported Windows toolchain
- .NET SDK 8+

Run from PowerShell:

```powershell
tools/engine/build_patched_godot_windows.ps1 -VerifyProject
```

The script:

1. clones Godot into a dedicated folder under the user's profile;
2. checks out the exact dev6 upstream commit;
3. applies `tools/engine/patches/godot-4.8-dev6-directional-shadow-sampler.patch`;
4. builds the Windows .NET editor;
5. generates Mono glue and GodotSharp assemblies;
6. optionally imports HFN with that patched editor;
7. runs `tests/systems/test_stylized_shadows.gd` with the patched executable, which forces the production custom-sampler shaders to compile.

No GitHub Actions are used. `-VerifyProject` is the final local gate: a stock Godot editor cannot compile the HFN shaders that reference `LIGHT_INDEX` and `sample_directional_shadow()`, while the patched editor must import them and pass the contract test.

## Why this exists

The public Godot shader API exposes only the shadow attenuation for the current fragment. The stylized reference needs two shadow-map samples at two noise-offset positions. A single `LIGHT_VERTEX` offset cannot reproduce that algorithm and also affects local Omni/Spot shadow lookup.

The patched path leaves Omni/Spot lighting untouched and only performs custom directional samples when HFN's material `light()` explicitly asks for them.
