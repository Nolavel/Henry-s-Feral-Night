class_name SoundLayer
extends Resource

## A looping bed whose loudness and pitch follow one named parameter, like a
## MetaSounds input: wind speed drives the wind bed, "interior" ducks it.

@export var stream: AudioStream
@export var bus: StringName = &"Ambience"
## The SoundSystem parameter this layer reads, e.g. &"wind_speed".
@export var parameter: StringName = &""
## Parameter value mapped to the curve's 0..1 x axis.
@export var parameter_min: float = 0.0
@export var parameter_max: float = 1.0
## Linear gain over the normalised parameter; empty means always full.
@export var gain_curve: Curve
## Pitch over the normalised parameter; empty means 1.0.
@export var pitch_curve: Curve
@export_range(-60.0, 12.0, 0.1) var volume_db: float = 0.0
## Seconds for gain to follow a parameter change; hides gust steps.
@export_range(0.0, 5.0, 0.01) var smoothing_s: float = 0.5


## Normalised 0..1 position of `value` on this layer's parameter range.
func normalise(value: float) -> float:
	if is_equal_approx(parameter_max, parameter_min):
		return 1.0
	return clampf((value - parameter_min) / (parameter_max - parameter_min), 0.0, 1.0)


func gain_at(value: float) -> float:
	if gain_curve == null:
		return 1.0
	return clampf(gain_curve.sample_baked(normalise(value)), 0.0, 1.0)


func pitch_at(value: float) -> float:
	if pitch_curve == null:
		return 1.0
	return maxf(pitch_curve.sample_baked(normalise(value)), 0.01)
