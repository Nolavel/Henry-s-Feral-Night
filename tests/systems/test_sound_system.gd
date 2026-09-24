extends SceneTree

## SoundSystem: variation picking, voice limits, cooldown, parameter-driven
## layers and the interior low-pass sweep.
## Run: godot --headless --audio-driver Dummy --script tests/systems/test_sound_system.gd

var _failures: int = 0
var _frame: int = 0
var _sound: Node
var _event: SoundEvent
var _layer: SoundLayer
var _layer_handle: int = -1


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_sound = root.get_node_or_null(^"SoundSystem")
			_check(_sound != null, "SoundSystem autoload is missing")
			if _sound == null:
				_finish()
				return false
			_check_buses()
			_check_variations()
			_check_limits()
			_check_cooldown()
			_start_layer()
		3:
			_sound.call(&"set_parameter", &"wind_speed", 20.0)
			_sound.call(&"set_parameter", &"interior", 1.0)
		90:
			var gain: float = float(_sound.call(&"get_layer_gain", _layer_handle))
			_check(gain > 0.9, "wind layer did not rise with wind speed (gain %.2f)" % gain)
			var cutoff: float = float(_sound.call(&"get_interior_cutoff_hz"))
			_check(cutoff < 1500.0, "interior did not close the low-pass (%.0f Hz)" % cutoff)
			_sound.call(&"stop", _layer_handle)
			_check(not bool(_sound.call(&"is_playing", _layer_handle)), "stopped layer still reports playing")
			_finish()
	return false


func _check_buses() -> void:
	for bus: StringName in [&"Music", &"SFX", &"Ambience", &"UI", &"Voice"]:
		_check(AudioServer.get_bus_index(bus) >= 0, "bus %s missing" % bus)


func _check_variations() -> void:
	var event := SoundEvent.new()
	event.streams = [_silence(), _silence(), _silence()]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var previous: AudioStream = null
	for i: int in range(30):
		var stream: AudioStream = event.next_stream(rng)
		_check(stream != previous, "no-repeat pick repeated a variation")
		previous = stream


func _check_limits() -> void:
	_event = SoundEvent.new()
	_event.streams = [_silence()]
	_event.spatial = false
	_event.max_instances = 2
	for i: int in range(4):
		_sound.call(&"play", _event)
	var voices: int = int(_sound.call(&"count_voices", _event))
	_check(voices == 2, "voice limit not enforced (%d voices)" % voices)


func _check_cooldown() -> void:
	var event := SoundEvent.new()
	event.streams = [_silence()]
	event.spatial = false
	event.cooldown_s = 1.0
	var first: int = int(_sound.call(&"play", event))
	var second: int = int(_sound.call(&"play", event))
	_check(first > 0 and second == -1, "cooldown did not drop the replay")


func _start_layer() -> void:
	_layer = SoundLayer.new()
	_layer.stream = _silence()
	_layer.parameter = &"wind_speed"
	_layer.parameter_min = 0.0
	_layer.parameter_max = 20.0
	_layer.gain_curve = Curve.new()
	_layer.gain_curve.add_point(Vector2(0.0, 0.0))
	_layer.gain_curve.add_point(Vector2(1.0, 1.0))
	_layer.smoothing_s = 0.3
	_layer_handle = int(_sound.call(&"start_layer", _layer))
	_check(_layer_handle > 0, "layer did not start")
	var gain: float = float(_sound.call(&"get_layer_gain", _layer_handle))
	_check(gain < 0.05, "calm wind started loud (gain %.2f)" % gain)


func _silence() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(22050 * 2)
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = 22050
	return wav


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	if _failures == 0:
		print("sound system: all checks passed")
	quit(1 if _failures > 0 else 0)
