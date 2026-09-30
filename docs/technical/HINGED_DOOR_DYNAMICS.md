# Hinged door dynamics

Scope: `HingedDoor` (`scripts/environment/interactive/hinged_door.gd`),
`DoorPushComponent` and `DoorHandIK` on Henry.

## Decision: kinematic hinge, not RigidBody3D

`cbafe26` moved the leaf onto a `RigidBody3D` + `HingeJoint3D`. The leaf sits a
few centimetres from its jambs and floor in a wall thicker than itself; once F
unfroze it, contact depenetration fought the joint and the leaf was thrown out
of the doorway (reported as "the door vanished on F"). A door is one angular
degree of freedom. It is integrated by script, as it was before `cbafe26`, but
now symmetrically in both directions:

```
HouseDoor (HingedDoor, Area3D)
└─ Hinge (Node3D, rotation.y = current angle)
   ├─ DoorLeaf (MeshInstance3D) ─ StaticBody3D  ← Henry collides with the visible leaf
   ├─ HandleOutside (+Z face) / HandleInside (−Z face)
```

Torque sources: body contacts after `move_and_slide()`, wind (v² pressure) and
F swings. Resisting: viscous damping, hinge stiction (`hinge_friction` — a resting
leaf ignores a breeze) and a door stop that only soaks up speed near the open
limit, so a fully open door stays open. The leaf never moves Henry: it stops a
margin short of his real capsule (`HingedDoor.blocker`), and when an F swing
comes towards him he steps out of its arc himself.

## Behaviour

The leaf opens one way, towards the sign of `open_angle_deg` (positive swings
towards the hinge's local −Z); that side is **inside**. The frame stops it at 0;
arriving faster than `slam_latch_speed_deg` it latches by itself.
`swings_both_ways` restores a saloon door. F reads where Henry stands:

| Henry | Door | F does |
|---|---|---|
| Outside (push side) | latched | Releases and cracks it inward (`handle_crack_deg`), hand on the handle. He then walks it open with his hand. |
| Inside (pull side) | latched | Pulls it wide (`pull_open_deg`) by the handle at `pull_speed_deg`. If he stands in the arc the leaf sweeps he takes the shortest step out of it; the leaf opens behind him as he clears. |
| Outside | open | Leaving: reaches the handle and pulls it shut; it latches. |
| Inside, behind the leaf | open | Palm on the face, pushes it shut; it latches. |
| Inside, in front of the leaf | open | Pulls it shut by the handle and steps out of its path; the leaf waits for him (up to `close_timeout_s`). |
| Anywhere | within `latch_angle_deg` | Latches at once. |

Without F: walking into an unlatched leaf from outside pushes it open with his
hand; from inside it pushes it back towards the frame, and a firm push latches it.
F swings are a spring towards a target angle (`drive_stiffness`, `drive_damping`),
so they can be blocked, resumed and interrupted by a hand push.

The hand push is a position constraint, not a force: `push_with_hand()` records
the leaf angle that clears the palm, and the next tick the leaf never swings
through it while inheriting the palm's angular speed. That is what makes the
hand look like it moves the door rather than hovering in front of it.

## Hand IK

`DoorHandIK` is a `SkeletonModifier3D` added last on Henry's skeleton (after
head look, wade and snow feet). It solves upperarm → lowerarm → hand to a wrist
point behind the palm, drops the elbow down and out like a braced push, and
turns the palm into the surface with fingers up. The palm frame is read from
the finger roots (`middle_01`, `index_01`, `pinky_01`), so it does not depend on
the hand bone's local axes. Godot 4.6+ also ships `TwoBoneIK3D`; the custom
solve is kept because it also lays the palm flat and matches the solver
`SnowFootModifier` already uses.

## Sources

- Godot: *Inverse kinematics returns to Godot 4.6* (`IKModifier3D`, `TwoBoneIK3D`).
- Naughty Dog, *The Last of Us Part II* door system (K. Margenau / M. Zhuravlov):
  doors pushed by walking, actions split into interruptible pieces.
- Common Unreal/Unity practice: a socket on the door, two-bone IK hand that
  follows the socket while the door moves.
