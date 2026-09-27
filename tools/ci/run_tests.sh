#!/usr/bin/env bash
## Runs every headless test suite under tests/systems and fails on the first
## suite that reports a failure. A suite that hangs is killed and counts as failed.
set -uo pipefail

GODOT_BIN="${GODOT_BIN:-$HOME/.local/bin/godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export VK_DRIVER_FILES="${VK_DRIVER_FILES:-/usr/share/vulkan/icd.d/lvp_icd.json}"

status=0
shopt -s nullglob
for suite in "$PROJECT_DIR"/tests/systems/test_*.gd; do
	name="$(basename "$suite")"
	echo "== $name"
	if ! timeout "${SUITE_TIMEOUT:-180}" "$GODOT_BIN" --headless --path "$PROJECT_DIR" --audio-driver Dummy \
		--script "res://tests/systems/$name"; then
		echo "FAILED: $name"
		status=1
	fi
done

if [ "$status" -eq 0 ]; then
	echo "all suites passed"
fi
exit "$status"
