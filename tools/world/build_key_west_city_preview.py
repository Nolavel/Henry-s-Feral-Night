#!/usr/bin/env python3
"""Builds lightweight Key West city massing data from OpenStreetMap.

This is a preview-only companion to issue #138:
- ways tagged building -> one oriented box per footprint;
- ways tagged highway -> terrain-draped road polylines in Godot;
- WGS84 coordinates are transformed into the exact NOAA UTM 17N frame used
  by build_key_west_preview.sh, then into the centred HFN metre frame.

OpenStreetMap data is ODbL. Derived preview metadata carries attribution and
must not be treated as authored HFN source geometry.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

from pyproj import Transformer

DEFAULT_REPORT = Path("docs/runtime_previews/key_west/source_report.json")
DEFAULT_OUTPUT = Path("docs/runtime_previews/key_west/city_preview.json")
OVERPASS = "https://overpass-api.de/api/interpreter"

ROAD_WIDTHS = {
    "motorway": 12.0,
    "trunk": 11.0,
    "primary": 9.0,
    "secondary": 8.0,
    "tertiary": 7.0,
    "residential": 5.5,
    "living_street": 5.0,
    "unclassified": 5.0,
    "service": 3.5,
}
SKIP_HIGHWAYS = {
    "footway", "path", "cycleway", "steps", "pedestrian", "track", "bridleway",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUTPUT)
    return parser.parse_args()


def fetch_overpass(south: float, west: float, north: float, east: float) -> dict:
    bbox = f"{south},{west},{north},{east}"
    query = f"""[out:json][timeout:120];
(
  way["building"]({bbox});
  way["highway"]({bbox});
);
out geom;"""
    body = urllib.parse.urlencode({"data": query}).encode("utf-8")
    request = urllib.request.Request(
        OVERPASS,
        data=body,
        headers={"User-Agent": "HFN-RIMEWATCH-KeyWest-Preview/1.0"},
        method="POST",
    )
    last_error: Exception | None = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                return json.loads(response.read().decode("utf-8"))
        except Exception as exc:
            last_error = exc
            if attempt < 2:
                time.sleep(4.0 * (attempt + 1))
    raise RuntimeError(f"Overpass download failed after retries: {last_error}")


def local_projector(report: dict):
    gt = report["source_geotransform"]
    step = float(report["preview_resolution_m"])
    width = int(report["width"])
    height = int(report["height"])
    span_x = (width - 1) * step
    span_z = (height - 1) * step
    centre_e = float(gt[0]) + span_x * 0.5
    centre_n = float(gt[3]) - span_z * 0.5
    transformer = Transformer.from_crs("EPSG:4326", "EPSG:32617", always_xy=True)

    def project(lon: float, lat: float) -> tuple[float, float]:
        east, north = transformer.transform(lon, lat)
        return float(east - centre_e), float(centre_n - north)

    return project


def numeric_prefix(value: str) -> float | None:
    match = re.search(r"-?\d+(?:\.\d+)?", value or "")
    return float(match.group(0)) if match else None


def building_height(tags: dict, footprint_area: float) -> float:
    explicit = numeric_prefix(tags.get("height", ""))
    if explicit is not None and 2.2 <= explicit <= 120.0:
        return explicit
    levels = numeric_prefix(tags.get("building:levels", ""))
    if levels is not None and 1.0 <= levels <= 40.0:
        return max(3.2, levels * 3.0)

    kind = tags.get("building", "")
    if kind in {"hotel", "apartments", "office", "commercial"}:
        return 9.0
    if kind in {"industrial", "warehouse", "retail"}:
        return 6.5
    if footprint_area > 1200.0:
        return 8.0
    if footprint_area > 450.0:
        return 5.5
    return 3.6


def oriented_box(points: list[tuple[float, float]], tags: dict) -> dict | None:
    if len(points) < 3:
        return None
    # Ignore the duplicated closing vertex for covariance.
    if len(points) > 3 and points[0] == points[-1]:
        points = points[:-1]
    if len(points) < 3:
        return None

    cx = sum(p[0] for p in points) / len(points)
    cz = sum(p[1] for p in points) / len(points)
    sxx = sxz = szz = 0.0
    for x, z in points:
        dx = x - cx
        dz = z - cz
        sxx += dx * dx
        sxz += dx * dz
        szz += dz * dz
    angle = 0.5 * math.atan2(2.0 * sxz, sxx - szz)
    ux, uz = math.cos(angle), math.sin(angle)
    vx, vz = -uz, ux

    pu = [(x - cx) * ux + (z - cz) * uz for x, z in points]
    pv = [(x - cx) * vx + (z - cz) * vz for x, z in points]
    min_u, max_u = min(pu), max(pu)
    min_v, max_v = min(pv), max(pv)
    width = max(2.5, max_u - min_u)
    depth = max(2.5, max_v - min_v)
    centre_u = (min_u + max_u) * 0.5
    centre_v = (min_v + max_v) * 0.5
    x = cx + centre_u * ux + centre_v * vx
    z = cz + centre_u * uz + centre_v * vz
    area = width * depth

    return {
        "x": round(x, 3),
        "z": round(z, 3),
        "width": round(width, 3),
        "depth": round(depth, 3),
        "height": round(building_height(tags, area), 3),
        "angle": round(angle, 6),
        "type": tags.get("building", "yes"),
    }


def main() -> None:
    args = parse_args()
    report = json.loads(args.report.read_text(encoding="utf-8"))
    crop = report["source_crop_lonlat"]
    west = float(crop["west"])
    south = float(crop["south"])
    east = float(crop["east"])
    north = float(crop["north"])

    osm = fetch_overpass(south, west, north, east)
    project = local_projector(report)

    buildings: list[dict] = []
    roads: list[dict] = []
    skipped_buildings = 0

    for element in osm.get("elements", []):
        if element.get("type") != "way":
            continue
        tags = element.get("tags", {})
        geometry = element.get("geometry") or []
        if len(geometry) < 2:
            continue
        points = [project(float(p["lon"]), float(p["lat"])) for p in geometry]

        if "building" in tags:
            box = oriented_box(points, tags)
            if box is None:
                skipped_buildings += 1
            else:
                buildings.append(box)
            continue

        highway = tags.get("highway")
        if not highway or highway in SKIP_HIGHWAYS:
            continue
        width = ROAD_WIDTHS.get(highway, 4.5)
        roads.append({
            "class": highway,
            "width": width,
            "points": [[round(x, 3), round(z, 3)] for x, z in points],
        })

    output = {
        "source": "OpenStreetMap",
        "attribution": "© OpenStreetMap contributors",
        "license": "ODbL 1.0",
        "copyright_url": "https://www.openstreetmap.org/copyright",
        "bbox_lonlat": crop,
        "projection": "EPSG:32617 -> HFN local metres",
        "buildings": buildings,
        "roads": roads,
        "stats": {
            "buildings": len(buildings),
            "roads": len(roads),
            "road_points": sum(len(r["points"]) for r in roads),
            "skipped_buildings": skipped_buildings,
        },
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(output, separators=(",", ":")), encoding="utf-8")
    print(
        "[key-west-osm] buildings=%d roads=%d road_points=%d skipped_buildings=%d"
        % (
            output["stats"]["buildings"],
            output["stats"]["roads"],
            output["stats"]["road_points"],
            output["stats"]["skipped_buildings"],
        )
    )


if __name__ == "__main__":
    main()
