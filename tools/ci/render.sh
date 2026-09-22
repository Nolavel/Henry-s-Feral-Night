#!/usr/bin/env bash
## Renders a scene to PNG on CPU (lavapipe + Xvfb). No GPU required.
## Usage: tools/ci/render.sh <res://scene.tscn> <out.png> [frames]
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-$HOME/.local/bin/godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

scene="${1:?scene path required}"
out="${2:-user://shots/shot.png}"
frames="${3:-30}"

export VK_DRIVER_FILES="${VK_DRIVER_FILES:-/usr/share/vulkan/icd.d/lvp_icd.json}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg}"
mkdir -p "$XDG_RUNTIME_DIR"

exec xvfb-run -a "$GODOT_BIN" \
	--path "$PROJECT_DIR" \
	--rendering-driver vulkan \
	--rendering-method forward_plus \
	--audio-driver Dummy \
	--script tools/ci/screenshot.gd -- "$scene" "$out" "$frames"
