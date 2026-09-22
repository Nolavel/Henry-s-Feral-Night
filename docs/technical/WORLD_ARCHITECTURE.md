# World architecture — what was taken from ADT, and why

Source: `Nolavel/ADT` @ `main`, read 2026-09-22. Its own `ARCHITECTURE.md` is
the best document in either project; this one records what crossed over.

---

## 1. The composition root

`world/world.gd` is now the one place systems are created and wired, and
**it does not grow as systems are added**. Three declarative lists say what
exists; the loops that build them are fixed.

```
WORLD_SYSTEM_SCRIPTS    Node classes via .new(),      parent: World
WORLD_3D_ENTITY_SCENES  .tscn via instantiate(),      parent: StreamContainer
WORLD_UI_SCENES         Control scenes,               parent: a CanvasLayer
```

Three lists rather than one, because the three categories are constructed
differently and parented differently. Adding anything is **one line**.

The island scene (`experimental_location/scenes/Graciosa_Island_Terrain.tscn`)
carries this script now; its root is `World` and it has a `StreamContainer`.
The old `GameRouter.gd` did one job — move the player onto a marker and free it
— and that job is `_place_player()` here.

## 2. `on_world_ready(context)` — the duck-typed lifecycle

Anything in those lists, plus the player, may implement:

```gdscript
func on_world_ready(context: WorldContext) -> void:
```

If the method exists it is called once, after the player, camera and every
system exist. If not, the node is skipped silently. No base class, no
registration step — `world.gd` checks `has_method()` and moves on.

`WorldContext` is a plain `RefCounted` holding `player`, `camera`,
`stream_container` and the live systems, with `get_system(SomeClass)` for the
case where a scene needs one specific system.

**This is the "almost DI" worth having.** Systems stop being hand-wired through
`@export` NodePaths in the scene, which is what every survival system here was
doing. `WeatherController` now finds the day/night clock and loads its profiles
in `on_world_ready` instead of waiting for someone to fill three exports.

The cost, and ADT states it plainly: **the dependency is invisible to static
analysis.** You cannot find it by searching for callers. That trade is
deliberate, and it is the reason this file documents it.

## 3. The save contract — converged, not reinvented

Our save system predates reading ADT and had arrived at nearly the same shape.
Where they differed, **ADT's version won**, because two codebases with the same
author should not disagree about this:

| | Before | Now |
|---|---|---|
| Key method | `save_id()` | **`get_save_key()`** |
| Partial implementation | accepted | **skipped, all-or-nothing** |
| Unknown version | passed through with a warning | **refused outright, nothing applied** |

The version rule is the important one. A half-applied save from a future build
is worse than a refused one, and ADT's note is exactly right: *a save format
without a version field is a migration problem that can never be fixed
retroactively*. Ours has carried `version` from its first commit; it now also
refuses what it cannot recognise.

`get_save_key()` over a class name exists so renaming a script never orphans a
save file.

## 4. Input — one reader, edges from events

`core/input/input_systems.gd` is an autoload and **the only file that reads
`Input` directly**. It holds no game logic: it does not decide what a press
means, it relays.

Two rules came straight from ADT's postmortems:

- **Edges come from events, levels come from polls.** A press or release is
  matched on the `InputEvent` in `_unhandled_input()`; held state and axes are
  polled in `_physics_process()`. **No `Input.is_action_just_pressed()`
  anywhere** — polling an edge from the physics frame drops presses the moment
  the idle and physics rates diverge. A query that must stay a poll is answered
  from this file's own latch.
- **One writer.** A second reader means two places decide what is pressed, and
  they will disagree on the frame it matters.

The sleep hold is relayed as three edges plus a duration. The relay never says
"that was a hold" — the one-second threshold belongs to `SleepPrompt`.

## 5. Naming, adopted

ADT's distinction, which this project does not currently follow:

- **Component** — attached to one owner entity (`StaminaComponent`)
- **Manager** — owns a collection of instances
- **System** — a single cross-cutting orchestrator

By that rule `BioMonitorManager`, `StaminaManager` and `InventoryManager` are
all **Components**: each is attached to Henry and owns no collection of
instances. `ThermalManager` is the same. Renaming them is a mechanical commit
that touches scenes as well as scripts, so it is **not** done here — it is
recorded so the next person does not add a fourth wrong name.

## 6. What was deliberately NOT ported

**The streaming pipeline.** ADT's is genuinely good — two rings, a cell state
machine with hysteresis, threaded loads budgeted at 2 concurrent and **1
instantiation per frame**, scanning no more than once per 50 m travelled. Ours
(`experimental_location/scripts/WorldStreamManager.gd`, 558 lines) already has
preload / activate / unload with hysteresis and an unload delay, so it is not
starting from nothing.

The gap is the one `AGENTS.md` already names: **`CHUNK_DEFINITIONS` is a
hardcoded dictionary**, one entry per chunk, exactly the "one `@onready` and one
`match` arm per chunk" the rules forbid. ADT solves this with
`WorldData`/`BlockData` resources exported from a `map_source` scene — layout is
data, not code.

The port is bounded and concrete:

1. `WorldData` / `ChunkData` resources mirroring `BlockData`
   (`id`, `position`, `silhouette_scene_path`, `content_scene_path`).
2. A generator that reads the existing `locations_data.json` polygons and writes
   `data/world_data.tres`, so nothing is re-authored by hand.
3. `WorldStreamManager` reads the resource; `CHUNK_DEFINITIONS` and
   `LOCATION_AREAS` are deleted.
4. Ring 0 silhouettes with permanent collision, so a chunk swap can never drop
   the floor out from under the player.

It was left out of this pass because doing it half way is worse than not
starting: the generator and the rewrite land together or not at all.

**Autoloads.** ADT holds a closed set of four and requires discussion to add a
fifth. This project had **none**; `InputSystems` is the first, and it is the
kind that earns it — a global relay with no state of its own. The same rule
applies from here: a new autoload needs an argument, not a convenience.

## 7. Two Godot traps this pass confirmed

Both were already costing debugging rounds in this project before ADT was read,
and both are the same underlying fact — **the scene tree is not ready during
`_initialize()` or before the first frame**:

- `_ready()` has not run, so anything constructed headlessly is uninitialised.
  Every system here has a public `initialize()` for that reason.
- `global_position` reads as zero and `get_tree()` returns null. The
  composition-root test now runs from the first frame rather than from
  `_initialize()`, which is also how the game actually runs.

`WeatherController._find_day_night_manager()` guards `get_tree()` for the same
reason.
