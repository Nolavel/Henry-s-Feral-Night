#!/usr/bin/env python3
"""Build chunk-aware Key West city data from OpenStreetMap for issue #138.

The generated dataset is preview/runtime research data, not authored source:
- buildings preserve their real footprint polygons and address/name metadata;
- roads preserve named polylines and road metadata;
- airport features are a first-class layer (runway/taxiway/apron/aerodrome);
- all content is partitioned into 512 m HFN chunks;
- each building also carries an oriented-box proxy for far Ring-0 massing.

OSM data is ODbL. NOAA remains the terrain source of truth.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import time
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path
from typing import Callable

from pyproj import Transformer

DEFAULT_REPORT = Path("docs/runtime_previews/key_west/source_report.json")
DEFAULT_OUTPUT = Path("docs/runtime_previews/key_west/city_preview.json")
OVERPASS = "https://overpass-api.de/api/interpreter"
CHUNK_SIZE_M = 512.0

ROAD_WIDTHS = {
    "motorway": 12.0, "trunk": 11.0, "primary": 9.0, "secondary": 8.0,
    "tertiary": 7.0, "residential": 5.5, "living_street": 5.0,
    "unclassified": 5.0, "service": 3.5,
}
SKIP_HIGHWAYS = {
    "footway", "path", "cycleway", "steps", "pedestrian", "track", "bridleway",
}
AIRPORT_WIDTHS = {
    "runway": 45.0,
    "taxiway": 18.0,
    "taxilane": 10.0,
    "service": 6.0,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--chunk-size", type=float, default=CHUNK_SIZE_M)
    return parser.parse_args()


def fetch_overpass(south: float, west: float, north: float, east: float) -> dict:
    bbox = f"{south},{west},{north},{east}"
    query = f"""[out:json][timeout:180];
(
  way["building"]({bbox});
  way["highway"]({bbox});
  way["aeroway"]({bbox});
  node["aeroway"="aerodrome"]({bbox});
  way["aeroway"="aerodrome"]({bbox});
  relation["aeroway"="aerodrome"]({bbox});
  node["addr:housenumber"]({bbox});
);
out center geom;"""
    body = urllib.parse.urlencode({"data": query}).encode("utf-8")
    mirrors = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
    ]
    last_error: Exception | None = None
    for endpoint in mirrors:
        request = urllib.request.Request(
            endpoint,
            data=body,
            headers={"User-Agent": "HFN-RIMEWATCH-KeyWest-Preview/2.0"},
            method="POST",
        )
        for attempt in range(2):
            try:
                with urllib.request.urlopen(request, timeout=240) as response:
                    return json.loads(response.read().decode("utf-8"))
            except Exception as exc:
                last_error = exc
                if attempt == 0:
                    time.sleep(4.0)
    raise RuntimeError(f"Overpass download failed: {last_error}")


def local_projector(report: dict) -> Callable[[float, float], tuple[float, float]]:
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


def geometry_points(element: dict, project) -> list[tuple[float, float]]:
    geometry = element.get("geometry") or []
    return [
        project(float(point["lon"]), float(point["lat"]))
        for point in geometry
        if "lon" in point and "lat" in point
    ]


def element_center(element: dict, project) -> tuple[float, float] | None:
    center = element.get("center")
    if center and "lon" in center and "lat" in center:
        return project(float(center["lon"]), float(center["lat"]))
    if "lon" in element and "lat" in element:
        return project(float(element["lon"]), float(element["lat"]))
    points = geometry_points(element, project)
    if not points:
        return None
    return (
        sum(point[0] for point in points) / len(points),
        sum(point[1] for point in points) / len(points),
    )


def numeric_prefix(value: str) -> float | None:
    match = re.search(r"-?\d+(?:\.\d+)?", value or "")
    return float(match.group(0)) if match else None


def compact_tags(tags: dict, keys: tuple[str, ...]) -> dict:
    return {key: tags[key] for key in keys if tags.get(key) not in (None, "")}


def polygon_area(points: list[tuple[float, float]]) -> float:
    if len(points) < 3:
        return 0.0
    total = 0.0
    for i, a in enumerate(points):
        b = points[(i + 1) % len(points)]
        total += a[0] * b[1] - b[0] * a[1]
    return abs(total) * 0.5


def point_in_polygon(point: tuple[float, float], polygon: list[tuple[float, float]]) -> bool:
    x, z = point
    inside = False
    j = len(polygon) - 1
    for i in range(len(polygon)):
        xi, zi = polygon[i]
        xj, zj = polygon[j]
        crosses = (zi > z) != (zj > z)
        if crosses:
            denom = (zj - zi) or 1e-12
            edge_x = (xj - xi) * (z - zi) / denom + xi
            if x < edge_x:
                inside = not inside
        j = i
    return inside


def distance_point_segment(
    point: tuple[float, float], a: tuple[float, float], b: tuple[float, float]
) -> float:
    px, pz = point
    ax, az = a
    bx, bz = b
    dx = bx - ax
    dz = bz - az
    length_sq = dx * dx + dz * dz
    if length_sq <= 1e-9:
        return math.hypot(px - ax, pz - az)
    t = max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / length_sq))
    qx = ax + t * dx
    qz = az + t * dz
    return math.hypot(px - qx, pz - qz)


def building_height(tags: dict, footprint_area: float) -> tuple[float, str]:
    explicit = numeric_prefix(tags.get("height", ""))
    if explicit is not None and 2.2 <= explicit <= 120.0:
        return explicit, "osm_height"
    levels = numeric_prefix(tags.get("building:levels", ""))
    if levels is not None and 1.0 <= levels <= 40.0:
        return max(3.2, levels * 3.0), "osm_levels"

    kind = tags.get("building", "")
    if kind in {"hotel", "apartments", "office", "commercial"}:
        return 9.0, "fallback_type"
    if kind in {"industrial", "warehouse", "retail", "hangar"}:
        return 6.5, "fallback_type"
    if footprint_area > 1200.0:
        return 8.0, "fallback_area"
    if footprint_area > 450.0:
        return 5.5, "fallback_area"
    return 3.6, "fallback_default"


def oriented_proxy(points: list[tuple[float, float]]) -> dict:
    cx = sum(point[0] for point in points) / len(points)
    cz = sum(point[1] for point in points) / len(points)
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
    centre_u = (min_u + max_u) * 0.5
    centre_v = (min_v + max_v) * 0.5
    return {
        "x": round(cx + centre_u * ux + centre_v * vx, 2),
        "z": round(cz + centre_u * uz + centre_v * vz, 2),
        "width": round(max(2.5, max_u - min_u), 2),
        "depth": round(max(2.5, max_v - min_v), 2),
        "angle": round(angle, 6),
    }


def chunk_coords(x: float, z: float, size: float) -> tuple[int, int]:
    return math.floor(x / size), math.floor(z / size)


def chunk_id(cx: int, cz: int) -> str:
    return f"{cx}:{cz}"


def touched_chunks(points: list[tuple[float, float]], size: float) -> list[str]:
    if not points:
        return []
    min_x = min(point[0] for point in points)
    max_x = max(point[0] for point in points)
    min_z = min(point[1] for point in points)
    max_z = max(point[1] for point in points)
    min_cx, min_cz = chunk_coords(min_x, min_z, size)
    max_cx, max_cz = chunk_coords(max_x, max_z, size)
    return [
        chunk_id(cx, cz)
        for cz in range(min_cz, max_cz + 1)
        for cx in range(min_cx, max_cx + 1)
    ]


def road_width(tags: dict) -> float:
    explicit = numeric_prefix(tags.get("width", ""))
    if explicit is not None and 1.5 <= explicit <= 30.0:
        return explicit
    lanes = numeric_prefix(tags.get("lanes", ""))
    base = ROAD_WIDTHS.get(tags.get("highway", ""), 4.5)
    if lanes is not None and 1.0 <= lanes <= 8.0:
        return max(base, lanes * 3.0)
    return base


def airport_width(tags: dict) -> float:
    explicit = numeric_prefix(tags.get("width", ""))
    if explicit is not None and 3.0 <= explicit <= 120.0:
        return explicit
    return AIRPORT_WIDTHS.get(tags.get("aeroway", ""), 10.0)


def rounded_points(points: list[tuple[float, float]]) -> list[list[float]]:
    return [[round(x, 2), round(z, 2)] for x, z in points]


def main() -> None:
    args = parse_args()
    report = json.loads(args.report.read_text(encoding="utf-8"))
    crop = report["source_crop_lonlat"]
    west = float(crop["west"])
    south = float(crop["south"])
    east = float(crop["east"])
    north = float(crop["north"])
    chunk_size = float(args.chunk_size)

    osm = fetch_overpass(south, west, north, east)
    project = local_projector(report)

    raw_buildings: list[dict] = []
    address_nodes: list[dict] = []
    roads: list[dict] = []
    airport_features: list[dict] = []
    aerodrome_candidates: list[dict] = []

    for element in osm.get("elements", []):
        tags = element.get("tags", {})
        element_type = element.get("type")
        osm_id = f"{element_type}/{element.get('id')}"

        if tags.get("addr:housenumber") and element_type == "node":
            center = element_center(element, project)
            if center is not None:
                address_nodes.append({
                    "point": center,
                    "tags": compact_tags(
                        tags,
                        ("addr:housenumber", "addr:street", "addr:city", "addr:postcode", "name"),
                    ),
                })

        if tags.get("aeroway") == "aerodrome":
            center = element_center(element, project)
            aerodrome_candidates.append({
                "osm_id": osm_id,
                "center": [round(center[0], 2), round(center[1], 2)] if center else None,
                "name": tags.get("name", ""),
                "iata": tags.get("iata", ""),
                "icao": tags.get("icao", ""),
                "operator": tags.get("operator", ""),
            })

        if element_type != "way":
            continue

        points = geometry_points(element, project)
        if len(points) < 2:
            continue

        if "building" in tags and len(points) >= 3:
            if points[0] == points[-1]:
                points = points[:-1]
            if len(points) >= 3:
                raw_buildings.append({
                    "osm_id": osm_id,
                    "tags": tags,
                    "points": points,
                })

        highway = tags.get("highway")
        if highway and highway not in SKIP_HIGHWAYS:
            road_index = len(roads)
            road = {
                "id": road_index,
                "osm_id": osm_id,
                "class": highway,
                "name": tags.get("name", ""),
                "ref": tags.get("ref", ""),
                "lanes": tags.get("lanes", ""),
                "surface": tags.get("surface", ""),
                "oneway": tags.get("oneway", ""),
                "bridge": tags.get("bridge", ""),
                "tunnel": tags.get("tunnel", ""),
                "width": round(road_width(tags), 2),
                "points": rounded_points(points),
                "chunk_ids": touched_chunks(points, chunk_size),
            }
            roads.append(road)

        aeroway = tags.get("aeroway")
        if aeroway:
            is_area = (
                len(points) >= 4
                and points[0] == points[-1]
                and aeroway in {"apron", "aerodrome", "helipad", "terminal", "hangar"}
            )
            if is_area:
                points = points[:-1]
            airport_features.append({
                "id": len(airport_features),
                "osm_id": osm_id,
                "kind": aeroway,
                "name": tags.get("name", ""),
                "ref": tags.get("ref", ""),
                "surface": tags.get("surface", ""),
                "width": round(airport_width(tags), 2),
                "is_area": is_area,
                "points": rounded_points(points),
                "chunk_ids": touched_chunks(points, chunk_size),
            })

    # Roads are indexed spatially for building street hints.
    named_road_segments: dict[tuple[int, int], list[tuple[str, tuple[float, float], tuple[float, float]]]] = defaultdict(list)
    for road in roads:
        if not road["name"]:
            continue
        pts = [(float(p[0]), float(p[1])) for p in road["points"]]
        for a, b in zip(pts, pts[1:]):
            mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)
            named_road_segments[chunk_coords(mid[0], mid[1], chunk_size)].append((road["name"], a, b))

    buildings: list[dict] = []
    building_buckets: dict[tuple[int, int], list[int]] = defaultdict(list)
    for raw in raw_buildings:
        tags = raw["tags"]
        points = raw["points"]
        area = polygon_area(points)
        proxy = oriented_proxy(points)
        height, height_source = building_height(tags, area)
        cx, cz = chunk_coords(proxy["x"], proxy["z"], chunk_size)
        metadata = compact_tags(
            tags,
            (
                "name", "addr:housenumber", "addr:street", "addr:city", "addr:postcode",
                "building", "building:levels", "height", "amenity", "shop", "tourism",
                "office", "operator", "historic",
            ),
        )
        building = {
            "id": len(buildings),
            "osm_id": raw["osm_id"],
            "chunk_id": chunk_id(cx, cz),
            "footprint": rounded_points(points),
            "proxy": proxy,
            "height": round(height, 2),
            "height_source": height_source,
            "area_m2": round(area, 1),
            "metadata": metadata,
        }
        buildings.append(building)
        building_buckets[(cx, cz)].append(building["id"])

    # Attach separately mapped address nodes to the containing/nearest building.
    assigned_addresses = 0
    for address in address_nodes:
        px, pz = address["point"]
        pcx, pcz = chunk_coords(px, pz, chunk_size)
        candidates: list[int] = []
        for dz in (-1, 0, 1):
            for dx in (-1, 0, 1):
                candidates.extend(building_buckets.get((pcx + dx, pcz + dz), []))
        best_id: int | None = None
        best_distance = 9999.0
        for building_id in candidates:
            building = buildings[building_id]
            polygon = [(float(p[0]), float(p[1])) for p in building["footprint"]]
            proxy = building["proxy"]
            if point_in_polygon((px, pz), polygon):
                best_id = building_id
                best_distance = 0.0
                break
            distance = math.hypot(px - float(proxy["x"]), pz - float(proxy["z"]))
            if distance < best_distance and distance <= 35.0:
                best_distance = distance
                best_id = building_id
        if best_id is None:
            continue
        metadata = buildings[best_id]["metadata"]
        for key, value in address["tags"].items():
            if not metadata.get(key):
                metadata[key] = value
        metadata["address_source"] = "osm_address_node"
        assigned_addresses += 1

    # Add a non-authoritative nearest named-road hint where OSM has no addr:street.
    street_hints = 0
    for building in buildings:
        metadata = building["metadata"]
        if metadata.get("addr:street"):
            continue
        proxy = building["proxy"]
        px = float(proxy["x"])
        pz = float(proxy["z"])
        pcx, pcz = chunk_coords(px, pz, chunk_size)
        nearest_name = ""
        nearest_distance = 45.0
        for dz in (-1, 0, 1):
            for dx in (-1, 0, 1):
                for name, a, b in named_road_segments.get((pcx + dx, pcz + dz), []):
                    distance = distance_point_segment((px, pz), a, b)
                    if distance < nearest_distance:
                        nearest_distance = distance
                        nearest_name = name
        if nearest_name:
            metadata["street_hint"] = nearest_name
            metadata["street_hint_distance_m"] = round(nearest_distance, 1)
            metadata["street_hint_source"] = "nearest_named_osm_road"
            street_hints += 1

    chunks: dict[str, dict] = {}

    def ensure_chunk(cid: str) -> dict:
        if cid not in chunks:
            cx, cz = (int(value) for value in cid.split(":"))
            chunks[cid] = {
                "id": cid,
                "cx": cx,
                "cz": cz,
                "origin": [round(cx * chunk_size, 2), round(cz * chunk_size, 2)],
                "size_m": chunk_size,
                "building_ids": [],
                "road_segments": [],
                "airport_feature_ids": [],
            }
        return chunks[cid]

    for building in buildings:
        ensure_chunk(building["chunk_id"])["building_ids"].append(building["id"])

    for road in roads:
        pts = [(float(p[0]), float(p[1])) for p in road["points"]]
        for segment_index, (a, b) in enumerate(zip(pts, pts[1:])):
            mid_x = (a[0] + b[0]) * 0.5
            mid_z = (a[1] + b[1]) * 0.5
            cid = chunk_id(*chunk_coords(mid_x, mid_z, chunk_size))
            ensure_chunk(cid)["road_segments"].append({
                "road_id": road["id"],
                "segment": segment_index,
                "a": [round(a[0], 2), round(a[1], 2)],
                "b": [round(b[0], 2), round(b[1], 2)],
            })

    for feature in airport_features:
        for cid in feature["chunk_ids"]:
            ensure_chunk(cid)["airport_feature_ids"].append(feature["id"])

    airport_center = None
    airport_meta = {}
    preferred = [
        item for item in aerodrome_candidates
        if item.get("iata") == "EYW" or item.get("icao") == "KEYW"
        or "key west" in item.get("name", "").lower()
    ]
    selected = preferred[0] if preferred else (aerodrome_candidates[0] if aerodrome_candidates else None)
    if selected is not None:
        airport_center = selected.get("center")
        airport_meta = {
            key: selected.get(key, "")
            for key in ("osm_id", "name", "iata", "icao", "operator")
        }

    if airport_center is None and airport_features:
        all_points = [
            point
            for feature in airport_features
            for point in feature["points"]
        ]
        if all_points:
            airport_center = [
                round(sum(float(p[0]) for p in all_points) / len(all_points), 2),
                round(sum(float(p[1]) for p in all_points) / len(all_points), 2),
            ]

    stats = {
        "buildings": len(buildings),
        "named_buildings": sum(bool(b["metadata"].get("name")) for b in buildings),
        "addressed_buildings": sum(bool(b["metadata"].get("addr:housenumber")) for b in buildings),
        "street_hints": street_hints,
        "address_nodes_assigned": assigned_addresses,
        "roads": len(roads),
        "named_roads": sum(bool(road["name"]) for road in roads),
        "road_points": sum(len(road["points"]) for road in roads),
        "airport_features": len(airport_features),
        "chunks": len(chunks),
        "max_buildings_in_chunk": max((len(chunk["building_ids"]) for chunk in chunks.values()), default=0),
    }

    output = {
        "schema": "hfn_key_west_city_preview_v2",
        "source": "OpenStreetMap",
        "attribution": "© OpenStreetMap contributors",
        "license": "ODbL 1.0",
        "copyright_url": "https://www.openstreetmap.org/copyright",
        "bbox_lonlat": crop,
        "projection": "EPSG:32617 -> HFN local metres",
        "chunk_size_m": chunk_size,
        "rings": {
            "detail_radius_m": 1150.0,
            "massing_radius_m": 3600.0,
        },
        "airport": {
            "center": airport_center,
            "metadata": airport_meta,
            "feature_ids": [feature["id"] for feature in airport_features],
        },
        "buildings": buildings,
        "roads": roads,
        "airport_features": airport_features,
        "chunks": chunks,
        "stats": stats,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(output, separators=(",", ":")), encoding="utf-8")
    print(
        "[key-west-osm-v2] buildings=%d named=%d addressed=%d roads=%d named_roads=%d airport=%d chunks=%d max_buildings/chunk=%d"
        % (
            stats["buildings"], stats["named_buildings"], stats["addressed_buildings"],
            stats["roads"], stats["named_roads"], stats["airport_features"],
            stats["chunks"], stats["max_buildings_in_chunk"],
        )
    )
    if airport_center is not None:
        print(
            "[key-west-osm-v2] airport center=(%.1f, %.1f) name=%s iata=%s icao=%s"
            % (
                float(airport_center[0]), float(airport_center[1]),
                airport_meta.get("name", ""), airport_meta.get("iata", ""),
                airport_meta.get("icao", ""),
            )
        )


if __name__ == "__main__":
    main()
