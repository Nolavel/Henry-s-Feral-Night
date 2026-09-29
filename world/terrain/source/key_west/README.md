# Key West terrain source

Status: **source manifest only; no NOAA raster has been committed yet.**

Target dataset for issue #138:

- NOAA / NGS 2016 Key West topobathymetric LiDAR DEM.
- Bare-earth/topobathy terrain is required; buildings and vegetation must not
  be baked into the HFN ground heightmap.
- First geographic scope: Key West, Fleming Key, Wisteria Island, Sunset Key,
  Stock Island, and the intervening water/shallow bathymetry.
- First Godot import keeps real XY scale and real elevation values.

The raw upstream raster is intentionally not stored here until size, exact
download selection, coordinate reference system, vertical datum, attribution
and redistribution terms have been recorded. The converter must produce a
reproducible 16-bit HFN heightmap plus JSON metadata from that documented source.

Do not edit the upstream DEM in Blender. Any later Blender pass happens only
after the Godot review gate and must be represented as authored HFN changes on
top of the preserved NOAA base.


## First verified Godot preview — 2026-09-29

The first NOAA → HFN → Godot proof completed successfully in Actions run
`36514874180` on `codex`.

Verified preview crop:
- lon/lat: west -81.835, south 24.535, east -81.705, north 24.595;
- derived preview resolution: 2 m/px;
- local Godot bounds: about **13.20 × 6.57 km**;
- raster: 6602 × 3286 px;
- source mosaic reports **EPSG:32617 (WGS 84 / UTM zone 17N)**;
- measured crop elevation range: -8.192 m to 28.526 m;
- sea level in HFN remains 0 m;
- no Blender edits or vertical exaggeration were applied.

The 2 m preview is disposable and exists to judge geography/performance before
committing a production dataset. The NOAA master remains the 1 m source of truth.
The high maximum value is recorded as source data, not interpreted as natural
ground height until infrastructure/outliers are audited.

Godot captures produced:
1. whole-cluster top view;
2. closer Key West top view;
3. oblique cluster view;
4. low coast-scale view.

The terrain loader was also hardened to read the packed LA8 PNG bytes directly
as an `Image`, bypassing Texture2D import/compression settings.


## Stage 4 verified Godot massing — 2026-09-29

Successful preview run: `36520195465` on `codex`.

Visual/data result:
- NOAA terrain remains unchanged; no Blender pass and no vertical exaggeration.
- Ice is no longer a raised full plane. It is rendered 0.04 m below sea level
  and masked to **ocean-connected** cells derived from the DEM, so enclosed
  below-zero terrain does not become fake inland ponds/lakes.
- Ocean mask preview resolution: 8 m/px.
- OpenStreetMap preview import: **12,354 building footprints** and
  **2,681 road ways** / **15,511 road points**.
- Building footprints are represented by one lightweight oriented box each and
  rendered through one MultiMesh for the geography proof.
- Roads are rendered as one combined terrain-draped ribbon mesh.
- OSM preview attribution is included in captures:
  `© OpenStreetMap contributors — ODbL`.
- Four Godot captures passed: cluster top, Key West top, oblique, and low coast.

The Stage 4 assets are still disposable preview outputs. They prove scale,
coverage and spatial rhythm; they are not final production buildings or roads.
