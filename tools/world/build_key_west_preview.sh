#!/usr/bin/env bash
## Builds the disposable 2 m/px Key West Godot preview for issue #138.
## The 1 m NOAA mosaic is downloaded unchanged, cropped/reprojected by GDAL,
## converted to the HFN 16-bit contract, then baked to the LA8 runtime image.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

NOAA_URL="https://noaa-nos-coastal-lidar-pds.s3.amazonaws.com/dem/NGS_FL_key_west_DEM_2016_6366/2016_key_west_mosaic_m6366.tif"
RAW="/tmp/hfn-key-west-noaa-2016.tif"
CROP="/tmp/hfn-key-west-preview-2m.tif"
SOURCE_PNG="world/terrain/source/key_west/key_west_preview_2m_height.png"
SOURCE_JSON="world/terrain/source/key_west/key_west_preview_2m_height.json"
RUNTIME_PNG="world/terrain/key_west_preview_2m_la8.png"
RUNTIME_JSON="world/terrain/key_west_preview_2m_la8.json"
OCEAN_MASK="docs/runtime_previews/key_west/ocean_connected_mask.png"
CITY_JSON="docs/runtime_previews/key_west/city_preview.json"
REPORT="docs/runtime_previews/key_west/source_report.json"

# Geographic gate for the first Godot proof: Key West + Fleming Key +
# Wisteria Island + Sunset Key + Stock Island, with a small sea/ice margin.
WEST="-81.835"
SOUTH="24.535"
EAST="-81.705"
NORTH="24.595"
STEP_M="2.0"

mkdir -p "$(dirname "$SOURCE_PNG")" "$(dirname "$REPORT")"

echo "[key-west] downloading NOAA 2016 topobathy DEM mosaic"
curl --fail --location --retry 3 --retry-delay 3 --silent --show-error "$NOAA_URL" -o "$RAW"

echo "[key-west] source"
gdalinfo "$RAW" | sed -n '1,45p'

echo "[key-west] crop + 2 m preview grid"
gdalwarp \
  -overwrite \
  -te "$WEST" "$SOUTH" "$EAST" "$NORTH" \
  -te_srs EPSG:4326 \
  -tr "$STEP_M" "$STEP_M" \
  -tap \
  -r bilinear \
  -dstnodata -16 \
  -co TILED=YES \
  -co COMPRESS=DEFLATE \
  "$RAW" "$CROP"

gdalinfo -stats -json "$CROP" > /tmp/hfn-key-west-preview-info.json

echo "[key-west] encode HFN 16-bit source (-16..48 m)"
gdal_translate \
  -ot UInt16 \
  -of PNG \
  -scale -16 48 0 65535 \
  "$CROP" "$SOURCE_PNG"

python3 - "$SOURCE_JSON" "$REPORT" "$STEP_M" "$WEST" "$SOUTH" "$EAST" "$NORTH" <<'PY'
import json
import sys

out_json, report_json, step, west, south, east, north = sys.argv[1:]
step = float(step)
info = json.load(open("/tmp/hfn-key-west-preview-info.json", encoding="utf-8"))
width, height = info["size"]
gt = info["geoTransform"]
band = info["bands"][0]
span_x = (width - 1) * step
span_z = (height - 1) * step
meta = {
    "origin_x": -span_x * 0.5,
    "origin_z": -span_z * 0.5,
    "m_per_px": step,
    "height_min": -16.0,
    "height_max": 48.0,
    "sea_level": 0.0,
    "width": width,
    "height": height,
    "axes": "col -> +X east, row -> +Z south (Godot)",
    "source": "2016 NOAA NGS Topobathy Lidar DEM: Key West (FL), dataset 6366",
    "source_url": "https://coast.noaa.gov/htdata/raster2/elevation/NGS_FL_key_west_DEM_2016_6366/",
    "source_resolution_m": 1.0,
    "preview_resolution_m": step,
    "source_crs_wkt": info.get("coordinateSystem", {}).get("wkt", ""),
    "source_geotransform": gt,
    "source_crop_lonlat": {
        "west": float(west), "south": float(south),
        "east": float(east), "north": float(north),
    },
    "source_elevation_min_m": band.get("minimum"),
    "source_elevation_max_m": band.get("maximum"),
    "note": "Disposable Godot-first preview for issue #138. NOAA XY/Y remain un-authored; no Blender edits.",
}
with open(out_json, "w", encoding="utf-8") as f:
    json.dump(meta, f, indent=1)
with open(report_json, "w", encoding="utf-8") as f:
    json.dump(meta, f, indent=1)
print("[key-west] local bounds %.0f x %.0f m; %d x %d px" % (span_x, span_z, width, height))
print("[key-west] source elevation", band.get("minimum"), "..", band.get("maximum"), "m")
PY

echo "[key-west] ocean-connected mask (8 m/px, enclosed depressions excluded)"
python3 - "$SOURCE_PNG" "$OCEAN_MASK" "$REPORT" <<'PY'
import json
import sys
from collections import deque

import numpy as np
from PIL import Image

source_png, mask_png, report_json = sys.argv[1:]
grey = np.asarray(Image.open(source_png), dtype=np.uint16)
stride = 4
coarse = grey[::stride, ::stride]
sea_code = int(round((0.0 - (-16.0)) / 64.0 * 65535.0))
water = coarse <= sea_code
ocean = np.zeros(water.shape, dtype=np.uint8)
rows, cols = water.shape
queue = deque()

def seed(r, col):
    if 0 <= r < rows and 0 <= col < cols and water[r, col] and not ocean[r, col]:
        ocean[r, col] = 1
        queue.append((r, col))

for col in range(cols):
    seed(0, col)
    seed(rows - 1, col)
for r in range(rows):
    seed(r, 0)
    seed(r, cols - 1)

while queue:
    r, col = queue.popleft()
    seed(r - 1, col)
    seed(r + 1, col)
    seed(r, col - 1)
    seed(r, col + 1)

Image.fromarray(ocean * 255, mode="L").save(mask_png, optimize=True)
report = json.load(open(report_json, encoding="utf-8"))
report["ocean_mask_resolution_m"] = float(report["preview_resolution_m"]) * stride
report["ocean_mask_connected_pixels"] = int(ocean.sum())
report["ocean_mask_total_pixels"] = int(ocean.size)
with open(report_json, "w", encoding="utf-8") as handle:
    json.dump(report, handle, indent=1)
print("[key-west] ocean mask", cols, "x", rows, "connected=", int(ocean.sum()))
PY

PYTHONPATH=tools/world python3 tools/world/bake_terrain.py \
  --source "$SOURCE_PNG" \
  --meta "$SOURCE_JSON" \
  --out-png "$RUNTIME_PNG" \
  --out-json "$RUNTIME_JSON"

echo "[key-west] OpenStreetMap roads + building massing"
python3 tools/world/build_key_west_city_preview.py --report "$REPORT" --out "$CITY_JSON"

echo "[key-west] generated:"
ls -lh "$SOURCE_PNG" "$SOURCE_JSON" "$RUNTIME_PNG" "$RUNTIME_JSON" "$OCEAN_MASK" "$CITY_JSON" "$REPORT"
