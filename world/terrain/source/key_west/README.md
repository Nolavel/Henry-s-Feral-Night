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
