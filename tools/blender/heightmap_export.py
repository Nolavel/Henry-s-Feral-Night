"""Writes an edited Heightmap object back into the heightmap PNG.

blender edited.blend --python tools/blender/heightmap_export.py -- [<png>] [--object Heightmap]

Only what changed is written: the edit is taken as a height difference on
the grid, interpolated onto 1 m pixels and added, so untouched 1 m detail
survives a coarse edit. Modifiers and sculpting are applied first.
"""
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import heightmap_common as hc  # noqa: E402


def main():
    args = hc.script_args()
    name = args[args.index("--object") + 1] if "--object" in args else "Heightmap"
    obj = bpy.data.objects[name]
    png = args[0] if args and not args[0].startswith("--") else obj["hm_png"]
    meta = hc.load_meta(png)
    grey = hc.read_png16(png)
    heights = hc.to_metres(grey, meta)
    col0, row0 = obj["hm_col0"], obj["hm_row0"]
    nc, nr, step = obj["hm_cols"], obj["hm_rows"], obj["hm_step"]
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph).to_mesh()
    if len(evaluated.vertices) != nr * nc:
        raise SystemExit("heightmap export: topology changed; edit heights only (sculpt, proportional edit, modifiers).")
    co = np.empty(len(evaluated.vertices) * 3, dtype=np.float32)
    evaluated.vertices.foreach_get("co", co)
    world = np.asarray(obj.matrix_world)
    pts = co.reshape(-1, 3) @ world[:3, :3].T + world[:3, 3]
    edited = pts[:, 2].reshape(nr, nc)
    rows = row0 + np.arange(nr) * step
    cols = col0 + np.arange(nc) * step
    delta = edited - heights[np.ix_(rows, cols)]
    ## Bilinear delta onto every pixel the grid covers.
    fine_r = np.arange(rows[0], rows[-1] + 1)
    fine_c = np.arange(cols[0], cols[-1] + 1)
    ri = np.clip((fine_r - rows[0]) / step, 0, nr - 1)
    ci = np.clip((fine_c - cols[0]) / step, 0, nc - 1)
    r0 = np.minimum(np.floor(ri).astype(int), max(nr - 2, 0))
    c0 = np.minimum(np.floor(ci).astype(int), max(nc - 2, 0))
    tr = (ri - r0)[:, None]
    tc = (ci - c0)[None, :]
    r1 = np.minimum(r0 + 1, nr - 1)
    c1 = np.minimum(c0 + 1, nc - 1)
    d = (delta[np.ix_(r0, c0)] * (1 - tr) * (1 - tc) + delta[np.ix_(r1, c0)] * tr * (1 - tc)
         + delta[np.ix_(r0, c1)] * (1 - tr) * tc + delta[np.ix_(r1, c1)] * tr * tc)
    changed = np.abs(d) > 0.0005
    region = heights[fine_r[0]:fine_r[-1] + 1, fine_c[0]:fine_c[-1] + 1]
    region[changed] += d[changed]
    heights[fine_r[0]:fine_r[-1] + 1, fine_c[0]:fine_c[-1] + 1] = region
    hc.write_png16(png, hc.to_grey(heights, meta))
    print(f"heightmap export: {int(changed.sum())} pixels changed, max |delta| {np.abs(delta).max():.3f} m -> {png}")


main()
