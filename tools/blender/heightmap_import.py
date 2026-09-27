"""Builds an editable grid mesh from the Graciosa heightmap.

blender --python tools/blender/heightmap_import.py -- <png> [--step 4] \
    [--window x0 z0 x1 z1] [--blend out.blend]

World X east -> Blender X, world Z south -> Blender -Y, height -> Blender Z.
The object remembers where it came from; heightmap_export.py writes it back.
Whole island: keep --step 4 or more. Detail work: a --window at --step 1.
"""
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import heightmap_common as hc  # noqa: E402

OBJECT_NAME = "Heightmap"


def main():
    args = hc.script_args()
    png = args[0]
    step = int(args[args.index("--step") + 1]) if "--step" in args else 4
    meta = hc.load_meta(png)
    heights = hc.to_metres(hc.read_png16(png), meta)
    m = meta["m_per_px"]
    col0, row0, col1, row1 = 0, 0, heights.shape[1] - 1, heights.shape[0] - 1
    if "--window" in args:
        i = args.index("--window")
        x0, z0, x1, z1 = (float(v) for v in args[i + 1:i + 5])
        col0 = max(0, int((min(x0, x1) - meta["origin_x"]) / m))
        col1 = min(heights.shape[1] - 1, int((max(x0, x1) - meta["origin_x"]) / m))
        row0 = max(0, int((min(z0, z1) - meta["origin_z"]) / m))
        row1 = min(heights.shape[0] - 1, int((max(z0, z1) - meta["origin_z"]) / m))
    cols = np.arange(col0, col1 + 1, step)
    rows = np.arange(row0, row1 + 1, step)
    grid = heights[np.ix_(rows, cols)]
    nr, nc = grid.shape
    xs = meta["origin_x"] + cols * m
    zs = meta["origin_z"] + rows * m
    X, Z = np.meshgrid(xs, zs)
    co = np.stack([X, -Z, grid], axis=-1).reshape(-1).astype(np.float32)
    idx = np.arange(nr * nc).reshape(nr, nc)
    quads = np.stack([idx[:-1, :-1], idx[1:, :-1], idx[1:, 1:], idx[:-1, 1:]], axis=-1).reshape(-1)
    mesh = bpy.data.meshes.new(OBJECT_NAME)
    mesh.vertices.add(nr * nc)
    mesh.vertices.foreach_set("co", co)
    n_faces = (nr - 1) * (nc - 1)
    mesh.loops.add(n_faces * 4)
    mesh.loops.foreach_set("vertex_index", quads.astype(np.int32))
    mesh.polygons.add(n_faces)
    mesh.polygons.foreach_set("loop_start", np.arange(0, n_faces * 4, 4, dtype=np.int32))
    mesh.polygons.foreach_set("loop_total", np.full(n_faces, 4, dtype=np.int32))
    mesh.update(calc_edges=True)
    mesh.validate()
    obj = bpy.data.objects.new(OBJECT_NAME, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for key, value in {"hm_col0": int(col0), "hm_row0": int(row0), "hm_cols": int(nc), "hm_rows": int(nr),
                       "hm_step": int(step), "hm_png": os.path.abspath(png)}.items():
        obj[key] = value
    print(f"heightmap import: {nc}x{nr} vertices at {step * m} m, window cols {col0}..{col1} rows {row0}..{row1}")
    if "--blend" in args:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(args[args.index("--blend") + 1]))


main()
