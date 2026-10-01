#!/usr/bin/env python3
"""Generate tileable brush-stroke masks that break up Hoarbound's stylized shadows.

Placeholders with the right structure until an artist bakes a mask (Blender Studio
Brushstroke Tools) or paints one (David Revoy's CC0 Krita brushes). Strokes are
stamped on a torus, so the result tiles. Deterministic: same seed, same bytes.

Writes assets/textures/shadows/shadow_brush_<style>.png (8-bit grey, 1024 px = 1.5 m).
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets" / "textures" / "shadows"
SIZE = 1024

## Stroke families in pixels at 1024 px per 1.5 m: one tile = 1.5 m of surface.
STYLES = {
    "dry": {
        "seed": 4211, "count": 620, "length": (120, 260), "width": (10, 22),
        "angle": 35.0, "angle_jitter": 12.0, "bend": 0.0012, "bristles": 9,
        "bristle_contrast": 0.75, "dry_end": 0.65, "edge_rough": 0.18, "value": (0.75, 1.0),
    },
    "flat": {
        "seed": 9127, "count": 140, "length": (180, 340), "width": (28, 48),
        "angle": 35.0, "angle_jitter": 14.0, "bend": 0.0006, "bristles": 6,
        "bristle_contrast": 0.3, "dry_end": 0.85, "edge_rough": 0.12, "value": (0.75, 1.0),
    },
}


def smoothstep(a: float, b: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def value_noise_1d(rng: np.random.Generator, x: np.ndarray, cells: int) -> np.ndarray:
    """Smooth 1D noise on [0, 1] with `cells` random knots."""
    knots = rng.random(cells + 2)
    f = np.clip(x, 0.0, 1.0) * cells
    i = np.floor(f).astype(int)
    t = f - i
    t = t * t * (3.0 - 2.0 * t)
    return knots[i] * (1.0 - t) + knots[i + 1] * t


def stamp(canvas: np.ndarray, rng: np.random.Generator, style: dict) -> None:
    length = rng.uniform(*style["length"])
    width = rng.uniform(*style["width"])
    angle = math.radians(style["angle"] + rng.normal(0.0, style["angle_jitter"]))
    bend = rng.normal(0.0, style["bend"])
    value = rng.uniform(*style["value"])
    cx, cy = rng.uniform(0, SIZE, 2)
    reach = int(length * 0.5 + width) + 2
    ys, xs = np.mgrid[-reach:reach + 1, -reach:reach + 1].astype(float)
    ca, sa = math.cos(angle), math.sin(angle)
    u = xs * ca + ys * sa                     # along the stroke
    w = -xs * sa + ys * ca - bend * u * u     # across, bent into an arc
    along = (u + length * 0.5) / length       # 0 at the start, 1 at the end
    pressure = smoothstep(0.0, 0.12, along) * smoothstep(1.0, 0.8, along)
    half = width * 0.5 * (0.55 + 0.45 * pressure)
    rough = (value_noise_1d(rng, along, 12) - 0.5) * style["edge_rough"] * width
    inside = smoothstep(1.5, -1.5, np.abs(w) - half - rough) * (along >= 0) * (along <= 1)
    across = np.clip((w / np.maximum(half, 1.0) + 1.0) * 0.5, 0.0, 1.0)
    bristle = value_noise_1d(rng, across, style["bristles"] * 3)
    bristle = 1.0 - style["bristle_contrast"] * (1.0 - bristle)
    ## Dry brush: paint runs out towards the end, bristle streaks break first.
    streak = value_noise_1d(rng, across, style["bristles"] * 5)
    dry = smoothstep(style["dry_end"] - 0.25, 1.0, along)
    breakup = smoothstep(dry - 0.1, dry + 0.1, streak * 0.8 + value_noise_1d(rng, along, 20) * 0.2)
    alpha = inside * bristle * np.where(dry > 0.0, breakup, 1.0)
    rows = (np.arange(-reach, reach + 1) + int(cy)) % SIZE
    cols = (np.arange(-reach, reach + 1) + int(cx)) % SIZE
    patch = canvas[np.ix_(rows, cols)]
    canvas[np.ix_(rows, cols)] = patch * (1.0 - alpha) + value * alpha


def generate(name: str) -> Path:
    style = STYLES[name]
    rng = np.random.default_rng(style["seed"])
    canvas = np.zeros((SIZE, SIZE))
    for _ in range(style["count"]):
        stamp(canvas, rng, style)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / f"shadow_brush_{name}.png"
    Image.fromarray(np.clip(canvas * 255.0 + 0.5, 0, 255).astype(np.uint8), "L").save(path, optimize=True)
    painted = (canvas > 0.35).mean()
    print(f"{path.relative_to(ROOT)}: painted {painted:.0%}, mean {canvas.mean():.2f}")
    return path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("styles", nargs="*", default=sorted(STYLES))
    for name in parser.parse_args().styles:
        generate(name)


if __name__ == "__main__":
    main()
