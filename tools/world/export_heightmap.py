"""One-off: turns the Terrain3D dump into the heightmap source of truth.

Usage: python3 tools/world/export_heightmap.py <dump_dir> [out.png]
Crops to the island plus a sea margin; everything outside is open sea.
"""
import json
import sys

import numpy as np

import heightmap

MARGIN_M = 256
SEA_FLOOR_M = -12.0
## Terrain3D's sea was a flat 0 m plane. A shelf that deepens away from the
## coast gives the sea a bed: about -1.8 m at 10 m out, -7.6 m at 60 m.
SHELF_RANGE_M = 60.0
LAND_M = 0.3


def main():
    dump = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else heightmap.DEFAULT_PNG
    meta = json.load(open(f"{dump}/meta.json"))
    h = np.fromfile(f"{dump}/heights.f32", dtype=np.float32).reshape(meta["rows"], meta["cols"])
    step = meta["step_m"]
    h = np.where(h <= -19.9, SEA_FLOOR_M, h)
    from scipy.ndimage import distance_transform_edt
    land = h > LAND_M
    offshore = distance_transform_edt(~land) * step
    shelf = -(-SEA_FLOOR_M) * (1.0 - np.exp(-offshore / SHELF_RANGE_M))
    h = np.where(land, h, np.minimum(h, shelf)).astype(np.float32)
    land = np.argwhere(h > 0.0)
    (r0, c0), (r1, c1) = land.min(0), land.max(0)
    pad = int(MARGIN_M / step)
    r0, c0 = max(r0 - pad, 0), max(c0 - pad, 0)
    r1, c1 = min(r1 + pad, h.shape[0] - 1), min(c1 + pad, h.shape[1] - 1)
    crop = h[r0:r1 + 1, c0:c1 + 1]
    origin_x = meta["origin_x"] + c0 * step
    origin_z = meta["origin_z"] + r0 * step
    written = heightmap.save(out, crop, origin_x, origin_z, step,
                             note="Exported from Terrain3D 'terrain_graciosa', 2026-09-24.")
    print(out, written["width"], "x", written["height"], "origin", origin_x, origin_z)


if __name__ == "__main__":
    main()
