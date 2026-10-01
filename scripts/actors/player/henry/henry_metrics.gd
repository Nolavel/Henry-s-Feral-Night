class_name HenryMetrics
extends Resource

## Henry's body as the game loads it (player.tscn → HenryUALVisual → henry_outfit.glb),
## measured by tools/runtime/measure_henry_metrics.gd. Heights are metres above the feet.

@export var source: String = ""

@export_group("Standing, dressed")
## Crown of the hat.
@export var standing_top: float = 0.0
## Eye line: halfway between chin and crown of the head mesh.
@export var standing_eye: float = 0.0
## Shoulder joints (upperarm bones).
@export var standing_shoulder: float = 0.0
## Highest point of the coat over the shoulders.
@export var standing_shoulder_top: float = 0.0

@export_group("Crouched, dressed")
@export var crouch_top: float = 0.0
@export var crouch_eye: float = 0.0
@export var crouch_shoulder: float = 0.0
@export var crouch_shoulder_top: float = 0.0

@export_group("Silhouette")
## Distance between the shoulder joints.
@export var shoulder_joint_width: float = 0.0
## Widest across at shoulder height, arms included, dressed.
@export var body_width: float = 0.0
## Torso front to back at chest height, dressed.
@export var body_depth: float = 0.0
## How far the pack and the bear stand out behind the coat; visual clearance only.
@export var pack_behind: float = 0.0
@export var pack_top: float = 0.0

@export_group("Physics capsule")
## The collider, kept apart from the visual body: it decides what Henry fits through.
@export var capsule_radius: float = 0.0
@export var capsule_height: float = 0.0
@export var crouch_capsule_height: float = 0.0
