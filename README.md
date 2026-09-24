# Henry's Feral Night

Third-person survival in the endless cold. A tropical island has frozen over;
Henry has to get from the bunker he woke in to a house he can hold through the
night: find fuel, board the windows, keep the stove burning, and stay dry.

Solo project, in active development. A prototype, not a shipping game.

**Engine:** Godot **4.8-dev6 .NET** · Forward+ (Vulkan) · GDScript
**Status:** vertical slice in progress — *First Exit*, the first route from
the bunker to the shelter on Graciosa.

> Сурвайвал от третьего лица в замёрзшем мире. Соло-проект в активной
> разработке, прототип. Движок Godot 4.8-dev6 .NET.

## What is in

- **World:** Graciosa as a heightmap-built island (`IslandTerrain`, LOD chunks,
  collision near the player) with the First Exit blockout: roads, lots,
  houses, the shelter, bunkers, frozen palms, wrecks. Routes and distances in
  `docs/world/FIRST_EXIT.md`.
- **Survival:** thermal model (body heat, wetness, wind, shelter zones, heat
  sources), hunger/thirst/energy, sleep with time skip, sea ice that breaks
  under load and cold-water immersion.
- **Shelter loop:** pick up boards, firewood and tinder; board breaches; light
  and feed the stove; sleep; save.
- **Henry:** UAL animation set on a runtime AnimationTree (locomotion, crouch,
  jump, carry, work actions), clothes built in Blender as skinned meshes,
  inventory and equipment, the backpack and Kenny.
- **Tech:** world composition root, streaming, SoundSystem autoload, weather,
  snow cover and footprints, atomic save slots, 29 headless test suites.

Not in yet: coastal ice route content, weather turn on the route, route audio,
held light sources in hand (#57), enemies.

## Run

Main scene: **`experimental_location/scenes/Graciosa_Island_Terrain.tscn`**
(set as `run/main_scene`). Henry starts at the bunker door.
Systems test scene: `tests/scenes/TestScene.tscn`.

```bash
tools/ci/setup_env.sh              # Godot 4.8-dev6 mono into ~/.local
godot --headless --import --quit   # first import
tools/ci/run_tests.sh              # all headless suites
tools/ci/render.sh res://tests/scenes/TestScene.tscn   # one frame, CPU (lavapipe)
```

## Controls

`project.godot` is the source of truth; CI rejects two actions on one key
unless `tools/ci/input_overlap_allowlist.txt` says why that is safe.

| Key | Action |
|---|---|
| `W A S D` | move (camera-relative) |
| `Shift` / `Space` / `C` | sprint / jump / crouch |
| `F` | interact: pick up, board up, feed the stove, open |
| `Q` / `E` | lean left / right |
| `Z` | switch camera shoulder |
| `,` / `.` | orbit the camera |
| `L` | flashlight |
| `Esc` | pause |
| `F` on a bed or mattress | sleep: wheel or `←` `→` hours, `F`/`Enter` sleep, `Esc` cancel |
| `L` | light a road flare / drop it |
| `Tab` | Player Hub: the pack opens on Henry's back; move items between the pack and pockets. `Tab`/`Esc` closes |
| `B` | lay the bedroll (until the inventory has Use); `F` on it sleeps, `F` at its head rolls it up |

## Layout

| Path | Purpose |
|---|---|
| `core/` | Autoloads and shared types: player state, input, audio, items, equipment |
| `scripts/` | Gameplay: actors, systems (survival, ice, weather, camera), environment, UI |
| `scenes/` | Player, UI and the generated First Exit blockout |
| `world/` | World composition root, streaming, terrain source and runtime |
| `data/` | Items, catalog, layouts (`data/world/first_exit_layout.json`) |
| `assets/` | Models, animations (UAL), textures, fonts, the Henry outfit GLB |
| `shaders/` | Terrain, snow, sky, VFX |
| `tools/` | CI scripts, Blender pipelines, world builders, capture tools |
| `tests/` | Headless suites (`tests/systems/`) and the systems test scene |
| `docs/` | Technical specs, world docs, art renders, third-party notices |

## Documentation

- `docs/technical/` — world architecture, thermal model, ice, snow cover, save
  system, audio, what was ported from ADT.
- `docs/world/` — First Exit route and metrics, terrain heightmap pipeline.
- `CHANGELOG.md` — every change, newest first.

## For collaborators

This codebase is developed by the author with two LLM coding agents: Claude
Code (technical direction, CI, systems — branch `claudeflow`) and Codex
(implementation passes — branch `codex`). `AGENTS.md` is the shared rulebook
for branches and conduct; `CLAUDE.md` is Claude's working brief. Agents merge
`main` into their own branch freely; nothing reaches `main` without the
author. Coordination happens in GitHub issues (#1 for handoffs).

Code comments are English, `##` doc style. Some older files still carry
Russian comments; they are translated when those files are next touched.

## Licence and credits

Copyright © 2025–2026 Nolavel. All rights reserved — **not open source**; see
[`LICENSE`](LICENSE) for what you may and may not do. Third-party components
(Godot, fonts, animation library, sounds) are credited with their own licences
in [`docs/THIRD_PARTY_NOTICES.md`](docs/THIRD_PARTY_NOTICES.md); keep that file
current in the same commit that adds an asset.
