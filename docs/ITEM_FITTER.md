# Item Fitter — Hoarbound

The Item Fitter is an editor-only dock for authoring how a one-hand item sits
in Henry's hand.

## Safety architecture

The preview is completely isolated from the scene currently open in the Godot
editor.

The dock owns a private `SubViewport`, and inside it it instantiates:

- `assets/characters/henry/henry_outfit.glb`;
- the model's real `Skeleton3D` and `AnimationPlayer`;
- the production UAL2 animation library;
- a private `BoneAttachment3D`;
- the real held prop created by `HeldPropFactory`.

The tool never adds temporary nodes to
`EditorInterface.get_edited_scene_root()` and never frees nodes from the
user's edited scene. This is intentional: Godot warns that freeing nodes from
tool scripts can crash the editor when those nodes are being used by the
editor.

## Enable

Project → Project Settings → Plugins → **Item Fitter** → Enable.

The addon is not force-enabled in `project.godot`.

## Use

1. Open the **ItemFitter** dock. No particular character scene needs to be open.
2. **Item** → choose an `ItemResource`, for example
   `data/items/road_flare.tres`.
3. **Hand**:
   - `Left / primary` = `hand_l`;
   - `Right / offhand` = `hand_r`.
4. **Pose** → choose any imported UAL1 or `UAL2/...` animation.
5. **Play** watches the animation. Pause it and use the time slider to hold the
   exact pose you want to inspect.
6. In the embedded 3D preview:
   - left mouse drag = orbit;
   - mouse wheel = zoom;
   - **Reset view** restores the default camera.
7. Adjust the item's local transform under **HeldFit transform**:
   - `Pos X/Y/Z` in metres;
   - `Rot X/Y/Z` in degrees;
   - `Scale X/Y/Z`.
   Changes are shown immediately in the preview.
8. Press **Save to item**.

The save writes only `ItemResource.held_fit`:
hand, local offset, local rotation and local scale.

## Recommended fitting order

For a flare/light, start with `Idle_Torch`. For a work tool, inspect its main
held pose and then scrub a work animation such as `Fixing_Kneeling`. The fit
should describe the object's grip in the palm; do not move the prop far away to
compensate for a bad animation.

Exact pickup/draw timing is deliberately out of scope. `HeldFit` answers only
**how the item sits in the hand**.

## Runtime contract

Generic one-hand items, the hammer and road flare all use
`HeldPropFactory + HeldFit`. The same transform saved in this dock is applied
by runtime after the prop is attached to the selected hand.

Source concept: `Nolavel/ADT/addons/item_fitter/`.
