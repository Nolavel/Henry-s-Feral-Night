# World profiles

Issue #138 adds real-world Key West as an **additional experimental dataset**.
The current Graciosa world remains the default and nothing in First Exit is
moved or deleted while the prototype is evaluated.

## Stage 0 contract

- `WorldProfile` is data only: terrain paths, streaming data path and provenance.
- `WorldProfileCatalog` provides one central lookup and reserves `HFN_WORLD` as
  the developer selector. Runtime switching is not enabled until the selected
  profile has real terrain/world data.
- `graciosa.tres` points at the exact files used before #138.
- `key_west_test.tres` is deliberately incomplete until the NOAA import exists.
- `IslandTerrain` now exposes image/meta paths but defaults to the same Graciosa
  files, so the main scene behaves exactly as before.
- `bake_terrain.py` accepts source/output arguments while its zero-argument
  invocation still bakes Graciosa.

## Order of work

1. Preserve the NOAA source/provenance and build a reproducible converter.
2. Produce a Key West + Fleming/Wisteria/Sunset/Stock Island heightmap.
3. View and measure the untouched NOAA-derived terrain in Godot.
4. Add lightweight road/building massing, using MultiMesh/chunking where useful.
5. Only after the Godot review decide whether Blender-authored height deltas are
   needed. Blender must not replace the NOAA base as the source of truth.
