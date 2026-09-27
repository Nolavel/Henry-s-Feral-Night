# Audio

Self-built, MetaSounds-inspired, deliberately small. Three pieces:

| Piece | File | Role |
|---|---|---|
| `SoundEvent` | `core/audio/sound_event.gd` | A bank of variations: no-repeat/random/sequence pick, volume and pitch jitter, bus, spatial range, voice limit, cooldown. |
| `SoundLayer` | `core/audio/sound_layer.gd` | A looping bed whose gain and pitch follow one named parameter through a `Curve` (wind speed → wind bed). |
| `SoundSystem` | `core/audio/sound_system.gd` (autoload) | Pooled flat/3D voices, voice stealing, global parameters, layer smoothing, bus layout, interior low-pass. |

`WorldAudioBinder` (`scripts/systems/audio/`) is the only place that knows the
game: it sets `wind_speed` from `WeatherController`, `interior` from
`ThermalManager.sheltered_changed`, and plays the footstep event from
`FootContactSensor.foot_planted`.

## Buses

`Master` ← `Music`, `SFX`, `Ambience`, `UI`, `Voice`. `SFX` and `Ambience` carry a
low-pass that sweeps exponentially from 20 kHz to `interior_cutoff_hz` as
`interior` goes 0 → 1: a closed room hears the storm through the walls.
Menus (`UI`) and `Music` are never muffled.

## Using it

```gdscript
SoundSystem.play(preload("res://data/audio/door_creak.tres"), global_position)
SoundSystem.set_parameter(&"wind_speed", 14.0)
var bed: int = SoundSystem.start_layer(preload("res://data/audio/wind_bed.tres"))
```

Content goes in `data/audio/*.tres`. There are no wind or footstep recordings
yet; the binder stays silent until events are assigned.

## Not built yet

Surface switch for footsteps (snow / ice / wood), occlusion raycasts, music
states, reverb zones per interior.
