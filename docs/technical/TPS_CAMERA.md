# TPS camera

Owner: Claude (`claudeflow`). Story: #170. Code: `scripts/systems/camera/`.

The gameplay camera is an over-the-shoulder follow camera in the line of
Naughty Dog's player cameras (Uncharted 3, The Last of Us Part II) and Rockstar's
Red Dead cameras. Neither studio has published its camera-collision code, so the
method is assembled from what they presented, plus the shipped open
implementations it reduces to: Epic's Lyra, Unity Cinemachine and Daedalic's
Unreal Fest sample.

## What the player gets

- **Mouse look lands in the same rendered frame.** Look is never filtered and is
  never tied to the physics rate.
- **Henry and the camera move smoothly at any refresh rate.** This comes from
  physics interpolation.
- **Walls never put the camera inside geometry.** A wall between camera and
  Henry snaps the camera in front of it at once (Red Dead's "snap through"), and
  the camera eases back out.
- **Thin things never move the camera.** Posts, planks, trunks, people and loose
  props let the boom pass; when they cross the view they turn see-through.
- **When there is no room at all, Henry's near parts dither out.** In a 1.2 m
  doorway with a 0.5 m capsule there is nowhere else for the camera to go. His
  head, shoulder and pack fade while his legs stay; he is never cut out in one
  frame.
- **The mouse owns where Henry walks.** WASD turns by the control yaw, and only
  the mouse (or `set_look`) changes it.
- **The camera turns by itself only after the mouse has rested for 0.9 s**, and
  only as a view offset: it finds room, follows a walk behind Henry, or steers
  away from a wall. The next mouse motion makes the view the player sees the new
  control yaw, so nothing jumps.
- **Breathing is presentation only.** Gameplay rays (interaction, boarding,
  bedroll, cursor) use `TpsCamera.aim_origin()` and `aim_direction()`, which
  leave the sway out.

Author decisions (2026-10-01, #170): walls snap and thin or small things fade;
the camera recentres behind a walking Henry; mouse response is P0.

## Frame order

`TpsCamera._process` runs every rendered frame:

1. `player.get_global_transform_interpolated()` gives the target. If the target
   jumps more than `teleport_distance` in one frame, the camera snaps.
   `snap_to_target()` does the same on demand.
2. `InputSystems.consume_look_delta()` returns all mouse travel since the last
   frame. It reads `screen_relative`, so the stretch mode cannot rescale look.
3. The stance is read from Henry's capsule: its height ratio sets the framing
   heights, and the feet stay on the ground.
4. The rods judge how open the space is, every frame, which sets the boom
   length. They cover the camera's half of the circle (straight back weighs
   most) and the ceiling over Henry, so a wall in front of him does not count.
5. The rig is swept (below), then the fades are updated.

The camera node opts out of physics interpolation. Teleport sites call
`reset_physics_interpolation()`: world spawn, sitting down and save load.

## Control and view

Unreal's split: `ControlRotation` drives the pawn, and camera modifiers change
only the view.

- `_yaw`, `_pitch_deg`: the control look. Only mouse travel and `set_look()`
  change it. `get_yaw()` returns it, and `Player._camera_relative()` turns WASD
  by it.
- `_auto_yaw`, `_auto_pitch_deg`: the automatic offset. The view is control plus
  offset (`get_view_yaw()`, `get_view_pitch_deg()`).
- On mouse travel the offset folds into the control look, so the player takes
  over the view they see without a jump.
- While movement keys steer, the recentre target is zero and the offset glides
  back to the control look. WASD stays on the control yaw throughout.

## The rig

```
Henry (interpolated) ── feet (from the capsule)
  └─ safe point: on the capsule axis, under its top by the probe radius   [Lyra]
       └─ leg 1, sphere sweep, nothing passes ─▶ shoulder point            [Cinemachine "hand"]
            (pivot = shoulder height + lead, lagged; + shoulder/lean offset)
            └─ leg 2 ─▶ camera
                 centre: sphere sweep, thin things pass        → hard limit, snaps in
                 feelers: ±16°, ±32° yaw, +20°/−20° pitch rays  → soft limit, eases in
                 any release eases back out                    [Lyra DistBlockedPct]
                 camera overlapping a blocking body            → pull in; thin ones only fade
```

- **The safe point** sits inside Henry's own capsule, so a cast from it never
  starts inside a wall or a low ceiling. Under a 1.5 m slab, a crouched Henry's
  safe point is below the slab and the camera stays under it.
- **The shoulder is a real offset**: 0.85 m, shrinking to 20 % in tight space.
  A wider tight shoulder (45 % was tried) swings the boom onto the door jamb
  when walking through a doorway: 2 pops and 0.41 m instead of none and 0.82 m.
  The old `h_offset` "lens shift" was a translation that no cast saw
  (`Camera3D._get_adjusted_camera_transform`).
- **Feelers** (weights 0.75, 0.5, 1.0, 0.5): a hit at share `t` limits the boom
  to `t + (1 − t)(1 − weight)`. They pull the camera off a wall before the
  centre sweep would have to snap.
- **Follow lag trails only the orbit centre**: 16 across the ground, 10 in
  height. The orbit itself answers the mouse with no lag.

## What stops the boom

`TpsBoomProbe.passes()` decides this per collider shape:

| Collider | Boom |
|---|---|
| Static or animatable body whose middle extent ≥ `thin_extent` (0.6 m): walls, doors, ground, buildings | stops; snaps in |
| Middle extent < 0.6 m: posts, poles, planks, trunks, small crates | passes; visuals fade |
| `CharacterBody3D` (NPCs, animals) | passes; visuals fade |
| `RigidBody3D` that is not frozen | passes; visuals fade |
| Frozen `RigidBody3D` | judged by size, like a static body |

This rule is derived from collider data, not from layers, so new content works
without tagging. One cast passes at most 16 such colliders (`MAX_PASSES`); the
next one counts as a wall. A long row of props therefore can never hide a wall
behind it: it fails toward the camera coming in, not toward it going through. If a level needs an invisible camera blocker (Unreal's Camera
Blocking Volume), a wide static body on a camera-only layer does that job.

## Automatic turns (`TpsAutoLook`)

All of them wait `auto_look_cooldown` (0.9 s) after the last mouse motion and
move only the view offset, never the control yaw.

- **Room search** runs when Henry stands still and the free boom is under 0.7 m.
  It looks for the cheapest view turn that gives room, rising over Henry before
  swinging along the wall (cost = yaw + 0.8·pitch), and glides there at 120°/s.
  The offset stays until the mouse takes it over or Henry walks off.
- **Recentre** runs on a walk no key steers (an F approach): the view follows
  Henry's heading at up to 90°/s at full sprint, unless he walks toward the
  camera (more than 110° off). While keys steer, its target is zero.
- **Whiskers** (Daedalic): booms swung ±20° and ±40° compare the room on each
  side, and while Henry moves the view leans toward the open side, up to 30°.

## Fades (`TpsCameraFader`)

- **Henry:** `camera_fade` is an instance uniform in
  `stylized_environment_body.gdshaderinc`, applied as a 4×4 Bayer screen-door
  discard. It ramps from 0 at 0.8 m from the eyes to 1 at 0.25 m. Each fragment
  is weighted by its own distance to the camera: full under 0.35 m, none past
  1.1 m. So the head, shoulder and pack go and the legs stay. The material stays
  opaque, so there are no sorting problems; his shadow dithers with him. Meshes
  without the stylized shader fall back to `transparency`, capped at 0.7.
- **Occluders:** the thin colliders on the camera-to-eyes line get
  `GeometryInstance3D.transparency` 0.7, and so do thin colliders the camera
  sphere sits inside. It eases in over 0.12 s and out over 0.35 s. Meshes wider
  than 1.5 m in their middle axis are never faded.

## Measuring it

- `tools/runtime/trace_tps_camera.gd` loads TestScene with the real Henry and
  drives the mouse and keys at `--fixed-fps 144` against 60 Hz physics. It
  records every frame against the render position and the `Head` bone: inside a
  collider, near-plane clipping, head occluded, body faded or hidden, and pops.
  Output: CSV and `summary.json` under `user://traces/tps_camera/<label>/`.
- `tools/runtime/capture_tps_camera.gd` takes the same stills for any camera
  build (lavapipe): `user://shots/tps_camera/<label>/`.

Before (`a604f60`) → after (#170, with the review fixes), TestScene at 144 fps:

| Measure | Before | After |
|---|---|---|
| Frames where the view turns under continuous mouse | 42 % | 100 % |
| Lag behind the mouse at 129°/s | 30 ms | 0 |
| 13° flick: 90 % reached | 76 ms | next frame (7 ms) |
| Walking: camera step cv | 1.18 | 0.008 |
| Walking: Henry's drawn step cv | 1.18 | 0.012 |
| 360° sweeps, 8 poses × 3 pitches: frames with Henry cut out | 1865 | 0 (near parts dithered instead) |
| Doorway sweep: closest to the eyes | 0.22 m | 0.29 m |
| Leaving the door: near plane clipping the jamb | 36 frames | 0 (one 0.43 m wall snap on the jamb) |
| Sideways door pass: Henry cut out | 246 frames | 0 (near parts dithered, at most 0.72) |
| Sideways door pass: largest one-frame pull-in | 1.37 m | 1.05 m (wall snap, by decision) |
| Crouching: camera drop (head drops 0.68 m) | 0.00 m | 0.50 m |
| Under a 1.5 m slab: frames with the head hidden by the slab | 414 (31 %) | 0 |
| Thin pole: boom pops | 3, up to 0.95 m | 0; the pole fades |
| Teleport into the shelter | 1.3 s flight | snap |
| Back to a wall, mouse moving: view turned by itself | 74° at once | 0.1° (the test jiggle) |
| Back to a wall, mouse at rest: view turn | — | 60°, starting 0.9 s after the mouse stops |
| Then W: walking heading against the mouse's control yaw | 74° | 0° |
| Scripted walk 60° off: view / control yaw | — | 60° / 0° |
| Strafing with D: heading against the mouse's right | — | 0° |

Key West, the real shelter (1.5 m door), same harness with `scene=` and the
`shelter` scenario:

| Measure | Before | After |
|---|---|---|
| Scripted walk from the porch through the open door into the room | clean (closest 1.14 m) | clean (closest 1.18 m) |
| Doorway sweeps at pitch −10/−40/+30: frames with Henry cut out | 63 / 51 / 87 | 0 / 0 / 0 (dithered, at most 0.87) |
| Doorway sweeps: near-plane clips | 12 / 0 / 15 | 0 / 0 / 0 |
| Doorway sweeps: pops over 0.3 m | 4 / 2 / 0 | 1 / 1 / 0 |
| Doorway sweeps: closest to the eyes | 0.49 / 0.50 / 0.46 m | 0.31 / 0.31 / 0.62 m |

The camera now comes closer in the doorway. The old assist swung it away even
while the player aimed; the new one leaves the aim alone and dithers Henry.

Frames: `docs/runtime_previews/tps_camera/` holds before/after sheets from
`capture_tps_camera.gd` (lavapipe, 960×540). The poses are: doorway with the
mouse moving and at rest, corner aimed and at rest, crouched under a slab, a
thin pole, leaving the shelter, and open ground. With the mouse moving, the old
camera had already swung away from the player's aim; the new one holds the aim
and dithers Henry until the mouse rests.

## Known limits

- **There is physically no room for the camera beside Henry in a 1.2 m doorway**
  (capsule radius 0.5 m). The camera comes within about 0.3 m of the eyes and he
  dithers. Wider doors or a slimmer capsule are design or level calls.
- **A wall between camera and Henry still snaps the boom**, by decision: up to
  about 1 m in one frame on a sideways door pass, and 0.3–0.45 m when the
  camera behind Henry grazes the jamb on the way out.
- **While an automatic view offset stands, W walks along the control yaw, not
  the screen centre.** That is the price of WASD never following automatic
  turns. The first mouse motion folds the offset in, and steering keys glide it
  back out.
- **Space queries run in `_process`.** That is safe while physics runs on the
  main thread (the project default).
- **Occluder fades use the transparent pipeline** while they are active.
