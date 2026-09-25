# Changelog

All notable changes to Henry's Feral Night. Newest first.
Maintained per branch; entries are added by whoever makes the change.

## [Unreleased] — `codex`

### 2026-09-25 — Register Grok in AGENTS.md (grok)

Added
- Grok role and branch ownership in `AGENTS.md`: commercial readiness,
  scope control, vertical-slice readiness audits and related technical docs.
  Proposes only; does not auto-implement gameplay.
- Knowledge-sync audit on branch `grok`:
  `docs/technical/GROK_AUDIT_2026-09-25.md` (baseline main @ 4c29171).

### 2026-09-25 — First Exit A playtest kit (#80) (claudeflow)

Added
- `docs/playtest/FIRST_EXIT_A_RUN.md`: what the observer says (and must not),
  the beat timeline with what to watch and what to ask, the retelling that
  decides pass, and the failure pass.
- `tools/runtime/capture_first_exit_frames.gd`: the six publisher frames of the
  #80 table from the real scene (exile, route clutter, weather turn, boarding,
  lit stove, seated with Kenny) into `docs/art/issue80/`.

### 2026-09-25 — Breach drafts; one weather controller (#80) (claudeflow)

Added
- `BreachDraft` on every `ShelterBreach`: snow blows in through an open breach,
  as dense as `get_exposure_against(wind)` times the wind speed, so the player
  sees which side to board first; a lee-side hole stays quiet and a boarded one
  stops. `test_breach_draft`, `tools/runtime/capture_breach_draft.gd`, frame
  `docs/art/issue80/01_snow_through_windward_breach.png`.

Removed
- The empty `WeatherController` node in `WorldEnvironmentSystem.tscn` and the
  unread `WorldEnvironmentController.weather_controller` export: the world's
  system controller is the only one.

### 2026-09-25 — Game time: 60 real minutes a day, start at noon (#42) (claudeflow)

Changed
- Author decision for First Exit A: a full game day is a stable 60 real minutes
  (`day_duration` + `night_duration` = 1800 + 1800 s, was 72 + 72), with no
  dynamic coefficients. One game hour = 2.5 real minutes.
- `DayNightManager.start_hour` (default 12.0): a new game starts at noon so a
  10–15 minute run reaches late afternoon and dusk; a save overrides it.
- Knock-on: one log (2 h) now burns 5 real minutes, warming on the stove
  (0.5 h) 75 s; the weather beat's 180 s storm is about 1.2 game hours.

### 2026-09-25 — Authored weather turn on the First Exit route (#78) (claudeflow)

Added
- `WeatherBeat` (placed by the First Exit builder, saveable): holds `calm` on the
  way out; once per run, when Henry is 200 m from his start (or after 300 s real
  as a fallback so the door cannot be waited out), and never while he is
  sheltered, it drives the one WeatherController into `blizzard` for 180 real
  seconds, then `windy` (never straight back to calm), then the scheduler.
  Beat length is in real seconds because the game clock runs a day in 144 s.
- `WeatherController.set_weather(id, instant, duration_h, then_id)`: an authored
  beat can pin a duration and the profile that follows; `then_id` is saved.
- The beat finds the populated WeatherController itself: the environment scene
  carries an empty leftover controller, and this scene gets no on_world_ready.
- `test_weather_beat`, `tools/runtime/capture_weather_beat.gd`, frame
  `docs/art/issue78/calm_then_storm.png`.

### 2026-09-25 — Consumed world pickups stay consumed (#79) (claudeflow)

Added
- `ItemPickup.world_id`: a stable id for authored pickups; the First Exit
  builder sets it from the layout id (all 11 route pickups).
- `PickupLedger` (one per built world, saveable, key `pickup_ledger`): records
  taken world ids and, on load, removes those pickups from the rebuilt world.
  Stores ids only; the items themselves stay in the inventory save. Stack pickups
  stay atomic; dropped items (no world id) are untouched.
- `test_pickup_ledger`: pick up boards/tinder/firewood/food → save → rebuild →
  load; items stay in the inventory, the pickups are gone, others remain.

### 2026-09-25 — Lighting the stove as an act (#42) (claudeflow)

Changed
- F on the stove is a staged act on top of `HeatSourceFeed` (no new survival
  architecture): tinder and a log go in at once, Henry kneels and holds still
  (`Player.hold_still()`), the door swings open and a weak flame grows; only
  after 5 s does the fire take, burn and heat. A log on a live fire is the short
  act (door, log, door; 2 s) and needs no tinder. The prompt reads "Light the
  stove" or "Add a log". `feed()` stays the instant path for systems and tests.
- `StoveVisual` shows as many logs as a full load holds (6 h / 2 h = 3), not 4;
  the log going in shows during the act. Balance is unchanged: 1 log = 2 h,
  6 h max, so a full night still needs tending.
- `test_stove_act`; frame `docs/art/issue42/07_lighting_act.png`.

### 2026-09-25 — Controls audit (#76) (claudeflow)

Removed
- Input actions nothing consumed: `open inventory` (I), `open map` (M),
  `open health_panel` (H), `open craft_panel` (K), `select item slot 5–8`,
  `reload` (R), `secondary action` (RMB), `drop item` (G), `toggle camera view` (V),
  `use_ability_gizmo_2` (X), `orbit_left`/`orbit_right` (, .), `DEBUG` (Enter).

Added
- `docs/technical/CONTROLS.md`: every key, and the context rules for F (one verb,
  resolved by what is in front of Henry) and Esc (always one step back), with the
  rules new features follow. `test_quick_access` guards against the dead actions returning.

### 2026-09-25 — Full pack inspection (#75) (claudeflow)

Added
- `PlayerHubComponent.open_inspection()`: a separate, slower Hub state. From the
  Hub ("Take the pack off") the pack comes off and stands in front of Henry,
  fully open, Kenny beside it; the camera looks down into it from past his left
  shoulder. Closing puts it back on. Seated by the stove, F on the set-down pack
  ("Go through the pack") opens inspection where it stands; afterwards it stays
  there, ajar.
- Extension point for sorting, sections, repair and crafting:
  `inspection_opened(pack)` / `inspection_closed`, and the panel lists the pack's
  sections in inspection mode.
- `test_pack_inspection`; frame `docs/art/issue68/10_full_inspection.png`.

### 2026-09-25 — Seated reach: warm and eat from the seat (#42) (claudeflow)

Changed
- Seated, `InteractComponent` picks the F target by where the camera looks
  (within 35° of the view) and reaches 2 m instead of 0.9 m: Henry leans to the
  stove's cooking ring and to the table, and never walks off to a target. Warming
  and eating off the stove now work from the seat.
- `test_seated_aim`.

### 2026-09-25 — Warming on the stove top (#42) (claudeflow)

Added
- `StoveWarmer` on the shelter stove's cooking ring. F with a warmable item
  carried puts one on the ring ("Warm up: Tinned stew"); it warms over 0.5 game
  hours, only while the stove burns (also through a seated wait); then F eats or
  drinks it straight off the stove ("Eat: Hot stew"), with steam while ready.
  Saved with the world.
- Items `tinned_stew_hot` (warms Henry, −0.8 °C cost) and `warm_water` (−0.3 °C,
  versus +0.35 °C for raw snow); `ItemResource.warms_into` names the warmed form.
- `HeatSource.heat_elapsed(hours)` for things warming on a fire;
  `ConsumptionController.consume_from_world()` for food that is not carried.
- `test_stove_warmer`; frames in `tools/runtime/capture_stove.gd`.

### 2026-09-25 — Stove ritual UX pass (#42) (claudeflow)

Changed
- Food on the meal table is real: one `TableFood` target per kind ("Eat: Tinned
  stew ×2", "Drink: …"); F eats one through ConsumptionController. Seated, F goes
  to whatever is at arm's length and only waits when nothing is; the seat is not
  a target while Henry sits on it.
- `1`–`4` only select a pocket; the wheel click uses it (no accidental eating).
- A wait starts at 1 hour (sleep keeps its own last choice) and says why it
  ended early: "Warm and dry" / "The stove went out".
- Waited time bills hunger and thirst including part-hours
  (`BioMonitorManager.pass_awake_hours(float)`); a 15-minute wait was free before.
- Drying steam: thin wisps from the chest and shoulders, lower while seated.
- The pack set down by the stove stands ajar (`PackRig.Openness.AJAR`): top and
  side flaps lifted a little.

### 2026-09-25 — Meal table by the stove (#42) (claudeflow)

Added
- `MealTable`: a small table with a cloth beside the rest crate. While Henry sits
  by it, the food and drink he carries (pack and pockets) is laid out on the
  cloth — a tin per stew, a snowball per handful of snow — and it follows what
  is eaten or moved; standing up clears it. Eating stays Hub/pocket Use (the
  seated clip is chair-sitting, so the cloth is on a table, not the floor).
- `test_shelter_recovery` covers the layout; frame `docs/art/issue42/04_meal_table.png`.

### 2026-09-25 — A real stove in the shelter (#42) (claudeflow)

Added
- `StoveVisual` around the shelter's HeatSource: legs, an ash pan with a draught
  vent and pull, a firebox with floor, walls and a front frame, a slotted door on
  a hinge with a knob, a cooktop with a cooking ring, and a flue. One log shows
  per fuel unit left (up to 4); the ember bed and an inner light glow through the
  door slots only while it burns, with a gentle flicker.
- The builder places it and keeps a collision hull; `test_stove_visual`,
  `tools/runtime/capture_stove.gd`, frame `docs/art/issue42/03_stove_states.png`.

### 2026-09-25 — Waiting seated; pack and Kenny set down by the stove (#42) (claudeflow)

Added
- Seated, `F` opens the sleep dialog in wait mode ("WAIT BY THE FIRE"): the same
  hour picker, no sleep, no save. `SleepController.try_wait()` advances the world
  and stops early once Henry is dry and warm or no fire warms him;
  `BioMonitorManager.pass_awake_hours()` bills the waited hours.
- On sitting Henry takes the pack off and stands it on his left; Kenny is set on
  his right, facing the pack. Both go back on when he stands
  (`HenryUALAnimation.set_pack_down()` / `pick_pack_up()`).
- A seated hint: "F — wait · move — stand up".

Changed
- Seated, `F` waits instead of standing up; Esc or any move input stands.
- Drying steam is thinner.

### 2026-09-25 — Recovery by the stove: sitting, trend marks, drying steam (#42) (claudeflow)

Added
- `RestSpot` (F — Sit down) and `RestComponent`: Henry sits on the seat facing
  its -Z; F, Esc or any move input stands him up. Sitting gives no bonus (author
  decision): the stove warms and dries, sitting only holds him still.
- `HenryUALAnimation` sit states: `Sitting_Enter` → `Sitting_Idle` loop → `Sitting_Exit`.
- First Exit shelter: a crate to sit on by the stove (`RestCrate`, via the builder).
- Vital HUD: a trend mark on the warmth cell and a wetness water-fill on the
  figure with its own mark (green when it helps Henry, red when it hurts).
- `DryingSteamComponent`: soft steam off wet clothes near a burning HeatSource,
  thinning with wetness.
- `tests/systems/test_shelter_recovery.gd`; sit states in `test_henry_animation`;
  `tools/runtime/capture_shelter_recovery.gd`, frame `docs/art/issue42/`.

### 2026-09-25 — Quick access from pockets; L key removed (#68, #73/#74) (claudeflow)

Added
- `QuickAccessComponent` on the Player: mouse wheel (`quick_next`/`quick_prev`)
  cycles worn pockets with a short readout; wheel click (`quick_use`) uses the
  selected pocket's item through the Use contract; `1`–`4` (existing
  `select item slot N`) pick and use a pocket directly. Q/E stay free for leaning.
- `PlayerHubComponent.use_from_zone()`: a pocketed item passes through the pack to
  its user and returns to the pocket if nothing could use it.
- `HeldLightComponent.release_held()`: the next quick-access click drops the burning flare.
- `ConsumptionController` joins the Use contract: food and drink are eaten through
  Hub Use or a pocket click. Nothing in gameplay called it before, so Henry could not eat.
- `tests/systems/test_quick_access.gd` (pockets, flare, eating).

Removed
- `toggle_flashlight` (L) action and its handler.

Fixed
- `tools/ci/check_input_map.py` ignored mouse-button events and quoted action
  names (e.g. `open hub`), so their overlaps went unchecked.

### 2026-09-25 — Use action; bedroll via preview, B key removed (#68, #74) (claudeflow)

Added
- Item Use contract: `PlayerHubComponent.can_use()/use_item()` hand an item to the
  sibling component whose `can_use(id)` accepts it. Hub panel has a Use button.
- Bedroll Use: the Hub closes and a see-through roll follows in front of Henry;
  `F` lays it there, `Esc` cancels (nothing is spent until placed).
- Flare Use: lights it into the hand (same `HeldLightComponent.light()`; `L` stays for now).

Removed
- `lay_bedroll` (B) input action and its handler.

Fixed
- The bedroll was laid behind Henry (+Z); it now lands in front (-Z).

### 2026-09-25 — Hold-F manual placement (#68) (claudeflow)

Added
- Holding F (0.35 s, `PlayerHubComponent.HOLD_TIME`) through a pickup opens the
  Hub in placement mode (`open_placement`): the pack opens fully, the item sits
  under the cursor, the pack and pockets it fits are lit (by `SizeClass`), LMB
  drags it and releasing drops it there and closes the Hub. A drop outside a lit
  pocket leaves it in the pack. Tap F stays the quick stow.
- `test_player_hub` covers the hold and the drop; frame `docs/art/issue68/07_hold_placement.png`.

### 2026-09-25 — Tap-F quick stow through the top flap (#68) (claudeflow)

Added
- `ItemPickup` hands its mesh to `PlayerHubComponent.stow_visual()`: the item
  lifts, drops into the pack's top flap (`TOP_ONLY`) and the pack shuts once it
  lands. The inventory gets the item at once; the flight is presentation only.
  Armfuls (`carried_in_hands`) still go to the hands.
- `test_player_hub` covers the stow; frames `docs/art/issue68/04–06`.

### 2026-09-24 — Player Hub foundation: four-flap pack and Quick Access (#68) (claudeflow)

Added
- `PackRig`: the backpack on Henry is a tray with four hinged flaps (top, bottom,
  left, right) over an inner attachment field. `TOP_ONLY` opens the top flap
  (future quick stow); `FULL` opens it like a book. Kenny rides the bottom flap.
- `PlayerHubComponent` on the Player (`Tab`, the existing `open hub` action):
  roots Henry, blends to a camera facing the pack, opens it fully. It reads
  `InventoryComponent` and worn pockets and stores nothing itself.
- Quick Access zones = pockets on worn garments (pack main compartment excluded).
  Items move pack → pocket → pack with no duplication; size class gates pockets.
- `PlayerHubPanel`: temporary localised readout (pack list, zones, weight, refusals).
- `tests/systems/test_player_hub.gd`, `tools/runtime/capture_player_hub.gd`,
  frames in `docs/art/issue68/`.

Fixed
- Pocketed items now count toward carried weight (`EquipmentComponent.get_carried_weight`).

### 2026-09-24 — First Exit split: land night vs Coast / Thin Ice (#24) (claudeflow)

Changed
- `docs/world/FIRST_EXIT.md`: First Exit (milestone A) is the land night only;
  the ice route moves to milestone B, Coast / Thin Ice.

### 2026-09-24 — Bedroll: sleep in the field (#63) (claudeflow)

Added
- `bedroll` item, found at the bunker (First Exit layout `bedroll_bunker`).
- `BedrollComponent` on the Player. `B` (`lay_bedroll`) spends the bedroll
  into a roll laid along Henry's facing, with a kneel. The roll offers
  F — Sleep through the same `SleepSpot`, so `SleepController` still refuses
  unsafe cold or wet, and a Roll-up prompt at its head returns it to the
  inventory. A laid roll is saved and restored (`saveable`). `B` stands in
  until the inventory has a Use action.
- `test_bedroll.gd`.

### 2026-09-24 — Flare pass 2: raised hand, spark fountain, breathing light (claudeflow)

Changed
- UAL `Idle_Torch` raises the *left* hand, so the shared hand socket and the
  held pose moved to `hand_l`. The flare is carried at chest height, tipped
  out of the fist.
- Sparks are a gravity fountain that spits in uneven spurts: more particles,
  higher speed during a spurt, and a colour ramp from orange-white to red.
  The light's reach breathes with the burn and swells on each spurt.
- Includes Codex's polish `f3ee73f`: soft spark billboards, warmer smoke,
  4.5 m / 2.8 indoor-friendly light.

### 2026-09-24 — Road flare in Henry's hand (#57) (claudeflow)

Added
- A shared held-item socket: `HenryUALAnimation.get_hand_socket()`, a
  BoneAttachment on `hand_r`. `hold_in_hand()` / `release_hand()` move props
  in and out of it. It is the one hand path for flares and later lights.
- A held pose: the right arm eases into `Idle_Torch` through a bone-filtered
  Blend2 over any locomotion, so the legs keep walking.
- `HeldLightComponent` on the Player. `L` (`toggle_flashlight`) spends a
  `road_flare` from the inventory into the hand. A second `L` drops it burning
  at Henry's feet. A spent flare lingers 3 s for its smoke, then goes. It
  forwards WorldContext, so the smoke gets live WeatherController wind.
- The `road_flare` item, a `test_held_light.gd` suite, and
  `tools/runtime/capture_held_flare_ingame.gd` (a night, windy capture in
  the main scene). Frames are in `docs/art/issue57/`.

### 2026-09-24 — Sleep is an interaction, not a key (claudeflow)

Changed
- There is no global sleep key. `SleepSpot`, an InteractiveArea, offers
  "F — Sleep" on a bed, mattress or bedroll. F opens the sleep dialog through
  the existing InteractComponent path, and a refusal (cold, wet, unsafe) shows
  on the spot. Inside the dialog, the mouse wheel or ← → change the hours,
  F or Enter sleeps and saves, and Esc cancels.
- `SleepPrompt` lost the hold-S charge and its widgets; `request_open()`
  checks `SleepController.can_sleep()` first.
- The First Exit shelter has a mattress by the west wall.

Removed
- Input actions `sleep`, `sleep_hours_less` and `sleep_hours_more` (S/A/D
  clashed with movement), with their InputSystems signals. Their allowlist
  entries are gone, so CI now rejects any new overlap with WASD.

### 2026-09-24 — Build hygiene from the #58 review (claudeflow)

Added
- `tools/ci/import_gate.sh`: the CI import now fails on load errors (second
  pass, after cold-cache ordering noise) and compiles every project script
  (`tools/ci/compile_scripts.gd`). This replaces the previous import-only check.

