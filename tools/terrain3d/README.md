# Terrain3D 1.0.1 compatibility with Godot 4.8

Godot 4.8-dev6 rejects Terrain3D's bindings that shadow inherited Resource
methods. The stock DLL logs five `already has member ''` errors. The empty
method name is a separate engine diagnostic bug, not a damaged terrain file.

Upstream references:
- https://github.com/TokisanGames/Terrain3D/pull/1045
- https://github.com/godotengine/godot/pull/123752

The narrow source patch keeps Terrain3D 1.0.1 and its serialized properties:
- Bind asset accessors as `get_asset_name` / `set_asset_name` while retaining
  the serialized `name` property and the native C++ implementations.
- Let script calls to `duplicate` use Resource's implementation. Native
  Terrain3D C++ calls retain their original implementation.
- Read the asset `name` property in the editor dock; this also works with the
  original DLL on older Godot versions.

No terrain data is rewritten or migrated. Do not replace only the DLL with
an unrelated Terrain3D release. The binaries are ignored by Git, so a fresh
checkout still requires a local build. The existing Linux CI installers use
the stock upstream release; they do not install this Windows compatibility build.

## Reproduce the Windows build

Use a separate source directory outside the Godot project. Download:
- Terrain3D tag `v1.0.1-stable` from
  https://github.com/TokisanGames/Terrain3D/archive/refs/tags/v1.0.1-stable.zip
- Its godot-cpp submodule at `6388e26dd8a42071f65f764a3ef3d9523dda3d6e` from
  https://github.com/godotengine/godot-cpp/archive/6388e26dd8a42071f65f764a3ef3d9523dda3d6e.zip
- Portable LLVM-MinGW `20260922`, `ucrt-x86_64`, from
  https://github.com/mstorsjo/llvm-mingw/releases/tag/20260922

Extract godot-cpp into the Terrain3D source's `godot-cpp` directory. Install
Python and SCons if unavailable. From this repository, apply the patch once:

```powershell
python tools/terrain3d/patch_godot48.py C:/build/Terrain3D-1.0.1-stable
Copy-Item tools/terrain3d/build_profile.json C:/build/Terrain3D-1.0.1-stable/hfn_build_profile.json
```

Then compile in the source directory, setting the actual compiler location:

```powershell
$compiler = 'C:/build/llvm-mingw-20260922-ucrt-x86_64'
$env:PATH = "$compiler/bin;" + $env:PATH
Set-Location C:/build/Terrain3D-1.0.1-stable
scons platform=windows target=editor arch=x86_64 use_mingw=yes use_llvm=yes "mingw_prefix=$compiler" build_profile=hfn_build_profile.json debug_symbols=no -j2
```

The result is `project/addons/terrain_3d/bin/libterrain.windows.debug.x86_64.dll`.
Use `target=template_release` for the export DLL. Keep a backup of the original
DLLs. Restart Godot after replacing them; an already running editor retains
the library it loaded. Copy the patched asset dock script as well, or use the
matching version tracked in this repository.

## Verify before installation

Use an isolated project with the candidate extension and its own `.godot`
directory, so the open editor's temporary DLL is not locked by a second editor.
Run `verify_godot48.gd` with the absolute Graciosa data directory after `--`.
It checks asset names, all five regions, and independent deep copies of their
height/control/color images and instance dictionaries. It does not save data.
Require zero compatibility failures and no native binding errors in the log.
