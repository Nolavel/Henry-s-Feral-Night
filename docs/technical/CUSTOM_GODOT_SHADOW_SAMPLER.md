# HFN custom directional-shadow sampler

Optional. The project runs on stock Godot 4.8-dev6 (CLAUDE.md engine baseline):
the default stylized-shadow path warps LIGHT_VERTEX and tears ATTENUATION into
ink. This patch is an opt-in upgrade for a local editor build; enable it by
uncommenting `#define HFN_PATCHED_SHADOW_SAMPLER` in
`shaders/environment/stylized_shadow.gdshaderinc`. Never commit it enabled:
CI, other machines and export templates run stock Godot.

## Engine base

The engine source patch is pinned to the exact upstream commit used by the official Godot **4.8-dev6** build:

`8898c2b3db32adf6f92c694ffb6dac19af672e5f`

Do not use it against another Godot revision without rebasing the source transforms.

## What the engine modification adds

Spatial `light()` gets:

- `LIGHT_INDEX : uint`
- `float sample_directional_shadow(uint light_index, vec3 vertex)`

The custom sampler accepts a **view-space** position and samples the current Forward+ directional shadow map at that position using Godot 4.8's PSSM/PCF data. HFN can therefore perform two independently displaced shadow-map lookups instead of approximating the effect by moving `LIGHT_VERTEX`.

Omni and Spot lights remain on Godot's physical shadow path. Forward Mobile stays buildable, but the custom sampler intentionally returns `1.0` there; HFN production uses Forward+.

## Why a Python source patcher is used

The first implementation used a unified `.patch`. Real Windows `git apply` exposed fragile hunk-position assumptions, so the build no longer relies on a text diff.

`tools/engine/apply_directional_shadow_sampler.py` performs exact, one-time source replacements against the pinned upstream SHA. If any expected Godot source fragment differs, it stops immediately before SCons starts. The build then runs `git diff --check`.

## Build on Windows (.NET)

Prerequisites:

- Git
- Python + SCons
- Visual Studio 2022 C++ Build Tools
- .NET SDK 8+

From the HFN repository root:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\tools\engine\build_patched_godot_windows.ps1 -VerifyProject
```

The script reuses `%USERPROFILE%\hfn-godot-4.8-dev6\godot` if it already exists. On every run it resets only **tracked Godot source files** to the pinned dev6 commit, reapplies the deterministic HFN source transform, validates the diff, and then builds. Existing SCons/bin outputs are left in place to make retries cheaper.

`-VerifyProject` then imports HFN with the patched editor and runs `tests/systems/test_stylized_shadows.gd`, forcing production receiver shaders that reference `LIGHT_INDEX` and `sample_directional_shadow()` to compile.

No GitHub Actions are used.
