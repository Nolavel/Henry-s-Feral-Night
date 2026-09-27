#!/usr/bin/env bash
## Import gate: fails when the project does not import cleanly.
## The first import on a cold cache logs ordering noise (a font read before it
## is imported), so the second pass is the one checked.
set -uo pipefail
GODOT="${GODOT:-$HOME/.local/bin/godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG="$(mktemp)"

"$GODOT" --headless --path "$PROJECT_DIR" --import --quit >/dev/null 2>&1
"$GODOT" --headless --path "$PROJECT_DIR" --import --quit >"$LOG" 2>&1

PATTERN='SCRIPT ERROR|Parse Error|Failed loading resource|Resource file not found|Cannot open file|Can.t open file|Error loading|Failed to load script'
if grep -E "$PATTERN" "$LOG"; then
	echo "import gate: the project does not import cleanly (see above)" >&2
	exit 1
fi
if ! "$GODOT" --headless --path "$PROJECT_DIR" --script res://tools/ci/compile_scripts.gd >"$LOG" 2>&1 \
		|| grep -E "SCRIPT ERROR|Parse Error" "$LOG"; then
	grep -E "SCRIPT ERROR|Parse Error|compile scripts" "$LOG" >&2
	echo "import gate: a script does not compile" >&2
	exit 1
fi
echo "import gate: clean"
