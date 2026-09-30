# Key West runtime snapshot

These are the frozen city, visual enrichment and ocean-connectivity data used by
`scenes/world/key_west/key_west.tscn`. They were recovered unchanged from the
verified First Exit Actions run `36574726378` at commit
`968def1a0fb883c871d36718c597c09972ae4b23`.

`source_receipt.json` records the artifact digest and individual file hashes.
`source_report.json` preserves the shared NOAA crop frame, so terrain, city,
ocean mask and gameplay anchors use the same coordinates. The derived heightmap
and upstream DEM receipt live under `world/terrain/source/key_west/`.

City geometry includes 12,354 OpenStreetMap building footprints, 2,681 roads
and 148 content chunks. OpenStreetMap attribution remains in the city payload
and rendering: OpenStreetMap contributors, ODbL. Visual enrichment retains its
Overture source metadata. These proxy buildings remain prototype content.

The files are committed for offline startup. The existing builders under
`tools/world/` produce candidate previews; promoting another snapshot requires
updating these files and their receipt together.
