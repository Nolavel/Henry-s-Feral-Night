# First Exit A — stranger playtest run (#80)

One continuous run on `main`, Graciosa, no debug, no teleport, no TestScene.
Game time is fixed: 60 real minutes per game day, a new game starts at 12:00
(#42), so a 10–15 minute run ends in late afternoon / dusk.

## Before: what the observer says to the tester

Say only this:

> "You play Henry. Survive the first night. Controls: WASD, F for everything,
> Tab for your pack, Esc to back out. I will not help; think aloud."

Do **not** mention: tinder, boards, the shelter house, wind, the weather turn,
sitting, the stove ring, the table, or sleep = save.

## Timeline and what to watch

| Real time | Beat | Watch for | Ask after the run |
|---|---|---|---|
| 0:00–0:45 | Bunker, exile | Does the tester try the bunker door? Do they read "no way back"? Is the water tower a heading? | "Where were you, and why did you leave?" |
| 0:45–2:00 | Route choice: road / shore / ruins | Which route, and did they look before choosing? | "Why that way?" |
| 2:00–5:30 | Resources | Do they read boards / tinder / firewood as future decisions? Do they leave something behind? | "What did you not take, and why?" |
| ~4:00–6:00 | Weather turn (200 m from the start, or 5 min) | Did the plan change: faster, less looting, a sheltered path, no going back? | "What changed when the storm came?" |
| 5:30–7:30 | Finding the shelter among 11 lots | Did they pick it by looking (breaches, stove, mattress), or by a prompt? | "How did you know which house?" |
| 7:00–9:00 | 5 breaches, 1–3 boards | Did they board the windward holes (snow blowing in) or the nearest ones? | "Which windows did you close, and why those?" |
| 8:00–12:00 | Stove and recovery | Light the stove (5 s act), sit, wait, dry (steam, trend marks), warm food on the ring, eat from the table. Did it read as a ritual or as a chain of F prompts? | "What were you doing by the stove?" |
| 11:00–15:00 | Sleep → save → reload | Sleep through the mattress/bedroll. Reload the slot: picked-up loot must not return (#79), shelter, fuel, weather, bedroll and inventory must hold. | — |

## Pass

**Pass** needs every beat to happen without the observer's help, and the
tester's own retelling to carry this chain, in their words:

> "They left me outside. I chose a path because I saw its cost. I did not take
> everything. The weather turned and made me change the plan. I found a house,
> saw where the wind got in, closed what I could, made a fire, warmed up, dried
> off, ate, and only then lay down. After loading, the world remembered."

If all systems fire but this chain does not appear in the retelling, First
Exit A is **not** done. Write one line per missing link and file it.

## Failure run (second pass)

Freeze or fail the night on purpose (greed for weight, ignoring the storm,
wrong boards). The tester must be able to say what to do differently.

## Publisher frames

`tools/runtime/capture_first_exit_frames.gd` renders the six frames of the #80
table (bunker and tower, route with clutter, weather turn, boarding, lit stove,
seated with Kenny) into `user://shots/first_exit/`. They are for the capture
checklist, not a substitute for the human run.
