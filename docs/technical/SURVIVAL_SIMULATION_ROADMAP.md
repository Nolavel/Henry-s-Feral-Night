# Systemic Survival Foundation — technical roadmap

Status: architecture plan for [#131](https://github.com/Nolavel/Henry-s-Feral-Night/issues/131).  
Public product name: **RIMEWATCH**.  
Implementation branch for Codex: **`codex` only**.

This document defines the migration path from the current working First Exit systems to a single deterministic survival simulation. It is intentionally **not** a rewrite plan. Existing Weather, Thermal, Save, Inventory and Equipment code remains the foundation and is moved behind clearer contracts one stage at a time.

---

## 1. Why this work exists

RIMEWATCH already has the pieces of a systemic survival game:

- `DayNightManager` owns elapsed game hours and sky/light presentation;
- `WeatherController` is a data-driven weather state machine;
- `ThermalManager` computes ambient, wind exposure, shelter, heat sources, clothing insulation, wetness and body temperature;
- `SleepController` advances sleep/wait;
- `BioMonitorManager` owns calories, hydration and fatigue;
- `InventoryComponent` / `EquipmentComponent` own carried and worn items;
- `SaveManager` writes participant state atomically;
- `SessionState` persists `game_hours` and Henry's position.

The problem is not missing systems. The problem is that **time is not yet a single public simulation contract**.

Today a long action can update the world by manually changing `DayNightManager.total_game_time_hours`, while `SleepController` directly calls `ThermalManager._on_time_update()`. `BioMonitorManager` bills sleep through its own code path. This is manageable for sleep, but it will become fragile when cooking, melting snow, repair, boarding, drying, food spoilage and status effects all need to advance the same world.

Target principle:

```text
Data
  ↓
Deterministic Simulation
  ↓
Presentation
```

Presentation may observe simulation. It must never become a second source of truth.

---

# 2. Non-negotiable architectural rules

1. **No second global clock.**  
   Introduce one canonical `SimulationClock`, world-scoped through the existing composition root. Do not add a time Autoload.

2. **No `Time.time_scale` for survival skips.**  
   Sleeping eight hours, cooking thirty minutes or repairing twenty minutes must advance simulation directly, not run physics/rendering faster.

3. **No cross-system private time calls.**  
   Code like `thermal_manager._on_time_update(...)` is migration debt and must disappear.

4. **No big-bang rewrite.**  
   Each phase lands with compatibility shims and regression tests before the old path is removed.

5. **Keep existing save keys unless there is a demonstrated reason not to.**  
   In particular:
   - `session`
   - `bio`
   - `equipment`
   - `inventory`
   - `thermal`
   - `weather`

6. **`PlayerState` remains a mode owner only.**  
   ON_FOOT / WORKING / SWIMMING / SLEEPING / MENU stay there. Hunger, wetness, diseases and clothing state do not.

7. **Shared Resource data is immutable at runtime.**  
   `GarmentData`, item definitions and weather profiles are definitions. Wetness, condition and other per-instance state live in runtime state, never by mutating shared Resources.

8. **The composition root remains authoritative.**  
   New world systems are created from `world/world.gd`; player-owned systems remain player components.

---

# 3. Phase 1 — SimulationClock / Time Advance API

## 3.1 Goal

Create one deterministic owner of absolute game time and one public way to advance it.

Suggested file:

```text
scripts/systems/time/simulation_clock.gd
```

Suggested ownership:

```text
World
 ├─ SimulationClock
 ├─ WeatherController
 ├─ ThermalManager
 ├─ SaveManager
 ├─ SleepController
 └─ ...
```

`SimulationClock` is a world system, not an Autoload.

## 3.2 Canonical time

Move canonical absolute time behind clock methods:

```gdscript
func get_total_hours() -> float
func get_hour_of_day() -> float
func get_day_number() -> int
func advance_hours(hours: float, reason: StringName) -> void
func set_total_hours(hours: float, reason: StringName = &"load") -> void
```

Do not let gameplay callers assign `total_game_time_hours` directly after migration.

### Compatibility

`SessionState` keeps save key `session` and field:

```json
{
  "game_hours": 27.5
}
```

On load it calls `SimulationClock.set_total_hours()`. No save format break is needed.

`DayNightManager` becomes a consumer of clock time for:

- sky;
- sun/moon;
- day/night events;
- display strings;
- authored critical-night visuals.

It should no longer be the canonical simulation timer.

## 3.3 Deterministic simulation participants

Large time jumps must be split into stable substeps. Example:

```gdscript
@export var max_step_hours: float = 0.25
```

A call:

```gdscript
clock.advance_hours(8.0, &"sleep")
```

becomes 32 deterministic 0.25 h steps.

Do not rely on signal connection order for simulation rules. Use an explicit participant contract, discovered/registered by WorldContext.

Suggested duck-typed protocol:

```gdscript
func get_simulation_priority() -> int
func advance_simulation(hours: float, context: SimulationStepContext) -> void
```

Suggested order:

```text
100  weather scheduling / ambient state
200  heat source fuel / shelter heat
300  clothing wetness / thermal body integration
400  hunger / hydration / fatigue
500  afflictions and derived consequences
```

Exact numbers are implementation detail; **stable ordering is not**.

`SimulationStepContext` may carry:

```text
start_total_hours
end_total_hours
hour_of_day
day_number
reason
```

This avoids every participant re-deriving wraparound time independently.

## 3.4 Normal realtime

Normal gameplay still advances time from frame delta, but through the same clock:

```text
_process(delta)
  → convert real seconds to game hours
  → advance_hours(small_delta, REALTIME)
```

That means realtime and skipped time use one simulation path.

## 3.5 Migration order

1. Add `SimulationClock` without removing current DayNight time.
2. Mirror DayNight time from clock and prove visual equivalence.
3. Move `WeatherController` from `GameHourTracker`/DayNight callbacks to simulation participant.
4. Move fuel and ThermalManager integration.
5. Move BioMonitor metabolism.
6. Move SessionState load/save to the clock API.
7. Remove direct write access from action systems.
8. Delete obsolete `GameHourTracker` usages only after all participants migrate.

## 3.6 Tests

Add focused headless tests:

```text
tests/systems/test_simulation_clock.gd
```

Required cases:

- 1.0 h realtime-equivalent advance == 1.0 h explicit advance;
- 8 h as one request == 32 × 0.25 h;
- midnight wrap is deterministic;
- same initial state + same sequence of advances = byte-equivalent save payload where ordering permits;
- load sets time without accidentally billing the load jump;
- participant execution order is stable;
- negative/zero time is rejected or no-op by contract.

---

# 4. Phase 2 — Time-costed Action System

> **Implementation status (codex, 2026-09-28): complete foundation.** Sleep and wait are migrated
> to the common action contract; deterministic billing, early-stop, staged progress, cancellation,
> realtime blocking and PlayerState restoration are covered by headless tests. Cooking, snow→water,
> repair and boarding remain phase-2 consumers to adopt one-by-one, not responsibilities of the
> action framework itself.

## 4.1 Goal

All meaningful long actions pay for themselves in the same simulation currency: **game time**.

Initial actions:

```text
sleep
wait
warm_and_dry
cook
melt_snow
repair
board_window
future_harvest / butcher
```

Suggested files:

```text
scripts/systems/actions/time_costed_action_system.gd
scripts/systems/actions/action_request.gd
```

Do not make this system a recipe database or inventory manager.

## 4.2 Responsibility boundary

### Gameplay owner decides

- whether the action is legal;
- required tool/item;
- required world target;
- resource reservation/consumption;
- output item/state;
- animation choice.

### TimeCostedActionSystem decides

- action lifecycle;
- elapsed/remaining action time;
- progress;
- cancellation;
- controlled calls to `SimulationClock.advance_hours()`;
- stop conditions supplied by the caller.

The action system must not know what a nail, tin, mug or board is.

## 4.3 Request shape

A runtime request can contain:

```text
action_id
duration_hours
reason
actor
target
interruptible
simulation_step_hours
completion callback / owner
optional stop predicate
```

Avoid a universal Resource for every possible runtime action at first. Use Resources only for reusable static tuning where it proves useful.

## 4.4 Lifecycle

```text
validate by gameplay owner
  ↓
reserve prerequisites
  ↓
action_started
  ↓
SimulationClock advances in deterministic slices
  ↓
progress_changed
  ↓
optional stop predicate
  ↓
complete OR cancel
  ↓
owner commits output/refund policy
```

Signals:

```gdscript
signal action_started(action_id: StringName, duration_h: float)
signal action_progress(action_id: StringName, progress: float)
signal action_completed(action_id: StringName, elapsed_h: float)
signal action_cancelled(action_id: StringName, elapsed_h: float, reason: StringName)
```

## 4.5 Important rule: resource commit policy

Every gameplay action must explicitly choose when irreversible resources are consumed.

Examples:

### Boarding

- hammer: required, not consumed;
- board: reserve when action starts;
- two nails: reserve when action starts;
- final board transform: commit on completion;
- cancel before first hammer strike may refund;
- cancel after commit boundary may not.

### Cooking

- food and container validated before start;
- fuel is not pre-charged by cooking — the stove burns naturally through SimulationClock;
- if the fire dies during action, stop predicate interrupts;
- output depends on elapsed progress/design.

### Melt snow

- mug/container required;
- snow input committed by gameplay owner;
- fire must remain valid;
- action advances time;
- result is potable/non-potable water according to the recipe design, not TimeCostedActionSystem.

### Sleep

- no fake reset;
- existing thermal/metabolism/fuel systems continue to advance;
- sleep completion triggers autosave exactly as current design requires.

## 4.6 PlayerState

While a blocking action is active:

```text
PlayerState.WORKING
```

Sleep remains:

```text
PlayerState.SLEEPING
```

The action system does not introduce a parallel player-mode enum.

## 4.7 Presentation

A generic progress presentation may subscribe to action signals.

It may show:

- action name;
- progress;
- estimated in-game completion time;
- interruption reason.

It must not control action completion.

## 4.8 Tests

Required:

- action advances exactly declared game time;
- fire/weather/metabolism advance during action;
- cancellation produces deterministic elapsed time;
- extinguished heat source can stop cook/melt action;
- boarding consumes resources once;
- no action directly mutates DayNightManager time;
- no duplicate billing between realtime clock and controlled action advance.

---

# 5. Phase 3 — Split BioMonitorManager

> **Implementation status (codex, 2026-09-28): complete.** Runtime state is owned by
> `HungerComponent`, `HydrationComponent` and `FatigueComponent`. `BioMonitorManager` remains
> the `bio` save adapter and legacy API/signal facade, with SimulationClock as the only production
> ticking source. The old DayNight metabolism callback has been removed.

## 5.1 Current problem

`BioMonitorManager` currently owns:

- calories;
- hydration;
- energy;
- three drain models;
- critical flags;
- sleep metabolism;
- rest quality;
- carry fatigue;
- UI signals;
- persistence.

This is already too many reasons to change one class.

## 5.2 Target ownership

Player subtree:

```text
Henry
 ├─ HungerComponent
 ├─ HydrationComponent
 ├─ FatigueComponent
 └─ BioMonitorManager   # temporary compatibility facade / save adapter
```

Suggested files:

```text
scripts/actors/player/henry/components/hunger_component.gd
scripts/actors/player/henry/components/hydration_component.gd
scripts/actors/player/henry/components/fatigue_component.gd
```

Do **not** introduce a deep `SurvivalMetric` inheritance hierarchy unless duplicated behavior remains after the split.

Prefer small composition.

## 5.3 Component responsibilities

### HungerComponent

Owns:

- current calories;
- maximum calories;
- base metabolism;
- activity/cold modifiers;
- add calories;
- normalized progress;
- critical edge signal.

### HydrationComponent

Owns:

- current hydration;
- base water loss;
- activity/environment modifiers;
- add hydration;
- normalized progress;
- dehydration edge signal.

### FatigueComponent

Owns:

- current energy;
- waking fatigue rate;
- sleep recovery;
- carry-load penalty;
- exertion modifiers;
- normalized progress;
- exhaustion edge signal.

## 5.4 Compatibility facade

For the migration period `BioMonitorManager`:

- owns no duplicated values;
- finds/references the three components;
- proxies current public methods;
- proxies legacy signals used by HUD;
- remains the save adapter for key `bio`.

Existing payload remains readable:

```json
{
  "calories": 1800.0,
  "hydration": 72.0,
  "energy": 48.0
}
```

`load_save_data()` delegates each value to the new component.

`get_save_data()` collects component values back into the same shape.

This prevents a save-version bump solely because internal ownership changed.

## 5.5 Simulation integration

Each component becomes a SimulationClock participant or one player-level metabolism coordinator advances the three in a fixed order.

Do not keep both:

- old `_on_time_changed()` hourly drain;
- new simulation-step drain.

There must be exactly one ticking path.

## 5.6 UI migration

Current HUD can continue listening to legacy BioMonitor signals while components are introduced.

Then migrate one track at a time to direct component signals.

Only after no consumer needs the facade signals should legacy proxy code be removed.

## 5.7 Tests

Required:

- old `bio` payload loads correctly;
- new save shape stays compatible;
- 24 × 1 h and 96 × 0.25 h produce equivalent values within tolerance;
- carry fatigue affects Fatigue only;
- eating cannot mutate hydration unless a food action explicitly does so;
- sleeping restores fatigue while still billing hunger/hydration;
- no duplicate signal/update after facade migration.

---

# 6. Phase 4 — Status / Affliction layer

> **Implementation status (codex, 2026-09-28): complete foundation.** Hypothermia,
> dehydration and exhaustion are persistent player-owned states driven by factual source-system
> thresholds. Definitions remain immutable Resources; runtime state is saveable under `afflictions`;
> consumers read named modifiers instead of afflictions mutating other systems. Starvation remains
> intentionally deferred until playtest evidence says it adds a useful consequence.

## 6.1 Goal

Convert survival threshold crossings into durable gameplay consequences without hard-wiring every system to every other system.

Suggested player component:

```text
scripts/actors/player/henry/components/affliction_component.gd
```

Suggested static definition:

```text
core/status/affliction_definition.gd
```

## 6.2 Start small

Initial candidates only:

- hypothermia;
- dehydration;
- exhaustion;
- starvation/critical hunger if playtest proves it useful.

Do not pre-build food poisoning, infection, sprains, frostbite, parasites, etc. until the game has mechanics that need them.

## 6.3 Data vs runtime state

### AfflictionDefinition Resource

Static:

```text
id
display/localization key
stack policy
severity limits
modifier definitions
optional recovery metadata
```

### Runtime AfflictionState

Dynamic:

```text
id
active
severity
elapsed_hours
recovery_progress
source
```

Never mutate the shared definition Resource.

## 6.4 Trigger ownership

The system that knows the factual threshold emits/sets the condition:

```text
ThermalManager stage
   → hypothermia state

HydrationComponent critical edge
   → dehydration state

FatigueComponent critical edge
   → exhaustion state
```

`AfflictionComponent` owns persistence and modifier aggregation.

## 6.5 Modifier boundary

Consumers ask for named modifiers rather than afflictions reaching into them.

Example:

```text
movement_speed_multiplier
fatigue_rate_multiplier
recovery_rate_multiplier
work_duration_multiplier
```

Possible API:

```gdscript
func get_multiplier(stat_id: StringName) -> float
func has_affliction(id: StringName) -> bool
func get_severity(id: StringName) -> float
```

Movement reads movement multiplier. Fatigue reads fatigue multiplier. Action duration may read work-duration multiplier.

This avoids:

```text
Hypothermia → MovementController.set_speed(...)
Hypothermia → FatigueComponent.rate = ...
Hypothermia → ActionSystem.duration = ...
```

which would create a dependency mesh.

## 6.6 Persistence

Give affliction runtime its own save key, for example `afflictions`.

Old saves simply have no afflictions and load with an empty active set. This is additive and safe.

## 6.7 Tests

Required:

- threshold edge activates exactly once;
- recovery deactivates exactly once;
- save/load preserves active severity;
- modifiers combine deterministically;
- same affliction cannot duplicate unless explicitly stackable;
- no presentation node is required for simulation correctness.

---

# 7. Phase 5 — Clothing layers and per-instance garment state

## 7.1 Current base

Current `GarmentData` already defines:

- body slot id;
- pockets brought by the garment;
- insulation;
- visual mesh name.

`EquipmentComponent` already owns body/pocket placement and save key `equipment`.

This must be extended, not replaced.

## 7.2 Static garment data

Add only definition-level values to `GarmentData`:

```text
body_region
layer
base_insulation_c
windproof
waterproof
drying_rate
max_condition
```

Suggested layer enum:

```text
BASE
MID
OUTER
```

The exact body regions come from the equipment layout, not hardcoded logic.

## 7.3 Layer occupancy

Equipment must be able to express:

```text
torso / base
torso / mid
torso / outer
legs / base
legs / outer
...
```

Do not special-case jacket/sweater names.

The preferred migration is to make layer part of slot identity/layout so the existing `_body` dictionary remains the authority.

Old slot ids require an explicit migration table based on the live equipment layout before implementation.

## 7.4 Runtime garment state

Wetness and condition belong to **an equipped/carried garment instance**, not `GarmentData`.

Runtime state example:

```json
{
  "wetness": 0.42,
  "condition": 0.81
}
```

Do not write:

```gdscript
item.garment.wetness = ...
```

because all items using that Resource would share the mutation.

## 7.5 Save extension

Keep save key `equipment`.

Existing fields:

```json
{
  "body": {},
  "pockets": {}
}
```

may be extended:

```json
{
  "body": {},
  "pockets": {},
  "garment_states": {}
}
```

Old save without `garment_states` means:

```text
wetness = 0
condition = 1
```

If wet garments can be removed and carried, state must travel with the item. That likely requires extending non-stackable inventory entries with optional instance state. Do not fake this by losing wetness on unequip.

## 7.6 Protection calculation

`EquipmentComponent` should expose effective aggregates, for example:

```gdscript
func get_effective_insulation_c() -> float
func get_wind_protection() -> float
func get_water_protection() -> float
```

ThermalManager asks EquipmentComponent for effective protection. It must not inspect individual garments itself.

Potential effective insulation:

```text
base insulation
× condition factor
× wetness factor
```

Exact curves are balance data, not architecture constants.

## 7.7 Layer wetting

A weather/wetness step applies moisture outside-in:

```text
OUTER receives exposure first
  ↓ remaining penetration after waterproof
MID
  ↓
BASE
```

Drying works per garment using environment warmth + garment drying rate.

This creates the desired gameplay behavior:

- a good outer layer protects inner insulation;
- damaged/wet outerwear leaks;
- taking clothing off near heat can become meaningful;
- a dry base layer remains valuable even when the coat is wet.

## 7.8 Condition

Condition reduces protection, but should not introduce item destruction until design explicitly calls for it.

Initial architecture only needs:

```text
0..1 condition
repair(amount)
damage(amount, cause)
```

Repair becomes a TimeCostedAction and therefore automatically bills fire/weather/metabolism while Henry works.

## 7.9 Tests

Required:

- shared `GarmentData` never changes at runtime;
- wet outer layer can protect inner layer according to waterproof value;
- wetness lowers effective insulation;
- condition lowers declared protections;
- unequip/re-equip preserves garment state;
- save/load preserves garment state;
- old equipment saves load dry/full-condition;
- invalid old layer slot migration fails visibly, not silently.

---

# 8. Save compatibility contract

| Existing key | Migration rule |
|---|---|
| `session` | Keep. `game_hours` now loads into SimulationClock. |
| `bio` | Keep. BioMonitor facade serializes the three new components. |
| `equipment` | Keep. Add optional garment state fields. |
| `inventory` | Keep. Extend only if non-stackable carried garment instance state is needed. |
| `thermal` | Keep body temperature and compatible wetness migration until per-garment wetness is authoritative. |
| `weather` | Keep current profile/duration state. |
| `afflictions` | New additive key; missing means empty. |

### Thermal wetness migration

Current `ThermalManager` owns one global wetness value. Per-garment wetness cannot replace it in one commit.

Migration order:

1. keep global wetness working;
2. add per-garment state;
3. derive clothing wetness aggregate from EquipmentComponent;
4. migrate consumers;
5. decide whether a separate body/skin wetness value is still needed;
6. only then remove or reinterpret the old thermal wetness field, with save migration.

---

# 9. Proposed PR sequence

Do not implement the epic as one PR.

### PR A — SimulationClock foundation

- clock;
- participant contract;
- tests;
- mirror DayNight without behavior change.

### PR B — Weather / heat / thermal migration

- migrate existing hourly systems;
- eliminate `GameHourTracker` where obsolete;
- no action changes yet.

### PR C — TimeCostedActionSystem

- migrate sleep + wait first;
- prove deterministic action-time path.

### PR D — Gameplay action adoption

- cooking;
- snow→water;
- repair;
- boarding;
- one action at a time.

### PR E — Metabolism split

- Hunger/Hydration/Fatigue;
- BioMonitor compatibility facade;
- save regression tests.

### PR F — Afflictions

- only first useful conditions;
- modifier query API;
- persistence.

### PR G — Clothing layers

- static layer/protection model;
- slot migration.

### PR H — Garment instance state

- wetness;
- condition;
- inventory/equipment state transfer;
- thermal integration.

The exact count can change. The **dependency order should not**.

---

# 10. First Exit regression contract

Every phase must preserve the playable loop:

```text
bunker
→ route/resources
→ authored weather turn
→ shelter
→ boards / nails / hammer
→ stove
→ warming / food / water
→ sleep
→ save
→ load
```

Architecture work is not complete if individual unit tests pass but this loop changes invisibly.

At minimum each implementation PR must identify which existing First Exit tests cover it and add a focused regression test for the new contract.

---

# 11. Definition of Done for the epic

The epic is complete only when:

- one SimulationClock owns canonical game time;
- all long actions use one TimeCostedAction path;
- no gameplay system calls another system's private time-update function;
- Weather / fuel / Thermal / Hunger / Hydration / Fatigue / Afflictions advance deterministically from the same time source;
- BioMonitor no longer owns three independent simulations;
- save key compatibility is proven by tests;
- clothing supports layers and per-instance wetness/condition;
- thermal protection is derived from actual worn garment state;
- UI/audio/VFX remain presentation consumers;
- First Exit still completes and restores correctly after save/load.

This is the foundation for systemic survival in RIMEWATCH. It is deliberately narrower than “copy The Long Dark”: the goal is one coherent simulation model that existing and future mechanics can join without creating parallel rules.
