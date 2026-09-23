#!/usr/bin/env python3
"""Generate HFN's weak 33^3 Cold Ash display LUTs without external packages.

The PNG layout is 33 horizontal blue slices. Inside every slice, red runs
left-to-right and green runs top-to-bottom, matching Godot's Texture3D
importer when ``slices/horizontal`` is set to 33.
"""

from __future__ import annotations

import argparse
import binascii
import math
from pathlib import Path
import struct
import zlib


LUT_SIZE = 33
OUTPUT_WIDTH = LUT_SIZE * LUT_SIZE
OUTPUT_HEIGHT = LUT_SIZE
ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = ROOT / "assets" / "textures" / "color_grading"


def clamp(value: float) -> float:
    return min(1.0, max(0.0, value))


def luma(rgb: tuple[float, float, float]) -> float:
    red, green, blue = rgb
    return red * 0.2126 + green * 0.7152 + blue * 0.0722


def saturate(rgb: tuple[float, float, float], amount: float) -> tuple[float, float, float]:
    gray = luma(rgb)
    return tuple(gray + (channel - gray) * amount for channel in rgb)


def lifted_gamma(channel: float, lift: float, gamma: float) -> float:
    # Both endpoints stay intentional: black is lifted, white remains white.
    return lift * (1.0 - channel) + math.pow(channel, gamma)


def cold_ash_night(rgb: tuple[float, float, float]) -> tuple[float, float, float]:
    """Street/night grade: darker mids, lifted blacks, restrained cold shadows."""
    source_red, _, source_blue = rgb
    gray = luma(rgb)
    graded = saturate(rgb, 0.90)
    graded = tuple(lifted_gamma(channel, 0.012, 1.11) for channel in graded)

    shadow = math.pow(1.0 - gray, 1.75)
    warm_source = clamp((source_red - source_blue) * 2.2)
    warm_highlight = warm_source * math.pow(gray, 1.35)
    tint = (
        -0.0035 * shadow + 0.0060 * warm_highlight,
        0.0010 * shadow + 0.0020 * warm_highlight,
        0.0045 * shadow - 0.0020 * warm_highlight,
    )
    return tuple(clamp(channel + tint[index]) for index, channel in enumerate(graded))


def cold_ash_shelter(rgb: tuple[float, float, float]) -> tuple[float, float, float]:
    """Shelter grade: warm dark/mid interior values, cool bright openings."""
    source_red, _, source_blue = rgb
    gray = luma(rgb)
    graded = saturate(rgb, 0.92)
    graded = tuple(lifted_gamma(channel, 0.015, 1.035) for channel in graded)

    interior = math.pow(1.0 - gray, 1.35)
    exterior_highlight = math.pow(gray, 2.0)
    warm_source = clamp((source_red - source_blue) * 2.0)
    warm_retention = warm_source * math.pow(gray, 1.15)
    tint = (
        0.0100 * interior - 0.0020 * exterior_highlight + 0.0030 * warm_retention,
        0.0035 * interior + 0.0005 * exterior_highlight + 0.0010 * warm_retention,
        -0.0065 * interior + 0.0040 * exterior_highlight - 0.0015 * warm_retention,
    )
    return tuple(clamp(channel + tint[index]) for index, channel in enumerate(graded))


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    checksum = binascii.crc32(kind)
    checksum = binascii.crc32(payload, checksum) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", checksum)


def encode_png(rows: list[bytes]) -> bytes:
    raw = b"".join(b"\x00" + row for row in rows)
    header = struct.pack(">IIBBBBB", OUTPUT_WIDTH, OUTPUT_HEIGHT, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", zlib.compress(raw, level=9))
        + png_chunk(b"IEND", b"")
    )


def build_lut(transform) -> bytes:
    rows: list[bytes] = []
    maximum = LUT_SIZE - 1
    for green_index in range(LUT_SIZE):
        row = bytearray()
        green = green_index / maximum
        for blue_index in range(LUT_SIZE):
            blue = blue_index / maximum
            for red_index in range(LUT_SIZE):
                red = red_index / maximum
                graded = transform((red, green, blue))
                row.extend(round(channel * 255.0) for channel in graded)
        rows.append(bytes(row))
    return encode_png(rows)


def write_or_check(path: Path, payload: bytes, check_only: bool) -> bool:
    if check_only:
        return path.is_file() and path.read_bytes() == payload
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="verify committed LUT bytes")
    args = parser.parse_args()

    outputs = {
        OUTPUT_DIR / "HFN_ColdAsh_Night.png": build_lut(cold_ash_night),
        OUTPUT_DIR / "HFN_ColdAsh_Shelter.png": build_lut(cold_ash_shelter),
    }
    valid = True
    for path, payload in outputs.items():
        matches = write_or_check(path, payload, args.check)
        valid = valid and matches
        verb = "verified" if matches and args.check else "wrote" if matches else "mismatch"
        print(f"{verb}: {path.relative_to(ROOT)} ({OUTPUT_WIDTH}x{OUTPUT_HEIGHT})")
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
