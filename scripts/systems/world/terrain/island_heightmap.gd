class_name IslandHeightmap
extends RefCounted

## The island's heights, read from the baked LA8 heightmap (L = high byte,
## A = low byte). World x, z in metres; heights in metres, sea level 0.

const DEFAULT_IMAGE: String = "res://world/terrain/graciosa_height_la8.png"
const DEFAULT_META: String = "res://world/terrain/graciosa_height_la8.json"

var origin: Vector2 = Vector2.ZERO
var metres_per_px: float = 1.0
var width: int = 0
var height: int = 0
var height_min: float = -16.0
var height_span: float = 64.0
var _data: PackedByteArray


static func load_default() -> IslandHeightmap:
	return load_from(DEFAULT_IMAGE, DEFAULT_META)


static func load_from(image_path: String, meta_path: String) -> IslandHeightmap:
	var map := IslandHeightmap.new()
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	var image: Image = load(image_path)
	if image == null or meta.is_empty():
		push_error("IslandHeightmap: cannot read %s" % image_path)
		return null
	map.origin = Vector2(float(meta["origin_x"]), float(meta["origin_z"]))
	map.metres_per_px = float(meta["m_per_px"])
	map.height_min = float(meta["height_min"])
	map.height_span = float(meta["height_max"]) - map.height_min
	map.width = image.get_width()
	map.height = image.get_height()
	map._data = image.get_data()
	return map


## Height of one pixel, clamped to the map; outside is the edge value.
func height_at_px(col: int, row: int) -> float:
	var c: int = clampi(col, 0, width - 1)
	var r: int = clampi(row, 0, height - 1)
	var i: int = 2 * (r * width + c)
	return float(_data[i] * 256 + _data[i + 1]) / 65535.0 * height_span + height_min


## Bilinear height at world x, z.
func get_height(x: float, z: float) -> float:
	var fx: float = (x - origin.x) / metres_per_px
	var fz: float = (z - origin.y) / metres_per_px
	var c: int = floori(fx)
	var r: int = floori(fz)
	var tx: float = fx - float(c)
	var tz: float = fz - float(r)
	var top: float = lerpf(height_at_px(c, r), height_at_px(c + 1, r), tx)
	var bottom: float = lerpf(height_at_px(c, r + 1), height_at_px(c + 1, r + 1), tx)
	return lerpf(top, bottom, tz)


## World-space rectangle the map covers.
func get_bounds() -> Rect2:
	return Rect2(origin, Vector2(float(width - 1), float(height - 1)) * metres_per_px)
