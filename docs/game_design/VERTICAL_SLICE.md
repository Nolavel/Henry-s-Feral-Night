# Vertical slice — First Exit A: One Land Night

Status: **current production target; live candidate awaiting a stranger run**, updated 2026-09-28.
Reference: *The Long Dark* for survival decision pressure; *The Road* for tone.

This document is the current scope contract for the first playable slice.
World coordinates, route lengths and authored placement live in
`docs/world/FIRST_EXIT.md` and `data/world/first_exit_layout.json`.

## 1. Split: A now, B later

The old "One Night on the Ice" target has been split.

### A — First Exit: land night

The current milestone is one uninterrupted land survival run on Graciosa:

```
bunker exit
  -> choose road / exposed shore / ruins
  -> collect scarce boards, tinder, fuel and food
  -> weather worsens and changes the return decision
  -> reach the suburb shelter
  -> choose which breaches to board (4 windows; placement quality matters)
  -> light and feed the stove
  -> recover / dry
  -> sleep -> save
```

There is **no inland lagoon and no thin-ice route in A**.

The historical scarcity target is 15 boards / 30 nails. For the current live
candidate the author explicitly retains all existing supplies: 33 boards,
66 nails, 12 logs, both starter kits and the shelter bonus stacks. This run
checks the complete interaction loop; it does not validate the reduced-stock
balance. Do not silently remove these supplies when regenerating the scene.

### B — Coast / Thin Ice

Coastal ice is a later slice built on real maritime geography: shore-fast ice,
shoals, frozen straits, small offshore islets/atolls and ice-locked ships.

The ice simulation already exists in the codebase, but `IceField` is not in
the current `world.gd` runtime system list and is not instantiated by the
Graciosa First Exit scene. That separation is intentional.

## 2. Player fantasy

Henry has been expelled from a bunker into a frozen version of a formerly
tropical island. He is inexperienced, exposed and running out of safe time.
The first problem is not combat. It is whether he can read the landscape,
carry enough useful material, prepare one bad house for the night and survive
the weather change.

Kenny is strapped to Henry's backpack during Act I. He has no battery and no
active abilities; his weight is part of what Henry chooses to keep carrying.

## 3. What already exists in production

- Graciosa runs on `IslandTerrain` built from the heightmap source.
- First Exit is a data-driven suburb/route blockout with resolved coordinates.
- Land routes are measured at human walk speed:
  road about 4.8 min, shore about 5.5 min, ruins about 5.7 min.
- Thermal model: ambient cold, wind chill, shelter, wetness and heat.
- Weather profiles: calm, snowfall, windy and blizzard.
- Hunger, thirst, energy and carry-weight pressure.
- First Exit shelter: four repairable windows and an operable door, carried-board placement, stove and mattress.
- Route and shelter pickups are authored and tested; current quantities are
  recorded above and in FIRST_EXIT.
- Shelter state persists boarded breaches and stove fuel.
- Sleep is contextual through `F` and sleeping saves.
- Field bedroll exists and persists while laid out.
- Weather profile and remaining duration persist.
- Kenny is visible on the pack and contributes weight.
- Henry has skinned cold-weather clothing with wetness darkening.
- Carry/work animations, cabinet interaction and breach kneeling are wired.
- Held road flare is integrated with hand pose, light, sparks, smoke and wind.
- Player Hub foundation exists: pack opens on Henry; real garment pockets are
  Quick Access zones; items can move pack <-> pocket without duplication.
- Quick Access draws physical tools, a finite flask and food tins. Pineapple
  opens with an owned knife before eating; carried wood can be put down with G.
- WeatherBeat requests the existing WeatherController's blizzard transition
  after 200 m from the bunker or a 300-second fallback. Shelter defers the beat;
  after the 180-second blizzard the route becomes windy. The beat state saves.
- The pickup ledger preserves consumed authored loot across save/load; loose
  wood and its contents restore without duplication.

## 4. Remaining A blockers

### Implemented — authored weather turn; live decision pressure unverified

WeatherBeat already uses WeatherController as the sole weather authority.
Focused tests cover its triggers and persistence. The remaining proof is whether
the actual route/weather timing changes a new player's decision.

Acceptance: during a normal 10–15 minute run, worsening wind/snow makes the
return leg materially colder and forces the player to reconsider time, route
or supplies.

### Implemented — save closure for world pickups; continuous run unverified

Inventory, equipment, weather, shelter, laid bedroll and consumed world pickups
persist. Focused tests cover the pickup ledger; the stranger run must still
confirm the complete sleep/save/reload sequence in the actual island scene.

Acceptance: pick up authored First Exit loot -> sleep/save -> reload -> the
same world pickup stays gone while the inventory result remains correct.

### P0 — one continuous stranger playtest

The proof is the real Graciosa scene, not TestScene and not debug teleporting.

Required path:
1. start at the bunker;
2. understand at least two route choices without a map;
3. find, carry and use supplies; record whether the retained stock erases choice;
4. experience the weather turn;
5. reach the shelter;
6. board a subset of the four repairable windows;
7. light/feed the stove;
8. sleep and save;
9. reload into a coherent world state.

If a required step needs a debug teleport or console repair, it is still an A
blocker.

## 5. Readability / P1 quality pass

These improve the slice but should not grow into new subsystem work before the
P0 loop closes:

- verify the bus/van/beach wreck silhouettes at 40–60 m;
- verify Kenny reads as a carried robot-bear mass from rear and 3/4 views;
- add a minimal route audio bed driven by existing exposure/weather concepts;
- capture a fixed publisher proof set after the continuous playtest passes.

Prefer scale, pose, spacing and audio routing over a texture-heavy art pass.

## 6. First Exit A is done when

1. A new player can go bunker -> shelter -> sleep/save in roughly 10–15 min.
2. The player can make a bad decision around time, greed or weather and
   understand why it hurt.
3. Road, shore and ruins read as different land routes without a map.
4. Shelter preparation is a sequence of choices, not an automatic safe room.
5. Sleep/load restores a coherent world: shelter/fuel/weather/bedroll and
   consumed route loot agree.
6. README, this document and FIRST_EXIT describe the same scope.
7. Thin ice neither blocks the run nor appears as a promised route in A.

## 7. Explicitly out of A

- coastal thin-ice geography and its presentation chain;
- combat and enemies;
- radiation gameplay;
- active Kenny/Gizmo abilities;
- large crafting trees;
- full wardrobe/fashion systems;
- heavy snow deformation;
- island expansion beyond what the First Exit route needs.

Those may become later milestones. They are not reasons to delay closing the
land-night slice.
