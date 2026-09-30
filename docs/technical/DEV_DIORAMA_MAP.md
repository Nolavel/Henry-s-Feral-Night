# Developer Diorama Map

The developer map is a debug-only live second camera over the production world.
It removes itself from release builds and does not own gameplay or streaming
state.

## Placement

- Upper-left corner.
- 500 × 320 px panel with a 20 px screen margin.
- Perspective camera, 36° FOV, 30 m default height.
- 64° downward pitch with a 12° yaw offset. The trapezoid comes from the real
  perspective camera; the viewport texture is not distorted.

## Modes

- **FOLLOW** — smoothly follows Henry.
- **FREE** — keeps an independent world focus; dragging the map enters this mode.
- **RECENTERING** — a short transition used by CENTER, then returns to FOLLOW.

Mouse wheel changes height between 18 and 60 m. The gold dot shows Henry when
he is visible in the map camera.

The SubViewport shares the parent World3D, so terrain, weather, snow, city
streaming and live world changes are the same objects the TPS camera sees.

## Preview

`tools/runtime/capture_dev_diorama_map.gd` captures the on-screen placement and
map-only frames for all three states. The existing `checks.yml` workflow has a
small `[dev-map-preview]` job that uploads those PNGs without invoking the
Key West GIS/Overture preview pipeline.
