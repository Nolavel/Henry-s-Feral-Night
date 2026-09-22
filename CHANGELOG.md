# Changelog

All notable changes to Henry's Feral Night. Newest first.
Maintained per branch; entries are added by whoever makes the change.

## [Unreleased] — `grok`

### 2026-09-23 — First Grok audit (commercial + vertical-slice readiness)

Added
- `docs/technical/GROK_AUDIT_2026-09-23.md` — status of each vertical-slice pillar against `main` @ `fd243d14`, scope-control rules, risk matrix, and checklist for a 5–10 minute playable demo.
- Grok registered in `AGENTS.md` (branch `grok`, commercial/product readiness ownership).

Note
- Systems listed as "Missing" in the 2026-09-22 `VERTICAL_SLICE.md` target (thermal, ice, sleep-to-save, data-driven streaming) are largely **Done** on current `main`. Remaining work is content placement, ice risk tuning (crouch or thickness), one dressed sub-area, and a minimal menu shell — not new architecture.
- No gameplay code in this commit.

## [Unreleased] — `claudeflow`

### 2026-09-22 (12) — Fix CI: the environment, not the code

The first CI run on PR #2 went red. Every cause was in the harness I wrote.

Fixed
- `setup_env.sh` was invoked as `sudo -E`, so the **whole** script ran as root
  and created `$HOME/.local` root-owned. Every later unprivileged step then
  failed to write `user://`, which is why the save tests could not create a
  slot. Root is needed for apt and nothing else, so the script now asks for it
  itself and the workflow calls it unprivileged.
- The artifact step ran `find` over a directory that does not exist when no
  render was produced, and `bash -e` turned that into a failed job even under
  `if: always()`. It tolerates a missing directory now.
- `HeatSource.get_offset_at()` read `global_position` without checking
  `is_inside_tree()`, flooding the log with engine errors on every headless
  temperature calculation. Guarded.
- Two suites dereferenced a null `FileAccess` when `user://` was unwritable, so
  a broken environment surfaced as a crash instead of a reason. They now report
  what could not be written and why.

Changed
- **All eight suites now run from the first frame** rather than `_initialize()`.
  Three of them had been relying on a node outside the tree returning a zero
  transform that happened to equal the origin — luck, not correctness. This is
  the same Godot trap recorded in `WORLD_ARCHITECTURE.md` §8, and it is now
  handled consistently everywhere. The engine-error flood in the logs is gone
  with it (from hundreds of lines to zero).

Verified
- Eight suites pass, `TestScene` renders, the workflow's step list is intact.


### 2026-09-22 (11) — ASCII filenames and the orphaned uid

Closes §3.10 of the commercial assessment.

Renamed
- `scenes/game/Сhunks/` → `scenes/game/chunks/` — the old directory began with
  **U+0421 CYRILLIC CAPITAL ES**, visually identical to a Latin `C` and quietly
  fatal to every grep, glob, path comparison and export filter written against
  it. Nine chunk scenes moved.
- `Warning sign101х86.png` / `Warning sign60х51.png` → `warning_sign_101x86.png`
  / `warning_sign_60x51.png`. Those `х` were Cyrillic too.
- The island scene's own node names with them: `FM_Сhunks` → `FM_Chunks`,
  `Сhunk_*` → `Chunk_*`.

Removed
- `scripts/systems/world/Debug_Accelerator.gd.uid`, orphaned when the script was
  renamed to `debug_accelerator.gd`. It kept handing out `uid://cjj38qmk6jo8p`,
  which `WorldEnvironmentSystem.tscn` still referenced — the scene loaded by
  text path with a warning on every boot. The scene now points at the real
  `uid://dgvkrwulefgho` and the warning is gone.

Added
- `tools/ci/check_filenames.sh`, wired into CI ahead of the tests: fails the
  build on any non-ASCII tracked path and on any `.uid` whose script is gone.
  Neither problem can come back silently.

Verified
- Eight suites pass; `data/world_data.tres` regenerated from the normalised
  scene (9 chunks, every content scene resolved); both the island and
  `TestScene` render; the gate reports clean.

*(Full claudeflow history entries 10–1 and earlier remain on `main` CHANGELOG; this branch entry records the Grok audit. Merge to main should use `main`'s full CHANGELOG and prepend the grok Unreleased block.)*
