"""Measures First Exit routes on the real heightfield and draws the layout.

Usage: python3 tools/world/route_metrics.py <dump_dir> <layout.json> <out_prefix>
Per route: length, share over sea (ice), time at walk speeds, steepest grade,
share within 25 m of the coast (wind exposure). Also checks the landmark is
visible from the spawn eye.
"""
import json
import math
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

SEA = 0.3
EYE_M = 1.6
WALK_SPEEDS = {"current_walk": 4.0, "proposed_walk": 2.0}
COAST_BAND_M = 25.0
ROUTE_COLOURS = {"shore": (80, 200, 255), "ruins": (255, 170, 60), "ice": (235, 235, 255)}


def main():
    dump, layout_path, out = sys.argv[1:4]
    meta = json.load(open(f"{dump}/meta.json"))
    h = np.fromfile(f"{dump}/heights.f32", dtype=np.float32).reshape(meta["rows"], meta["cols"])
    step, ox, oz = meta["step_m"], meta["origin_x"], meta["origin_z"]
    layout = json.load(open(layout_path))
    if "--with-proposals" in sys.argv:
        h = _apply_proposals(h, meta, layout)

    def height(x, z):
        c, r = int((x - ox) / step), int((z - oz) / step)
        return float(h[r, c])

    from scipy.ndimage import distance_transform_edt
    land = h > SEA
    coast_dist = distance_transform_edt(land) * step

    def near_coast(x, z):
        c, r = int((x - ox) / step), int((z - oz) / step)
        return coast_dist[r, c] < COAST_BAND_M and land[r, c]

    report = {"routes": [], "landmarks": []}
    for route in layout["routes"]:
        pts = route["points"]
        length = sea = coast = 0.0
        steepest = 0.0
        for (x0, z0), (x1, z1) in zip(pts, pts[1:]):
            seg = math.hypot(x1 - x0, z1 - z0)
            n = max(2, int(seg / step))
            prev = None
            for i in range(n + 1):
                t = i / n
                x, z = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
                y = height(x, z)
                ds = seg / n
                if i > 0:
                    length += ds
                    if y <= SEA:
                        sea += ds
                    elif near_coast(x, z):
                        coast += ds
                    if prev is not None and y > SEA and prev > SEA:
                        steepest = max(steepest, math.degrees(math.atan(abs(y - prev) / ds)))
                prev = y
        entry = {"id": route["id"], "label": route["label"], "length_m": round(length),
                 "over_sea_m": round(sea), "coast_band_m": round(coast),
                 "steepest_deg": round(steepest, 1)}
        for name, speed in WALK_SPEEDS.items():
            entry[f"minutes_{name}"] = round(length / speed / 60.0, 1)
        report["routes"].append(entry)

    spawn = layout["spawn"]
    sy = height(spawn["x"], spawn["z"]) + EYE_M
    for s in layout["structures"]:
        if s["kind"] not in ("water_tower", "chapel", "house_bungalow", "bunker_portal"):
            continue
        top = height(s["x"], s["z"]) + s["size"][2]
        dist = math.hypot(s["x"] - spawn["x"], s["z"] - spawn["z"])
        n = int(dist / step)
        blocked = False
        for i in range(1, n):
            t = i / n
            x, z = spawn["x"] + (s["x"] - spawn["x"]) * t, spawn["z"] + (s["z"] - spawn["z"]) * t
            if height(x, z) > sy + (top - sy) * t:
                blocked = True
                break
        report["landmarks"].append({"id": s["id"], "distance_m": round(dist), "visible_from_spawn": not blocked})

    json.dump(report, open(f"{out}.json", "w"), indent=1)
    _draw(h, meta, layout, report, out)
    for r in report["routes"]:
        print(r)
    for l in report["landmarks"]:
        print(l)


def _apply_proposals(h, meta, layout):
    """Carves proposed lagoons into a copy of the heightfield, for measuring only."""
    from matplotlib.path import Path
    step, ox, oz = meta["step_m"], meta["origin_x"], meta["origin_z"]
    h = h.copy()
    for prop in layout.get("terrain_proposals", []):
        poly = prop["polygon"]
        xs, zs = [p[0] for p in poly], [p[1] for p in poly]
        c0, c1 = int((min(xs) - ox) / step), int((max(xs) - ox) / step) + 1
        r0, r1 = int((min(zs) - oz) / step), int((max(zs) - oz) / step) + 1
        cc, rr = np.meshgrid(np.arange(c0, c1), np.arange(r0, r1))
        pts = np.stack([ox + (cc.ravel() + 0.5) * step, oz + (rr.ravel() + 0.5) * step], 1)
        inside = Path(poly).contains_points(pts).reshape(cc.shape)
        h[r0:r1, c0:c1][inside] = prop["depth_m"]
    return h


def _draw(h, meta, layout, report, out):
    step, ox, oz = meta["step_m"], meta["origin_x"], meta["origin_z"]
    xs = [p[0] for r in layout["routes"] for p in r["points"]] + [s["x"] for s in layout["structures"]]
    zs = [p[1] for r in layout["routes"] for p in r["points"]] + [s["z"] for s in layout["structures"]]
    pad = 60
    x0, x1, z0, z1 = min(xs) - pad, max(xs) + pad, min(zs) - pad, max(zs) + pad
    c0, c1, r0, r1 = int((x0 - ox) / step), int((x1 - ox) / step), int((z0 - oz) / step), int((z1 - oz) / step)
    sub = h[r0:r1, c0:c1]
    base = np.where(sub > SEA, 150 + np.clip(sub, 0, 40) * 2.5, 60).astype(np.uint8)
    rgb = np.stack([base * 0.8, base * 0.85, base * 0.8 + (sub <= SEA) * 60], -1).clip(0, 255).astype(np.uint8)
    img = Image.fromarray(rgb)
    k = max(1, int(1400 / max(img.size)))
    img = img.resize((img.size[0] * k, img.size[1] * k), Image.NEAREST)
    d = ImageDraw.Draw(img)
    font = ImageFont.load_default(size=15)
    px = lambda x, z: ((x - x0) / step * k, (z - z0) / step * k)
    for prop in layout.get("terrain_proposals", []):
        d.polygon([px(*p) for p in prop["polygon"]], outline=(120, 200, 255))
        d.text(px(*prop["polygon"][0]), prop["id"] + " (proposal)", fill=(120, 200, 255), font=font,
               stroke_width=2, stroke_fill=(0, 0, 0))
    for r in layout["routes"]:
        d.line([px(*p) for p in r["points"]], fill=ROUTE_COLOURS.get(r["id"], (255, 255, 255)), width=4)
    for row in layout["palm_rows"]:
        (ax, az), (bx, bz) = row["from"], row["to"]
        n = max(1, int(math.hypot(bx - ax, bz - az) / row["spacing"]))
        for i in range(n + 1):
            x, z = ax + (bx - ax) * i / n, az + (bz - az) * i / n
            cx, cz = px(x, z)
            d.ellipse([cx - 3, cz - 3, cx + 3, cz + 3], fill=(70, 120, 70))
    for s in layout["structures"]:
        w, dp = s["size"][0], s["size"][1]
        yaw = math.radians(s.get("yaw_deg", 0))
        corners = []
        for sx, sz in ((-w / 2, -dp / 2), (w / 2, -dp / 2), (w / 2, dp / 2), (-w / 2, dp / 2)):
            corners.append(px(s["x"] + sx * math.cos(yaw) + sz * math.sin(yaw),
                              s["z"] - sx * math.sin(yaw) + sz * math.cos(yaw)))
        d.polygon(corners, fill=(60, 60, 60), outline=(255, 255, 255))
        cx, cz = px(s["x"], s["z"])
        d.text((cx + 8, cz - 8), s["id"], fill=(255, 255, 255), font=font, stroke_width=2, stroke_fill=(0, 0, 0))
    sp = px(layout["spawn"]["x"], layout["spawn"]["z"])
    d.ellipse([sp[0] - 7, sp[1] - 7, sp[0] + 7, sp[1] + 7], fill=(230, 60, 50))
    y = 10
    for r in report["routes"]:
        text = (f"{r['id']}: {r['length_m']} m, {r['minutes_current_walk']} min @4 m/s, "
                f"{r['minutes_proposed_walk']} min @2 m/s, ice {r['over_sea_m']} m, coast {r['coast_band_m']} m")
        d.text((10, y), text, fill=ROUTE_COLOURS.get(r["id"], (255, 255, 255)), font=font, stroke_width=2,
               stroke_fill=(0, 0, 0))
        y += 20
    bar = 100 / step * k
    d.rectangle([10, img.size[1] - 24, 10 + bar, img.size[1] - 18], fill=(255, 255, 255))
    d.text((16 + bar, img.size[1] - 30), "100 m", fill=(255, 255, 255), font=font)
    img.save(f"{out}.png")


if __name__ == "__main__":
    main()
