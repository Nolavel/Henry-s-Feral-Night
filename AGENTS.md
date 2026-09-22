# AGENTS.md

This file applies to the entire repository.

## Branch ownership — strict rule

One agent uses one branch. Agents never share a working branch.

- Codex owns `codex`.
- Any other AI/automation agent must create and use its own uniquely named branch.
- Never commit directly to `main`.
- Never push commits to another agent's branch.
- Never force-move another agent's branch.
- Merge/rebase only when the user explicitly asks for integration.
- Before writing, verify the current branch belongs to the acting agent.

If an agent cannot create or write its own branch, it must stop instead of falling back to `main`.

## Engine baseline

- Godot: **4.8 dev6 .NET (mono)**
- Godot.NET.Sdk: **4.8.0-dev.6**
- .NET target: **net8.0**
- Main development scene: `res://tests/scenes/TestScene.tscn`
- Terrain3D remains a third-party addon. Do not rewrite its internal code as project gameplay code.

## Repository hygiene

- No ProjectSettings dump/load tools in runtime.
- No generated settings dictionaries committed into `project.godot`.
- Debug/profiling UI must be lightweight and optional.
- Legacy experiments do not live in a production `garbage/` folder.
- Prefer project systems under `scripts/`; tools under `tools/` must not own gameplay state.

## Architecture guardrails

- Player movement, rotation, camera, interaction, and survival components keep separate ownership.
- Camera feedback may lag aesthetically, but input response must not be delayed by stacked smoothing systems.
- Terrain3D owns terrain geometry/LOD. Project streaming owns gameplay content chunks.
- Streaming must preload before activation and use unload hysteresis; do not load on boundary entry and immediately free on boundary exit.
- Chunk definitions are data-driven. Avoid one `@onready` variable and one `match` arm per chunk.
