#!/usr/bin/env bash
## Provisions Godot 4.8-dev6 mono + CPU Vulkan (lavapipe) in a fresh container.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.8-dev6}"
GODOT_PKG="Godot_v${GODOT_VERSION}_mono_linux_x86_64"
PREFIX="$HOME/.local/opt"

apt-get update -qq
apt-get install -y -qq mesa-vulkan-drivers vulkan-tools xvfb unzip dotnet-sdk-8.0

mkdir -p "$PREFIX" "$HOME/.local/bin"
if [ ! -x "$PREFIX/godot-mono/${GODOT_PKG%_x86_64}.x86_64" ]; then
	curl -sSL -o /tmp/godot.zip \
		"https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/${GODOT_PKG}.zip"
	unzip -q -o /tmp/godot.zip -d "$PREFIX"
	rm -rf "$PREFIX/godot-mono"
	mv "$PREFIX/$GODOT_PKG" "$PREFIX/godot-mono"
fi
ln -sf "$PREFIX/godot-mono/${GODOT_PKG%_x86_64}.x86_64" "$HOME/.local/bin/godot"

"$HOME/.local/bin/godot" --headless --version
