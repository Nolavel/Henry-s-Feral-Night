# Hinged door dynamics

Hoarbound exterior doors use a deterministic one-degree-of-freedom hinge rather
than a RigidBody3D/HingeJoint3D.

The rendered leaf and its StaticBody3D remain under the same `door_hinge`.
`Player.gd` calls `HingedDoor.apply_character_collisions()` only after
`CharacterBody3D.move_and_slide()`; therefore body torque exists only when
Henry actually collided with the leaf. Contact point, collision normal and the
attempted player velocity produce torque around the hinge axis.

The leaf integrates:

`player torque + wind torque + soft-stop spring - hinge damping`

into `angular_velocity` and `current_angle_rad`. Angular speed is capped so
the manually moving collider cannot sweep a large distance through Henry in one
physics frame. The StaticBody stays collidable but does **not** receive constant
surface velocity: doing that makes CharacterBody3D inherit the door's motion and
feel pushed backward. Henry moves the door; the door does not act as a conveyor.

F operates the latch only. A latched press releases the handle and gives enough
initial angular velocity to settle near the authored 8–15 degree crack angle.
A free door is pushed continuously by Henry; F latches it only inside
`latch_angle_deg`.

Wind comes from the existing `WeatherController`: projected wind pressure
(`speed^2`) acts at the leaf centre and becomes a deliberately weak hinge
torque. Latched doors ignore all external torque.

`get_door_save_data()` / `load_door_save_data()` preserve partial angle,
latch state and a clamped angular velocity without serializing physics nodes.
