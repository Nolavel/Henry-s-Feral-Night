class_name SnowTrackStore
extends RefCounted
## Packed snow that left Henry's window, kept as coarse world tiles with the fill
## clock they were stored at; restored with the fill-in since then applied at once.

## Side of one tile in metres; the window moves in steps of this size.
const TILE_M: float = 3.2
## Texels along one tile side (10 cm each).
const TILE_TEX: int = 32
## Metres of packing per stored byte step.
const DEPTH_STEP_M: float = 0.005
## Tiles kept at most; the longest-filled ones go first.
const MAX_TILES: int = 4096
## Stored packing below this after fill-in is not worth keeping, metres.
const MIN_PACK_M: float = 0.01

## Tile key -> [clock stamp, PackedByteArray of TILE_TEX² depths].
var tiles: Dictionary = {}
## Fill-in done so far, as -ln(share left); packing left after a span is exp(-Δ).
var clock: float = 0.0


## Advances the fill clock by one frame's fill share.
func advance(fill: float) -> void:
	clock += -log(maxf(1.0 - clampf(fill, 0.0, 0.999999), 1e-6))


## Files every tile of `field` (R: metres packed, window at `origin`) that lies
## outside `keep`, the window that stays on screen.
func store(field: Image, origin: Vector2, window_m: float, keep: Rect2) -> void:
	var tiles_across: int = roundi(window_m / TILE_M)
	var px: int = field.get_width() / tiles_across
	for ty: int in range(tiles_across):
		for tx: int in range(tiles_across):
			var corner: Vector2 = origin + Vector2(tx, ty) * TILE_M
			if keep.has_area() and keep.encloses(Rect2(corner, Vector2.ONE * TILE_M)):
				continue
			var region: Image = field.get_region(Rect2i(tx * px, ty * px, px, px))
			region.resize(TILE_TEX, TILE_TEX, Image.INTERPOLATE_BILINEAR)
			var bytes := PackedByteArray()
			bytes.resize(TILE_TEX * TILE_TEX)
			var any: bool = false
			for y: int in range(TILE_TEX):
				for x: int in range(TILE_TEX):
					var b: int = clampi(roundi(region.get_pixel(x, y).r / DEPTH_STEP_M), 0, 255)
					bytes[y * TILE_TEX + x] = b
					any = any or b > 0
			var key: Vector2i = tile_key(corner + Vector2.ONE * TILE_M * 0.5)
			if any:
				tiles[key] = [clock, bytes]
			else:
				tiles.erase(key)
	_trim()


## Packing for a window at `origin`, `side` texels across, with the fill-in since
## each tile was stored already applied. R: metres packed.
func restore(origin: Vector2, window_m: float, side: int) -> Image:
	var out := Image.create_empty(side, side, false, Image.FORMAT_RF)
	var tiles_across: int = roundi(window_m / TILE_M)
	var px: int = side / tiles_across
	for ty: int in range(tiles_across):
		for tx: int in range(tiles_across):
			var key: Vector2i = tile_key(origin + (Vector2(tx, ty) + Vector2(0.5, 0.5)) * TILE_M)
			if not tiles.has(key):
				continue
			var entry: Array = tiles[key]
			var left: float = exp(-(clock - float(entry[0])))
			if 255.0 * DEPTH_STEP_M * left < MIN_PACK_M:
				continue
			var small := Image.create_empty(TILE_TEX, TILE_TEX, false, Image.FORMAT_RF)
			var bytes: PackedByteArray = entry[1]
			for i: int in range(bytes.size()):
				small.set_pixel(i % TILE_TEX, i / TILE_TEX, Color(float(bytes[i]) * DEPTH_STEP_M * left, 0, 0))
			small.resize(px, px, Image.INTERPOLATE_BILINEAR)
			out.blit_rect(small, Rect2i(0, 0, px, px), Vector2i(tx * px, ty * px))
	return out


static func tile_key(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / TILE_M), floori(at.y / TILE_M))


func get_save_data() -> Dictionary:
	var out: Dictionary = {}
	for key: Vector2i in tiles:
		var entry: Array = tiles[key]
		out["%d:%d" % [key.x, key.y]] = [entry[0], Marshalls.raw_to_base64(entry[1])]
	return {"clock": clock, "tiles": out}


func load_save_data(data: Dictionary) -> void:
	tiles.clear()
	clock = float(data.get("clock", 0.0))
	var saved: Dictionary = data.get("tiles", {})
	for name: String in saved:
		var parts: PackedStringArray = name.split(":")
		var entry: Array = saved[name]
		if parts.size() != 2 or entry.size() != 2:
			continue
		var bytes: PackedByteArray = Marshalls.base64_to_raw(String(entry[1]))
		if bytes.size() == TILE_TEX * TILE_TEX:
			tiles[Vector2i(int(parts[0]), int(parts[1]))] = [float(entry[0]), bytes]


## Drops the tiles that have filled in longest once the store is full.
func _trim() -> void:
	if tiles.size() <= MAX_TILES:
		return
	var keys: Array = tiles.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return float(tiles[a][0]) < float(tiles[b][0]))
	for i: int in range(tiles.size() - MAX_TILES):
		tiles.erase(keys[i])
