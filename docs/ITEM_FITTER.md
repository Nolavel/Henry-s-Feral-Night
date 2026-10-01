# Item Fitter — Hoarbound

Port of ADT's `addons/item_fitter/` editor workflow.

The original ADT tool assumed persistent `GripPivot` nodes. Hoarbound creates
its hand sockets at runtime, so this version creates an **unowned temporary
BoneAttachment3D** on Henry's actual skeleton. The preview is also unowned and
cannot be serialized into the character scene.

## Enable

Project → Project Settings → Plugins → **Item Fitter** → Enable.

It is intentionally not force-enabled in `project.godot`: enabling it there
would make a tooling-only port alter startup configuration and trigger the
project's render-preview CI path.

## Use

1. Open `scenes/actors/player/HenryUALVisual.tscn` (or a Player scene that
   contains it).
2. Open the **Item Fit** dock.
3. Pick an `ItemResource` from `data/items/`.
4. Pick left/primary or right/offhand.
5. Pick an animation and scrub the time slider.
6. Move/rotate/scale `ItemFitPreview` with Godot's normal 3D gizmo.
7. **Save to item**.

The dock uses `SurvivalItemVisual.make()`, the same prop factory used by
runtime. It writes only `ItemResource.held_fit`.

## Runtime contract

`HeldItemComponent` applies `HeldFit` after attaching the prop to Henry's
hand socket. Items without a fit keep the exact legacy hard-coded transform,
so adding this tool does not move existing production props until they are
explicitly authored.

Source port: `Nolavel/ADT/addons/item_fitter/`.
