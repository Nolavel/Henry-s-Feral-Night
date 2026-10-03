# Hoarbound — Game Design Document

> **Статус документа:** code-grounded GDD / living design snapshot.  
> **Аудит-контекст:** ветка `codex`, исходный runtime snapshot `804887cb248cd5d9d68f7723bb0ad94419b1ea8a` (2026-10-04).  
> **Главное правило этого документа:** описание фактической игры отделено от продуктового намерения. Наличие имени, ресурса, input action или старого кода не считается доказательством работающей механики.

## 0. Как читать статусы

| Маркер | Значение |
|---|---|
| **[IMPLEMENTED]** | Механика существует в текущем runtime-коде и имеет явную точку подключения к production scene/composition root. |
| **[PARTIAL]** | Есть существенная реализация, но нет полной runtime-цепочки, подтверждённого end-to-end loop либо часть поведения остаётся legacy/placeholder. |
| **[MENTIONED]** | Механика описана в PRD/design docs, названа enum/input/resource или сохранена как будущий scope, но production-реализация не подтверждена. |
| **[INFERRED]** | Намерение можно предположить по структуре проекта, однако оно не является зафиксированной текущей функцией. |

### 0.1. Источники истины

1. `project.godot` — запуск, autoload, input map, renderer, physics/render layers.
2. `scenes/**/*.tscn` и production-instantiated tool scenes — фактическая Godot scene composition.
3. `world/world.gd`, `core/**/*.gd`, `scripts/**/*.gd` — runtime ownership и связи систем.
4. `data/**/*.tres`, `data/**/*.json` — authored gameplay/world data.
5. `PRD.md`, `README.md`, `docs/game_design/VERTICAL_SLICE.md` — **product/design intent**, а не автоматическое доказательство реализации.
6. `archive/`, `tests/`, CI/render tools и `addons/` учитываются как история, тестовая инфраструктура или dependency; их наличие не повышает статус gameplay-функции до **IMPLEMENTED**.

---

# 1. High concept

**[IMPLEMENTED + DOCUMENTED INTENT]** `Hoarbound` — third-person systemic survival на замёрзшем Key West. Генри должен управлять холодом, ветром, влажностью одежды, голодом, жаждой, усталостью, переносимым весом, топливом и временем, превращая небезопасное строение в рабочее убежище.

**Evidence**
- `README.md` — “Third-person systemic survival”, frozen Key West, Henry, connected cold/wind/wet clothing/carried weight/fuel/time.
- `PRD.md :: Vision / Player fantasy и core loop` — bunker → route → scarce resources → weather → shelter → repair/fire/dry → sleep/save.
- `scenes/world/key_west/key_west.tscn :: World` — production main scene composition.
- `scripts/systems/survival/thermal_manager.gd :: ThermalManager` — body temperature, wind chill, wetness, insulation, shelter/heat zones.
- `scenes/actors/player/player.tscn :: HungerComponent / HydrationComponent / FatigueComponent / InventoryComponent / EquipmentComponent`.

**Current product target:** vertical slice **First Exit A: One Land Night**, рассчитанный design docs на один непрерывный 10–15-минутный survival run. Это target, а не доказанная длительность: `PRD.md :: Current product milestone` и `docs/game_design/VERTICAL_SLICE.md :: First Exit A` прямо указывают, что live/stranger run ещё должен подтвердить loop.

---

# 2. Design pillars

## 2.1. Survival decisions, not meter maintenance

**[IMPLEMENTED/PARTIAL]** Системы связаны между собой так, чтобы ресурсы меняли маршрут и темп, а не существовали отдельно.

- Carry weight ограничивает inventory и снижает movement acceleration/speed; fatigue также читает load fraction.  
  **Evidence:** `scripts/actors/player/henry/components/inventory_component.gd :: max_carry_weight/get_load_fraction`, `scripts/actors/player/henry/Controllers/MovementController.gd :: get_load_speed_multiplier/get_load_accel_multiplier`, `scripts/actors/player/henry/Managers/BioMonitorManager.gd :: carry_fatigue_factor`.
- Одежда даёт insulation, её wetness снижает thermal protection, тепло сушит одежду.  
  **Evidence:** `scripts/systems/survival/thermal_manager.gd :: get_insulation_c/get_wetness/get_wetness_insulation_multiplier`, `scripts/actors/player/henry/components/equipment_component.gd`.
- Погода и время кормят thermal/weather/snow presentation через общий simulation path.  
  **Evidence:** `world/world.gd :: WORLD_SYSTEM_SCRIPTS`, `scripts/systems/time/simulation_clock.gd :: SimulationClock`, `scripts/systems/world/WeatherController.gd`, `scripts/systems/world/snow/snow_presentation_system.gd`.

## 2.2. Shelter-as-verb

**[IMPLEMENTED/PARTIAL]** Убежище — не статичный safe room: код поддерживает repairable breaches, carried boards, heat source/fuel, stove workflow, resting/sleeping и shelter state persistence.

**Evidence**
- `scripts/environment/interactive/breach_board_up.gd`
- `scripts/systems/survival/shelter_breach.gd`, `shelter_state.gd`, `breach_draft.gd`
- `scripts/environment/interactive/heat_source_feed.gd`, `scripts/systems/survival/heat_source.gd`
- `scripts/environment/stove/stove_visual.gd`, `stove_warmer.gd`, `lighter_strike_vfx.gd`
- `scenes/world/first_exit/first_exit_blockout.tscn :: ShelterHouse/House`
- `scripts/world/key_west_first_exit.gd :: _transplant_first_exit()` переносит authored shelter в Key West.

**Limitation:** реальная decision pressure от количества досок/гвоздей сейчас не подтверждена. `PRD.md` и `VERTICAL_SLICE.md` фиксируют текущий live candidate с избыточным запасом (33 boards / 66 nails / 12 logs) и отдельно говорят, что исторический scarcity target этим прогоном не валидируется.

## 2.3. Physical, diegetic handling of gear

**[IMPLEMENTED/PARTIAL]** Предметы существуют как data-driven `ItemResource`; есть body equipment slots, inventory weight, player hub, quick access, held items, held light, carried-in-hands limits и per-item `HeldFit`.

**Evidence**
- `core/items/item_resource.gd :: ItemResource`
- `core/items/held_fit.gd`
- `core/equipment/equipment_layout.gd`, `equipment_slot_definition.gd`
- `scenes/actors/player/player.tscn :: EquipmentComponent / InventoryComponent / PlayerHubComponent / QuickAccessComponent / HeldItemComponent / HeldLightComponent / CarryComponent`
- `data/equipment/player_layout.tres`
- `data/items/*.tres`.

## 2.4. Weather and world as pressure

**[IMPLEMENTED/PARTIAL]** Weather, day/night, snow, thermal state and world traversal являются системными источниками pressure.

**Evidence**
- `scenes/game/systems/world/WorldEnvironmentSystem.tscn :: DayNightManager / WorldEnvironment / ColorGradeController / SunLight`
- `scripts/systems/world/WeatherController.gd`
- `scripts/world/weather_beat.gd`
- `scripts/systems/world/weather/snowfall_vfx.gd`
- `scripts/systems/world/snow/{snow_shell,snow_presentation_system,footprint_system,snow_track_store}.gd`
- `scripts/systems/survival/thermal_manager.gd`.

---

# 3. Core gameplay loop

## 3.1. Intended First Exit A loop

**[DOCUMENTED INTENT]**

`Bunker → выбрать land route → найти/нести boards, tinder, fuel, food → weather turn → shelter → выбрать breaches → board windows → light/feed stove → warm/dry/recover → sleep → save/reload`

**Evidence:** `PRD.md :: Player fantasy и core loop`, `docs/game_design/VERTICAL_SLICE.md :: A — First Exit: land night`.

## 3.2. What the current runtime can support

1. **Movement/exploration — [IMPLEMENTED].** CharacterBody3D Henry, TPS camera, walk/crouch/sprint/jump, slopes, stamina, snow/load/status modifiers.  
   **Evidence:** `scenes/actors/player/player.tscn :: Player/MovementController/StaminaManager`, `scripts/actors/player/henry/Controllers/MovementController.gd`, `scenes/game/systems/camera/tps_camera.tscn`.
2. **Focus/interact/pickup — [IMPLEMENTED].** Central interaction component + reusable InteractiveArea/item pickups.  
   **Evidence:** `player.tscn :: InteractComponent`, `scripts/actors/player/henry/components/interact_component.gd`, `scenes/environment/interactive/InteractiveArea.tscn`, `scripts/environment/interactive/{interactive_area,item_pickup}.gd`.
3. **Resource carrying — [IMPLEMENTED].** 30 kg loose carry cap by default, stack rules and special two-hand carry rules.  
   **Evidence:** `inventory_component.gd :: max_carry_weight/get_add_refusal`.
4. **Survival decay — [IMPLEMENTED].** Hunger/hydration/fatigue advance on simulation hours; thermal state responds to weather/wind/equipment/wetness/zones.  
   **Evidence:** `BioMonitorManager.gd :: advance_simulation`, `ThermalManager.gd`.
5. **Shelter work — [IMPLEMENTED/PARTIAL].** Boarding, salvage, doors/cabinets, heat source/stove, rest/sleep code exists and First Exit template is transplanted into Key West.  
   **Evidence:** `scripts/environment/interactive/*`, `scripts/world/key_west_first_exit.gd :: _transplant_first_exit`.
6. **Time-costed actions — [IMPLEMENTED].** Work/sleep/wait can advance canonical simulation time through action requests.  
   **Evidence:** `scripts/systems/actions/{time_action_request,time_costed_action_system}.gd`, `scripts/systems/time/simulation_clock.gd`.
7. **Sleep/save — [IMPLEMENTED/PARTIAL].** Sleep is the in-play autosave trigger; persistence architecture is substantial, but design docs still require one coherent end-to-end human reload validation.  
   **Evidence:** `scripts/systems/save/{sleep_controller,save_manager}.gd`, `VERTICAL_SLICE.md :: Remaining A blockers`.

## 3.3. Current blocker to the intended opening

**[CONTRADICTION]** `scenes/world/key_west/key_west.tscn :: World` currently sets `spawn_at_shelter = true`. `world/world.gd :: _place_player()` therefore prefers `ShelterSpawnPoint`, while PRD/Vertical Slice define the run as starting at the bunker. The game systems support the intended loop, but the checked-in production main scene currently bypasses its intended first leg unless another runtime change overrides this flag.

---

# 4. Player abilities

| Ability | Status | Runtime evidence |
|---|---|---|
| Walk / directional locomotion | **IMPLEMENTED** | `project.godot :: move_forward/backward/left/right`; `MovementController.gd`; `player.tscn :: MovementController` |
| Sprint + stamina | **IMPLEMENTED** | `project.godot :: sprint`; `MovementController.gd`; `StaminaManager.gd` |
| Crouch | **IMPLEMENTED** | `project.godot :: crouch`; `InputSystems.get_lean_axis/is_crouching`; `MovementController.set_crouching` |
| Jump | **IMPLEMENTED** | `project.godot :: jump`; `InputSystems.jump_pressed`; `MovementController.gd` |
| Lean left/right | **IMPLEMENTED/PARTIAL** | `project.godot :: lean_left/lean_right` (Q/E), `InputSystems.get_lean_axis`; camera/player consumption is present in TPS/player scripts but this GDD does not assume combat use |
| Shoulder swap | **IMPLEMENTED** | `project.godot :: switch_shoulder` (Z), `InputSystems.consume_switch_shoulder`, `tps_shoulder_state.gd` |
| Interact press/hold/release | **IMPLEMENTED** | `project.godot :: interact` (F); `InputSystems` interact claim system; `InteractComponent` |
| Pickup/store/use physical items | **IMPLEMENTED/PARTIAL** | Inventory/Equipment/QuickAccess/HeldItem components in `player.tscn`; catalog in `data/items/` |
| Carry bulky objects in hands | **IMPLEMENTED** | `ItemResource.carried_in_hands/hand_carry_limit`, `CarryComponent`, `drop_carried` (G) |
| Use quick-access slots | **IMPLEMENTED/PARTIAL** | actions `select item slot 1..4`, `quick_use`, `quick_prev`, `quick_next`; `QuickAccessComponent` |
| Wear clothing / insulation | **IMPLEMENTED** | `EquipmentComponent`, garment resources, ThermalManager lookup |
| Board breaches / hammer work | **IMPLEMENTED** | `HammerComponent`, `WoodWorkComponent`, `breach_board_up.gd` |
| Place/use bedroll | **IMPLEMENTED/PARTIAL** | `BedrollComponent`, `rest_component.gd`, save contract; human-flow verification still pending per slice docs |
| Scoop/handle snow | **IMPLEMENTED/PARTIAL** | `SnowScoopComponent`, `snow_handful.tres`, mug snow/water item states |
| Flashlight / held flare | **IMPLEMENTED/PARTIAL** | `HeldLightComponent`, `HeldFlare.tscn`, `held_flare.gd`, `Flashlight.tscn` |
| Narrow passage traversal | **IMPLEMENTED/PARTIAL** | `passage_traversal_component.gd`, `scripts/environment/passage/{narrow_passage,passage_info}.gd` |

### Default input map relevant to gameplay

**Evidence: `project.godot [input]`.** W/S/A/D movement, Space jump, sprint action, F interact, LMB `fire`, Tab `open hub`, Escape pause/sleep cancel, 1–4 item slots, Q/E lean, Z shoulder switch, C crouch, G drop carried, M dev map; middle mouse `quick_use`, wheel directions `quick_prev/quick_next`.

**Important:** existence of `fire` **does not mean combat exists**; see Combat section.

---

# 5. Progression

## 5.1. Current progression model

**[PARTIAL / SYSTEMIC, NOT META-PROGRESSION]** В коде нет подтверждённой XP/level/perk/skill-tree progression. Текущий “progress” — изменение состояния мира и возможностей через:

- acquired/consumed items and carried mass — `InventoryComponent`, `data/items/catalog.tres`;
- equipped garments and pocket/tool placement — `EquipmentComponent`, `player_layout.tres`;
- repaired shelter + fuel — `ShelterState`, `HeatSource`;
- persistent world pickups — `scripts/environment/interactive/pickup_ledger.gd`;
- sleep/save checkpoint — `SleepController`, `SaveManager`;
- time/weather/thermal consequences — `SimulationClock`, `WeatherController`, `ThermalManager`.

## 5.2. Not currently implemented

**[MENTIONED/ABSENT]** No XP, character levels, unlock tree, formal crafting progression, quest reward progression or active Kenny ability progression was found in the current runtime architecture. `PRD.md` explicitly places “active Kenny abilities” outside First Exit A; `VERTICAL_SLICE.md` also places large crafting trees outside A.

---

# 6. Combat, enemies and weapons

## 6.1. Combat

**[MENTIONED BUT NOT IMPLEMENTED]** Combat is explicitly out of First Exit A.

**Evidence**
- `PRD.md :: Out of scope` — Combat / enemies.
- `docs/game_design/VERTICAL_SLICE.md :: Explicitly out of A` — combat and enemies.
- `core/items/item_resource.gd` explicitly states the ADT ranged-weapon group, throwing and weapon ownership were trimmed from Hoarbound.
- `scripts/actors/player/henry/components/equipment_component.gd` documents “no weapons here”.

## 6.2. Enemies

**[ABSENT]** No production enemy actor/AI system is present in the audited `scenes/actors`, `scripts/actors`, `scripts/systems` runtime tree. The current player fantasy is environmental survival rather than enemy pressure.

## 6.3. Weapons/tools

**[PARTIAL / TOOLS, NOT COMBAT]** `data/items/` contains `axe.tres`, `knife.tres`, `hammer.tres`, `lighter.tres` and other tools. Their existence is inventory/tool data, not a combat framework. `knife` participates in food opening status/requirements through `ItemResource`; hammer participates in boarding work. No damage/attack weapon pipeline is established by these resources.

## 6.4. Orphan/forward-looking input

**[MENTIONED/TECH DEBT]** `project.godot` still defines `fire` on LMB, while the current item model says ranged weapons were removed. Until a non-combat use is explicitly connected, `fire` should be treated as an unused/legacy action, not a player ability.

---

# 7. Survival systems

## 7.1. Core temperature / cold

**[IMPLEMENTED]** `ThermalManager` owns body temperature, felt temperature, hypothermia stages, wind chill, clothing insulation, wetness penalty, drying, exertion warmth, zones and lethal floor.

**Evidence:** `scripts/systems/survival/thermal_manager.gd :: Stage, WetnessStage, advance_simulation/get_*`.

## 7.2. Clothing and wetness

**[IMPLEMENTED]** `EquipmentComponent` supplies effective insulation to ThermalManager; garment state tracks runtime condition/wetness (`core/items/garment_instance_state.gd`, `garment_data.gd`). Starter wear is authored on `player.tscn :: EquipmentComponent`: worn coat, knit hat, work trousers, worn boots, backpack.

## 7.3. Hunger / hydration / fatigue

**[IMPLEMENTED with partial depth]** Three dedicated components store the tracks; `BioMonitorManager` acts as compatibility/simulation/save facade. Awake/sleep hours have different metabolism/rest behavior. Carry weight affects fatigue.

**Partial depth:** `BioMonitorManager.apply_hunger_modifiers()` and `apply_thirst_modifiers()` currently return the base rate unchanged, so those extension seams exist without additional modifiers.

## 7.4. Health and afflictions

**[IMPLEMENTED/PARTIAL]** `player.tscn` instantiates `PlayerHealthSystem` and `AfflictionComponent`; afflictions have data/state types in `core/status/{affliction_definition,affliction_state}.gd` and a save contract. Exact long-term disease/injury content should not be inferred beyond authored definitions.

## 7.5. Stamina

**[IMPLEMENTED]** `StaminaManager` gates sprint/jump behavior used by `MovementController`.

## 7.6. Carry pressure

**[IMPLEMENTED]** Loose carry default cap is 30 kg. Two-hand objects obey visible item limits; Kenny/equipment weight feeds total carry. Load fraction affects movement and fatigue.

## 7.7. Fire / shelter / drying

**[IMPLEMENTED/PARTIAL]** Heat source, stove feed, shelter zones and drying are wired. `ShelterState` saves shelter/fire state. End-to-end player readability remains a vertical-slice validation task.

## 7.8. Weather

**[IMPLEMENTED]** `WeatherController` is created by `world.gd`; `key_west_test.tres` starts with `initial_weather_profile_id = "blizzard"`; `WeatherBeat` exists to author a timed/distance weather turn. Weather persistence participates in save.

## 7.9. Snow

**[IMPLEMENTED/PARTIAL]** Runtime includes snowfall VFX, snow presentation, local snow shell, footprints and packed track storage. `SnowTrackStore` preserves displaced local snow in coarse tiles; `snow_shell.gd` has a save key for tracks. Heavy deformation remains explicitly outside First Exit A in design docs.

## 7.10. Thin ice / cold water

**[IMPLEMENTED CODE, NOT CURRENT SLICE RUNTIME]** Ice code exists (`scripts/systems/ice/{ice_field,ice_profile,ice_gait_binder,cold_water_immersion}.gd`), including a save contract in `IceField`, but `VERTICAL_SLICE.md` explicitly states `IceField` is not in the current `world.gd` runtime system list. Therefore Coast / Thin Ice is **not** a current First Exit A mechanic.

---

# 8. Inventory, equipment and items

## 8.1. Data model

**[IMPLEMENTED]** `ItemResource` uses optional facets: garment, consumable, water state, warming/opening transitions, held fit, physical carry semantics.

**Evidence:** `core/items/{item_resource,consumable_data,garment_data,garment_instance_state,held_fit,item_traits}.gd`.

## 8.2. Catalog content currently present

**[IMPLEMENTED DATA]** `data/items/` contains authored resources including axe, backpack, bedroll, boards, firewood, hammer, Kenny, knife, clothing, lighter, mug/snow mug, nails, road flare, tinder, canned food variants, warm water variants and finite water flask states. Presence in the catalog means the item can be resolved as data; it does **not** automatically prove every item has a complete physical pickup/use animation.

## 8.3. Runtime ownership graph

```text
Player
├─ EquipmentComponent ── data/equipment/player_layout.tres
├─ InventoryComponent ──> EquipmentComponent (weight includes carried equipment)
├─ PlayerHubComponent ──> InventoryComponent + EquipmentComponent
├─ QuickAccessComponent ──> PlayerHubComponent
├─ HeldItemComponent ──> Inventory + Equipment + ConsumptionController
├─ HeldLightComponent ──> Inventory
├─ HammerComponent ──> Inventory
├─ CarryComponent ──> Inventory
├─ BedrollComponent ──> Inventory
├─ SnowScoopComponent ──> Inventory
└─ ConsumptionController ──> Inventory + Equipment + BioMonitorManager
```

**Evidence:** node-path wiring in `scenes/actors/player/player.tscn`.

## 8.4. Starter state

**[IMPLEMENTED]** `player.tscn` seeds garments (`worn_coat`, `knit_hat`, `work_trousers`, `worn_boots`, `backpack`), body-slot items (`kenny`, `lighter`, `tinder`) and loose inventory (`tinned_stew`, `mug`). Save loading replaces new-session inventory state where the relevant components implement the save contract.

---

# 9. Saving and session persistence

## 9.1. Save architecture

**[IMPLEMENTED]** `SaveManager` implements versioned JSON slots under `user://saves`, validates a three-method all-or-nothing participant contract, and writes atomically through a temporary file + rename.

Contract:

```text
get_save_key() -> StringName
get_save_data() -> Dictionary
load_save_data(data: Dictionary)
```

**Evidence:** `scripts/systems/save/save_manager.gd`.

## 9.2. Sleep = autosave

**[IMPLEMENTED/PARTIAL]** `SaveManager.SLEEP_SLOT = 0`; comments and `SleepController` establish sleeping as the in-play save trigger. Title/load support is represented by `pending_load_slot`, `has_sleep_save()` and `scenes/ui/menu/title_menu.tscn`, but the First Exit design docs still require coherent human sleep→reload validation.

## 9.3. Known save participants

**[IMPLEMENTED]** Searchable save-contract owners include:
- session — `scripts/systems/save/session_state.gd`;
- inventory — `inventory_component.gd`;
- equipment — `equipment_component.gd`;
- bio — `BioMonitorManager.gd`;
- afflictions — `affliction_component.gd`;
- weather — `WeatherController.gd`;
- thermal — `thermal_manager.gd`;
- shelter/fire state — `shelter_state.gd`;
- snow + snow tracks — `snow_presentation_system.gd`, `snow_shell.gd`;
- pickup ledger — `scripts/environment/interactive/pickup_ledger.gd`;
- authored furniture/work states such as `table_salvage.gd`;
- weather beat — `scripts/world/weather_beat.gd`.

**Limitation:** presence of individual save contracts is stronger than a stub, but it does not replace the pending production-scene end-to-end reload proof described by `VERTICAL_SLICE.md`.

---

# 10. World structure

## 10.1. Production entry scene

**[IMPLEMENTED]** `project.godot` launches `res://scenes/world/key_west/key_west.tscn`.

`key_west.tscn :: World` contains/wires:
- `StartupTitleCard`;
- `StreamContainer`;
- `Player` (`player.tscn`);
- `PlayerCamera` (`tps_camera.tscn`);
- `IslandTerrain` focused on Player;
- `WorldEnvironmentSystem`.

The root script is `world/world.gd` and the pinned profile is `data/world_profiles/key_west_test.tres`.

## 10.2. Key West world profile

**[IMPLEMENTED/PARTIAL]** `key_west_test.tres` is explicitly marked `experimental = true`. It references NOAA-derived terrain files, `key_west_first_exit.tscn`, spawn marker `SpawnPoint`, initial blizzard weather and a source manifest.

## 10.3. First Exit transplant

**[IMPLEMENTED/PARTIAL]** `KeyWestFirstExit` instantiates `scenes/world/first_exit/first_exit_blockout.tscn`, extracts `ShelterHouse/House`, `BunkerPortal`, authored pickups and spawn anchors, moves them onto Key West terrain and creates Key West-specific spawn/shelter placement. This is authored deterministic scenario composition, not random level generation.

**Evidence:** `scripts/world/key_west_first_exit.gd :: prepare_world_content/_transplant_first_exit`.

## 10.4. Terrain

**[IMPLEMENTED]** `IslandTerrain` reads a baked heightmap + metadata, while `World._apply_profile_terrain()` validates profile files before reloading. The production scene points to `world/terrain/key_west_preview_2m_la8.png/.json`.

## 10.5. City

**[IMPLEMENTED/PARTIAL, EXPERIMENTAL]** `ChunkedCityMassing` reads deterministic city/enrichment datasets (`data/world/key_west/city_preview.json`, `visual_enrichment.json`), produces ring-0 massing and near detailed geometry/roads/airport features, and exposes chunk descriptors to the shared streaming state machine. `KeyWestFirstExit.on_world_ready()` expects **148** registered runtime city chunks.

**Evidence:** `scripts/systems/world/city/chunked_city_massing.gd`, `scripts/world/key_west_first_exit.gd`.

## 10.6. Authored chunk scene assets

**[PARTIAL/LEGACY-ADJACENT]** Nine named chunk scenes remain under `scenes/game/chunks/`: Alata Battery, East Point Redoubt, Echo Glade, Gateway Cove, Guards Beach, Radio Shadow, The Patrol Trail, The Pit Descent, The Waiting Hill. The current Key West main path registers runtime city chunks instead of referencing those scene assets, so they must not be described as the current island's active regions without an explicit runtime reference.

---

# 11. World streaming

## 11.1. Streaming owner

**[IMPLEMENTED]** `core/world/streaming_system.gd :: StreamingSystem` is instantiated by `world/world.gd` and owns the state machine:

`UNLOADED → QUEUED → LOADING → READY → ACTIVE → UNLOADED`.

It supports threaded `PackedScene` loading, a concurrency budget, one-per-frame instantiation budget, XZ distance bands and unload hysteresis.

Default tuning in code:
- `load_margin_m = 140`;
- `unload_hysteresis_m = 120`;
- `rescan_distance_m = 40`;
- `max_concurrent_loads = 2`;
- `instantiation_budget_per_frame = 1`.

## 11.2. Ring 0

**[IMPLEMENTED]** Static `WorldData` can provide never-unloaded silhouette scenes in `Ring0`; runtime sources may implement their own ring-0 builder.

## 11.3. Key West runtime streaming

**[IMPLEMENTED/PARTIAL]** The Key West profile does not author a static `world_data_path`; StreamingSystem therefore supports runtime-only initialization, and `KeyWestFirstExit` registers `ChunkedCityMassing` as the runtime source. Exact geometry is built/removed around the player while city source JSON stays immutable.

## 11.4. Streaming limitation

The top comment/default path in `StreamingSystem` still names `archive/graciosa/data/world_data.tres`, while the class now supports profile override and runtime sources. This is stale documentation/default fallback rather than a description of the current pinned Key West runtime.

---

# 12. Procedural / generated content

## 12.1. What is actually procedural

**[IMPLEMENTED/PARTIAL]** The project contains runtime-generated geometry/presentation built deterministically from baked geographic data, especially `ChunkedCityMassing` and terrain/city enrichment pipelines.

## 12.2. What it is not

**[NOT IMPLEMENTED]** No evidence supports a roguelike-style random world seed, random quest generation, random dungeon generation or procedurally changing Key West topology. The First Exit scenario uses fixed authored coordinates and data; `KeyWestFirstExit` constants define bunker/shelter positions and transplant deterministic authored content.

---

# 13. Quests / objectives

## 13.1. Formal quest framework

**[NOT IMPLEMENTED]** No production `Quest`, `QuestManager`, objective graph or reward-state subsystem was found in the first-party runtime architecture.

## 13.2. Scenario objective structure

**[PARTIAL / DOCUMENT-DRIVEN]** First Exit functions as an authored scenario objective sequence rather than a formal quest system. Progress is currently inferred from world actions/state: leave/start point, acquire supplies, weather beat, repair shelter, fire, recovery, sleep/save.

**Evidence:** `PRD.md`, `VERTICAL_SLICE.md`, `KeyWestFirstExit`, `WeatherBeat`, shelter/save systems.

**Unknown design decision:** whether Hoarbound will ever need an explicit quest journal/objective state machine, or whether survival state/world affordances remain the primary guidance model.

---

# 14. Vehicles / transport

## 14.1. Drivable transport

**[NOT IMPLEMENTED]** No vehicle controller/enter-drive-exit gameplay system is present in the production runtime tree.

## 14.2. Environmental vehicles

**[IMPLEMENTED AS WORLD CLUTTER]** First Exit world-building tools can generate cars/pickups/vans/buses as wreck/street-furniture forms with roll/sink/open-door presentation. These are spatial/readability props, not transport.

**Evidence:** `tools/world/build_first_exit_blockout.gd`, `docs/world/FIRST_EXIT.md`. `docs/technical/PORTED_FROM_ADT.md` explicitly states vehicle functionality was dropped during the ADT port.

---

# 15. UI / UX

## 15.1. Runtime HUD composition

**[IMPLEMENTED]** `player.tscn` directly owns:
- `MouseCursorUI` — `scenes/ui/hud/dynamic_cursor/mouse_cursor_ui.tscn`;
- `VitalHUD` — `scenes/ui/hud/vitals/vital_hud.tscn`.

`VitalHUD` contains `HealthStrip` and `VitalCluster` anchored to the lower-left area.

## 15.2. World-level UI

**[IMPLEMENTED, partly developer-facing]** `world/world.gd :: WORLD_UI_SCENES` instantiates into a shared CanvasLayer:
- `tools/StatsDisplay/StatsDisplay.tscn`;
- `scenes/ui/debug/dev_diorama_map.tscn`;
- `scenes/ui/hud/input_hints/key_hints_panel.tscn`;
- `scenes/ui/hud/sleep_prompt.tscn`;
- `scenes/ui/menu/pause_menu.tscn`.

`key_west.tscn` currently enables runtime dev map.

## 15.3. Interaction readability

**[IMPLEMENTED/PARTIAL]** There are dedicated 3D action prompt, dynamic cursor, input hint catalog/panel and sleep prompt systems:
- `scenes/ui/hud/action_prompt/action_prompt_3d.tscn`;
- `scripts/ui/hud/action_prompt/{action_prompt_3d,action_prompt_face}.gd`;
- `scripts/ui/hud/dynamic_cursor/mouse_cursor_ui.gd`;
- `data/key_hints.tres`.

## 15.4. Player Hub

**[IMPLEMENTED/PARTIAL]** Hub ownership is on `player.tscn :: PlayerHubComponent`, with `scripts/ui/hud/player_hub_panel.gd` as UI implementation and `QuickAccessComponent` depending on Hub. It is a real inventory/equipment interaction layer, but the design docs still list new-player validation/readability as Now/Next work.

## 15.5. Menus

**[IMPLEMENTED/PARTIAL]** Pause and title menu scenes/scripts exist. `project.godot` launches the world scene directly rather than `title_menu.tscn`, so this GDD does not claim the title menu is the current process entry point. Startup presentation instead includes `StartupTitleCard` inside `key_west.tscn`.

---

# 16. Audio

**[IMPLEMENTED/PARTIAL]** `SoundSystem` is an autoload. `WorldAudioBinder` feeds weather wind, shelter/interior state and foot-contact/snow information into audio parameters/events.

**Evidence:** `project.godot [autoload] :: SoundSystem`, `core/audio/{sound_system,sound_event,sound_layer}.gd`, `scripts/systems/audio/world_audio_binder.gd`, `player.tscn :: FootContactSensor`.

Route-specific ambience remains a P1 readability target in `VERTICAL_SLICE.md`; do not describe a complete adaptive score/route audio system yet.

---

# 17. Camera and locomotion UX

**[IMPLEMENTED]** Third-person camera is a dedicated scene and component family:
- `scenes/game/systems/camera/tps_camera.tscn :: PlayerCamera`;
- `scripts/systems/camera/tps_camera.gd`;
- `tps_auto_look.gd`, `tps_boom_probe.gd`, `tps_camera_fader.gd`, `tps_passage_framing.gd`, `tps_shoulder_state.gd`.

Locomotion has authored walk/crouch/sprint speed, slope response, acceleration/deceleration, stamina and load/snow/status multipliers (`MovementController.gd`).

**Technical inconsistency:** `core/input/input_systems.gd` declares that only it reads `Input` directly, but current `scripts/actors/player/henry/Player.gd` still computes movement from `Input.get_action_strength(...)`, and `MovementController.gd` contains a direct `Input.is_action_pressed("sprint")` query. The intended single-input-owner architecture is therefore **PARTIAL**, not fully enforced.

---

# 18. Technical architecture

## 18.1. Engine/runtime configuration

**[IMPLEMENTED]** `project.godot` declares Godot feature set `4.8`, `C#`, `Forward Plus`; project has `.csproj/.sln` but the audited gameplay runtime is predominantly GDScript. Main output is PC-oriented per README/PRD.

## 18.2. Autoloads

Production/global autoloads in `project.godot`:
- `PlayerState` → `core/player_state/player_state.gd`;
- `InputSystems` → `core/input/input_systems.gd`;
- `SoundSystem` → `core/audio/sound_system.gd`;
- `_mcp_game_helper` → `addons/godot_ai/runtime/game_helper.gd` (**development/plugin helper, not gameplay**).

## 18.3. Composition root

**[IMPLEMENTED]** `world/world.gd` is the world composition root. It owns three declarative groups:
1. `WORLD_SYSTEM_SCRIPTS` — Node systems constructed by `.new()`;
2. `WORLD_3D_ENTITY_SCENES` — standalone scenes (currently empty list);
3. `WORLD_UI_SCENES` — shared world UI scenes.

Initialization order is explicit: resolve nodes → profile terrain/content → build systems → place player → build `WorldContext` → call optional `on_world_ready(context)` recursively → build standalone entities/UI.

## 18.4. Runtime system list

`world/world.gd :: WORLD_SYSTEM_SCRIPTS` currently creates:
- SimulationClock;
- TimeCostedActionSystem;
- WeatherController;
- SnowfallVFX;
- SnowPresentationSystem;
- FootprintSystem;
- SnowShell;
- SaveManager;
- StreamingSystem;
- ThermalManager;
- ShelterState;
- ShelterGradeBinder;
- WorldAudioBinder;
- SleepController;
- SessionState.

This list is a stronger indicator of production status than the mere existence of a script elsewhere.

## 18.5. WorldContext dependency injection

**[IMPLEMENTED]** `core/world/world_context.gd` carries references to player, camera, stream container, world and system list; systems resolve dependencies from context rather than hard-coded scene paths where possible.

## 18.6. Canonical time

**[IMPLEMENTED]** `SimulationClock` is the world-scoped canonical game clock; `DayNightManager` has a bridge/reference to it rather than being a second independent production clock. Time-costed actions, weather and survival systems consume deterministic simulation slices.

**Evidence:** `scripts/systems/time/simulation_clock.gd`, search/use in `DayNightManager.gd`, `WeatherController.gd`, `ThermalManager.gd`, `SleepController.gd`.

## 18.7. Data-driven authoring

**[IMPLEMENTED]** Major runtime data is authored as resources/JSON rather than per-case code: items, equipment layouts, world profiles, terrain metadata, city preview/enrichment and (for static/archived worlds) `WorldData/ChunkData`.

---

# 19. Rendering / presentation architecture relevant to design

**[IMPLEMENTED/PARTIAL]**

- Forward Plus renderer — `project.godot`.
- Internal 3D scaling is `0.77`; screen-space AA enabled; 3D MSAA disabled — `project.godot [rendering]`.
- Directional shadows use 2048 map setting; actual production `SunLight` in `WorldEnvironmentSystem.tscn` has `directional_shadow_max_distance = 20.0`.
- World environment includes fog/volumetric fog, Freeman/parallax cloud shader, day/dusk/night/shelter color-grade resources and stylized-shadow globals.
- Shader globals expose snow cover/depth/drift/wind/window plus stylized shadow brush controls — `project.godot [shader_globals]`.

This section describes presentation plumbing only; it does not claim a final art-quality pass.

---

# 20. Scene audit — current first-party production scene surface

The following scene files exist under `scenes/` and are treated as first-party game scenes. `archive/`, addon demos and test/CI scenes are not promoted to gameplay. `tools/StatsDisplay/StatsDisplay.tscn` is the exception because `world.gd` explicitly instantiates it at runtime.

## Actors
- `scenes/actors/player/player.tscn` — Henry gameplay root.
- `scenes/actors/player/HenryUALVisual.tscn` — skinned visual/animation scene.
- `scenes/actors/player/held/HeldFlare.tscn` — held road flare.

## Environment
- `scenes/environment/interactive/InteractiveArea.tscn`.
- `scenes/environment/props/Flashlight/Flashlight.tscn`.
- `scenes/environment/props/Masks/AFM/Airlock_Filter_Mask.tscn`.
- `scenes/environment/shelter/test_shelter.tscn` — test/support scene, not production main world.
- `scenes/environment/visual_fx/FadeVolume.tscn`.

## Game systems/content
- `scenes/game/systems/camera/tps_camera.tscn`.
- `scenes/game/systems/world/WorldEnvironmentSystem.tscn`.
- `scenes/game/chunks/chunk_alata_battery.tscn`.
- `scenes/game/chunks/chunk_east_point_redoubt.tscn`.
- `scenes/game/chunks/chunk_echo_glade.tscn`.
- `scenes/game/chunks/chunk_gateway_cove.tscn`.
- `scenes/game/chunks/chunk_guards_beach.tscn`.
- `scenes/game/chunks/chunk_radio_shadow.tscn`.
- `scenes/game/chunks/chunk_the_patrol_trail.tscn`.
- `scenes/game/chunks/chunk_the_pit_descent.tscn`.
- `scenes/game/chunks/chunk_the_waiting_hill.tscn`.

## UI / splash
- `scenes/splash/splash_scene.tscn`.
- `scenes/ui/debug/dev_diorama_map.tscn`.
- `scenes/ui/hud/action_prompt/action_prompt_3d.tscn`.
- `scenes/ui/hud/dynamic_cursor/mouse_cursor_ui.tscn`.
- `scenes/ui/hud/input_hints/key_hints_panel.tscn`.
- `scenes/ui/hud/sleep_prompt.tscn`.
- `scenes/ui/hud/vitals/vital_hud.tscn`.
- `scenes/ui/menu/pause_menu.tscn`.
- `scenes/ui/menu/title_menu.tscn`.

## World
- `scenes/world/key_west/key_west.tscn` — **main scene**.
- `scenes/world/key_west/key_west_first_exit.tscn` — profile content bootstrap (`KeyWestFirstExit` + `WindGusts`).
- `scenes/world/first_exit/first_exit_blockout.tscn` — reusable authored First Exit template transplanted by Key West runtime.

---

# 21. Current limitations

1. **First Exit opening is currently bypassed in main scene.** `key_west.tscn :: spawn_at_shelter = true` conflicts with the bunker-first loop.
2. **No completed stranger-run proof.** PRD/Vertical Slice still treat one continuous 10–15-minute run and coherent reload as acceptance work.
3. **Combat/enemies absent by design for A.** `fire` remains in InputMap but no production weapon/combat stack backs it.
4. **No drivable vehicles.** Vehicle geometry is environment clutter only.
5. **No formal quest/progression framework.** Current progression is systemic/world-state driven.
6. **Thin ice not integrated into First Exit A.** Ice code exists, but `IceField` is not in `WORLD_SYSTEM_SCRIPTS`.
7. **Input ownership is inconsistent.** `InputSystems` architecture rule is violated by direct reads in Player/MovementController.
8. **Key West profile is still marked experimental.** `data/world_profiles/key_west_test.tres :: experimental = true`.
9. **City streaming source labels itself experimental.** `chunked_city_massing.gd` header still calls it an experimental renderer even though current Key West content uses it.
10. **Debug/dev UI is mixed into production composition.** StatsDisplay, dev map and environment debug controls exist in runtime scene/composition; visibility/gating must remain deliberate for release builds.
11. **Some naming/provenance is stale.** HFN-prefixed color-grade resources and HFN comments remain; StreamingSystem's default/comment still points to archived Graciosa.
12. **Nine authored chunk scenes are not the current Key West runtime source.** Their future ownership should be explicit to avoid two competing world-content models.
13. **Survival extension seams are not all populated.** Hunger/thirst modifier hooks currently pass base rates through unchanged.
14. **World content is data-heavy and system-complete relative to content breadth.** The code supports more systemic state than First Exit currently proves in human play; feature expansion before the loop closes risks hiding usability/balance defects.

---

# 22. Contradictions and unknown design decisions

| Priority | Question / contradiction | Evidence | Required decision |
|---|---|---|---|
| **P0** | Bunker-first design vs shelter-first checked-in main scene | `PRD.md`, `VERTICAL_SLICE.md` vs `key_west.tscn :: spawn_at_shelter = true`; `World._place_player()` | Restore bunker start for production run, or explicitly redefine First Exit and docs. |
| **P0** | Single Input owner rule is not enforced | `core/input/input_systems.gd` header vs direct `Input.*` reads in `Player.gd` / `MovementController.gd` | Finish migration to InputSystems or relax/document the architecture rule. |
| **P0** | “Implemented persistence” vs “coherent reload not human-verified” | many `get_save_key()` implementations vs `VERTICAL_SLICE.md :: Remaining A blockers` | Treat system tests as necessary but not sufficient; execute canonical sleep/load run. |
| **P1** | First Exit scarcity values are not settled | PRD/Vertical Slice: historical 15/30 vs retained 33/66/12 candidate | Decide whether current abundance is test scaffolding or shipping balance. |
| **P1** | What guides the player without quests? | No quest subsystem; First Exit relies on world grammar and prompts | Decide whether diegetic guidance is sufficient or a lightweight objective layer is needed. |
| **P1** | `fire` input without combat | `project.godot :: fire`; weapon group explicitly removed in `ItemResource` | Remove/repurpose action until combat is deliberately scheduled. |
| **P1** | Debug UI in runtime composition | `world.gd :: WORLD_UI_SCENES`, `key_west.tscn :: enable_runtime_dev_map = true`, `WorldEnvironmentSystem.tscn :: Debug*` | Define dev/export gating and release ownership. |
| **P1** | World-profile fallback still says Graciosa | `WorldProfileCatalog.DEFAULT_PROFILE_ID = "graciosa"`; current main pins Key West and Graciosa is archived | Decide fallback semantics or rename/remove stale default. |
| **P1** | StreamingSystem documentation/default is stale | `streaming_system.gd :: DEFAULT_WORLD_DATA/archive/graciosa` while Key West uses runtime-only source | Make current multi-profile/runtime-source contract explicit. |
| **P1** | `VERTICAL_SLICE.md` contains an outdated “real Graciosa scene” phrase inside a Key West target | `VERTICAL_SLICE.md :: P0 stranger playtest` vs its own Key West header/current scope | Correct wording so QA cannot test the wrong world. |
| **P2** | Future role of the nine `scenes/game/chunks` scenes | Present in tree; current Key West city comes from runtime `ChunkedCityMassing` | Archive, repurpose or document them as another profile/content set. |
| **P2** | Thin ice: signature feature or separate optional slice? | Ice implementation exists but is intentionally absent from A | Lock B acceptance criteria before integrating into production system list. |
| **P2** | Combat/enemies: later pillar or permanently out? | Explicitly out of A, no current stack | Do not build enemy/weapon architecture until product direction says environmental survival needs it. |
| **P2** | Meta progression / formal quests | No current subsystem | Decide only after First Exit proves the systemic loop; current architecture does not require either. |

---

# 23. Roadmap

This section separates the **existing product roadmap** from **technical/design recommendations produced by this audit**.

## 23.1. Existing product roadmap

From `PRD.md`:
- **Now:** First Exit A; core actions exist, live run not confirmed.
- **Now/Next:** Diegetic Inventory + Player Hub; physical items/Quick Access exist, new-player validation remains.
- **Next:** Coast / Thin Ice B.
- **Later:** survival-pressure polish/readability/captures.

## 23.2. Recommended closure order from this audit

### P0 — prove the game that already exists

1. **Resolve spawn contradiction** before any canonical playtest: production First Exit must start where the acceptance path says it starts.  
   Files: `key_west.tscn`, `world/world.gd`, `KeyWestFirstExit`.
2. **Run one canonical bunker→shelter→sleep→reload pass** and record failures by system boundary, not by symptom.  
   Systems: interaction, inventory/equipment, weather beat, shelter, stove, thermal, save/pickup ledger.
3. **Verify coherent save closure** for the exact participants promised in PRD: shelter, fuel, weather, bedroll, inventory/equipment and consumed world pickups.
4. **Finish InputSystems ownership migration** so event timing and pause/mode blocking have one authority.

### P1 — make decisions readable

5. Validate route differentiation without dev map: road / exposed shore / ruins must read through geometry, sightlines, weather exposure and audio rather than labels.
6. Validate scarcity with the intended stock target; keep “interaction proof stock” and “shipping balance stock” as explicit profiles if both are still needed.
7. Validate Hub/Quick Access with a fresh player: physical pocket placement must not become UI bookkeeping.
8. Gate StatsDisplay/dev map/debug accelerators by development build/export policy.
9. Clean stale naming/defaults (`HFN_*`, Graciosa fallback/comments) where they can mislead authoring or QA.

### P2 — extend only after A closes

10. Integrate Coast / Thin Ice B through the existing world/system lifecycle instead of a parallel scene-specific manager.
11. Decide whether formal objectives are necessary only after observing First Exit navigation failures; prefer world/readability fixes when the problem is spatial grammar.
12. Decide combat/enemies as a product pillar before reintroducing ADT weapon abstractions. Current code intentionally removed them.
13. Decide the long-term content model for static `WorldData/ChunkData` scenes versus runtime-generated Key West city sources; keep one streaming owner either way.

---

# 24. Dependency map

```text
project.godot
├─ main_scene -> scenes/world/key_west/key_west.tscn
├─ Autoload PlayerState
├─ Autoload InputSystems
├─ Autoload SoundSystem
└─ dev/plugin helper _mcp_game_helper

key_west.tscn :: World (world/world.gd)
├─ world_profile -> data/world_profiles/key_west_test.tres
│  ├─ terrain -> Key West heightmap/meta
│  └─ content -> key_west_first_exit.tscn
│     └─ KeyWestFirstExit
│        ├─ transplants first_exit_blockout.tscn
│        └─ registers ChunkedCityMassing -> StreamingSystem
├─ Player -> player.tscn
│  ├─ movement/stamina/health/bio/afflictions
│  ├─ inventory/equipment/hub/quick access
│  ├─ held/carry/work/rest components
│  └─ cursor + vital HUD
├─ PlayerCamera -> tps_camera.tscn
├─ IslandTerrain
├─ WorldEnvironmentSystem
│  ├─ DayNightManager <-> SimulationClock bridge
│  ├─ SunLight / WorldEnvironment
│  └─ ColorGrade / performance / shadow policies
└─ World systems created by world.gd
   ├─ SimulationClock -> deterministic simulation slices
   ├─ TimeCostedActionSystem
   ├─ WeatherController -> Thermal/Snow/Audio
   ├─ Snow systems
   ├─ StreamingSystem -> runtime city chunks
   ├─ ThermalManager -> Equipment + Weather + Zones
   ├─ ShelterState -> breaches/fires
   ├─ SaveManager -> systems + player subtree contracts
   ├─ SleepController -> time + save
   └─ SessionState
```

---

# 25. Senior design assessment

The current repository is **not an empty prototype with disconnected survival scripts**. It already has a coherent systemic spine: a composition root, canonical simulation time, environmental pressure, data-driven items/equipment, physical carry costs, shelter work, sleep/save persistence, deterministic world/profile loading and one streaming owner. The strongest design identity visible in code is **environmental survival through connected state**, not combat.

The main risk is therefore not “missing more systems”; it is **failing to prove the existing systems as one readable 10–15-minute decision loop**. The repository contains enough mechanics to generate complexity faster than First Exit can currently validate it. Until bunker→route→weather→shelter→sleep/reload works cleanly for a fresh player, additional combat, quest, vehicle or meta-progression architecture would increase surface area without proving the core fantasy.

That conclusion is grounded in the current code paths above and in the project's own acceptance docs; it is a recommendation, not a claim that future combat/progression is forbidden.
