class_name TimeActionRequest
extends RefCounted

## Runtime description of one time-costed action. Gameplay owners keep resource
## validation/commit rules; this object carries only lifecycle and time policy.

var action_id: StringName = &""
var duration_hours: float = 0.0
## Zero means simulate immediately (sleep/wait). Positive values drive a staged
## real-time presentation while game time is billed deterministically.
var presentation_seconds: float = 0.0
## When true, the gameplay presenter calls advance_presentation instead of the system ticking twice.
var external_presentation: bool = false
var reason: StringName = &"action"
var actor: Node
var target: Node
var interruptible: bool = true
var simulation_step_hours: float = 0.25
## Optional PlayerState.Mode integer. -1 leaves the current mode untouched.
var player_mode: int = -1
## Returns an empty StringName to continue, or a reason to stop.
var stop_check: Callable
var on_complete: Callable
var on_cancel: Callable


func is_valid() -> bool:
	return action_id != &"" and duration_hours > 0.0 and simulation_step_hours > 0.0
