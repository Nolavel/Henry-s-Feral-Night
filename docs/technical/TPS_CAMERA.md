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
- **A narrow doorway is a short traversal.** Holding a key along it carries
  Henry through its centre, and the frame closes round him from behind. Only
  where geometry leaves no room at all do his near parts dither out (head,
  shoulder, pack; the legs stay); he is never cut out in one frame.
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
3. The stance is read from Henry's capsule. Where its height sits between the
   measured standing and crouch heights picks the framing heights from
   `HenryMetrics`, and the feet stay on the ground.
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
            (pivot = feet + lead, lagged; + Henry's shoulder joints and the doorway rise;
             + shoulder/lean offset)
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
- **One smoothing per quantity.** The lag follows Henry's feet. The framing
  heights (stance, doorway rise) are added after it, each eased by its own
  exponential damp `1 − exp(−rate·Δt)`, ADT's `damp_factor`. A crouch or a
  doorway is never smoothed twice.

## Henry's body (`HenryMetrics`)

The framing heights come from Henry as the game loads him, not from another
character's body ratios (ADT's 0.94 / 0.82 of 1.8 m were dropped; author's
comment on #170).

`tools/runtime/measure_henry_metrics.gd` loads `player.tscn` →
`HenryUALVisual` → `henry_outfit.glb` and skins every visible vertex of the
dressed body on the CPU through the live `Skeleton3D`. It averages 16 poses of
the idle and crouch-idle cycles (one pose varies by 1–2 cm), and writes
`data/characters/henry_metrics.tres`. Re-run it whenever the model, outfit,
scale or capsule changes. `TpsCamera` warns when the capsule no longer matches.

| Metres above the capsule bottom | Standing | Crouched |
|---|---|---|
| Crown of the hat | 1.79 | 1.08 |
| Eyes (midway chin–crown of the head) | 1.62 | 0.90 |
| Shoulder joints (`upperarm`) — **orbit pivot** | 1.40 | 0.86 |
| Coat over the shoulders | 1.52 | 0.97 |

| Silhouette, metres | |
|---|---|
| Between the shoulder joints | 0.38 |
| Widest at shoulder height, arms in, dressed | 0.60 (crouched 0.74) |
| Chest front to back | 0.36 |
| Pack and bear behind the coat (visual clearance only) | +0.32, 0.54 behind the capsule axis |
| Physics capsule | radius 0.50, height 2.00 / crouched 1.30 |

- **The pivot is at the shoulder joints**, 0.22 m under the eyes. With the
  pivot on the coat (0.10 m under the eyes), a camera pressed against a wall
  behind Henry sat 0.20 m from his eyes and hid him; `test_tps_camera_orbit`
  caught that.
- **The eyes** are used for line of sight and the body fade.
- **Between stances** the heights follow the capsule's own height (2.0 ↔ 1.3)
  with one damp. A crouch drops Henry's eyes by 0.72 m; scaling 1.8 m by the
  capsule ratio would have put them 0.20 m too high.

## Doorways (`PassageTraversalComponent`)

Author's direction (#170): in a narrow doorway, keep Henry in frame through
composition and a short traversal, not free orbit and not a fade.

**Henry (physics, `PassageTraversalComponent` on the player):**
- **Detection.** Every physics frame, at 1.3 m over the feet, opposite rays
  look for two solid faces turned toward each other (normals within ~45° of
  opposite), less than 1.9 m apart. Walking at a wall, the wall is scanned for
  a floor-level gap 0.7–1.9 m wide, which is then measured from inside. Thin
  props do not count, by the same rule as the boom.
- **Short or corridor.** A gap is a doorway only if it opens up within 0.9 m
  along its axis on at least one side. A corridor is narrow at both ends and
  never starts a traversal.
- **Steering.** While a movement key pushes along the axis (at least 25 % of
  the input), the direction is bent toward the axis and onto the centre line.
  The bend is full within 0.4 m of the door plane and gone 1.1 m past it. W
  carries Henry through; S carries him back out. Animation, speed and
  collision are unchanged, and nothing is teleported.

**Camera (`TpsCamera`):** a blend rises as Henry nears the door plane (full
inside 0.35 m) and falls by 1.1 m past it. It drives:

| | Free | In the door |
|---|---|---|
| Boom | open-space length | at most 1.4 m |
| Shoulder offset | 0.85 m | 25 % (0.21 m) |
| Pivot | shoulder joints | +0.15 m |
| FOV | base | +6° |
| View yaw | free | within ±35° of the passage axis; the mouse cannot push past |
| Automatic turns | as usual | off |

- **The frame closes fast and opens softly:** the blend damps at rate 12 on
  the way in and at 3 on the way out. Each quantity reads that one blend, and
  pivot heights are added after the follow lag, so nothing is smoothed twice.
- **The body fade stays as a fallback** for geometry that leaves no room. It
  is no longer the plan for a door.

**Fit, from the measured body** (shelter door 1.46 m clear with the leaf open,
2.25 m high):

| Room per side, walking the centre line | 1.46 m door | 1.2 m stress case |
|---|---|---|
| Capsule Ø 1.00 | 0.23 m | 0.10 m |
| Visual body 0.60 | 0.43 m | 0.30 m |
| Camera on the axis (sphere 0.2 + margin 0.1): largest shoulder offset | 0.43 m | 0.30 m |

The doorway shoulder (0.21 m) fits both. Under the lintel, the camera passes
behind Henry at about 2.0 m with the default pitch, against a 2.25 m opening.

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
- `tools/runtime/capture_tps_doorway.gd` grabs the Key West shelter door at
  entry, middle and exit (straight, 35° off, and stopped with the mouse turned
  aside): `user://shots/tps_doorway/<label>/`. No frames were rendered for
  the doorway pass; the author reviews it locally.
- `tools/runtime/measure_henry_metrics.gd` rebuilds `HenryMetrics`.

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
  (capsule radius 0.5 m). The traversal frames him from behind along the axis;
  orbiting the mouse sideways in a doorway is limited to ±35°.
- **The capsule (Ø 1.0 m) is much wider than Henry (0.60 m).** His coat stops
  0.2 m short of a wall, while the pack (0.54 m behind his axis) reaches 4 cm
  past the capsule. The capsule size and the doorway standard are design and
  level calls; 1.5 m with the leaf open (1.46 clear) by 2.25 m is the working
  hypothesis, and 1.2 m is the stress case.
- **Releasing the keys inside a doorway stops Henry there.** The traversal
  only acts while a key pushes along the passage.
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
