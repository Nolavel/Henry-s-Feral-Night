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

## R: snow top (world y), G: depth, B: 1 where the shell is cut away.
var image: Image
var origin: Vector2 = Vector2(INF, INF)

var _ground: PackedVector2Array = []
var _noise: FastNoiseLite = FastNoiseLite.new()


func _init() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = 1901


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
	if image == null or image.get_width() != res:
		image = Image.create_empty(res, res, false, Image.FORMAT_RGBF)
	var side := Vector2(-wind.y, wind.x)
	var settled: float = lerpf(cover_depth_m.x, cover_depth_m.y, cover)
	var step: int = maxi(1, roundi(0.35 / texel_m()))
	for ty: int in range(res):
		for tx: int in range(res):
			var g: Vector2 = _ground[ty * res + tx]
			if g.y > 0.5:
				image.set_pixel(tx, ty, Color(g.x, 0.0, 1.0))
				continue
			var at: Vector2 = _world_of(tx, ty)
			var along: float = at.dot(wind)
			var across: float = at.dot(side)
			var ridge: float = smoothstep(0.1, 0.7, _noise.get_noise_2d(along * 0.16, across * 0.55))
			var drift: float = pow(cover, 1.5) * drift_m * ridge
			var lee: float = cover * lee_m * _lee(tx, ty, wind, step)
			## Wind scours the face that rises into it and fills hollows.
			var rise: float = _height_at(tx + roundi(wind.x * step), ty + roundi(wind.y * step)) - g.x
			var scour: float = clampf(1.0 - rise / (0.35 * float(step) * texel_m()) * 0.5, 0.35, 1.25)
			var depth: float = (settled + max(drift, lee) + min(drift, lee) * 0.3) * scour
			depth += settled * 0.15 * _noise.get_noise_2d(at.x * 1.3, at.y * 1.3)
			## Snow thins to nothing at the water's edge and never lies below it.
			depth *= smoothstep(sea_level_m + 0.05, sea_level_m + 0.8, g.x)
			var cut: float = 1.0 if g.x < sea_level_m + 0.02 else 0.0
			depth = maxf(depth, 0.0)
			image.set_pixel(tx, ty, Color(g.x + depth, depth, cut))


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


func _height_at(tx: int, ty: int) -> float:
	tx = clampi(tx, 0, res - 1)
	ty = clampi(ty, 0, res - 1)
	return _ground[ty * res + tx].x


## 0..1: how much an obstacle upwind shelters this point.
func _lee(tx: int, ty: int, wind: Vector2, step: int) -> float:
	var pile: float = 0.0
	for k: int in range(1, 9):
		var sx: int = tx - roundi(wind.x * step * k)
		var sy: int = ty - roundi(wind.y * step * k)
		if sx < 0 or sy < 0 or sx >= res or sy >= res:
			break
		if _ground[sy * res + sx].y > 0.5:
			pile = maxf(pile, smoothstep(0.0, 1.5, float(k)) * (1.0 - float(k) / 9.0))
	var fx: int = clampi(tx + roundi(wind.x * step), 0, res - 1)
	var fy: int = clampi(ty + roundi(wind.y * step), 0, res - 1)
	if _ground[fy * res + fx].y > 0.5:
		pile = maxf(pile, 0.6)
	return pile
