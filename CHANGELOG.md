# Changelog

All notable changes to Henry's Feral Night. Newest first.
Maintained per branch; entries are added by whoever makes the change.

## [Unreleased] — `claudeflow`

### 2026-09-22 (2) — Sync with main, Terrain3D provisioning, slice definition

Changed
- Merged `origin/main` (Codex HEAD `4ba97eb`) into `claudeflow`. Conflicts:
  `AGENTS.md` kept Claude's roles table on top of Codex's rules; `global.json`
  took `main`'s version (`8.0.400` + `rollForward` + `allowPrerelease`).
- `tools/ci/setup_env.sh` now fetches the pinned Terrain3D `v1.0.1-stable`
  GDExtension binaries. They are not vendored — `addons/terrain_3d/bin/` is
  gitignored — so a clean checkout is reproducible without adding 40 MB to a
  repository that already has no LFS.
- `CLAUDE.md`: single-branch rule made explicit, plus a "Staying in sync"
  protocol (fetch, merge `main`, re-render, report in issue #1) and the list of
  recurring conflict files.

Added
- `docs/game_design/VERTICAL_SLICE.md` — the agreed next target: a *Long Dark*-style
  night on the frozen island, with the breaking-ice mechanic specified (per-tile
  integrity, creak → crack → break, cold-water survival rather than instant death),
  a pillar-by-pillar cost table, an explicit out-of-scope list and open questions.

Findings
- `scenes/game/Сhunks/` uses a Cyrillic С homoglyph (U+0421), as do the node
  paths in `WorldStreamManager.gd`. Logged as §3.10 of the assessment.
- Body temperature is not simulated anywhere; `vital_signs.gd` only displays it.
  This is the slice's core pillar and is the first system to build.

Verified
- After the merge, `TestScene` imports and renders clean: Henry's UAL rig is
  textured and posed, the day/night HUD reports live values, Terrain3D loads.


### 2026-09-22 — Agent infrastructure and headless render pipeline

Added
- `CLAUDE.md` — Claude's charter as technical director: role, branch ownership,
  engine baseline, comment policy (English, `##`, max 2 lines), GDScript style.
- `AGENTS.md` — adopted from `codex`, extended with a roles table and handover rules.
- `CHANGELOG.md` — this file.
- `tools/ci/setup_env.sh` — provisions Godot 4.8-dev6 mono, Mesa/lavapipe,
  Xvfb and .NET 8 in a clean container.
- `tools/ci/screenshot.gd` — `SceneTree` harness: boots a scene, runs N frames,
  writes the viewport to PNG.
- `tools/ci/render.sh` — one-line CPU render of any scene to PNG.
- `tools/ci/render_smoke.tscn` — minimal lit scene proving the render path.
- `.github/workflows/render-smoke.yml` — CI job importing the project and
  rendering the smoke scene on every push.
- `docs/technical/COMMERCIAL_ASSESSMENT.md` — commercial-readiness review of the
  prototype with a prioritised backlog.

Changed
- `global.json` — SDK pin `8.0.407` relaxed to `8.0.0` + `rollForward: latestFeature`,
  so the project builds on any installed .NET 8 SDK instead of one exact patch.

Verified
- Godot 4.8-dev6 mono runs Forward+/Vulkan on lavapipe (llvmpipe) under Xvfb.
- `res://tests/scenes/TestScene.tscn` boots and renders a frame headlessly.
