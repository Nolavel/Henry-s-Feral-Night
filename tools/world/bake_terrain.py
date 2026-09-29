"""Bakes a 16-bit HFN heightmap source into the LA8 file Godot reads.

Godot loads 16-bit PNG as 8-bit, so the game gets the same heights packed as
an 8-bit grey+alpha PNG: L = high byte, A = low byte.

With no arguments this preserves the historical Graciosa bake exactly:
    PYTHONPATH=tools/world python3 tools/world/bake_terrain.py

Any additional world can use the same pipeline:
    PYTHONPATH=tools/world python3 tools/world/bake_terrain.py \
        --source world/terrain/source/key_west/key_west_height.png \
        --out-png world/terrain/key_west_height_la8.png
"""
import argparse
import hashlib
import json
import os

import numpy as np
from PIL import Image

import heightmap

DEFAULT_OUT_PNG = "world/terrain/graciosa_height_la8.png"


def _default_out_json(out_png):
    return os.path.splitext(out_png)[0] + ".json"


def _source_hash(source):
    return hashlib.sha1(open(source, "rb").read()).hexdigest()


def _parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default=heightmap.DEFAULT_PNG, help="16-bit source PNG")
    parser.add_argument("--meta", default="", help="source metadata JSON; defaults next to --source")
    parser.add_argument("--out-png", default=DEFAULT_OUT_PNG, help="game-readable LA8 output PNG")
    parser.add_argument("--out-json", default="", help="output metadata JSON; defaults next to --out-png")
    return parser.parse_args(argv)


def _ensure_parent(path):
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)


def main(argv=None):
    args = _parse_args(argv)
    source = args.source
    source_meta = args.meta or heightmap.meta_path(source)
    out_png = args.out_png
    out_json = args.out_json or _default_out_json(out_png)

    grey = np.asarray(Image.open(source), dtype=np.uint16)
    if grey.ndim != 2:
        raise ValueError("heightmap source must be a single-channel 16-bit image: %s" % source)

    la = np.stack(
        [(grey >> 8).astype(np.uint8), (grey & 0xFF).astype(np.uint8)], axis=-1
    )
    _ensure_parent(out_png)
    _ensure_parent(out_json)
    Image.fromarray(la, mode="LA").save(out_png, optimize=True)

    with open(source_meta, encoding="utf-8") as handle:
        meta = json.load(handle)
    meta["encoding"] = "LA8: grey16 = L * 256 + A"
    meta["source_sha1"] = _source_hash(source)
    with open(out_json, "w", encoding="utf-8") as handle:
        json.dump(meta, handle, indent=1)

    print(out_png, la.shape, meta["source_sha1"][:10])


if __name__ == "__main__":
    main()
