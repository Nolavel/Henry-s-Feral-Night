#!/usr/bin/env bash
## Provisions Godot 4.8-dev6 mono + CPU Vulkan (lavapipe) in a fresh container.
##
## Run this WITHOUT sudo. Only the apt step needs root and asks for it itself:
## under `sudo -E` the whole script runs as root, $HOME/.local is created root-
## owned, and every later unprivileged step then fails to write user://.
set -euo pipefail

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
	SUDO="sudo"
fi

GODOT_VERSION="${GODOT_VERSION:-4.8-dev6}"
GODOT_PKG="Godot_v${GODOT_VERSION}_mono_linux_x86_64"
PREFIX="$HOME/.local/opt"

$SUDO apt-get update -qq
$SUDO apt-get install -y -qq mesa-vulkan-drivers vulkan-tools xvfb unzip dotnet-sdk-8.0

mkdir -p "$PREFIX" "$HOME/.local/bin"
if [ ! -x "$PREFIX/godot-mono/${GODOT_PKG%_x86_64}.x86_64" ]; then
	curl -sSL -o /tmp/godot.zip \
		"https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/${GODOT_PKG}.zip"
	unzip -q -o /tmp/godot.zip -d "$PREFIX"
	rm -rf "$PREFIX/godot-mono"
	mv "$PREFIX/$GODOT_PKG" "$PREFIX/godot-mono"
fi
ln -sf "$PREFIX/godot-mono/${GODOT_PKG%_x86_64}.x86_64" "$HOME/.local/bin/godot"

## Terrain3D GDExtension binaries are not vendored; fetch the pinned release.
TERRAIN3D_VERSION="${TERRAIN3D_VERSION:-v1.0.1-stable}"
TERRAIN3D_ZIP="${TERRAIN3D_ZIP:-Terrain3D_v1.0.1.zip}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [ ! -f "$PROJECT_DIR/addons/terrain_3d/bin/libterrain.linux.debug.x86_64.so" ]; then
	curl -sSL -o /tmp/terrain3d.zip \
		"https://github.com/TokisanGames/Terrain3D/releases/download/${TERRAIN3D_VERSION}/${TERRAIN3D_ZIP}"
	unzip -q -o /tmp/terrain3d.zip "addons/terrain_3d/bin/*" -d "$PROJECT_DIR"
	rm -f /tmp/terrain3d.zip
fi

"$HOME/.local/bin/godot" --headless --version
