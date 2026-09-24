class_name SoundEvent
extends Resource

## One playable sound: a bank of variations plus how to vary, route and limit
## them. The designer-facing unit; code only ever says "play this event".

enum Pick { RANDOM_NO_REPEAT, RANDOM, SEQUENCE }

@export var streams: Array[AudioStream] = []
@export var pick: int = Pick.RANDOM_NO_REPEAT
@export var bus: StringName = &"SFX"

@export_group("Variation")
@export_range(-60.0, 12.0, 0.1) var volume_db: float = 0.0
@export_range(0.0, 12.0, 0.1) var volume_jitter_db: float = 0.0
@export_range(0.25, 4.0, 0.01) var pitch: float = 1.0
## Random pitch spread either side of `pitch`, as a fraction.
@export_range(0.0, 0.5, 0.005) var pitch_jitter: float = 0.0

@export_group("Space")
## A spatial event needs a position; a flat one ignores it.
@export var spatial: bool = true
@export var unit_size: float = 4.0
@export var max_distance_m: float = 40.0

@export_group("Limits")
## Voices of this event at once; the oldest is stolen past this.
@export_range(1, 32) var max_instances: int = 4
## A replay sooner than this is dropped, seconds.
@export_range(0.0, 5.0, 0.01) var cooldown_s: float = 0.0

var _last_index: int = -1
var _sequence: int = 0


## Picks the next variation by this event's rule; null when the bank is empty.
func next_stream(rng: RandomNumberGenerator) -> AudioStream:
	var count: int = streams.size()
	if count == 0:
		return null
	var index: int = 0
	match pick:
		Pick.SEQUENCE:
			index = _sequence % count
			_sequence += 1
		Pick.RANDOM:
			index = rng.randi_range(0, count - 1)
		_:
			index = rng.randi_range(0, count - 1)
			if count > 1 and index == _last_index:
				index = (index + 1 + rng.randi_range(0, count - 2)) % count
	_last_index = index
	return streams[index]


func roll_volume_db(rng: RandomNumberGenerator) -> float:
	return volume_db + rng.randf_range(-volume_jitter_db, volume_jitter_db)


func roll_pitch(rng: RandomNumberGenerator) -> float:
	return pitch * (1.0 + rng.randf_range(-pitch_jitter, pitch_jitter))
