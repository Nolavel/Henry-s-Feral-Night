# Terrain: the heightmap is the source of truth

Author's decision (2026-09-24): Graciosa's shape lives in a heightmap edited
through Blender. The game will build its own terrain mesh from it and
Terrain3D goes away.

## The file

`world/terrain/source/graciosa_height.png` with `graciosa_height.json` next to
it. Godot does not import this folder (`.gdignore`).

| Property | Value |
|---|---|
| Format | 16-bit greyscale PNG, lossless |
| Size | 4123 × 2836 px, **1 px = 1 m** |
| Pixel → world | `x = origin_x + col`, `z = origin_z + row` (origin −2292, −1532) |
| Grey → height | 0…65535 linear onto **−16…+48 m** (fixed, ~1 mm per step) |
| Sea level | 0 m. The sea bed shelves from the coast: about −1.8 m at 10 m out, −7.6 m at 60 m, −12 m in open water. Terrain3D had a flat 0 m plane there. |
| Axes | Godot: +X east, +Z south. Blender: x = X, y = −Z, z = height. |

The PNG was exported from Terrain3D `terrain_graciosa` with a maximum error of
**0.5 mm**. It weighs 8 MB, against 25 MB for the Terrain3D region files.

## Editing in Blender

Import a region, edit heights, and write back only what changed:

```bash
# whole island, coarse (4 m grid) or a detail window at 1 m
blender --python tools/blender/heightmap_import.py -- world/terrain/source/graciosa_height.png --step 4
blender --python tools/blender/heightmap_import.py -- world/terrain/source/graciosa_height.png \
    --step 1 --window 1000 -1000 1500 -550 --blend first_exit_terrain.blend

# after sculpting / proportional editing / modifiers
blender first_exit_terrain.blend --background --python tools/blender/heightmap_export.py
```

Rules:
- **Edit heights only.** Sculpt, proportional edit or a Displace modifier are
  fine. Adding or deleting vertices is refused, because the grid maps back to
  pixels.
- The export writes a **height difference**, interpolated onto 1 m pixels.
  Pixels the edit did not move stay bit-identical, so a coarse 4 m edit never
  blurs 1 m detail.
- Both scripts also run headless as `bpy` modules. They were verified here:
  a no-edit round trip changes 0 pixels, and a 3 m bump raised exactly its
  20 m radius at the right world position.

Commit the PNG and JSON after every edit, then re-run the tools below.

## Tools that read it

`tools/world/heightmap.py` loads and saves the file (`numpy`, `pillow`). The
island report and the route metrics accept the PNG directly, with no Godot and
no Terrain3D:

```bash
PYTHONPATH=tools/world python3 tools/world/route_metrics.py world/terrain/source/graciosa_height.png \
    data/world/first_exit_layout.json docs/world/first_exit_routes
PYTHONPATH=tools/world python3 tools/world/island_report.py world/terrain/source/graciosa_height.png \
    docs/world/first_exit_area 1300 -900 350
```

Measured on the PNG, the First Exit route lengths match the Terrain3D
measurement to the metre. The coast-exposure band differs by a few metres
because it is now sampled at 1 m instead of 2 m.

## In the game: `IslandTerrain`

Godot reads a 16-bit PNG as 8-bit, which gives 25 cm height steps. The game
therefore reads a baked copy with the same bytes:
`world/terrain/graciosa_height_la8.png`, an 8-bit grey+alpha PNG where
L = high byte and A = low byte. It is imported as a raw `Image`, so no alpha
fix-up touches it. Rebuild it after every edit of the source:

```bash
PYTHONPATH=tools/world python3 tools/world/bake_terrain.py
```

The JSON next to it records the source's SHA-1, so a stale bake is detectable.

`scripts/systems/world/terrain/island_terrain.gd` (`IslandTerrain`) builds the
ground:
- 128 m chunks with three levels of detail: 1 m within 192 m, 4 m within
  768 m, 16 m beyond. Only chunks that rise above −1.5 m are built.
- Skirts on every chunk, so seams between levels never gap.
- `HeightMapShape3D` collision only within about 200 m of the focus (the
  player, or the camera).
- Chunks rebuild a few per frame, so there is no hitch.
- `get_height(x, z)` gives the exact bilinear ground height, the same numbers
  the Python tools use.

Its shader, `shaders/environment/terrain/island_terrain.gdshader`, colours by
height and slope (sand at the tide line, turf on flats, rock on slopes) and
adds the shared settled snow driven by the `snow_cover` global.

`test_island_terrain.gd` checks the exact height at a known pixel, that detail
follows the focus, and that collision under the spawn matches the ground
within 15 cm.

**Stability:**
- With `IslandTerrain` in place of Terrain3D, the full Graciosa scene rendered
  all 7 First Exit shots in **3 of 3 runs** under lavapipe. With Terrain3D it
  crashed every time.
- The light stage with the mesh terrain renders all shots in one process.
- To reproduce: `HFN_FULL_SCENE=1 HFN_TERRAIN=mesh` with
  `tools/runtime/capture_first_exit.gd`.

## Stages

1. **Done:** heightmap as source, Blender round trip, tools on the PNG.
2. **Done:** `IslandTerrain` with chunks, LOD, skirts, collision and shader.
3. **Done:** the main scene runs on `IslandTerrain`.
   - The `NavigationRegion3D` and its Terrain3D child are removed; the nav
     mesh was empty and nothing used it.
   - `IslandTerrain` follows the Player, and the Player starts at the spawner.
   - The blockout builder samples the heightmap, so Blender edits reach the
     greybox on rebuild.
   - Checked: the main scene ran 600 frames without a crash, and full-scene
     captures succeeded in 2 of 2 runs with 7 shots each.
4. **Done:** Terrain3D is removed from `addons/`, `project.godot`, CI and the
   capture tools. Its region data and the dump/export scripts are gone too; git
   history keeps them. The heightmap PNG is the only terrain source.
