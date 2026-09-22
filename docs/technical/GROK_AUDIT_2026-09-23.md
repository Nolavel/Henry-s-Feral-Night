# Grok audit — 2026-09-23

**Agent:** Grok (xAI)  
**Branch:** `grok` (from `main` @ `fd243d14`)  
**Role:** Professional game-development analyst; commercial + technical readiness  
**Baseline:** `main` after merge of PR #2 (claudeflow survival systems, ASCII fixes, CI harness)

This document is the first commit on the `grok` branch. It does not change gameplay code.
It re-evaluates product readiness against the agreed vertical slice and the earlier commercial assessment.

---

## 1. What the project is (confirmed)

Third-person survival-action in a nuclear-winter setting on Godot **4.8-dev6 .NET (mono)**, `net8.0`, Forward+/Vulkan.

Core fantasy (VERTICAL_SLICE.md): alone on a frozen island, cold rising, ice as road and trap, sleep-to-save.

Differentiating systems already present:
- Cursor-driven rotation / camera (signature feel).
- Thermal model + weather state machine + heat sources + fuel.
- Ice field (gait-scaled load, creak → crack → break, cold-water immersion).
- Sleep-to-save with hold UI and fuel checks.
- Data-driven world streaming (composition root, WorldContext, chunk resources).
- CI: tests + headless render + non-ASCII filename gate.

---

## 2. Vertical slice status vs definition ("One Night on the Ice")

| Pillar | VERTICAL_SLICE (2026-09-22 target) | Status on main @ fd243d14 | Gap for playable demo |
|---|---|---|---|
| **Cold / body temperature** | Missing; HUD only | **Done** — ThermalManager, zones, heat sources, basal metabolism, HUD binding, tests | Tune "shelter too safe"; expose failure to player clearly |
| **Hunger / thirst** | BioMonitor exists; need food items | Partial — rates exist; **food items + search reason still thin** | Place 3–4 findable food items in the sub-area |
| **Shelter + sleep-to-save** | Missing | **Done** — SleepController, SaveManager, fuel burn, hold-to-sleep UI, tests | One authored shelter that is findable on first play |
| **Breaking ice** | Missing | **Done** — IceField, IceProfile, IceGaitBinder, immersion, audio-first ladder, tests | **Crouch still missing** — careful crossing unavailable; bay shortcut currently too safe when sprinted |
| **Island / streaming** | Terrain + hardcoded chunks | **Done** — data-driven streaming, generator, 9 chunks, composition root | Ring-0 silhouettes empty; dress **one** sub-area for winter; pick playable bounds |
| **Day/night + weather** | DayNight exists; wind not gameplay | **Improved** — weather profiles, wind chill in thermal | Wind VFX/audio optional for slice |
| **Character + camera** | Works | Works | None blocking |

**Net:** The systems that blocked the slice in the 2026-09-22 commercial assessment are largely implemented. The remaining work is **content placement, tuning, and one sub-area** — not more architecture.

---

## 3. Scope control (hard rules for the next 4–6 weeks)

### In scope for playable vertical slice / demo

1. One continuous 5–10 minute loop on **one** sub-area of the island.
2. Spawn cold + hungry → explore → find food/fuel → optional ice shortcut → shelter → light fire → sleep → wake harder.
3. Failure: freeze, starve, fall through ice (recoverable immersion preferred).
4. Success: wake warm with a save written.
5. Menu: start / load last sleep / quit (minimal).
6. English player-facing strings only (via localisation keys).

### Explicitly out of scope (do not start)

- Combat, enemies, crafting trees, Gizmo's ability set, inventory depth, dialogue, the second protagonist, multiple locations, the full 27-hectare island.
- New engine features, new major systems, C# gameplay systems.
- Visual overhauls beyond what is needed for readability of cold/ice/shelter.

### Decision lock

Any PR or agent work that does not move the 5–10 minute loop closer to "stranger can play without a guide" is deferred. Author has final say; agents must flag cost before expanding scope.

---

## 4. Risk matrix

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **Godot 4.8-dev instability** | Medium | High (breaks CI / imports) | Pin exact build; one deliberate upgrade commit only; keep lavapipe CI green |
| **Ice shortcut never used** (sprint survives; no crouch) | High | High (signature mechanic invisible) | Add crouch or re-tune thickness / load so sprint fails mid-bay; force a visible choice |
| **Shelter still too safe** after fuel work | Medium | Medium | Fuel burn already added; verify one night can run a fire out mid-sleep |
| **Content emptiness** (systems without placed items/shelter) | High | High | Author/art: one shelter, 3–4 items, clear path markers |
| **Multi-agent drift** (claudeflow / codex / grok) | Medium | Medium | Strict branch ownership; AI Talk issue; merge to main only on author request |
| **Repo size / no LFS** (historical) | Medium | Medium onboarding cost | LFS migration still recommended; not blocking slice |
| **Localisation / Cyrillic in player strings** | Low (CI now blocks path homoglyphs) | Medium for external playtest | Keep English source; route HUD/prompts through translation |
| **Terrain3D binary / streaming edge cases** | Low–Med | Medium | Already fetched in CI; keep hysteresis tests green |

---

## 5. What is needed for a playable demo / vertical slice

### Must-have (block "show to stranger / publisher")

1. **One dressed sub-area** with clear landmarks (shore → bay → shelter).
2. **Placed content:** fuel, food, light source, one shelter volume that works with ThermalZone + HeatSource.
3. **Ice choice is real:** either crouch exists, or sprint-across-bay fails on current map numbers (see ICE_SYSTEM.md §7 levers).
4. **Cold pressure is legible** in HUD and failure is understandable without reading docs.
5. **Sleep-to-save** works end-to-end from cold start; load from menu restores body heat / time / inventory.
6. **Minimal shell:** title → New / Continue → quit; pause with resume/quit.
7. **CI still green** on the slice scene (render + relevant suites).

### Nice-to-have (not required for first external playtest)

- Wind audio/VFX.
- Crack decals on ice.
- Gizmo as non-interactive prop.
- Second night escalation.

### Suggested order of work (agents + author)

1. Author: freeze sub-area bounds and item list.
2. Grok/Claude: crouch or ice retune so the bay is a real risk (design decision first).
3. Content placement + one shelter scene.
4. Minimal menu / continue from last sleep.
5. Playtest loop (fail once, succeed once) and tune numbers.
6. Capture 40–60 s store-page GIF from the same path.

---

## 6. Relation to prior docs

- Supersedes the *product gap* conclusion of `COMMERCIAL_ASSESSMENT.md` §3.1 for systems that CHANGELOG shows landed on 2026-09-22; repo-hygiene items that remain open (LFS, some placeholders) are secondary to the slice.
- Complements `VERTICAL_SLICE.md`: same fantasy and pillars; this audit marks pillars that moved from "Missing" to "Done" and lists remaining content/tuning debt.
- Does not replace ICE_SYSTEM.md / THERMAL_MODEL.md / SAVE_SYSTEM.md / WORLD_ARCHITECTURE.md — those remain the technical sources of truth.

---

## 7. Agent note

- Branch ownership: **Grok owns `grok` only**. Never push to `main`, `claudeflow`, or `codex`.
- Before further commits: ensure `grok` is not behind `main` if integration happened.
- Coordination: comment on issue #1 (AI Talk) when starting overlapping work; commercial handoff also filed as a dedicated issue.

— Grok, 2026-09-23
