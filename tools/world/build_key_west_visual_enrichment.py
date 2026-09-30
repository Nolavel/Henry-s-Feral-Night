#!/usr/bin/env python3
"""Build a visual-only Key West enrichment sidecar.

The frozen Stage 5 city_preview.json remains immutable. This tool adds only
attributes and small-scale visual features for the TPS presentation pass:

* Overture Buildings: height/floors/roof/facade attributes matched by OSM id.
* Overture Transportation: surface/width/flags/speed metadata matched by OSM id.
* Overture Base infrastructure: local projected infrastructure features.
* Supplemental OSM: sidewalks, barriers, piers/breakwaters, poles/lamps and
  coastline geometry that the Stage 5 city snapshot deliberately omitted.

Output is disposable preview data and may be deleted without changing the
underlying city geometry or StreamingSystem chunk layout.
"""
from __future__ import annotations

import argparse
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Callable

from pyproj import Transformer

OVERTURE_RELEASE = "2026-09-23.1"
DEFAULT_REPORT = Path("docs/runtime_previews/key_west/source_report.json")
DEFAULT_CITY = Path("docs/runtime_previews/key_west/city_preview.json")
DEFAULT_OUT = Path("docs/runtime_previews/key_west/visual_enrichment.json")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    p.add_argument("--city", type=Path, default=DEFAULT_CITY)
    p.add_argument("--overture-buildings", type=Path)
    p.add_argument("--overture-segments", type=Path)
    p.add_argument("--overture-infrastructure", type=Path)
    p.add_argument("--out", type=Path, default=DEFAULT_OUT)
    return p.parse_args()


def load_json(path: Path | None) -> dict:
    if path is None or not path.exists():
        return {"type": "FeatureCollection", "features": []}
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def local_projector(report: dict) -> Callable[[float, float], tuple[float, float]]:
    gt = report["source_geotransform"]
    step = float(report["preview_resolution_m"])
    width = int(report["width"])
    height = int(report["height"])
    centre_e = float(gt[0]) + (width - 1) * step * 0.5
    centre_n = float(gt[3]) - (height - 1) * step * 0.5
    transformer = Transformer.from_crs("EPSG:4326", "EPSG:32617", always_xy=True)

    def project(lon: float, lat: float) -> tuple[float, float]:
        east, north = transformer.transform(lon, lat)
        return float(east - centre_e), float(centre_n - north)

    return project


def jsonish(value: Any) -> Any:
    if not isinstance(value, str):
        return value
    text = value.strip()
    if not text or text[0] not in "[{":
        return value
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return value


def osm_ids(properties: dict) -> list[str]:
    sources = jsonish(properties.get("sources", []))
    if not isinstance(sources, list):
        return []
    result: list[str] = []
    for source in sources:
        if not isinstance(source, dict):
            continue
        if str(source.get("dataset", "")).lower() != "openstreetmap":
            continue
        record = str(source.get("record_id", ""))
        match = re.match(r"([nwr])(\d+)@", record)
        if not match:
            continue
        prefix = {"n": "node", "w": "way", "r": "relation"}[match.group(1)]
        result.append(f"{prefix}/{match.group(2)}")
    return result


def compact(properties: dict, keys: tuple[str, ...]) -> dict:
    result: dict = {}
    for key in keys:
        value = jsonish(properties.get(key))
        if value not in (None, "", [], {}):
            result[key] = value
    return result


def overture_building_attrs(collection: dict, known_ids: set[str]) -> tuple[dict, dict]:
    matches: dict[str, dict] = {}
    stats = {"features": 0, "osm_matches": 0, "with_height": 0, "with_roof": 0}
    for feature in collection.get("features", []):
        stats["features"] += 1
        props = feature.get("properties", {})
        attrs = compact(
            props,
            (
                "height", "num_floors", "min_height", "min_floor",
                "facade_color", "facade_material", "roof_material", "roof_shape",
                "roof_direction", "roof_orientation", "roof_color", "roof_height",
                "has_parts", "class", "subtype",
            ),
        )
        if "height" in attrs:
            stats["with_height"] += 1
        if any(key.startswith("roof_") for key in attrs):
            stats["with_roof"] += 1
        if not attrs:
            continue
        for oid in osm_ids(props):
            if oid not in known_ids:
                continue
            existing = matches.setdefault(oid, {})
            for key, value in attrs.items():
                existing.setdefault(key, value)
            stats["osm_matches"] += 1
    return matches, stats


def first_rule_value(value: Any, key: str = "value") -> Any:
    value = jsonish(value)
    if isinstance(value, list):
        for item in value:
            if isinstance(item, dict) and item.get(key) not in (None, ""):
                return item[key]
    return None


def road_attrs(collection: dict, known_ids: set[str]) -> tuple[dict, dict]:
    matches: dict[str, dict] = {}
    stats = {"features": 0, "osm_matches": 0, "surface": 0, "width": 0, "flags": 0}
    for feature in collection.get("features", []):
        props = feature.get("properties", {})
        if str(props.get("subtype", "")) != "road":
            continue
        stats["features"] += 1
        attrs: dict[str, Any] = {}
        surface = first_rule_value(props.get("road_surface"))
        if surface:
            attrs["surface"] = surface
            stats["surface"] += 1
        width = first_rule_value(props.get("width_rules"))
        if width is not None:
            try:
                attrs["width"] = float(width)
                stats["width"] += 1
            except (TypeError, ValueError):
                pass
        flags = jsonish(props.get("road_flags"))
        if flags not in (None, "", [], {}):
            attrs["road_flags"] = flags
            stats["flags"] += 1
        speed = jsonish(props.get("speed_limits"))
        if speed not in (None, "", [], {}):
            attrs["speed_limits"] = speed
        attrs.update(compact(props, ("class", "subclass")))
        if not attrs:
            continue
        for oid in osm_ids(props):
            if oid not in known_ids:
                continue
            current = matches.setdefault(oid, {})
            for key, value in attrs.items():
                current.setdefault(key, value)
            stats["osm_matches"] += 1
    return matches, stats


def project_geometry(geometry: dict, project) -> dict | None:
    kind = geometry.get("type")
    coords = geometry.get("coordinates")

    def point(value: list) -> list[float]:
        x, z = project(float(value[0]), float(value[1]))
        return [round(x, 2), round(z, 2)]

    if kind == "Point" and isinstance(coords, list):
        return {"type": kind, "coordinates": point(coords)}
    if kind == "LineString" and isinstance(coords, list):
        return {"type": kind, "coordinates": [point(p) for p in coords]}
    if kind == "Polygon" and isinstance(coords, list):
        return {"type": kind, "coordinates": [[point(p) for p in ring] for ring in coords]}
    if kind == "MultiLineString" and isinstance(coords, list):
        return {"type": kind, "coordinates": [[point(p) for p in line] for line in coords]}
    if kind == "MultiPolygon" and isinstance(coords, list):
        return {
            "type": kind,
            "coordinates": [[[point(p) for p in ring] for ring in poly] for poly in coords],
        }
    return None


def overture_infrastructure(collection: dict, project) -> tuple[list[dict], dict]:
    output: list[dict] = []
    classes: dict[str, int] = {}
    for feature in collection.get("features", []):
        props = feature.get("properties", {})
        klass = str(props.get("class", ""))
        subtype = str(props.get("subtype", ""))
        if not klass and not subtype:
            continue
        geometry = project_geometry(feature.get("geometry", {}), project)
        if geometry is None:
            continue
        classes[klass or subtype] = classes.get(klass or subtype, 0) + 1
        output.append({
            "id": str(feature.get("id", "")),
            "class": klass,
            "subtype": subtype,
            "height": props.get("height"),
            "surface": props.get("surface"),
            "names": jsonish(props.get("names")),
            "geometry": geometry,
        })
    return output, {"features": len(output), "classes": classes}


def fetch_supplemental_osm(crop: dict) -> dict:
    west, south, east, north = (
        float(crop["west"]), float(crop["south"]),
        float(crop["east"]), float(crop["north"]),
    )
    bbox = f"{south},{west},{north},{east}"
    query = f"""[out:json][timeout:180];
(
  way["highway"~"footway|pedestrian"]["footway"!="crossing"]({bbox});
  way["barrier"~"fence|wall|retaining_wall|guard_rail"]({bbox});
  way["man_made"~"pier|breakwater|groyne"]({bbox});
  way["natural"="coastline"]({bbox});
  node["highway"="street_lamp"]({bbox});
  node["power"~"pole|tower"]({bbox});
  node["man_made"~"mast|tower"]({bbox});
);
out geom;"""
    body = urllib.parse.urlencode({"data": query}).encode("utf-8")
    endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
    ]
    last_error: Exception | None = None
    for endpoint in endpoints:
        request = urllib.request.Request(
            endpoint,
            data=body,
            method="POST",
            headers={"User-Agent": "HFN-Hoarbound-KeyWest-Visuals/1.0"},
        )
        for attempt in range(2):
            try:
                with urllib.request.urlopen(request, timeout=240) as response:
                    return json.loads(response.read().decode("utf-8"))
            except Exception as exc:  # noqa: BLE001 - mirror fallback
                last_error = exc
                if attempt == 0:
                    time.sleep(3.0)
    raise RuntimeError(f"supplemental Overpass request failed: {last_error}")


def supplemental_features(osm: dict, project) -> tuple[list[dict], dict]:
    output: list[dict] = []
    counts: dict[str, int] = {}
    for element in osm.get("elements", []):
        tags = element.get("tags", {})
        kind = ""
        if tags.get("natural") == "coastline":
            kind = "coastline"
        elif tags.get("man_made") in {"pier", "breakwater", "groyne"}:
            kind = str(tags["man_made"])
        elif tags.get("barrier"):
            kind = f"barrier:{tags['barrier']}"
        elif tags.get("highway") in {"footway", "pedestrian"}:
            kind = "sidewalk"
        elif tags.get("highway") == "street_lamp":
            kind = "street_lamp"
        elif tags.get("power") in {"pole", "tower"}:
            kind = f"power:{tags['power']}"
        elif tags.get("man_made") in {"mast", "tower"}:
            kind = f"man_made:{tags['man_made']}"
        if not kind:
            continue

        geometry: dict | None = None
        if element.get("type") == "node":
            if "lon" in element and "lat" in element:
                x, z = project(float(element["lon"]), float(element["lat"]))
                geometry = {"type": "Point", "coordinates": [round(x, 2), round(z, 2)]}
        else:
            points = [
                project(float(p["lon"]), float(p["lat"]))
                for p in element.get("geometry", [])
                if "lon" in p and "lat" in p
            ]
            if len(points) >= 2:
                geometry = {
                    "type": "LineString",
                    "coordinates": [[round(x, 2), round(z, 2)] for x, z in points],
                }
        if geometry is None:
            continue
        counts[kind] = counts.get(kind, 0) + 1
        output.append({
            "osm_id": f"{element.get('type')}/{element.get('id')}",
            "kind": kind,
            "tags": {
                key: tags[key]
                for key in (
                    "name", "surface", "width", "height", "lit", "sidewalk",
                    "fence_type", "material", "access",
                )
                if tags.get(key) not in (None, "")
            },
            "geometry": geometry,
        })
    return output, {"features": len(output), "kinds": counts}


def main() -> None:
    args = parse_args()
    report = load_json(args.report)
    city = load_json(args.city)
    project = local_projector(report)

    building_ids = {str(item.get("osm_id", "")) for item in city.get("buildings", [])}
    road_ids = {str(item.get("osm_id", "")) for item in city.get("roads", [])}

    building_attrs, building_stats = overture_building_attrs(
        load_json(args.overture_buildings), building_ids
    )
    road_enrichment, road_stats = road_attrs(
        load_json(args.overture_segments), road_ids
    )
    infrastructure, infrastructure_stats = overture_infrastructure(
        load_json(args.overture_infrastructure), project
    )

    supplemental_osm = fetch_supplemental_osm(report["source_crop_lonlat"])
    supplemental, supplemental_stats = supplemental_features(supplemental_osm, project)

    output = {
        "schema": "hfn_key_west_visual_enrichment_v1",
        "base_city_snapshot": "Stage 5 city_preview.json; geometry/chunks unchanged",
        "overture_release": OVERTURE_RELEASE,
        "sources": {
            "overture": {
                "release": OVERTURE_RELEASE,
                "license_note": "Buildings/transportation/base are ODbL due to OSM-containing themes.",
            },
            "openstreetmap_supplemental": {
                "attribution": "© OpenStreetMap contributors",
                "license": "ODbL 1.0",
            },
            "noaa": {
                "note": "Terrain and shoreline elevation remain the existing NOAA 2016 source.",
            },
        },
        "building_attrs": building_attrs,
        "road_attrs": road_enrichment,
        "infrastructure": infrastructure,
        "supplemental": supplemental,
        "stats": {
            "buildings": building_stats,
            "roads": road_stats,
            "infrastructure": infrastructure_stats,
            "supplemental": supplemental_stats,
        },
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(output, separators=(",", ":")), encoding="utf-8")
    print("[key-west-visuals]", json.dumps(output["stats"], ensure_ascii=False))


if __name__ == "__main__":
    main()
