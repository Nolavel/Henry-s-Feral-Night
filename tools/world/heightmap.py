"""Graciosa heightmap: the terrain's source of truth, a 16-bit greyscale PNG.

Pixel (col, row) is the height at world (origin_x + col * m_per_px,
origin_z + row * m_per_px); +X east, +Z south (Godot). Grey 0..65535 maps
linearly onto height_min..height_max metres. Metadata sits in a JSON next to
the PNG. Edit in Blender (tools/blender/heightmap_*.py) or any 16-bit editor.
"""
import json
import os

import numpy as np
from PIL import Image

DEFAULT_PNG = "world/terrain/source/graciosa_height.png"
## Fixed range so an edit never rescales the whole file: ~1 mm per step.
HEIGHT_MIN = -16.0
HEIGHT_MAX = 48.0


def meta_path(png_path):
    return os.path.splitext(png_path)[0] + ".json"


def load(png_path=DEFAULT_PNG):
    """Returns (meta, heights) with heights in metres, rows along +Z."""
    meta = json.load(open(meta_path(png_path)))
    grey = np.asarray(Image.open(png_path), dtype=np.float64)
    span = meta["height_max"] - meta["height_min"]
    heights = (grey / 65535.0 * span + meta["height_min"]).astype(np.float32)
    meta = dict(meta, cols=heights.shape[1], rows=heights.shape[0], step_m=meta["m_per_px"])
    return meta, heights


def save(png_path, heights, origin_x, origin_z, m_per_px=1.0, sea_level=0.0, note=""):
    """Writes heights (rows along +Z) and their metadata."""
    span = HEIGHT_MAX - HEIGHT_MIN
    grey = np.clip((heights - HEIGHT_MIN) / span * 65535.0 + 0.5, 0, 65535).astype(np.uint16)
    Image.fromarray(grey, mode="I;16").save(png_path, optimize=True)
    meta = {
        "origin_x": float(origin_x), "origin_z": float(origin_z), "m_per_px": float(m_per_px),
        "height_min": HEIGHT_MIN, "height_max": HEIGHT_MAX, "sea_level": float(sea_level),
        "width": int(heights.shape[1]), "height": int(heights.shape[0]),
        "axes": "col -> +X east, row -> +Z south (Godot); Blender: x = X, y = -Z, z = height",
        "note": note,
    }
    json.dump(meta, open(meta_path(png_path), "w"), indent=1)
    return meta
