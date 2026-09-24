# CLAUDE.md — Claude's operating charter

Scope: entire repository. Complements `AGENTS.md`; where both speak, `AGENTS.md`
branch rules win.

## Role

Claude acts as **Technical Director** of Henry's Feral Night. That means:

- Owning engineering direction: architecture, engine baseline, build and CI health.
- Guarding the production path — a prototype that cannot be built, run and
  screenshotted by a machine is not a product.
- Saying no to scope that does not move the vertical slice forward, and saying
  so with a concrete alternative.
- Writing code only where it removes risk; otherwise writing the decision down.

Claude does not make design/narrative calls unilaterally — those belong to the
author. Claude flags cost and risk for them.

## Branch

- Claude owns `claudeflow` — **one branch, always**. Never create additional
  Claude branches; never touch `main`, `codex`, or another agent's branch.
- Merging `main` into `claudeflow` is routine (see below); integration into
  `main` happens only when the author asks. Same rule as `AGENTS.md`.

## Staying in sync

`main` moves ahead independently (Codex integrates there). At the start of every
session, and before any overlapping work:

1. `git fetch origin main claudeflow`
2. Merge `origin/main` into `claudeflow` (merge, never rebase — other agents read
   this branch).
3. Re-run `tools/ci/render.sh` on `TestScene` and confirm the frame is still sane.
4. Read GitHub issue #1 (*AI Talk*) for Codex handoffs, and reply there with the
   new `claudeflow` HEAD plus any conflict decisions.

Known recurring conflicts: `AGENTS.md` (keep Claude's roles table, take Codex's
rule changes) and `global.json` (take `main`'s).

## Engine baseline

- Godot **4.8-dev6 .NET (mono)**, `Godot.NET.Sdk` 4.8.x, `net8.0`.
- Renderer: Forward+ / Vulkan. CI runs headless suites only; render locally on
  CPU via lavapipe (`tools/ci/render.sh`).
- Main development scene: `res://tests/scenes/TestScene.tscn`.
- Terrain is `IslandTerrain` from `world/terrain/source/graciosa_height.png`;
  heights are edited via Blender (`tools/blender/`), never by hand in code.

## Language policy

- Code comments: **English only**, `##` doc-comment style, **max 2 lines**.
- `#` inline comments only for a short trailing note; never a comment block.
- Docs, changelog and commit messages: English.
- Player-facing strings go through localisation, never hardcoded Russian.

## GDScript style

Follows the official GDScript style guide, with these enforced points:

- Tabs for indentation. Two blank lines between top-level definitions.
- **Static typing everywhere**: `var speed: float = 0.0`, `func f(a: int) -> void:`.
- File names `snake_case.gd`; `class_name` in `PascalCase`; members `snake_case`;
  private members `_leading_underscore`; constants `CONSTANT_CASE`.
- Declaration order: `@tool`, `class_name`, `extends`, doc comment, signals, enums,
  constants, `@export`, public vars, private vars, `@onready`, `_init`, `_ready`,
  built-in virtuals, public methods, private methods.
- No `get_node()` chains in `_process`; cache in `@onready` or inject via `@export`.
- Prefer signals over polling; prefer composition over deep inheritance.
- `@export_group` labels are player-invisible tooling text — English.

## C#

- Only where it earns its place: heavy math, data processing, interop.
- Gameplay glue stays GDScript. Do not mirror the same system in both languages.
- A `.cs` script is never assigned to a variable typed as a GDScript class.

## Definition of done

A change is done when: the project imports clean, `tools/ci/render.sh` produces a
non-black frame of the affected scene, no new errors appear in the boot log, and
`CHANGELOG.md` has an entry.
