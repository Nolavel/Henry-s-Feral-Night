# Save system — architecture

Status: **implemented** (`scripts/systems/save/`)
Tests: `tests/systems/test_save_system.gd` — run via `tools/ci/run_tests.sh`

---

## 1. Why this shape

The GDD states one rule: **you save by sleeping, and only by sleeping.** That is
a design pillar, so the save system is built around the sleep verb rather than
around a menu button. `SaveManager` knows how to persist; `SleepController` owns
the only condition under which it is allowed to.

Nothing else calls `save_to_slot()` during play.

## 2. The participant contract

A system takes part in saving by implementing three methods — the convention
`DayNightManager` already established:

```gdscript
func save_id() -> StringName      # optional; falls back to the node name
func get_save_data() -> Dictionary
func load_save_data(data: Dictionary) -> void
```

It then joins in one of two ways:

- **Explicit registration** — `save_manager.register(self)` from `_ready()`.
  Deterministic, and the right default for anything that must be saved.
- **Group membership** — join `"saveable"`. Convenient for scene-authored
  objects, but it only works once the tree has settled.

Registration exists because the group route has a real failure mode: during the
first frame, and in headless tools, `get_nodes_in_group()` returns nothing. That
is exactly how the save system's own tests first failed.

Currently participating: `ThermalManager` (body temperature, wetness, death),
`WeatherController` (active profile and its remaining duration). `DayNightManager`
already satisfies the contract and only needs adding to the group in the scene.

## 3. Failure modes, and what each one does

A save system is judged entirely by how it behaves when things go wrong.

| Situation | Behaviour |
|---|---|
| **No participants** | **Refuses to write.** A save containing nothing is the worst possible outcome — the player believes they are safe. Fails loudly with a reason. |
| **Two participants claim one id** | Refuses to write; the previous save in that slot is left untouched. |
| **A participant returns a non-Dictionary** | Refuses to write, naming the participant. |
| **Crash mid-write** | Impossible to corrupt the slot: the payload is written to `slot_N.json.tmp` and only then renamed over the real file. |
| **Corrupt file on disk** | `read_slot()` returns empty, `load_from_slot()` returns false, and `list_slots()` reports the slot with `corrupt = true` rather than hiding it — the player is told their save is damaged instead of it silently vanishing. |
| **Empty / missing slot** | Reported as empty, never as an error state. |
| **Save from a newer build** | Passed through with a warning rather than mangled by a downgrade migration. |

Every failure sets a human-readable reason retrievable via `get_last_error()`
and emits `save_failed` / `load_failed` for the UI.

## 4. Format

`user://saves/slot_N.json`, plain JSON so a save can be inspected and diffed
while the game is in development:

```json
{
  "version": 1,
  "saved_at_unix": 1790000000,
  "metadata": { "day": 3, "hour": 6.2, "slept_hours": 8.0, "body_temp_c": 36.6 },
  "payload": {
    "thermal": { "body_temp_c": 36.6, "wetness": 0.0, "is_dead": false },
    "weather": { "profile_id": "snowfall", "remaining_h": 2.4 }
  }
}
```

`metadata` is deliberately separate from `payload`: a load menu can list every
slot without deserialising game systems. `version` drives `_migrate()`, which is
a real seam, not a placeholder — the layout will change.

Slot 0 is the sleep autosave (`SaveManager.SLEEP_SLOT`); slots 1..`max_slot` are
available for manual or debug saves.

Binary format is a later optimisation, and only once the payload is large enough
to matter. Readability is worth more than bytes right now.

## 5. Sleeping

`SleepController.can_sleep()` returns a `Refusal`, never a bare bool, so the HUD
can say *why*:

| Refusal | Condition |
|---|---|
| `NOT_SHELTERED` | Not inside an interior `ThermalZone`. A tarp is not a bedroom. |
| `TOO_COLD` | Felt temperature below `minimum_felt_temp_c` (5 °C). Warm enough to survive is not warm enough to sleep. |
| `TOO_ALERT` | Energy above `maximum_energy_to_sleep`; Henry is not tired. |
| `ALREADY_SLEEPING` | Reentrancy guard. |

`describe_refusal()` returns localisation keys, never sentences.

On success `try_sleep(hours)`:

1. `bio_monitor.rest_sleep(hours)` restores energy.
2. Pushes `day_night_manager.total_game_time_hours` forward.
3. **Steps the thermal model through the night in quarter-hour increments.**
4. Writes the autosave with metadata, and reports whether it landed.

Step 3 is the important one. Sleeping does not hand the player a free reset: if
the fire burns out the shelter cools and the body keeps losing heat while
asleep. A test asserts this — sleeping through a shelter that goes cold must
cost body heat. That is what makes banking fuel before bed a real decision, and
it is the hook the "too safe shelter" problem from the thermal model needs.

## 6. The sleep UI, and the two key conflicts

Both keys you asked for were already taken, and neither conflict is fudged:

- **S is `move_backward`.** The hold only charges while sleeping is genuinely
  possible *and* no movement action is held. Walking backwards can never start
  it; holding S standing still in a warm shelter always does. `can_begin_hold()`
  is the single predicate, and a test asserts S does nothing in the open.
- **E is `interact`.** Opening the dialog sets `get_tree().paused = true` while
  the prompt itself runs with `PROCESS_MODE_ALWAYS`. `InteractionManager` is
  paused, so it never sees the E press — no edits to its file, no input-order
  guessing. Pausing is also the right behaviour for a modal dialog.

Controls: hold **S** for one second → **A / D** choose 1–8 hours → **E** sleeps
and saves, **Esc** cancels.

The warning line is not decoration. `fire_outlasts_sleep()` checks every fire
actually warming the spot against the chosen duration, so the player is told
they will wake up cold *before* committing, and the warning appears and clears
as the hours change.

`scenes/ui/hud/sleep_prompt.tscn` carries the layout.
`tools/runtime/capture_sleep_prompt.gd` renders both states for review.

One Godot detail worth recording: **a node-reference `@export` on a scene root
cannot resolve to its own children**, because root properties are applied before
children are added. `SleepPrompt.resolve_nodes()` fills in any widget the scene
left null, by conventional node name. This silently produced a dialog that
never appeared.

## 7. Not built yet

- **Player position and inventory** do not participate yet; `InventoryManager`
  needs `get_save_data()`/`load_save_data()` over its slot array.
- **No UI.** No load menu, no sleep prompt, no "you cannot sleep here" toast.
  The signals they need all exist.
- **No death handling.** `is_dead` persists, so loading a dead save currently
  restores a dead player. A death screen must intercept before that matters.
