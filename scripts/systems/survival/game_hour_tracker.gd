class_name GameHourTracker
extends RefCounted

## Turns DayNightManager's absolute hour-of-day signal into per-tick deltas,
## handling the wrap at midnight. Shared by every hourly survival system.

const HOURS_PER_DAY: float = 24.0

var _last_hour: float = -1.0


## Delta in game hours since the previous call; 0.0 on the first call.
func consume(current_hour: float) -> float:
	if _last_hour < 0.0:
		_last_hour = current_hour
		return 0.0
	var delta: float = current_hour - _last_hour
	if delta < 0.0:
		delta += HOURS_PER_DAY
	_last_hour = current_hour
	return delta


## Forgets the previous sample, so the next call returns 0.0 again.
func reset() -> void:
	_last_hour = -1.0
