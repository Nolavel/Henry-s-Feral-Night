# Ported from ADT

Source: `Nolavel/ADT` — *Vertical Trespass* / *Another Digital Thriller*.

ADT's licence reserves all rights and forbids reuse of its source in another
project **without prior written permission from the copyright holder**. Both
projects are owned by the same copyright holder, who granted that permission on
2026-09-23. See `docs/THIRD_PARTY_NOTICES.md`.

This file records what crossed over, what was dropped on the way, and what was
added that ADT does not have. It is not a changelog — it is the answer to "why
does this look like the other project".

---

## Why port rather than write

The two codebases are almost perfectly complementary. ADT has no temperature,
no weather, no ice and no hunger; this project had no items, no equipment, no
working interaction and no player state. ADT supplies the **body and
interaction**; this project supplies the **environment and simulation**.

## What came across

| ADT | Here | Changed |
|---|---|---|
| `core/player_state/player_state.gd` | `core/player_state/player_state.gd` | Modes replaced with this game's (`ON_FOOT`, `WORKING`, `SWIMMING`, `SLEEPING`, `MENU`); `ViewMode` and `Stance` dropped |
| interact claim in `core/input/input_systems.gd` | same file here | unchanged in substance |
| `core/items/item_traits.gd` | same | **`Readability` dropped** |
| `core/items/garment_data.gd` | same | **`insulation_c` added** |
| `core/items/item_resource.gd` | same | ranged group, held mesh/fit, throwing, readability dropped; `consumable` added |
| `core/items/item_catalog.gd` | same | unchanged |
| `core/equipment/equipment_slot_definition.gd` | same | `refuses_threatening` → `excluded_from_auto_stow` |
| `core/equipment/equipment_layout.gd` | same | unchanged |
| `player/.../equipment_component.gd` | `scripts/actors/player/henry/components/` | draw/holster dropped; `get_total_insulation_c()` added |
| `player/.../inventory_component.gd` | same directory | `try_remove`, `get_count`, and the save contract added |
| `player/.../interact_component.gd` | `scripts/actors/player/henry/components/interact_component.gd` | targets `InteractiveArea` instead of `InteractableObject`; carry/throw, vehicle and HoldPrompt dropped; focus hits must lie ahead |
| `ui/widgets/dynamic_cursor/dynamic_cursor_ui.gd` | `scripts/ui/hud/dynamic_cursor/mouse_cursor_ui.gd` | ring only: weapon brackets, morph and 3D-UI brackets dropped |
| `camera/camera_component/on_foot_camera_component.gd`, `tps_shoulder_camera_state.gd` | `scripts/systems/camera/tps_camera.gd`, `tps_shoulder_state.gd` | view toggle, lock-on and aim dropped; adaptive boom (rods) added |

### Rules carried across verbatim, because they are the point

- **Body slots are fixed; pockets belong to the garment.** Take the coat off and
  its pockets, and their contents, go with it. Slot count is a property of
  clothing, not of the character, which is what makes clothing replaceable.
- **`equip()` into an occupied slot refuses rather than swapping.** A component
  that knows nothing about the inventory could only drop what it displaced.
- **`unequip()` refuses while the garment's own pockets hold anything.**
- **Item ids are stored, never `ItemResource` references** — the save contract
  carries primitives, arrays and dictionaries, and does not widen to
  accommodate a system that cannot express itself that way.
- **`load_save_data()` restores body slots before pockets** (a pocket exists
  only while its garment is worn) and re-validates every id against the layout
  and the catalog rather than trusting the file.
- **The catalog loads by path, never by scanning the directory.** An exported
  build converts `.tres` to binary behind a `.remap`, and a runtime `DirAccess`
  scan finds nothing. This is the difference between working in the editor and
  working in a build.
- **MENU is reachable only through `open_menu()`/`close_menu()`**, and pause is
  set before the signal fires.

## What was dropped, and why

**`Readability`** (`CONCEALABLE / ORDINARY / THREATENING`) is ADT's social axis:
how an item reads to someone looking at the player. It exists there for crowd
reaction and Iris Access. This game has no observers and, per the direction
agreed in issue #4, is not getting a threat taxonomy. Carrying the field across
would have meant a dead enum that someone later tries to make sense of.

Its one mechanical role here was deciding which back slot an automatic stow may
use. That role is kept under an honest name: `excluded_from_auto_stow`, which
Kenny's fixture carries. What rides there is a decision Henry makes, never where
the game drops spare weight.

**Weapons** — the ranged group, held meshes and `HeldFit` — went with combat,
which is out of the vertical slice.

## What was added that ADT does not have

**`GarmentData.insulation_c`** and **`EquipmentComponent.get_total_insulation_c()`**.

ADT's garments carry **no stats at all**. Here, `ThermalManager` reads the sum
of what is worn on the body — pockets do not count, since a tin in a pocket
keeps nobody warm — and falls back to its exported `clothing_insulation_c` when
no equipment component is wired, so every pre-existing test kept passing
unchanged.

Fully dressed is about 11 °C of insulation against the old flat 6 °C, and a test
asserts that a dressed Henry cools measurably slower than a bare one, and that
taking the coat off is felt immediately rather than at the next save.

**`ConsumableData`** — the edible facet, mapping onto `BioMonitorManager`'s
three tracks so eating is one call rather than a special case per item. It also
carries `body_heat_cost_c`, because eating snow for water should cost heat.

## Deliberately not built yet

- **Per-limb insulation.** A hat and boots do not warm the same way a coat does,
  but the thermal model has one body temperature. Two axes before the first is
  tuned is guessing.
- **Per-garment wetness.** Wetness is global on `ThermalManager`. Moving it onto
  the garment means per-item state in the save, and is worth doing only once
  drying is a real activity.
- **Encumbrance affecting movement.** Weight gates what the inventory accepts;
  it does not slow Henry down. A limit the player can feel comes before a
  penalty they cannot see the shape of.
- **An equipment UI.** Neither project has one.


## ADT KeyHintsPanel → HFN production controls blot

- ADT source: `ui/hud/player_hud/key_hints_panel.gd/.tscn`,
  `key_hint_entry.gd`, `key_hints_catalog.gd`,
  `data/key_hints.tres`, and `vfx/shaders/key_hints_blot.gdshader`.
- HFN keeps the lower-right placement, key-cap styling, ink shader constants and
  ink→text / text→ink choreography. The catalog is rewritten for HFN's real
  InputMap and PlayerState plus Hub/Rest component state; no parallel player
  state or second input manager was added.
- ADT's BlackRock font is deliberately NOT copied: ADT marks it as a
  project-only asset not for redistribution. HFN therefore uses its own project
  font for prose while preserving ADT's monospace key caps.


## ADT HoldPrompt → HFN ActionPrompt3D

- ADT source: `ui/widgets/hold_prompt/hold_prompt.gd/.tscn`.
- HFN keeps the load-bearing production shape: a Control rendered into a
  SubViewport, carried by a billboarded Sprite3D in world space, always on top,
  rising from the target rather than living as a fixed screen tooltip.
- HFN intentionally does not copy the entire F→circle→dot hold mechanic because
  First Exit's current world interactions are press/approach actions, not a
  generic hold contract. Instead the plate gives a short press pulse after the
  real `interaction_performed` signal.
- HFN deliberately has no enclosing rectangular banner. The same eight-blob
  shader as ADT KeyHints is the entire backing: blobs assemble first, then the
  key/action/detail fade in; on target loss the content fades out first and the
  blobs dissolve second.
- A real interaction press briefly warms the key fill toward yellow as an
  acknowledgement, then runs the same content-out -> ink-out sequence. The
  prompt stays suppressed for that same target until focus is reacquired.
- Action text comes from `InteractiveArea._get_interaction_text()`, so doors,
  pickups and other targets remain the source of truth.
