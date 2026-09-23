"""Apply the narrow Godot 4.8 binding fix to Terrain3D v1.0.1-stable sources."""

import argparse
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    root = args.source.resolve()
    plugin = root / "project/addons/terrain_3d/plugin.cfg"
    if 'version="1.0.1"' not in plugin.read_text(encoding="utf-8"):
        raise SystemExit("Expected the upstream Terrain3D v1.0.1-stable sources")

    edits: dict[Path, str] = {}
    for kind in ("mesh", "texture"):
        path = root / f"src/terrain_3d_{kind}_asset.cpp"
        source = path.read_text(encoding="utf-8")
        replacements = {
            'D_METHOD("set_name", "name")': 'D_METHOD("set_asset_name", "name")',
            'D_METHOD("get_name")': 'D_METHOD("get_asset_name")',
            '"set_name", "get_name");': '"set_asset_name", "get_asset_name");',
        }
        for old, new in replacements.items():
            if source.count(old) != 1:
                raise SystemExit(f"Unexpected source or already patched: {path}: {old}")
            source = source.replace(old, new)
        edits[path] = source

    path = root / "src/terrain_3d_region.cpp"
    source = path.read_text(encoding="utf-8")
    binding = '\tClassDB::bind_method(D_METHOD("duplicate", "deep"), &Terrain3DRegion::duplicate, DEFVAL(false));\n'
    if source.count(binding) != 1:
        raise SystemExit("Unexpected region duplicate binding or already patched")
    edits[path] = source.replace(binding, "")

    path = root / "project/addons/terrain_3d/src/asset_dock.gd"
    source = path.read_text(encoding="utf-8")
    for kind in ("Mesh", "Texture"):
        old = f"(resource as Terrain3D{kind}Asset).get_name()"
        if source.count(old) != 1:
            raise SystemExit(f"Unexpected asset dock source: {old}")
        source = source.replace(old, f"(resource as Terrain3D{kind}Asset).name")
    edits[path] = source

    for path, source in edits.items():
        path.write_text(source, encoding="utf-8", newline="\n")
        print(f"Patched {path.relative_to(root)}")


if __name__ == "__main__":
    main()
