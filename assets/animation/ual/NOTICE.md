# Quaternius Universal Animation Library

Henry's Feral Night uses the **non-root-motion UAL1 humanoid rig** as the active
player visual/locomotion animation source. CharacterBody3D movement remains
authoritative; the animation layer only reads the player's resulting velocity.

- Upstream: Quaternius — Universal Animation Library
- License: CC0 1.0 Universal / public domain dedication
- UAL1 binary used by the player: `Unreal-Godot/UAL1_Standard.glb`
- UAL2 is vendored alongside it as a compatible secondary animation library,
  but is not currently instantiated by Henry.

DOGWATCH is the architectural reference for this integration: its player/crew
visuals use the same UAL-style non-root-motion split between gameplay movement
and skeletal animation.

The original DOGWATCH repository is private, so GitHub repository-scoped Actions
could not copy its binary blobs directly. The vendored GLBs in this repository
were obtained from a public CC0 mirror of the Quaternius UAL releases instead.
They are therefore the same asset family and rig contract, but should not be
described as byte-identical copies of DOGWATCH's current blobs.
