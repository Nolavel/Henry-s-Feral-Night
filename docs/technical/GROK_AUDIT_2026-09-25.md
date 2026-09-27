# Grok audit — 2026-09-25

**Agent:** Grok (xAI)
**Branch:** `grok`
**Baseline:** `main` @ `4c29171a3332f33337e57b4cbb579b815f171c81` (Merge PR #101 — First Exit A playtest kit)
**Role:** Professional game-development analyst. Scope control + technical readiness for vertical slice.

This document updates knowledge on the `grok` branch to the live main. Previous audit (2026-09-23) is historical. No gameplay code changed in this commit.

---

## 1. Current main snapshot (re-checked 2026-09-25 16:08 +08)

### Commits (last ~20 on main)
Heavy activity from `claudeflow` today (2026-09-25):
- Playtest kit + observer/publisher frames (#80)
- Breach drafts + single WeatherController cleanup
- Game time 60 real min/day, start at noon (#42)
- Authored WeatherBeat on route (#78)
- PickupLedger + world_id for consumed pickups (#79)
- Stove lighting as staged act, warming on ring, meal table, seated reach/wait, pack-down, recovery HUD
- Controls audit: dead actions removed, CONTROLS.md (#76)
- Full pack inspection (#75)
- Quick Access + Use contract + bedroll via preview (B removed)
- Player Hub foundation (four-flap PackRig)

### Open issues (relevant)
| # | Title | Notes |
|---|---|---|
| 42 | First Exit | Still open, high priority. Land-night tracker. |
| 80 | Continuous stranger playtest + publisher captures | Open. Kit just landed. |
| 78 | Authored weather turn | Open in tracker, but CHANGELOG shows implementation landed. Possible close candidate after verification. |
| 76 / 75 / 74 / 68 | Inventory / Hub family | Advanced significantly; many acceptance items now present. |
| 51 | Henry animation superstructure | Open |
| 16 | Snow/frost presentation | Open (wontfix label?) |
| 7 | Commercial readiness (Grok original) | Open |
| 1 | AI Talk | Open |

Milestone still centres on #42. #24 closed historically per prior notes.

### Engine / architecture (unchanged core)
- Godot 4.8-dev6 .NET, IslandTerrain + heightmap (Terrain3D removed long ago).
- Composition root, WorldContext, data-driven streaming.
- One WeatherController (empty leftover node removed today).
- Save contract with PickupLedger, WeatherBeat, stove state, etc.

---

## 2. What moved since 2026-09-23 audit

Systems that were "content debt" are now largely in place for the land loop:

- **Shelter recovery loop**: RestSpot, stove act (kneel + 5 s light), warmer ring, meal table, seated F-reach, pack/Kenny set-down, drying steam, wait-by-fire.
- **Inventory grammar**: PlayerHub (Tab), PackRig flaps, Quick Access (pockets + wheel), Use contract, hold-F placement, full inspection mode. Dead keys purged.
- **Route pressure**: Authored WeatherBeat (calm → blizzard 180 s @ 200 m / 300 s fallback → windy). Breach drafts visualise windward holes.
- **Persistence**: Consumed pickups stay gone (world_id + ledger). Game day = 60 real minutes, noon start.
- **Playtest support**: FIRST_EXIT_A_RUN.md + capture script for 6 publisher frames.

Ice remains explicitly out of First Exit A (milestone B).

---

## 3. Confirmed local base (no dissonance claimed without evidence)

Before declaring "explicit dissonance" or "technical error", the following were verified against live files/CHANGELOG on main:

- AGENTS.md on main still lists only Author / Claude / Codex. Grok role exists only in the old grok-branch audit (this is documentation lag, not a runtime error).
- WeatherBeat implementation exists and is described as finding the populated WeatherController itself; empty node was removed.
- PickupLedger + world_id on the 11 route pickups.
- Input map cleaned; CONTROLS.md is the new grammar source.
- First Exit layout is data-driven (`first_exit_layout.json` → builder → resolved.json). Positions not hand-authored in scene.
- Human speeds (1.5 / 4.5) and Kenny as 3 kg back-fixture item confirmed in docs.

Any claim of "obvious bug" below is cross-checked against CHANGELOG + open issues + key docs (FIRST_EXIT.md, CONTROLS.md, WORLD_ARCHITECTURE.md).

---

## 4. Observed confusions / discrepancies / weak points

### A. Documentation vs tracker lag (high visibility, low risk)
- #78 remains OPEN while CHANGELOG records the WeatherBeat landing. Same pattern may exist for parts of #76/#75/#74.
- Recommendation: after the playtest kit is verified, close or rewrite the implemented issues with "landed in X" notes. Keeps stranger/publisher view accurate.

### B. AGENTS.md role table incomplete on main
- Grok is not registered in the live AGENTS.md. Branch ownership rule is clear, but role visibility is missing.
- Non-blocking; can be fixed in a later docs PR from this branch if author wants.

### C. Continuous stranger path still the P0 gate (#80)
- All the new systems are in place, but the acceptance of #80 is the continuous run without debug teleports.
- Weak point: any remaining "requires knowledge of hidden key" or "clutter turns route into maze" will surface only in the observer pass. The kit now exists to catch it.

### D. Inventory depth vs First Exit scarcity
- Hub + inspection + Quick Access are sophisticated for a 10–15 min land loop. Risk of over-teaching the player before the weather turn and boarding decisions land.
- Not an error — architecture is correct for the long term — but for the vertical slice the first interaction surface should stay minimal. Playtest will show whether Tab + F is discoverable enough.

### E. Game-time / weather-beat units
- Day = 60 real min (1800+1800 s). WeatherBeat uses real seconds (180 s storm). Documented. No contradiction found, but any future authored beats must stay consistent with the real-time duration choice (clock runs a day in 144 s was the old number; now updated).

### F. No runtime IceField in First Exit A world
- Confirmed by design (milestone split). ICE_SYSTEM.md remains valid for B. No false expectation in current layout.

### G. Potential residual empty controllers / exports
- CHANGELOG notes removal of the empty WeatherController node and unread export. Good. Future agents should not re-introduce dual weather sources.

---

## 5. Technical hygiene notes (not blockers)

- CI and test suites appear to have grown with the new components (test_weather_beat, test_pickup_ledger, test_stove_act, test_pack_inspection, test_quick_access, test_seated_aim, etc.). Keep them green.
- Capture tools under `tools/runtime/` are the correct place for publisher frames; do not move proof into gameplay code.
- Layout remains the single source of truth for positions. Never hard-code coordinates in scenes for First Exit content.

---

## 6. Recommended next actions for Grok (propose only)

1. After #80 observer run results land, re-evaluate remaining open inventory issues for close/rewrite.
2. If author requests, open a small docs PR from `grok` that registers Grok in AGENTS.md + prepends this audit note to CHANGELOG Unreleased.
3. Do **not** auto-implement P1 route audio or Coast planning issues (prior standing rule).
4. Watch for any new dual-controller patterns or input actions that bypass the Use / F grammar.

---

## 7. Branch hygiene

- `grok` was ~3 days / many commits behind. This file brings knowledge current.
- Future merges: prefer `git merge main` into `grok` (never rebase) per AGENTS.md. If conflicts reappear on docs, resolve by taking main + adding the Grok audit entry.

— Grok, 2026-09-25
