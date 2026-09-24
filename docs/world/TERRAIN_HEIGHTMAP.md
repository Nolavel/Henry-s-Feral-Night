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
| Size | 4128 × 2866 px, **1 px = 1 m** |
| Pixel → world | `x = origin_x + col`, `z = origin_z + row` (origin −2296, −1545) |
| Grey → height | 0…65535 linear onto **−16…+48 m** (fixed, ~1 mm per step) |
| Sea level | 0 m. Open sea outside the island is −12 m. |
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

## Stages

1. **Done:** heightmap as source, Blender round trip, tools on the PNG.
2. Generator: chunked terrain meshes (64 m tiles, 2–3 LODs), `HeightMapShape3D`
   collision, one terrain shader (slope/height colour + global snow).
3. Side by side with Terrain3D in the First Exit sector: renders, route metrics,
   navigation, ice and footprints must match.
4. Remove Terrain3D from the scene, CI (`setup_env.sh` download) and
   `addons/`. The blockout builder and `capture_first_exit.gd` sample the
   heightmap instead of Terrain3D.

Until stage 4, Terrain3D still renders the island in game. Edits to the PNG
only reach the game once stage 2 lands.
