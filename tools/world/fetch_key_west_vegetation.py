#!/usr/bin/env python3
"""Fetch mapped trees, tree rows and woods for Key West from Overture base/land.

Writes data/world/key_west/vegetation.json in the city's local metres.
Run: python3 tools/world/fetch_key_west_vegetation.py  (needs pyarrow, pyproj)
"""
from __future__ import annotations

import json
from pathlib import Path

import pyarrow.compute as pc
import pyarrow.dataset as ds
import pyarrow.fs as fs
from pyproj import Transformer
from shapely import wkb

OVERTURE_RELEASE = "2026-09-23.1"
REPORT = Path("data/world/key_west/source_report.json")
CITY = Path("data/world/key_west/city_preview.json")
OUT = Path("data/world/key_west/vegetation.json")
KINDS = {"tree": "tree", "tree_row": "tree_row", "wood": "wood", "forest": "wood", "scrub": "scrub"}


def projector(report: dict):
    gt = report["source_geotransform"]
    step = float(report["preview_resolution_m"])
    centre_e = float(gt[0]) + (int(report["width"]) - 1) * step * 0.5
    centre_n = float(gt[3]) - (int(report["height"]) - 1) * step * 0.5
    transformer = Transformer.from_crs("EPSG:4326", "EPSG:32617", always_xy=True)

    def project(lon: float, lat: float) -> list[float]:
        east, north = transformer.transform(lon, lat)
        return [round(east - centre_e, 2), round(centre_n - north, 2)]

    return project


def main() -> None:
    report = json.loads(REPORT.read_text())
    bbox = json.loads(CITY.read_text())["bbox_lonlat"]
    project = projector(report)
    s3 = fs.S3FileSystem(anonymous=True, region="us-west-2")
    land = ds.dataset(f"overturemaps-us-west-2/release/{OVERTURE_RELEASE}/theme=base/type=land", filesystem=s3, format="parquet")
    inside = (
        (pc.field("bbox", "xmin") > bbox["west"]) & (pc.field("bbox", "xmax") < bbox["east"])
        & (pc.field("bbox", "ymin") > bbox["south"]) & (pc.field("bbox", "ymax") < bbox["north"])
    )
    table = land.to_table(columns=["id", "class", "geometry"], filter=inside)
    features = []
    for row in table.to_pylist():
        kind = KINDS.get(row["class"])
        if kind is None:
            continue
        shape = wkb.loads(row["geometry"])
        if shape.geom_type == "Point":
            coords = project(shape.x, shape.y)
        elif shape.geom_type == "LineString":
            coords = [project(x, y) for x, y in shape.coords]
        elif shape.geom_type == "Polygon":
            coords = [project(x, y) for x, y in shape.exterior.coords]
        else:
            continue
        features.append({"id": row["id"], "kind": kind, "type": shape.geom_type, "coordinates": coords})
    features.sort(key=lambda f: f["id"])
    OUT.write_text(json.dumps({
        "schema": "hfn.key_west.vegetation.v1",
        "source": f"Overture Maps base/land release {OVERTURE_RELEASE} (OpenStreetMap contributors, ODbL)",
        "features": features,
    }, separators=(",", ":")))
    print(f"wrote {len(features)} features to {OUT}")


if __name__ == "__main__":
    main()
