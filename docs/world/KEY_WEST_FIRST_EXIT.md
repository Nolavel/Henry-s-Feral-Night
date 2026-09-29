# Key West First Exit — Whitehead Spit → Fort Street

The experimental `key_west_test` profile owns the new gameplay start.

- Bunker/spawn: Whitehead Spit, local NOAA frame **(-3452.88, 2273.84)**.
- First shelter: real OSM footprint beside **Fort Street**, local
  **(-3551.61, 1567.72)** (preview building 10453, about 81.5 m²).
- Separation is about **713 m**.
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
148 city chunks register into that same lifecycle; Graciosa remains the default
when `HFN_WORLD` is unset.

Build the documented NOAA/OSM preview assets, then launch:

```bash
HFN_WORLD=key_west_test godot --path .
```

Validation/capture extends the existing checks workflow; no second CI pipeline
is introduced.
