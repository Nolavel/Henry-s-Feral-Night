# Controls and context rules

Every key in `project.godot` does something in the game. A key without a
consumer is removed rather than kept "for later" (#76). `tools/ci/check_input_map.py`
fails the build when two actions share a key without an entry in
`tools/ci/input_overlap_allowlist.txt`.

## Keys

| Key | Action | What it does |
|---|---|---|
| W A S D | `move_*` | Walk; any move input also stands Henry up from a seat |
| Shift | `sprint` | Sprint |
| Space | `jump` | Jump; also stands Henry up from a seat |
| C | `crouch` | Crouch |
| Q / E | `lean_left` / `lean_right` | Lean (reserved; Q/E never carry item actions) |
| Z | `switch_shoulder` | Camera shoulder |
| F | `interact` | Context action, see below |
| Tab | `open hub` | Player Hub: pack on Henry, pockets, Use |
| Wheel | `quick_next` / `quick_prev` | Pick a pocket (quick access) |
| Wheel click | `quick_use` | Use the selected Quick Access item; also remains an alternate held-item Use |
| 1–4 | `select item slot 1–4` | Direct Quick Access draw; held-capable items such as a road flare come into Henry's hand unlit |
| Esc | `pause` | Context back-out, see below |
| LMB | `fire` | In gameplay: Use the item already in Henry's hand; in the Hub: drag/drop |

### Lighting the road flare

1. Tap `F` by the flare to pick it up. After the pickup-stow animation it is
   auto-sorted into a compatible Quick Access pocket when one is free. Holding
   `F` opens manual placement instead.
2. Press the matching `1`–`4` Quick Access slot. Henry draws the **unlit**
   flare into the existing hand socket and raises the held-item arm pose.
3. Press **LMB**. Because the flare is already physically in Henry's hand, the
   existing `fire` input becomes contextual **Use held item** and strikes it.
4. Press **LMB** again to drop the burning flare.
5. Wheel-click (`quick_use`) remains available for using the selected Quick
   Access item directly; the mouse wheel still selects pockets without drawing them.

It is a single-use pyrotechnic light, not an on/off electric torch. At the
First Exit clock rate (a 24-hour day in 3600 real seconds), its 75 real seconds
of burn time equal **30 game minutes**.

## F: one verb, resolved by context

F always acts on the thing in front of Henry. The first matching row wins.

| Context | F does |
|---|---|
| A dialog is open (sleep or wait prompt) | Confirm the dialog |
| Hold-F placement is running | Nothing (LMB drags; release drops) |
| Seated, and the camera looks at something within 2 m (food on the table, the stove ring, the set-down pack) | Act on it: eat, warm up, go through the pack |
| Seated, nothing looked at | Open the wait prompt |
| Standing, a target within 0.9 m | Act on it: pick up, open, board up, feed the stove, sit, sleep |
| Standing, a target further away | Walk to it, then act |
| Pickup, F held past 0.35 s | Open the Hub in placement mode instead of the quick stow |
| Bedroll placement preview is up | Lay the bedroll here |

Rules for new features:
- A new interaction is an `InteractiveArea`, never a new key.
- Something that must take F from world targets (a preview, a dialog) handles it in
  `_input` and marks it handled; everything else stays in the normal target path.
- A seated feature is reached by looking at it (`InteractComponent` seated aim), not
  by a second key.

## Esc: always one step back

| Context | Esc does |
|---|---|
| Sleep or wait prompt open | Cancel the prompt |
| Hub open (any mode, including inspection) | Close the Hub; an inspected pack goes back on |
| Bedroll placement preview | Cancel the preview; nothing is spent |
| Seated | Stand up |
| Otherwise | Pause menu |

Each owner claims Esc in `_input` and marks it handled, so the pause menu
(`_unhandled_input`) only sees it when nothing else is open.
