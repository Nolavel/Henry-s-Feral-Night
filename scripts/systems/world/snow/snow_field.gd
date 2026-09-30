class_name SnowField
extends RefCounted

## The one answer to "how much snow is here": ground, settled depth, drifts and
## lee piles on a grid that follows Henry. Shaders and gameplay read the same data.

## Ground height and obstacle flag at a world point, as Vector2(height, 0 or 1).
var ground_sampler: Callable

var window_m: float = 25.6
var res: int = 128
var sea_level_m: float = 0.0
## Settled depth at snow_cover 0 and 1.
var cover_depth_m: Vector2 = Vector2(0.05, 0.25)
## Tallest wind drift and lee pile at snow_cover 1.
var drift_m: float = 0.3
var lee_m: float = 0.6
## Snow rounds off ground detail finer than this, in metres.
var smooth_m: float = 1.0

## R: snow top (world y), G: depth, B: 1 where cut away, A: city wind factor.
var image: Image
var origin: Vector2 = Vector2(INF, INF)

## City-scale wind field (R prevailing, G storm depth factor); null outside a city.
var wind_field: Image
var wind_field_origin: Vector2 = Vector2.ZERO
var wind_field_cell_m: float = 4.0
var wind_field_max: float = 2.5
## Share of the storm pattern over the prevailing one.
var storm_share: float = 0.4

var _ground: PackedVector2Array = []
var _bed: PackedFloat32Array = []
var _noise: FastNoiseLite = FastNoiseLite.new()


func _init() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = 1901


## Loads a baked wind field (PNG + JSON beside it); false when absent.
func load_wind_field(png_path: String) -> bool:
	var meta_path: String = png_path.get_basename() + ".json"
	if not FileAccess.file_exists(png_path) or not FileAccess.file_exists(meta_path):
		return false
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if typeof(meta) != TYPE_DICTIONARY:
		return false
	var tex := load(png_path) as Texture2D
	if tex == null:
		return false
	wind_field = tex.get_image()
	if wind_field.is_compressed():
		wind_field.decompress()
	var o: Array = (meta as Dictionary).get("origin", [0, 0])
	wind_field_origin = Vector2(float(o[0]), float(o[1]))
	wind_field_cell_m = float((meta as Dictionary).get("cell_m", 4.0))
	wind_field_max = float((meta as Dictionary).get("factor_max", 2.5))
	return true


## Wind ridge crest 0..1; mirrors snow_ridge() in snow_surface.gdshaderinc bit for bit.
static func ridge_at(xz: Vector2, wind: Vector2) -> float:
	var side := Vector2(-wind.y, wind.x)
	var q := Vector2(xz.dot(wind) * 0.16, xz.dot(side) * 0.55)
	var n: float = _vnoise(q) * 0.7 + _vnoise(q * 2.0 + Vector2(11.0, 5.0)) * 0.3
	return smoothstep(0.45, 0.85, n)


static func _ihash(x: int, y: int) -> float:
	const M: int = 0xFFFFFFFF
	var h: int = ((x & M) * 374761393 + (y & M) * 668265263) & M
	h = ((h ^ (h >> 13)) * 1274126177) & M
	h ^= h >> 16
	return float(h & 65535) / 65535.0


static func _vnoise(p: Vector2) -> float:
	var i := Vector2i(floori(p.x), floori(p.y))
	var f := p - Vector2(i)
	var u := f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	return lerpf(
		lerpf(_ihash(i.x, i.y), _ihash(i.x + 1, i.y), u.x),
		lerpf(_ihash(i.x, i.y + 1), _ihash(i.x + 1, i.y + 1), u.x),
		u.y
	)


## Drift crest height for a snow_cover value.
func drift_amplitude(cover: float) -> float:
	return pow(clampf(cover, 0.0, 1.0), 1.5) * drift_m


## Settled depth for a snow_cover value, before the city's wind reshapes it.
func settled_depth(cover: float) -> float:
	return lerpf(cover_depth_m.x, cover_depth_m.y, clampf(cover, 0.0, 1.0))


## True inside a mapped building footprint (snow lies on its roof, not here).
func is_building(at: Vector2) -> bool:
	if wind_field == null:
		return false
	var p := Vector2i(((at - wind_field_origin) / wind_field_cell_m).floor())
	if p.x < 0 or p.y < 0 or p.x >= wind_field.get_width() or p.y >= wind_field.get_height():
		return false
	return wind_field.get_pixel(p.x, p.y).a > 0.5


## How the city's wind scales settled snow here: under 1 scoured, over 1 deposited.
func wind_factor(at: Vector2) -> float:
	if wind_field == null:
		return 1.0
	var p: Vector2 = (at - wind_field_origin) / wind_field_cell_m - Vector2(0.5, 0.5)
	var x0: int = clampi(floori(p.x), 0, wind_field.get_width() - 2)
	var y0: int = clampi(floori(p.y), 0, wind_field.get_height() - 2)
	var f := Vector2(clampf(p.x - float(x0), 0.0, 1.0), clampf(p.y - float(y0), 0.0, 1.0))
	var top: Color = wind_field.get_pixel(x0, y0).lerp(wind_field.get_pixel(x0 + 1, y0), f.x)
	var bottom: Color = wind_field.get_pixel(x0, y0 + 1).lerp(wind_field.get_pixel(x0 + 1, y0 + 1), f.x)
	var c: Color = top.lerp(bottom, f.y)
	return lerpf(c.r, c.g, storm_share) * wind_field_max


func texel_m() -> float:
	return window_m / float(res)


## Rebuilds the field for a window whose minimum corner is `new_origin`.
func rebuild(new_origin: Vector2, cover: float, wind: Vector2) -> void:
	origin = new_origin
	cover = clampf(cover, 0.0, 1.0)
	wind = wind.normalized() if wind.length_squared() > 0.0001 else Vector2(0, -1)
	_ground.resize(res * res)
	for ty: int in range(res):
		for tx: int in range(res):
			_ground[ty * res + tx] = ground_sampler.call(_world_of(tx, ty))
	_smooth_bed()
	if image == null or image.get_width() != res:
		image = Image.create_empty(res, res, false, Image.FORMAT_RGBAF)
	var side := Vector2(-wind.y, wind.x)
	var settled: float = settled_depth(cover)
	var step: int = maxi(1, roundi(0.35 / texel_m()))
	var n: int = res * res
	var depth_sum := PackedFloat32Array()
	var weight := PackedFloat32Array()
	var fill := PackedFloat32Array()
	depth_sum.resize(n)
	weight.resize(n)
	fill.resize(n)
	for ty: int in range(res):
		for tx: int in range(res):
			var i: int = ty * res + tx
			var g: Vector2 = _ground[i]
			if g.y > 0.5:
				continue
			var at: Vector2 = _world_of(tx, ty)
			var along: float = at.dot(wind)
			var across: float = at.dot(side)
			var ridge: float = ridge_at(at, wind)
			## The city field sets how much this street keeps; local lee piles ride on top.
			var city: float = wind_factor(at)
			var drift: float = drift_amplitude(cover) * ridge * minf(city, 1.5)
			var lee: float = cover * lee_m * _lee(tx, ty, wind, step)
			## Wind scours the face that rises into it and fills hollows.
			var bed: float = _bed[i]
			var rise: float = _bed_at(tx + roundi(wind.x * step), ty + roundi(wind.y * step)) - bed
			var scour: float = clampf(1.0 - rise / (0.35 * float(step) * texel_m()) * 0.5, 0.35, 1.25)
			var depth: float = (settled * city + max(drift, lee) + min(drift, lee) * 0.3) * scour
			depth += settled * 0.15 * _noise.get_noise_2d(at.x * 1.3, at.y * 1.3)
			## Snow thins to nothing at the water's edge and never lies below it.
			var shore: float = smoothstep(sea_level_m + 0.05, sea_level_m + 0.8, g.x)
			depth_sum[i] = maxf(depth * shore, 0.0)
			weight[i] = 1.0
			fill[i] = (bed - g.x) * shore
	## Wind never leaves one-cell spikes: soften depth over ~0.5 m, ignoring
	## cells nothing lies on so snow still meets walls at full height.
	var r: int = maxi(1, roundi(0.25 / texel_m()))
	var tmp := PackedFloat32Array()
	tmp.resize(n)
	_blur_rows(depth_sum, tmp, r)
	_blur_cols(tmp, depth_sum, r)
	_blur_rows(weight, tmp, r)
	_blur_cols(tmp, weight, r)
	for ty: int in range(res):
		for tx: int in range(res):
			var i: int = ty * res + tx
			var g: Vector2 = _ground[i]
			if g.y > 0.5:
				image.set_pixel(tx, ty, Color(g.x, 0.0, 1.0, 0.0))
				continue
			var depth: float = depth_sum[i] / maxf(weight[i], 0.0001)
			var cut: float = 1.0 if g.x < sea_level_m + 0.02 else 0.0
			## Depth is measured from the real ground, so the shader's ground stays true.
			var top: float = g.x + fill[i] + depth
			image.set_pixel(tx, ty, Color(top, top - g.x, cut, wind_factor(_world_of(tx, ty))))


## Snow top at a world point (bilinear), or -INF outside the window.
func get_snow_top(x: float, z: float) -> float:
	return _sample(x, z).x


## Settled depth at a world point (bilinear), 0 outside the window.
func get_depth(x: float, z: float) -> float:
	return _sample(x, z).y


func _sample(x: float, z: float) -> Vector2:
	if image == null:
		return Vector2(-INF, 0.0)
	var p: Vector2 = (Vector2(x, z) - origin) / texel_m() - Vector2(0.5, 0.5)
	if p.x < 0.0 or p.y < 0.0 or p.x > res - 1 or p.y > res - 1:
		return Vector2(-INF, 0.0)
	var i := Vector2i(mini(floori(p.x), res - 2), mini(floori(p.y), res - 2))
	var f: Vector2 = p - Vector2(i)
	var a: Color = image.get_pixel(i.x, i.y)
	var b: Color = image.get_pixel(i.x + 1, i.y)
	var c: Color = image.get_pixel(i.x, i.y + 1)
	var d: Color = image.get_pixel(i.x + 1, i.y + 1)
	var top: float = lerpf(lerpf(a.r, b.r, f.x), lerpf(c.r, d.r, f.x), f.y)
	var depth: float = lerpf(lerpf(a.g, b.g, f.x), lerpf(c.g, d.g, f.x), f.y)
	return Vector2(top, depth)


func _world_of(tx: int, ty: int) -> Vector2:
	return origin + (Vector2(tx, ty) + Vector2(0.5, 0.5)) * texel_m()


## Only walls shelter a lee; a roofed floor is cut away but piles nothing.
func _is_wall(tx: int, ty: int) -> bool:
	var kind: float = _ground[ty * res + tx].y
	return kind > 0.5 and kind < 1.5


## Share of wall around a cell: a lone fence post shelters far less than a wall.
func _wall_share(tx: int, ty: int) -> float:
	var walls: int = 0
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if _is_wall(clampi(tx + dx, 0, res - 1), clampi(ty + dy, 0, res - 1)):
				walls += 1
	return clampf(float(walls) / 3.0, 0.0, 1.0)


func _bed_at(tx: int, ty: int) -> float:
	tx = clampi(tx, 0, res - 1)
	ty = clampi(ty, 0, res - 1)
	return _bed[ty * res + tx]


## The surface snow settles on: the ground box-blurred twice, never below it,
## so hollows and terrain facets fill while nothing pokes through.
func _smooth_bed() -> void:
	var n: int = res * res
	var a := PackedFloat32Array()
	a.resize(n)
	for i: int in range(n):
		a[i] = _ground[i].x
	var r: int = maxi(1, roundi(smooth_m / texel_m() * 0.5))
	var b := PackedFloat32Array()
	b.resize(n)
	for _pass: int in range(2):
		_blur_rows(a, b, r)
		_blur_cols(b, a, r)
	_bed.resize(n)
	for i: int in range(n):
		_bed[i] = maxf(a[i], _ground[i].x)


func _blur_rows(src: PackedFloat32Array, dst: PackedFloat32Array, r: int) -> void:
	for y: int in range(res):
		var row: int = y * res
		var sum: float = 0.0
		for k: int in range(-r, r + 1):
			sum += src[row + clampi(k, 0, res - 1)]
		for x: int in range(res):
			dst[row + x] = sum / float(2 * r + 1)
			sum += src[row + mini(x + r + 1, res - 1)] - src[row + maxi(x - r, 0)]


func _blur_cols(src: PackedFloat32Array, dst: PackedFloat32Array, r: int) -> void:
	for x: int in range(res):
		var sum: float = 0.0
		for k: int in range(-r, r + 1):
			sum += src[clampi(k, 0, res - 1) * res + x]
		for y: int in range(res):
			dst[y * res + x] = sum / float(2 * r + 1)
			sum += src[mini(y + r + 1, res - 1) * res + x] - src[maxi(y - r, 0) * res + x]


## 0..1: how much an obstacle upwind shelters this point.
func _lee(tx: int, ty: int, wind: Vector2, step: int) -> float:
	var pile: float = 0.0
	for k: int in range(1, 9):
		var sx: int = tx - roundi(wind.x * step * k)
		var sy: int = ty - roundi(wind.y * step * k)
		if sx < 0 or sy < 0 or sx >= res or sy >= res:
			break
		pile = maxf(pile, _wall_share(sx, sy) * smoothstep(0.0, 1.5, float(k)) * (1.0 - float(k) / 9.0))
	var fx: int = clampi(tx + roundi(wind.x * step), 0, res - 1)
	var fy: int = clampi(ty + roundi(wind.y * step), 0, res - 1)
	pile = maxf(pile, 0.6 * _wall_share(fx, fy))
	return pile
