# Hinged door dynamics

HFN now uses Godot's physics solver for exterior doors instead of integrating a
synthetic hinge angle in GDScript.

## Model

Legacy packed scenes are upgraded once at runtime:

```text
Hinge (fixed Node3D)
├─ DoorBody (RigidBody3D)
│  ├─ DoorLeaf
│  ├─ DoorCollision
│  ├─ HandleOutside
│  └─ HandleInside
└─ DoorHingeJoint (HingeJoint3D)
```

The old StaticBody3D shape is transferred to the RigidBody3D and disabled on the
legacy body before it is freed.

The HingeJoint has symmetric limits (`-open_angle_deg .. +open_angle_deg`).
That is intentional: Henry can push the same leaf from either side of the
doorway. There is no one-sided `0°` clamp anymore.

## Character contact

`Player.gd` already calls `HingedDoor.apply_character_collisions()` after
`move_and_slide()`. A real KinematicCollision3D supplies the contact point and
normal. The door computes the player's velocity difference along the push
normal and calls `RigidBody3D.apply_impulse()` at that contact point. The
off-centre impulse creates hinge torque naturally; pushing near the hinge is
weaker than pushing the free edge.

F only freezes/unfreezes the latch. Releasing the handle applies a small impulse
at the free edge away from Henry, so the initial crack direction follows the
side he is standing on.

Wind uses `RigidBody3D.apply_force()` at the leaf centre. A soft counter-torque
near either angular limit damps the final approach while HingeJoint3D remains the
hard constraint.

## Godot references used for the design

- RigidBody3D / Using RigidBody: physics-driven bodies should be moved with
  forces and impulses rather than per-frame transform writes.
- HingeJoint3D: constrains a RigidBody3D to a hinge and provides angular limits.
- KinematicCollision3D: supplies global collision position and normal.
- CharacterBody-to-RigidBody push patterns use `apply_impulse()` at
  `collision_position - rigid_body.global_position`.

We deliberately do not combine HingeJoint3D with angular axis locks because
Godot/Jolt has had documented bugs with that configuration.
