# Item Fitter — Hoarbound

Hoarbound-specific authoring layer over ADT's `addons/item_fitter/` workflow.

The production Henry animation graph is intentionally runtime-built in
`HenryUALAnimation.gd`. The editor tool does **not** turn that controller into
an `@tool` script and does not run the production `AnimationTree` in the
editor. Instead it creates a temporary, unowned `AnimationPlayer` beside the
imported player, copies Henry's UAL1 library, mounts the same UAL2 library used
at runtime, and scrubs the real editor skeleton.

The hand socket and item preview are also temporary unowned nodes. Pressing
Ctrl+S cannot serialize them into the character scene.

## Enable

Project → Project Settings → Plugins → **Item Fitter** → Enable.

The plugin remains editor-only and is intentionally not forced on in
`project.godot`.

## Recommended setup

1. Open `scenes/actors/player/HenryUALVisual.tscn`.
   `scenes/actors/player/player.tscn` also works, but the visual-only scene is
   cleaner for fitting.
2. Enable **Item Fitter** if it is not already enabled.
3. Open the **Item Fit** dock (right/bottom dock area).
4. In **Item**, choose the real `ItemResource` from `data/items/`.
5. Choose the hand:
   - **Left / primary** → Henry's `hand_l` socket.
   - **Right / offhand** → Henry's `hand_r` socket.
6. In **Pose**, choose the animation you want to judge the grip against.
   The list contains the imported UAL1 clips plus the same **UAL2/** library
   mounted in production.
7. Use **Play** to watch the clip, then pause and drag the time slider to the
   exact pose you want to inspect.
8. The tool selects `ItemFitPreview` automatically. Use Godot's normal 3D
   translate / rotate / scale gizmo to seat the object in the palm.
9. Click **Save to item**.

That writes only `ItemResource.held_fit`:

- hand;
- local offset;
- local rotation;
- local scale.

Runtime `HeldItemComponent`, the hammer path and the road-flare path all use
the same `HeldPropFactory + HeldFit` contract, so the transform you save here
is the transform production applies after the item is attached to the chosen
hand.

## Which pose should I fit against?

The saved fit is one stable local transform. The hand bone moves; the item
follows it. Therefore choose the pose where the grip is easiest to judge:

- held light / flare: usually `Idle_Torch`;
- hammer or another work tool: inspect both the ordinary held pose and
  `Fixing_Kneeling`;
- food, flask or another pocket item: use the pose in which it spends most of
  its visible held time, then quickly scrub the related action clip to make sure
  it does not intersect the hand badly.

Do **not** compensate for a bad animation by moving the item far away from the
palm. Fit the object's grip/origin to the hand once, then use the animation to
move the hand.

## What the authoring layer deliberately does not do

This pass is about **how the item sits in the hand**, not the exact frame at
which a pickup/draw action transfers an object into the hand.

The dock does not write attach/detach timing cues. Current gameplay components
still decide when an item becomes held. If exact draw/pickup timing is authored
later, it should be a separate cue/event contract; it should not be mixed into
`HeldFit`.

## Runtime / editor safety

- The editor preview uses an unowned temporary `AnimationPlayer`; it does not
  mutate or serialize Henry's imported AnimationPlayer.
- UAL2 is duplicated into that temporary player only.
- The temporary `BoneAttachment3D` and `ItemFitPreview` are also unowned.
- Switching edited scenes clears the preview/context.
- `HenryUALAnimation.gd` stays runtime-only; no editor execution of backpack,
  equipment, head-look, weather or gameplay code is introduced.

## Adding another item

If `HeldPropFactory.make(item.id, item)` can create a visual for the item,
Item Fitter can fit it without item-specific editor code.

Generic survival items already go through `SurvivalItemVisual`. Specialized
props such as the hammer and road flare are registered in `HeldPropFactory`.
A future specialized prop only needs to be added to that factory; its hand
transform still belongs in `ItemResource.held_fit`.

## Troubleshooting

**No item appears**

- Make sure `HenryUALVisual.tscn` or a Player scene containing it is the
  currently edited scene.
- Make sure the selected `ItemResource` has a visual that
  `HeldPropFactory` can create.
- Read the status line at the bottom of the dock; it reports missing Henry,
  skeleton, hand bone or prop separately.

**Animation list is empty**

The edited scene does not contain Henry's visual, or the imported model has no
`AnimationPlayer`. Re-open `HenryUALVisual.tscn`, then reselect the item.

**The animation moves but the item does not follow the hand**

The selected hand bone is missing or the preview socket was invalidated by a
scene switch. Reselect the item; the dock rebuilds the temporary socket.

**The item is the wrong size**

Do not use scale to compensate for an incorrectly imported asset. `HeldFit`
scale is for deliberate per-item fitting only; fix an import-scale problem at
the asset/import level.

Source concept: `Nolavel/ADT/addons/item_fitter/`.
