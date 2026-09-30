# Key West First Exit — Whitehead Spit → Fort Street

The main scene `scenes/world/key_west/key_west.tscn` pins the `key_west_test`
profile and owns the default F5 gameplay start.

- Bunker/spawn: Whitehead Spit, local NOAA frame **(-3452.88, 2273.84)**.
- First shelter: a vacant **Fort Street** lot, house origin local
  **(-3579.85, 1574.51)**, yaw **126.76°**, porch facing the street. The lot was
  chosen from the city data: no OSM building and no road inside the fenced
  yard (checked by `test_key_west_first_exit.gd`), so no real house is removed.
- The house is seated by its stair foot: ground there meets the bottom stair,
  an invisible ~10° ramp over the steps lets Henry walk onto the veranda, and a
  dark plinth fills down to the lowest ground under the floor.
- Separation is about **710 m**.
- The production First Exit shelter is reused: repairable windows, operable
  door, stove, sleep/rest content, hammer/nails/boards, food/water and pickups.
- Bunker bedroll + road flare stay at the start. Shelter supplies preserve exact
  placement; old route loot is compressed into the final Fort Street approach.
- No waypoint is added.

Key West starts directly in the existing `blizzard` profile. Sustained wind
is pinned to **8°**, Whitehead toward Fort Street, while gusts/jitter remain.
World initialization happens before the first visible frame for this profile.
SnowfallVFX already preprocesses its GPU layers for 2 seconds; the local
HeightField and WorldAudioBinder reuse the same authoritative weather values.

Key West uses the existing StreamingSystem in runtime-only mode. Its generated
148 city chunks register into that same lifecycle. Production city/mask data
are committed under `data/world/key_west/`; the frozen snapshot and its hashes
are recorded in `source_receipt.json`. NOAA terrain is committed under
`world/terrain/`, with its derived source and provenance in `source/key_west/`.

Launch with F5 or:

```bash
godot --path .
```

The scene contains the player, TPS camera, IslandTerrain, environment and title
card, and reuses the shared First Exit content through its profile. It does not
instantiate the archived Graciosa scene. Graciosa is retained with its authored
terrain and streaming data under `archive/graciosa/` and has its own pinned
profile for direct F6 launches. Test scenes keep their existing isolated defaults.

Validation/capture extends the existing checks workflow; no second CI pipeline
is introduced.

## Shelter start toggle

On the main scene's `World` root, enable **Spawn At Shelter** (`spawn_at_shelter`)
to start 2.5 m in front of the Fort Street shelter's porch steps, facing the
door. Disable it (the default) for the Whitehead bunker
scenario. Both modes retain the same initial blizzard and streaming lifecycle.
Continue still restores the saved position through the existing save system.
