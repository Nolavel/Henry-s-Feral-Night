"""Bakes the heightmap source into the file the game reads.

Godot loads 16-bit PNG as 8-bit (25 cm steps), so the game gets the same
heights packed as an 8-bit grey+alpha PNG: L = high byte, A = low byte.
Usage: PYTHONPATH=tools/world python3 tools/world/bake_terrain.py
"""
import hashlib
import json
import shutil

import numpy as np
from PIL import Image

import heightmap

SOURCE = heightmap.DEFAULT_PNG
OUT_PNG = "world/terrain/graciosa_height_la8.png"
OUT_JSON = "world/terrain/graciosa_height_la8.json"


def source_hash():
    return hashlib.sha1(open(SOURCE, "rb").read()).hexdigest()


def main():
    grey = np.asarray(Image.open(SOURCE), dtype=np.uint16)
    la = np.stack([(grey >> 8).astype(np.uint8), (grey & 0xFF).astype(np.uint8)], axis=-1)
    Image.fromarray(la, mode="LA").save(OUT_PNG, optimize=True)
    meta = json.load(open(heightmap.meta_path(SOURCE)))
    meta["encoding"] = "LA8: grey16 = L * 256 + A"
    meta["source_sha1"] = source_hash()
    json.dump(meta, open(OUT_JSON, "w"), indent=1)
    print(OUT_PNG, la.shape, meta["source_sha1"][:10])


if __name__ == "__main__":
    main()
