extends Resource
class_name ColorGradeProfile

## Immutable authoring data for one Environment color-correction profile.

@export var profile_id: StringName
@export var lut: Texture3D
@export_range(0.0, 2.0, 0.01) var brightness: float = 1.0
@export_range(0.0, 2.0, 0.01) var contrast: float = 1.0
@export_range(0.0, 2.0, 0.01) var saturation: float = 1.0
