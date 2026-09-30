# AGENTS.md

This file applies to the entire repository.

## Branch ownership — strict rule

One agent uses one branch. Agents never share a working branch.

- Codex owns `codex`.
- Any other AI/automation agent must create and use its own uniquely named branch.
- Never commit directly to `main`.
- Never push commits to another agent's branch.
- Never force-move another agent's branch.
- Before every new task or substantial pass, an agent MUST synchronize the current `main` into its own branch; see **Mandatory pre-task sync** below.
- Integration into `main` happens only when the author asks for it.
- Before writing, verify the current branch belongs to the acting agent.

If an agent cannot create or write its own branch, it must stop instead of falling back to `main`.

## Mandatory pre-task sync

Before every new user task, substantial implementation pass, experiment,
review-with-fixes, CI repair, or resumed work after another agent may have
integrated changes, the acting agent **MUST** synchronize its permanent working
branch with the current `main` before the first write for that task.

Required order:

1. Fetch the current `main` and the agent's own permanent branch.
2. Verify whether current `main` is already an ancestor of the working branch.
3. If the branch is behind `main`, merge `main` into the working branch.
   Merge only; never rebase or force-push a shared agent branch.
4. Resolve conflicts and inspect the integrated version before editing files.
5. Only after the working branch contains current `main` may the agent make
   task-specific edits, commits, expensive CI runs, or open/update a PR.

A sync from an earlier session or an earlier task does **not** count if `main`
has moved since then. The required flow is always:

`main -> permanent agent branch -> new work -> verification -> PR/integration`

If another agent's fix has reached `main`, do not recreate, revert, or work
around that fix from a stale branch state. Sync first and inspect the integrated
version. Before reporting a recurring CI failure as unresolved, verify that the
working branch contains the latest `main`.

Never create a temporary branch merely to avoid synchronizing the permanent
agent branch.

## Roles

| Agent | Branch | Owns |
|---|---|---|
| **Author (human)** | any | Design, narrative, art direction, final say on scope. |
| **Claude** | `claudeflow` | Technical direction: architecture, engine baseline, build/CI, headless render pipeline, code review. See `CLAUDE.md`. |
| **Codex** | `codex` | Implementation passes: rendering/shader work, tooling, refactors it opens. |
| **Grok** | `grok` | Commercial readiness, scope control, vertical-slice readiness audits, risk matrix, and related technical docs. Proposes only; does not auto-implement gameplay. |

Handover rules:

- An agent reviews the other's branch on request; it never pushes to it.
- Conflicting opinions are resolved in writing (a note in `CHANGELOG.md` or a doc under `docs/`), not by silently reverting the other's work.
- Shared conventions (style, engine version, hygiene) live in this file and in `CLAUDE.md`; neither agent changes them without saying so in `CHANGELOG.md`.

## Product documents

- [PRD.md](PRD.md) — Product Requirements Document (vision, current north-star, success criteria, out of scope).
- [CONTRIBUTING_DECOMPOSITION.md](CONTRIBUTING_DECOMPOSITION.md) — правила декомпозиции PRD → Epic → User Story → Task → Subtask.
- [docs/game_design/VERTICAL_SLICE.md](docs/game_design/VERTICAL_SLICE.md) — текущий scope First Exit A.

## Engine baseline

- Godot: **4.8 dev6 .NET (mono)**
- Godot.NET.Sdk: **4.8.0-dev.6**
- .NET target: **net8.0**
- Main development scene: `res://tests/scenes/TestScene.tscn`
- Terrain is `IslandTerrain` built from the heightmap PNG; edit heights in Blender, not in code.

## Repository hygiene

- No ProjectSettings dump/load tools in runtime.
- No generated settings dictionaries committed into `project.godot`.
- Debug/profiling UI must be lightweight and optional.
- Legacy experiments do not live in a production `garbage/` folder.
- Prefer project systems under `scripts/`; tools under `tools/` must not own gameplay state.

## Architecture guardrails

- Player movement, rotation, camera, interaction, and survival components keep separate ownership.
- Camera feedback may lag aesthetically, but input response must not be delayed by stacked smoothing systems.
- `IslandTerrain` owns terrain geometry/LOD. Project streaming owns gameplay content chunks.
- Streaming must preload before activation and use unload hysteresis; do not load on boundary entry and immediately free on boundary exit.
- Chunk definitions are data-driven. Avoid one `@onready` variable and one `match` arm per chunk.
