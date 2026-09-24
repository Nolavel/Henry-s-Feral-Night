"""Shared by the Blender heightmap scripts: metadata, 16-bit PNG I/O.

Reading goes through Blender's image loader (any PNG filter); writing is a
plain 16-bit greyscale PNG so no colour management can touch the values.
"""
import json
import os
import struct
import sys
import zlib

import bpy
import numpy as np


def script_args():
    """Arguments after '--', for `blender --python x.py -- a b` and bpy-as-module."""
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def load_meta(png_path):
    return json.load(open(os.path.splitext(png_path)[0] + ".json"))


def read_png16(png_path):
    """Grey levels 0..65535 as float64, row 0 = top of the file (north)."""
    image = bpy.data.images.load(os.path.abspath(png_path), check_existing=False)
    image.colorspace_settings.name = "Non-Color"
    w, h = image.size
    pixels = np.empty(w * h * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    grey = pixels.reshape(h, w, 4)[::-1, :, 0].astype(np.float64)
    return np.round(grey * 65535.0)


def write_png16(png_path, grey):
    """Writes uint16 grey levels as a 16-bit greyscale PNG."""
    grey = np.clip(np.round(grey), 0, 65535).astype(">u2")
    h, w = grey.shape
    raw = b"".join(b"\x00" + grey[r].tobytes() for r in range(h))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    with open(png_path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 16, 0, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def to_metres(grey, meta):
    return grey / 65535.0 * (meta["height_max"] - meta["height_min"]) + meta["height_min"]


def to_grey(metres, meta):
    return (metres - meta["height_min"]) / (meta["height_max"] - meta["height_min"]) * 65535.0
