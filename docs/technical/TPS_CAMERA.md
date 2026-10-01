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
- **When there is no room at all, Henry dithers out.** In a 1.2 m doorway with a
  0.5 m capsule there is nowhere else for the camera to go. He fades instead of
  being cut out in one frame.
- **The camera only turns by itself after the mouse has rested for 0.9 s.** Then
  it can find room, follow a walk behind Henry, or steer away from a wall. WASD
  always follows the view on screen.

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
4. The rods (10 Hz) judge how open the space is, which sets the boom length.
5. The rig is swept (below), then the fades are updated.

The camera node opts out of physics interpolation. Teleport sites call
`reset_physics_interpolation()`: world spawn, sitting down and save load.

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
                 camera overlapping anything                   → pull in, nothing passes
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
without tagging. If a level needs an invisible camera blocker (Unreal's Camera
Blocking Volume), a wide static body on a camera-only layer does that job.

## Automatic turns (`TpsAutoLook`)

All of them wait `auto_look_cooldown` (0.9 s) after the last mouse motion. None
of them undoes itself.

- **Room search** runs when Henry stands still and the free boom is under 0.7 m.
  It looks for the cheapest turn that gives room, rising over Henry before
  swinging along the wall (cost = yaw + 0.8·pitch), and glides there at 120°/s.
- **Recentre** runs on W or during a scripted walk: the view yaw follows Henry's
  heading at up to 90°/s at full sprint. It does not run on strafing, backing up,
  or when Henry walks toward the camera (more than 110° off).
- **Whiskers** (Daedalic): booms swung ±20° and ±40° compare the room on each
  side, and the view steers toward the open side at up to 45°/s while moving.

## Fades (`TpsCameraFader`)

- **Henry:** `camera_fade` is an instance uniform in
  `stylized_environment_body.gdshaderinc`, applied as a 4×4 Bayer screen-door
  discard. It ramps from 0 at 0.8 m from the eyes to 1 at 0.25 m. The material
  stays opaque, so there are no sorting problems. His shadow dithers with him.
  Meshes without the stylized shader fall back to `transparency`.
- **Occluders:** the thin colliders on the camera-to-eyes line get
  `GeometryInstance3D.transparency` 0.7. It eases in over 0.12 s and out over
  0.35 s. Meshes wider than 1.5 m in their middle axis are never faded.

## Measuring it

- `tools/runtime/trace_tps_camera.gd` loads TestScene with the real Henry and
  drives the mouse and keys at `--fixed-fps 144` against 60 Hz physics. It
  records every frame against the render position and the `Head` bone: inside a
  collider, near-plane clipping, head occluded, body faded or hidden, and pops.
  Output: CSV and `summary.json` under `user://traces/tps_camera/<label>/`.
- `tools/runtime/capture_tps_camera.gd` takes the same stills for any camera
  build (lavapipe): `user://shots/tps_camera/<label>/`.

Before (`a604f60`) → after (#170), TestScene at 144 fps:

| Measure | Before | After |
|---|---|---|
| Frames where the view turns under continuous mouse | 42 % | 100 % |
| Lag behind the mouse at 129°/s | 30 ms | 0 |
| 13° flick: 90 % reached | 76 ms | next frame (7 ms) |
| Walking: camera step cv | 1.18 | 0.005 |
| Walking: Henry's drawn step cv | 1.18 | 0.003 |
| 360° sweeps, 8 poses × 3 pitches: frames with Henry cut out | 1865 | 0 (dithered instead) |
| Doorway sweep: closest to the eyes | 0.22 m | 0.29 m |
| Leaving the door: near plane clipping the jamb | 36 frames | 0 |
| Sideways door pass: Henry cut out | 246 frames | 0 (dithered, at most 0.85) |
| Sideways door pass: largest one-frame pull-in | 1.37 m | 0.76 m (wall snap, by decision) |
| Crouching: camera drop (head drops 0.68 m) | 0.00 m | 0.50 m |
| Under a 1.5 m slab: frames with the head hidden by the slab | 414 (31 %) | 0 |
| Thin pole: boom pops | 3, up to 0.95 m | 0; the pole fades |
| Teleport into the shelter | 1.3 s flight | snap; 0.2 s for the boom to fit the room |
| Back to a wall: automatic turn | 74° at once, mouse or not | none while the mouse moves (0.1° = the test jiggle); starts 0.9 s after it rests |
| Scripted walk 60° off the view | — | the view follows all 60° |
| Strafing with D, no mouse | — | the view stays (0°) |

Key West, the real shelter (1.5 m door), same harness with `scene=` and the
`shelter` scenario:

| Measure | Before | After |
|---|---|---|
| Scripted walk from the porch through the open door into the room | clean (closest 1.14 m) | clean (closest 1.18 m) |
| Doorway sweeps at pitch −10/−40/+30: frames with Henry cut out | 63 / 51 / 87 | 0 / 0 / 0 (dithered, at most 0.87) |
| Doorway sweeps: near-plane clips | 12 / 0 / 15 | 0 / 0 / 0 |
| Doorway sweeps: pops over 0.3 m | 4 / 2 / 0 | 1 / 1 / 0 |
| Doorway sweeps: closest to the eyes | 0.49 / 0.50 / 0.46 m | 0.31 / 0.33 / 0.62 m |

The camera now comes closer in the doorway. The old assist swung it away even
while the player aimed; the new one leaves the aim alone and dithers Henry.

## Known limits

- **There is physically no room for the camera beside Henry in a 1.2 m doorway**
  (capsule radius 0.5 m). The camera comes within about 0.3 m of the eyes and he
  dithers. Wider doors or a slimmer capsule are design or level calls.
- **A wall between camera and Henry still snaps the boom**, by decision: up to
  about 1 m in one frame on a sideways door pass.
- **Space queries run in `_process`.** That is safe while physics runs on the
  main thread (the project default).
- **Occluder fades use the transparent pipeline** while they are active.
