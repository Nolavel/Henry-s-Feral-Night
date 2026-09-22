# Commercial readiness assessment — Henry's Feral Night

Reviewer: Claude (technical director)
Date: 2026-09-22
Baseline reviewed: `main` @ `29d3f2a`; **revised 2026-09-22 against `main` @ `4ba97eb`**
(fast-forwarded to Codex HEAD), plus the `prototype` branch
Engine used for verification: Godot 4.8-dev6 mono, Forward+/Vulkan on lavapipe

---

## 0. Revision note (main @ 4ba97eb)

`main` was fast-forwarded to Codex HEAD after the first pass. Several §3 findings
are **resolved** and are kept below only for the record:

- Duplicate solutions gone — one `Henry's Feral Night.sln` / `.csproj` remains,
  `Сrimson Flow.*` deleted (§3.2).
- `ProjectSettings` dump/load tooling and the `ScanFolderFiles` debug UI removed;
  `project.godot` is no longer a settings dump (§3.2).
- `DayNightCalculator.cs` deleted; the GDScript/C# duplication that broke
  `DayNightManager.gd:31` is gone (§3.4).
- `global.json` now carries `rollForward: latestFeature` + `allowPrerelease` (§3.5).
- Third-party notices landed (`docs/THIRD_PARTY_NOTICES.md`) (§3.7).
- Henry has a real UAL rig and runtime locomotion; verified rendering headlessly.

Still open: §3.1 (no game loop), §3.2 (382 MB git, no LFS), §3.3 (case/homoglyph
filenames — see §3.10), §3.6 (no tests), §3.8 (localisation debt), §3.9 (Terrain3D
binaries — now worked around by `tools/ci/setup_env.sh`).

Revised verdict: **6.5/10**. The repository hygiene gap closed noticeably; the
product gap did not move, because no playable loop was added. See
`docs/game_design/VERTICAL_SLICE.md` for the agreed target.

## 1. Verdict

The project is a **credible pre-production prototype with one genuinely
differentiating system and no product wrapper around it**. It is not a demo you
could put in front of a publisher today, but it is 2–3 focused months away from
being one — and that gap is mostly discipline, not talent.

Score on a "can this become a commercial product" axis: **6/10 now, 8/10
achievable** — conditional on the fixes in §5.

The honest framing: this is not yet a game. It is a technical playground with a
very good camera/rotation system in it. The commercial question is not "is the
tech good" (it is, in places) — it is "can a 5-minute slice be extracted from it".

## 2. What is genuinely valuable

**The cursor-driven rotation and camera system.** `RotationController.gd` (586
lines) and `PlayerCamera.gd` (448 lines) implement world-cursor lock, front/back
rotation sectors with hysteresis, adaptive delay, momentum decay and animated
180° snap turns. This is a real, non-obvious control scheme — the kind of thing
that reads as a signature mechanic in a store page GIF. Nothing else in the repo
is as defensible.

**Systemic survival scaffolding exists.** `BioMonitorManager`, `StaminaManager`,
`PlayerHealthManager`, `DayNightManager`, `WeatherController` and a 439-line
`InventoryManager` are present and wired into a HUD that boots and draws.

**The fiction is marketable.** Nuclear winter, a boy and a robot companion,
father–son dynamic, save-by-sleeping. That is a clean elevator pitch in a genre
with proven demand, and the GDD already states audience and USP.

**Terrain3D integration.** Chunked terrain streaming experiments exist on
`main`; the addon is vendored rather than forked, which is the right call.

## 3. What blocks commercialisation

### 3.1 There is no game loop
There are systems, not a loop. No objectives, no failure state, no progression,
no AI, no combat resolution, no save/load, no menu. The GDD's player loop
(explore → gather → fight/avoid → maintain warmth → sleep to save) is not
implemented end to end anywhere. **A publisher, a Kickstarter and a Steam page
all need the same thing: five uninterrupted minutes.** That artifact does not
exist yet.

### 3.2 The repository is not production-shaped
Verified on a clean checkout:

- **Three competing solutions/projects** — ``Henry`s Feral Night.sln``,
  ``Henry`s-Feral-Night.sln``, and `Сrimson Flow.sln` (note: leading **Cyrillic С**
  in the filename). `project.godot` still sets the application name and
  `dotnet/project/assembly_name` to `Сrimson Flow`. The product does not agree
  with itself about its own name — that reaches the window title and the binary.
- **`project.godot` is ~96 KB** and carries a dumped settings dictionary plus a
  `project_settings.json` / `SettingsLoader` round-trip. Engine configuration is
  being treated as runtime data. `codex` is right to call this out.
- **A `garbage/` folder is tracked**, alongside empty `levels/`, `ui/`,
  `systems/`, `autoloads/` placeholder directories.
- **A zero-byte file named `main`** is committed at the repository root.
- **`.git` is 382 MB** with 97 binary assets (PNG/JPG/GLB/FBX/TTF) committed
  directly and **no Git LFS**. At the current growth rate, onboarding a
  contributor or a CI runner becomes measured in tens of minutes. This gets
  worse monotonically and is expensive to fix later — fix it now.

### 3.3 Broken on any case-sensitive filesystem
`scenes/game/systems/world/WorldEnvironmentSystem.tscn` references
`res://scripts/systems/world/Debug_Accelerator.gd`; the file on disk is
`debug_accelerator.gd`. This loads on Windows and **fails on Linux and macOS** —
confirmed in this session's boot log. Same class of issue will appear on every
Linux/macOS export until filename casing is normalised project-wide.

### 3.4 The C#/GDScript boundary is not designed
`DayNightManager.gd:31` does `preload("DayNightCalculator.cs").new()` into a
variable typed `Node`, which is a hard parse error on 4.8 and takes
`WorldEnvironmentController.gd` down with it. More broadly: `Flashlight_Gizmo`
exists in **both** `.cs` and `.gd`, and `DayNightCalculator.cs` (388 lines)
duplicates logic that `DayNightManager.gd` (303 lines) also holds. Two languages
are being used interchangeably rather than for their strengths. The `codex`
branch has already deleted `DayNightCalculator.cs` — that direction is correct.
Pick one gameplay language (GDScript) and reserve C# for measured hot paths.

### 3.5 Build configuration is stale and over-pinned
``Henry`s-Feral-Night.csproj`` targets `Godot.NET.Sdk/4.3.0` and `net6.0` while
the engine baseline is 4.8/`net8.0`. `global.json` pinned an exact SDK patch
(`8.0.407`), so the project refused to build on any other .NET 8 install —
fixed in this branch, but symptomatic.

### 3.6 No tests, no CI, no reproducible build
`tests/` contains two scenes, not tests. Nothing verified that the project even
imports until this session. For a two-agent + one-human team, the absence of an
automated "does it still boot and draw" gate is the single highest-leverage
missing process.

### 3.7 Legal hygiene is incomplete on `main`
Character models appear to be Tripo/AI-generated (`*_tripo_rgb_*.jpg`), fonts are
third-party, Terrain3D is MIT. `main` has no third-party notices file; `codex`
has added `docs/THIRD_PARTY_NOTICES.md` and `assets/animation/ual/NOTICE.md`.
**Before any commercial release, every asset needs a documented licence and
redistribution right.** AI-generated assets in particular need their provenance
and terms recorded now, while it is still cheap to re-source them.

### 3.8 Localisation debt
30 GDScript files contain Cyrillic comments, `@export_group` labels and
`push_error` strings. Debug output in Russian surfaces in logs a publisher or QA
house will read. Player-facing strings are not routed through a translation
system, so the project is currently single-language by construction.

### 3.9 Terrain3D ships without its binaries
`addons/terrain_3d/bin/` does not exist in the repository — the GDExtension
libraries are untracked (they are `.so`/`.dll` files, and `.gitignore` does not
exclude them, so they were simply never committed). Every scene using Terrain3D
therefore fails to load on a clean checkout, on every platform. This makes the
terrain work on `main` unreproducible for a new contributor or a CI runner.
Either vendor the release binaries (LFS) or pin the addon version and fetch it
in `tools/ci/setup_env.sh`.

### 3.10 Cyrillic homoglyphs in filenames
`scenes/game/Сhunks/` begins with **U+0421 CYRILLIC CAPITAL LETTER ES**, not
Latin `C` — verified at byte level (`\320\241hunks`). The node paths inside
`WorldStreamManager.gd` (`FM_Сhunks/Сhunk_EastPointRedoubt`) carry the same
character. It is visually identical to `Chunks` and will silently defeat any
grep, glob, path comparison or export filter that anyone writes against it. The
same class of bug produced the old `Сrimson Flow` name. This is not cosmetic —
it is a defect that only shows up at the worst moment.

**Resolved 2026-09-22.** Every tracked path is ASCII: `scenes/game/Сhunks/` →
`scenes/game/chunks/`, the two `Warning sign…х…png` textures renamed, and the
scene's own node names (`FM_Сhunks`, `Сhunk_*`) normalised with them.
`tools/ci/check_filenames.sh` now fails the build on any non-ASCII tracked path,
so it cannot come back.

The same pass removed an orphaned `Debug_Accelerator.gd.uid` — left behind when
the script was renamed to `debug_accelerator.gd` — which was still handing out
`uid://cjj38qmk6jo8p` to a scene that then loaded by text path with a warning.
The gate rejects orphaned `.uid` files too.

## 4. Market position — candid

Survival-action is a crowded genre where solo/small-team entries usually fail on
content volume, not on mechanics. This project's realistic commercial paths, best
first:

1. **Narrative vertical slice → publisher / grant funding.** Strongest fit. The
   two-protagonist emotional hook and the signature camera are pitchable. Needs
   ~5 polished minutes, not a full map.
2. **Steam page + wishlist campaign on atmosphere.** Viable once the visual
   identity is finished (the `codex` shader work — fade volumes, stylised
   shadows — is aimed correctly at this).
3. **Early Access.** Not recommended at current content volume. Early Access
   punishes thin content harder than it rewards early revenue.

Realistic budget/time to a pitchable slice with the current team shape:
**2–3 months of focused work**, provided §5.1 is done first and scope is frozen.

## 5. Prioritised backlog

### 5.1 Blockers — do before any new feature (1–2 weeks)
1. Settle the product identity: one `.sln`, one `.csproj`, one application name,
   one assembly name. Delete `Сrimson Flow.*`.
2. Normalise filename casing project-wide; fix the `Debug_Accelerator.gd`
   reference. Add the boot-check CI gate so this cannot regress.
3. Delete `garbage/`, the empty placeholder directories and the stray `main` file.
4. Migrate binary assets to Git LFS and add `.gitattributes` filters.
5. Resolve the C#/GDScript overlap: remove duplicated systems, target
   `Godot.NET.Sdk` 4.8.x / `net8.0`.
6. ~~Restore Terrain3D binaries~~ — **done**: `tools/ci/setup_env.sh` fetches the
   pinned `v1.0.1-stable` release; `addons/terrain_3d/bin/` is gitignored.
6a. Purge Cyrillic homoglyphs from all paths and add a non-ASCII filename CI gate.
7. Land the engine 4.8 upgrade as **one deliberate commit** — importing under 4.8
   rewrites ~120 `.import` files; that churn belongs in its own commit, not
   scattered across feature work.

### 5.2 Product (4–8 weeks)
8. Build one playable loop in one small hand-authored location: spawn → explore →
   find resource → survive a cold/radiation pressure → sleep to save → wake.
9. Implement save/load. "Save by sleeping" is a stated USP and is currently absent.
10. Add a main menu, pause and settings. Publishers read their absence as immaturity.
11. One simple hostile entity with a readable telegraph — enough to make the
    combat pillar legible.
12. Finish Gizmo as a companion with at least one mechanical verb (scan, light,
    or unlock), not just an icon set.

### 5.3 Process (continuous)
13. Extend the CI gate from "renders" to "renders and matches a reference frame"
    for the key scenes.
14. Extract the `@export`-heavy tuning blocks into `Resource` files so designers
    tune data, not scenes.
15. Third-party notices and asset licence register on `main`.
16. Route player-facing strings through Godot localisation; English as source.

## 6. Tooling delivered with this assessment

Reproducible CPU rendering, so any agent can see the game without a GPU or a
local install:

```bash
sudo -E tools/ci/setup_env.sh                                   # Godot 4.8-dev6 mono + lavapipe
tools/ci/render.sh res://tests/scenes/TestScene.tscn user://shots/test.png 40
```

Verified in this session: Forward+/Vulkan on llvmpipe under Xvfb, `TestScene`
boots and produces a frame. This is now also a GitHub Actions job
(`.github/workflows/render-smoke.yml`) that uploads renders as artifacts.
