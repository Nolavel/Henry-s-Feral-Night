"""Island report: renders height/slope maps and finds buildable flat sites.

Input: the heightmap PNG (world/terrain/source/graciosa_height.png).
Usage: python3 tools/world/island_report.py <png> <out_prefix> [cx cz half_m]
World axes: +X east, +Z south (Godot); maps draw north up.
"""
import json
import math
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

SEA_LEVEL = 0.3
FLAT_SLOPE_DEG = 6.0
SITE_RADIUS_M = 10.0
SITE_SPACING_M = 45.0


def load(source):
    """The heightmap PNG, the source of truth, with First Exit footprints as markers."""
    import heightmap
    meta, h = heightmap.load(source)
    resolved = json.load(open("docs/world/first_exit_resolved.json"))["footprints"]
    meta["markers"] = [{"name": f["id"], "x": f["x"], "z": f["z"]} for f in resolved
                       if f["kind"] not in ("street_lamp", "pickup", "lot") or f.get("is_shelter")]
    return meta, h


def slope_deg(h, step):
    gz, gx = np.gradient(h, step)
    return np.degrees(np.arctan(np.hypot(gx, gz)))


def hillshade(h, step, az=315.0, alt=40.0):
    gz, gx = np.gradient(h, step)
    slope = np.arctan(np.hypot(gx, gz))
    aspect = np.arctan2(-gx, gz)
    az_r, alt_r = math.radians(az), math.radians(alt)
    shade = np.sin(alt_r) * np.cos(slope) + np.cos(alt_r) * np.sin(slope) * np.cos(az_r - aspect)
    return np.clip(shade, 0, 1)


def colour(h):
    """Hypsometric tint: sea, shore, lowland, hills."""
    stops = [(-20, (26, 46, 66)), (0.0, (58, 96, 120)), (SEA_LEVEL, (214, 206, 176)),
             (3, (156, 170, 128)), (10, (120, 140, 100)), (20, (140, 124, 96)), (40, (230, 226, 220))]
    out = np.zeros(h.shape + (3,), dtype=np.float32)
    for (h0, c0), (h1, c1) in zip(stops, stops[1:]):
        m = (h >= h0) & (h < h1)
        t = ((h[m] - h0) / (h1 - h0))[:, None]
        out[m] = np.array(c0) * (1 - t) + np.array(c1) * t
    out[h >= stops[-1][0]] = stops[-1][1]
    return out


def flat_sites(h, slope, step, mask):
    """Greedy pick of cells whose whole disc is flat and dry, spaced apart."""
    r = max(1, int(SITE_RADIUS_M / step))
    from numpy.lib.stride_tricks import sliding_window_view
    pad = np.pad(slope, r, constant_values=90)
    worst = sliding_window_view(pad, (2 * r + 1, 2 * r + 1)).max(axis=(2, 3))
    hpad = np.pad(h, r, constant_values=-20)
    low = sliding_window_view(hpad, (2 * r + 1, 2 * r + 1)).min(axis=(2, 3))
    ok = (worst < FLAT_SLOPE_DEG) & (low > SEA_LEVEL + 0.5) & mask
    ys, xs = np.where(ok)
    order = np.argsort(worst[ys, xs])
    picked = []
    min_cells = SITE_SPACING_M / step
    for i in order:
        y, x = ys[i], xs[i]
        if all((y - py) ** 2 + (x - px) ** 2 >= min_cells ** 2 for py, px in picked):
            picked.append((y, x))
    return [(y, x, float(worst[y, x])) for y, x in picked]


def main():
    dump, out = sys.argv[1], sys.argv[2]
    meta, h = load(dump)
    step, ox, oz = meta["step_m"], meta["origin_x"], meta["origin_z"]
    to_px = lambda x, z: ((x - ox) / step, (z - oz) / step)
    if len(sys.argv) >= 6:
        cx, cz, half = float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
    else:
        land = np.argwhere(h > SEA_LEVEL)
        (y0, x0), (y1, x1) = land.min(0), land.max(0)
        cx, cz = ox + (x0 + x1) / 2 * step, oz + (y0 + y1) / 2 * step
        half = max(x1 - x0, y1 - y0) / 2 * step + 80
    c0, c1 = int((cx - half - ox) / step), int((cx + half - ox) / step)
    r0, r1 = int((cz - half - oz) / step), int((cz + half - oz) / step)
    sub = h[max(r0, 0):r1, max(c0, 0):c1]
    sl = slope_deg(sub, step)
    rgb = colour(sub) * (0.55 + 0.45 * hillshade(sub, step))[..., None]
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8))
    scale = max(1, int(1400 / max(img.size)))
    img = img.resize((img.size[0] * scale, img.size[1] * scale), Image.NEAREST)
    d = ImageDraw.Draw(img)
    font = ImageFont.load_default(size=14)
    k = scale / step
    wx = lambda x: (x - (ox + max(c0, 0) * step)) * k
    wz = lambda z: (z - (oz + max(r0, 0) * step)) * k
    # 5 m contours
    for level in range(5, 45, 5):
        m = (sub[:-1, :] < level) != (sub[1:, :] < level)
        m2 = (sub[:, :-1] < level) != (sub[:, 1:] < level)
        for y, x in np.argwhere(m[:, :-1] | m2[:-1, :]):
            d.point((x * scale, y * scale), fill=(40, 40, 40))
    # grid
    grid = 100 if half < 700 else 250
    for gx in range(int((cx - half) // grid * grid), int(cx + half), grid):
        d.line([(wx(gx), 0), (wx(gx), img.size[1])], fill=(255, 255, 255, 60), width=1)
        d.text((wx(gx) + 3, 3), f"x{gx}", fill=(255, 255, 255), font=font)
    for gz in range(int((cz - half) // grid * grid), int(cz + half), grid):
        d.line([(0, wz(gz)), (img.size[0], wz(gz))], fill=(255, 255, 255, 60), width=1)
        d.text((3, wz(gz) + 3), f"z{gz}", fill=(255, 255, 255), font=font)
    # flat sites
    mask = np.ones_like(sub, dtype=bool)
    sites = flat_sites(sub, sl, step, mask)
    report_sites = []
    for y, x, worst in sites[:60]:
        sx, sz = ox + (max(c0, 0) + x + 0.5) * step, oz + (max(r0, 0) + y + 0.5) * step
        rr = SITE_RADIUS_M * k
        d.ellipse([wx(sx) - rr, wz(sz) - rr, wx(sx) + rr, wz(sz) + rr], outline=(255, 210, 60), width=2)
        report_sites.append({"x": round(sx, 1), "z": round(sz, 1), "h": round(float(sub[y, x]), 2),
                             "max_slope_deg": round(worst, 1)})
    # markers
    for mk in meta["markers"]:
        if abs(mk["x"] - cx) > half or abs(mk["z"] - cz) > half:
            continue
        px, pz = wx(mk["x"]), wz(mk["z"])
        d.ellipse([px - 5, pz - 5, px + 5, pz + 5], fill=(230, 60, 50))
        d.text((px + 8, pz - 8), mk["name"].strip(), fill=(255, 255, 255), font=font, stroke_width=2,
               stroke_fill=(0, 0, 0))
    # scale bar
    bar = 100 * k
    d.rectangle([20, img.size[1] - 30, 20 + bar, img.size[1] - 24], fill=(255, 255, 255))
    d.text((24 + bar, img.size[1] - 36), "100 m", fill=(255, 255, 255), font=font)
    img.save(f"{out}.png")
    land = sub > SEA_LEVEL
    stats = {
        "window": {"cx": cx, "cz": cz, "half_m": half},
        "land_area_m2": float(land.sum() * step * step),
        "height_m": {"max": float(sub.max()), "p50_land": float(np.median(sub[land])) if land.any() else 0},
        "flat_sites": report_sites,
    }
    json.dump(stats, open(f"{out}.json", "w"), indent=1)
    print(f"{out}.png", img.size, len(report_sites), "sites")


if __name__ == "__main__":
    main()
