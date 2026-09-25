# AGENTS.md

This file applies to the entire repository.

## Branch ownership — strict rule

One agent uses one branch. Agents never share a working branch.

- Codex owns `codex`.
- Any other AI/automation agent must create and use its own uniquely named branch.
- Never commit directly to `main`.
- Never push commits to another agent's branch.
- Never force-move another agent's branch.
- An agent may merge `main` into its own branch at any time to stay in sync (merge, never rebase).
- Integration into `main` happens only when the author asks for it.
- Before writing, verify the current branch belongs to the acting agent.

If an agent cannot create or write its own branch, it must stop instead of falling back to `main`.

## Roles

| Agent | Branch | Owns |
|---|---|---|
| **Author (human)** | any | Design, narrative, art direction, final say on scope. |
| **Claude** | `claudeflow` | Technical direction: architecture, engine baseline, build/CI, headless render pipeline, code review. See `CLAUDE.md`. |
| **Codex** | `codex` | Implementation passes: rendering/shader work, tooling, refactors it opens. |
| **Grok** | `grok` | Commercial readiness, scope control, vertical-slice readiness audits, risk matrix, and related technical docs. Proposes only; does not auto-implement gameplay. |

Handover rules:

- An agent reviews the other's branch on request; it never pushes to it.
- Conflicting opinions are resolved in writing (a note in `CHANGELOG.md` or a doc
  under `docs/`), not by silently reverting the other's work.
- Shared conventions (style, engine version, hygiene) live in this file and in
  `CLAUDE.md`; neither agent changes them without saying so in `CHANGELOG.md`.

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
