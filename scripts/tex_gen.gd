class_name TexGen
extends RefCounted
## Procedural low-res textures. Everything is tiny (32-64 px) and sampled
## with nearest filtering for the chunky late-90s look, so the project
## ships with no image assets at all.


static func _tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func material(tex: Texture2D, roughness := 0.9, tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.roughness = roughness
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return m


static func flat_material(col: Color, roughness := 0.8, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = roughness
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func _noise_fill(img: Image, base: Color, amount: float, rng: RandomNumberGenerator) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var v := rng.randf_range(-amount, amount)
			img.set_pixel(x, y, Color(base.r + v, base.g + v, base.b + v))


static func _speckle(img: Image, cols: Array, chance: float, rng: RandomNumberGenerator) -> void:
	for y in img.get_height():
		for x in img.get_width():
			if rng.randf() < chance:
				var c: Color = cols[rng.randi() % cols.size()]
				img.set_pixel(x, y, c)


## Road textures: x runs across the road (0 = left edge), y runs along it.
static func road(kind: String) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	match kind:
		"asphalt":
			_noise_fill(img, Color(0.36, 0.37, 0.40), 0.04, rng)
			_speckle(img, [Color(0.5, 0.5, 0.52), Color(0.26, 0.26, 0.28)], 0.08, rng)
			_lines(img, Color(0.92, 0.92, 0.88), true)
		"wet":
			_noise_fill(img, Color(0.20, 0.23, 0.30), 0.03, rng)
			for y in 64:
				for x in 64:
					# streaky reflections along the driving line
					if (x + y * 3) % 23 < 2 and rng.randf() < 0.7:
						img.set_pixel(x, y, Color(0.45, 0.52, 0.66))
			_lines(img, Color(0.75, 0.78, 0.80), true)
		"gravel":
			_noise_fill(img, Color(0.62, 0.52, 0.38), 0.05, rng)
			_speckle(img, [Color(0.78, 0.72, 0.62), Color(0.44, 0.36, 0.26), Color(0.70, 0.66, 0.60)], 0.22, rng)
			for y in 64:
				for x in [16, 17, 18, 19, 20, 43, 44, 45, 46, 47]:
					img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.18))
			for y in 64:
				for x in [0, 1, 2, 61, 62, 63]:
					img.set_pixel(x, y, Color(0.36, 0.42, 0.20).lerp(img.get_pixel(x, y), rng.randf() * 0.6))
		"ice":
			_noise_fill(img, Color(0.80, 0.88, 0.95), 0.03, rng)
			for i in 9:
				var x := rng.randi_range(0, 63)
				var y := rng.randi_range(0, 63)
				for s in 14:
					x = clampi(x + rng.randi_range(-1, 1), 0, 63)
					y = (y + 1) % 64
					img.set_pixel(x, y, Color(0.62, 0.74, 0.86))
			for y in 64:
				for x in [0, 1, 2, 3, 60, 61, 62, 63]:
					img.set_pixel(x, y, Color(0.97, 0.98, 1.0))
		"grass":
			_noise_fill(img, Color(0.30, 0.48, 0.18), 0.06, rng)
			_speckle(img, [Color(0.42, 0.58, 0.22), Color(0.22, 0.36, 0.12)], 0.2, rng)
			for y in 64:
				for x in range(14, 22) + range(42, 50):
					img.set_pixel(x, y, Color(0.42, 0.33, 0.20).lerp(img.get_pixel(x, y), rng.randf() * 0.4))
		"mud":
			_noise_fill(img, Color(0.36, 0.25, 0.15), 0.05, rng)
			_speckle(img, [Color(0.46, 0.34, 0.20), Color(0.26, 0.18, 0.10)], 0.2, rng)
			# churned wheel tracks and a few shiny puddles
			for y in 64:
				for x in range(13, 22) + range(42, 51):
					img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.22))
			for p in 5:
				var c := Vector2(rng.randi_range(6, 58), rng.randi_range(0, 63))
				var r := rng.randf_range(3.0, 6.0)
				for y in 64:
					for x in 64:
						var d := Vector2(x - c.x, wrapf(y - c.y, -32, 32))
						if (d * Vector2(1.0, 0.6)).length() < r:
							img.set_pixel(x, y, Color(0.42, 0.40, 0.36) if (x + y) % 5 else Color(0.62, 0.62, 0.58))
			for y in 64:
				for x in [0, 1, 2, 61, 62, 63]:
					img.set_pixel(x, y, Color(0.22, 0.36, 0.12).lerp(img.get_pixel(x, y), rng.randf() * 0.5))
		"ford":
			# river bed seen through shallow brown water
			_noise_fill(img, Color(0.40, 0.36, 0.26), 0.05, rng)
			_speckle(img, [Color(0.55, 0.50, 0.40), Color(0.30, 0.27, 0.20), Color(0.62, 0.60, 0.55)], 0.3, rng)
		"wood":
			# planks laid across the deck
			_noise_fill(img, Color(0.52, 0.38, 0.22), 0.05, rng)
			for y in 64:
				var plank := y / 8
				var tint := 0.9 + 0.2 * fmod(plank * 0.618, 1.0)
				for x in 64:
					var c := img.get_pixel(x, y) * tint
					if y % 8 == 0:
						c = Color(0.22, 0.15, 0.09)
					elif (x + plank * 13) % 29 == 0:
						c = c.darkened(0.3)
					img.set_pixel(x, y, Color(c.r, c.g, c.b))
	return _tex(img)


static func _lines(img: Image, col: Color, center: bool) -> void:
	for y in 64:
		for x in [3, 4, 59, 60]:
			img.set_pixel(x, y, col)
		if center and y < 30:
			img.set_pixel(31, y, col)
			img.set_pixel(32, y, col)


static func grass() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	_noise_fill(img, Color(0.80, 0.80, 0.80), 0.08, rng)
	_speckle(img, [Color(0.95, 0.95, 0.85), Color(0.6, 0.6, 0.6)], 0.18, rng)
	return _tex(img)


static func stone_wall() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var img := Image.create(32, 16, false, Image.FORMAT_RGB8)
	_noise_fill(img, Color(0.55, 0.53, 0.48), 0.06, rng)
	for y in 16:
		for x in 32:
			var row := y / 4
			var off := 4 if row % 2 == 1 else 0
			if y % 4 == 0 or (x + off) % 8 == 0:
				img.set_pixel(x, y, Color(0.30, 0.29, 0.26))
	return _tex(img)


static func stripes(a: Color, b: Color, w := 4) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 16:
			img.set_pixel(x, y, a if ((x + y) / w) % 2 == 0 else b)
	return _tex(img)


static func checker() -> ImageTexture:
	var img := Image.create(16, 4, false, Image.FORMAT_RGB8)
	for y in 4:
		for x in 16:
			img.set_pixel(x, y, Color.WHITE if (x / 2 + y / 2) % 2 == 0 else Color(0.05, 0.05, 0.05))
	return _tex(img)


static func foliage(seed_val: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	_noise_fill(img, Color(0.78, 0.82, 0.78), 0.14, rng)
	_speckle(img, [Color(0.45, 0.5, 0.45), Color(1, 1, 0.92)], 0.2, rng)
	return _tex(img)


## Soft-edged pixel puff used by dust/spray/smoke particles.
static func puff() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			var d := Vector2(x - 3.5, y - 3.5).length() / 4.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.2 - d * 1.3, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## Equirectangular sky with saturated blue and chunky clouds (Sega Rally sky).
static func sky_panorama(theme := "") -> ImageTexture:
	var w := 512
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 1.6
	noise.fractal_octaves = 4
	var top := Color(0.08, 0.30, 0.86)
	var horizon := Color(0.60, 0.78, 0.98)
	var ground := Color(0.42, 0.52, 0.48)
	var cloud_hi := Color(0.98, 0.98, 1.0)
	var cloud_lo := Color(0.72, 0.76, 0.86)
	if theme == "wasteland":
		# nuclear dusk: rust-brown overhead, a sick orange glow on the horizon
		top = Color(0.22, 0.17, 0.14)
		horizon = Color(0.88, 0.55, 0.26)
		ground = Color(0.35, 0.28, 0.22)
		cloud_hi = Color(0.62, 0.50, 0.40)
		cloud_lo = Color(0.24, 0.20, 0.18)
	for y in h:
		var lat := 0.5 - float(y) / h  # +0.5 top, -0.5 bottom
		for x in w:
			var c: Color
			if lat < 0.0:
				c = horizon.lerp(ground, clampf(-lat * 6.0, 0.0, 1.0))
			else:
				c = horizon.lerp(top, pow(clampf(lat * 2.4, 0.0, 1.0), 0.6))
				var a := TAU * float(x) / w
				var n := noise.get_noise_3d(cos(a), sin(a), lat * 5.0)
				var band := clampf(1.0 - absf(lat - 0.12) * 5.0, 0.0, 1.0)
				var cloud := clampf((n + 0.05) * 3.0, 0.0, 1.0) * band
				if cloud > 0.0:
					var shade := cloud_hi.lerp(cloud_lo, clampf(-n * 2.0 + 0.4, 0.0, 1.0))
					c = c.lerp(shade, cloud)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


# --------------------------------------------------------------------------- scenery

static var _cache := {}


static func _cached(key: String, make: Callable) -> ImageTexture:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


## One storey of house wall, 3 m x 3 m: plaster, shuttered window, sill and a
## darker band at the floor line. Tiles across and up the wall.
static func house_wall(variant: int) -> ImageTexture:
	return _cached("wall%d" % variant, _make_house_wall.bind(variant))


const WALL_COLORS := [Color(0.93, 0.89, 0.79), Color(0.88, 0.80, 0.66), Color(0.95, 0.94, 0.91), Color(0.86, 0.72, 0.58)]
const SHUTTER_COLORS := [Color(0.25, 0.45, 0.30), Color(0.30, 0.42, 0.62), Color(0.50, 0.32, 0.20), Color(0.62, 0.20, 0.16)]


static func _make_house_wall(variant: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 40 + variant
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	var plaster: Color = WALL_COLORS[variant % WALL_COLORS.size()]
	var shutter: Color = SHUTTER_COLORS[variant % SHUTTER_COLORS.size()]
	_noise_fill(img, plaster, 0.035, rng)
	_speckle(img, [plaster.darkened(0.12)], 0.05, rng)
	for x in 32:
		for y in [29, 30, 31]:
			img.set_pixel(x, y, plaster.darkened(0.3 if y == 29 else 0.22))
	# shutters
	for x in [7, 8, 9, 10, 21, 22, 23, 24]:
		for y in range(9, 23):
			img.set_pixel(x, y, shutter.darkened(0.25) if y % 2 == 0 else shutter)
	# frame + glass with mullions and a highlight
	for x in range(11, 21):
		for y in range(9, 23):
			var edge := x == 11 or x == 20 or y == 9 or y == 22
			var mull := x == 15 or x == 16 or y == 15
			var c := Color(0.94, 0.93, 0.88) if edge or mull else Color(0.12, 0.16, 0.28)
			if not edge and not mull and (x - y) % 7 == 0:
				c = Color(0.42, 0.52, 0.70)
			img.set_pixel(x, y, c)
	for x in range(10, 22):
		img.set_pixel(x, 23, Color(0.72, 0.70, 0.66))
	return _tex(img)


## Terracotta roof tiles in staggered rows.
static func roof_tiles() -> ImageTexture:
	return _cached("roof", _make_roof_tiles)


static func _make_roof_tiles() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	var base := Color(0.68, 0.28, 0.17)
	for row in 8:
		for tile in 6:
			var shade := rng.randf_range(-0.07, 0.07)
			var x0 := tile * 6 - (3 if row % 2 == 1 else 0)
			for y in range(row * 4, row * 4 + 4):
				for dx in 6:
					var x := wrapi(x0 + dx, 0, 32)
					var c := Color(base.r + shade, base.g + shade * 0.6, base.b + shade * 0.5)
					if y == row * 4 + 3:
						c = c.darkened(0.45)  # shadow under the row above
					elif dx == 0:
						c = c.darkened(0.25)
					elif y == row * 4:
						c = c.lightened(0.12)
					img.set_pixel(x, y, c)
	return _tex(img)


## Planked door with a frame and a brass knob.
static func door() -> ImageTexture:
	return _cached("door", _make_door)


static func _make_door() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var img := Image.create(16, 32, false, Image.FORMAT_RGB8)
	_noise_fill(img, Color(0.42, 0.26, 0.14), 0.04, rng)
	for y in 32:
		for x in 16:
			if x == 0 or x == 15 or y == 0:
				img.set_pixel(x, y, Color(0.9, 0.88, 0.82))
			elif x % 4 == 0:
				img.set_pixel(x, y, Color(0.28, 0.16, 0.08))
	img.set_pixel(12, 17, Color(0.95, 0.8, 0.3))
	img.set_pixel(12, 18, Color(0.75, 0.6, 0.2))
	return _tex(img)


## Straw for hay bales.
static func hay() -> ImageTexture:
	return _cached("hay", _make_hay)


static func _make_hay() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	_noise_fill(img, Color(0.84, 0.72, 0.36), 0.04, rng)
	for i in 120:
		var x := rng.randi_range(0, 31)
		var y := rng.randi_range(0, 31)
		var c := Color(0.95, 0.86, 0.5) if rng.randf() < 0.5 else Color(0.62, 0.50, 0.22)
		for k in rng.randi_range(2, 5):
			img.set_pixel(wrapi(x + k, 0, 32), y, c)
	for y in 32:  # twine
		for x in [10, 21]:
			img.set_pixel(x, y, Color(0.45, 0.30, 0.15))
	return _tex(img)


## Corrugated armco crash barrier.
static func armco() -> ImageTexture:
	return _cached("armco", _make_armco)


static func _make_armco() -> ImageTexture:
	var img := Image.create(32, 16, false, Image.FORMAT_RGB8)
	var shades := [0.55, 0.62, 0.75, 0.86, 0.80, 0.66, 0.55, 0.62, 0.75, 0.86, 0.80, 0.66, 0.5, 0.35, 0.35, 0.35]
	for y in 16:
		for x in 32:
			var v: float = shades[y]
			if y >= 13:
				v = 0.30 if x % 16 < 2 else 0.42  # posts and shadow under the rail
			img.set_pixel(x, y, Color(v * 0.96, v, v * 1.04))
	for x in [3, 19]:
		img.set_pixel(x, 5, Color(0.3, 0.3, 0.32))
	return _tex(img)


## Weathered wooden planks for fences.
static func planks() -> ImageTexture:
	return _cached("planks", _make_planks)


static func _make_planks() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	for x in 32:
		var plank := x / 4
		var tone := 0.48 + (plank * 37 % 7) * 0.02
		for y in 32:
			var c := Color(tone, tone * 0.70, tone * 0.40)
			if x % 4 == 0:
				c = c.darkened(0.45)
			elif rng.randf() < 0.12:
				c = c.darkened(0.15)
			img.set_pixel(x, y, c)
	return _tex(img)


## Packed snow for the ice-section walls.
static func snow() -> ImageTexture:
	return _cached("snow", _make_snow)


static func _make_snow() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	_noise_fill(img, Color(0.92, 0.94, 0.98), 0.03, rng)
	_speckle(img, [Color(0.78, 0.84, 0.94), Color(1, 1, 1)], 0.15, rng)
	return _tex(img)


## Pine bark, stretched up the trunks.
static func bark() -> ImageTexture:
	return _cached("bark", _make_bark)


static func _make_bark() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for x in 16:
		var tone := rng.randf_range(0.30, 0.42)
		for y in 16:
			var c := Color(tone, tone * 0.68, tone * 0.42)
			if rng.randf() < 0.18:
				c = c.darkened(0.4)
			img.set_pixel(x, y, c)
	return _tex(img)


## Steel track links: u runs along the track, v across it.
static func track_links() -> ImageTexture:
	return _cached("track", _make_track_links)


static func _make_track_links() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	for y in 8:
		for x in 8:
			var c := Color(0.30, 0.29, 0.27)
			if x == 0:
				c = Color(0.08, 0.08, 0.08)  # gap between links
			elif x == 1 or y == 0 or y == 7:
				c = Color(0.18, 0.18, 0.17)
			elif (y == 3 or y == 4) and x >= 3 and x <= 5:
				c = Color(0.48, 0.47, 0.44)  # guide horn
			img.set_pixel(x, y, c)
	return _tex(img)


# --------------------------------------------------------------------------- car decals

## 3x5 pixel font for decals and plates (rows top to bottom, 3 bits each).
const FONT := {
	"A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "D": "110101101101110",
	"E": "111100110100111", "F": "111100110100100", "G": "011100101101011", "H": "101101111101101",
	"I": "111010010010111", "J": "001001001101010", "K": "101101110101101", "L": "100100100100111",
	"M": "101111111101101", "N": "110101101101101", "O": "010101101101010", "P": "110101110100100",
	"Q": "010101101110011", "R": "110101110101101", "S": "011100010001110", "T": "111010010010010",
	"U": "101101101101111", "V": "101101101101010", "W": "101101111111101", "X": "101101010101101",
	"Y": "101101010010010", "Z": "111001010100111", "0": "111101101101111", "1": "010110010010111",
	"2": "110001010100111", "3": "110001010001110", "4": "101101111001001", "5": "111100110001110",
	"6": "011100110101010", "7": "111001010010010", "8": "010101010101010", "9": "010101011001110",
	"-": "000000111000000", " ": "000000000000000", ".": "000000000000010", "!": "010010010000010",
}


## Text sticker: pixel-font text on a coloured panel with an optional border.
static func pixel_text(text: String, fg: Color, bg: Color, border := Color(0, 0, 0, 0)) -> ImageTexture:
	var key := "txt|%s|%s|%s|%s" % [text, fg.to_html(), bg.to_html(), border.to_html()]
	return _cached(key, _make_pixel_text.bind(text, fg, bg, border))


static func _make_pixel_text(text: String, fg: Color, bg: Color, border: Color) -> ImageTexture:
	var pad := 2 if border.a > 0.0 else 1
	var w := text.length() * 4 - 1 + pad * 2
	var h := 5 + pad * 2
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(bg)
	if border.a > 0.0:
		for x in w:
			img.set_pixel(x, 0, border)
			img.set_pixel(x, h - 1, border)
		for y in h:
			img.set_pixel(0, y, border)
			img.set_pixel(w - 1, y, border)
	for i in text.length():
		var glyph: String = FONT.get(text[i].to_upper(), FONT[" "])
		for row in 5:
			for col in 3:
				if glyph[row * 3 + col] == "1":
					img.set_pixel(pad + i * 4 + col, pad + row, fg)
	return ImageTexture.create_from_image(img)


## Radiator grille: dark slats in a chrome surround.
static func grille() -> ImageTexture:
	return _cached("grille", _make_grille)


static func _make_grille() -> ImageTexture:
	var img := Image.create(16, 6, false, Image.FORMAT_RGB8)
	for y in 6:
		for x in 16:
			var c := Color(0.05, 0.05, 0.06)
			if y == 0 or y == 5 or x == 0 or x == 15:
				c = Color(0.75, 0.76, 0.78)
			elif y % 2 == 0:
				c = Color(0.22, 0.22, 0.24)
			elif x == 8:
				c = Color(0.55, 0.56, 0.58)  # badge
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Square headlight: bright lens with a reflector ring and an indicator at the edge.
static func headlight() -> ImageTexture:
	return _cached("headlight", _make_headlight)


static func _make_headlight() -> ImageTexture:
	var img := Image.create(10, 5, false, Image.FORMAT_RGB8)
	for y in 5:
		for x in 10:
			var c := Color(1.0, 0.98, 0.86)
			if x >= 8:
				c = Color(1.0, 0.62, 0.15)  # indicator
			elif y == 0 or y == 4 or x == 0 or x == 7:
				c = Color(0.6, 0.62, 0.66)
			elif (x == 2 or x == 5) and y == 2:
				c = Color(0.85, 0.85, 0.75)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Tail light cluster: brake, indicator and reversing segments.
static func taillight() -> ImageTexture:
	return _cached("taillight", _make_taillight)


static func _make_taillight() -> ImageTexture:
	var img := Image.create(10, 4, false, Image.FORMAT_RGB8)
	for y in 4:
		for x in 10:
			var c := Color(0.85, 0.06, 0.04)
			if x < 2:
				c = Color(1.0, 0.55, 0.1)
			elif x >= 8:
				c = Color(0.92, 0.92, 0.92)
			elif y == 0:
				c = Color(1.0, 0.3, 0.25)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)



# --------------------------------------------------------------------------- wasteland

## Road surfaces after the bombs: cracked, pot-holed tarmac with faded
## lines, concrete rubble, toxic sludge, ash verges.
static func road_wasted(kind: String) -> ImageTexture:
	return _cached("waste_" + kind, _make_road_wasted.bind(kind))


static func _make_road_wasted(kind: String) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + 666
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	match kind:
		"asphalt":
			_noise_fill(img, Color(0.27, 0.27, 0.28), 0.04, rng)
			_speckle(img, [Color(0.38, 0.37, 0.36), Color(0.18, 0.18, 0.19)], 0.1, rng)
			for y in 64:  # faded edge lines with gaps
				if (y / 6) % 3 != 0:
					for x in [3, 4, 59, 60]:
						img.set_pixel(x, y, Color(0.62, 0.60, 0.52))
			_cracks(img, rng, 7, Color(0.10, 0.10, 0.10))
			for h in 3:  # potholes
				var cx := rng.randi_range(10, 54)
				var cy := rng.randi_range(4, 60)
				var r := rng.randi_range(2, 4)
				for y in range(-r, r + 1):
					for x in range(-r, r + 1):
						if x * x + y * y <= r * r:
							img.set_pixel(clampi(cx + x, 0, 63), wrapi(cy + y, 0, 64), Color(0.14, 0.13, 0.12))
		"gravel":
			_noise_fill(img, Color(0.46, 0.44, 0.40), 0.05, rng)
			_speckle(img, [Color(0.62, 0.60, 0.56), Color(0.30, 0.29, 0.27), Color(0.52, 0.40, 0.30)], 0.3, rng)
			_cracks(img, rng, 4, Color(0.2, 0.19, 0.18))
		"wet":
			_noise_fill(img, Color(0.20, 0.25, 0.13), 0.03, rng)
			for y in 64:
				for x in 64:
					if (x * 2 + y * 3) % 19 < 2 and rng.randf() < 0.6:
						img.set_pixel(x, y, Color(0.45, 0.58, 0.18))
			_cracks(img, rng, 3, Color(0.10, 0.12, 0.06))
		_:
			_noise_fill(img, Color(0.34, 0.31, 0.27), 0.05, rng)
			_speckle(img, [Color(0.22, 0.20, 0.18), Color(0.46, 0.42, 0.36)], 0.25, rng)
	return _tex(img)


static func _cracks(img: Image, rng: RandomNumberGenerator, count: int, col: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for c in count:
		var x := rng.randi_range(w / 10, w - w / 10)
		var y := rng.randi_range(0, h - 1)
		for k in rng.randi_range(8, 20):
			img.set_pixel(x, y, col)
			x = clampi(x + rng.randi_range(-1, 1), 0, w - 1)
			y = wrapi(y + (1 if rng.randf() < 0.7 else 0), 0, h)


## Rough cast concrete, stained.
static func concrete() -> ImageTexture:
	return _cached("concrete", _make_concrete)


static func _make_concrete() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	_noise_fill(img, Color(0.58, 0.56, 0.52), 0.05, rng)
	_speckle(img, [Color(0.44, 0.42, 0.39), Color(0.66, 0.64, 0.60)], 0.12, rng)
	for x in 32:
		for y in range(24, 32):
			if rng.randf() < 0.3 + (y - 24) * 0.08:
				img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.25))  # water stains at the foot
	_cracks(img, rng, 2, Color(0.3, 0.29, 0.27))
	return _tex(img)


## One storey of a burnt-out apartment block: concrete, soot above the
## empty window holes, the odd shard of glass left.
static func ruin_wall(variant: int) -> ImageTexture:
	return _cached("ruin%d" % variant, _make_ruin_wall.bind(variant))


static func _make_ruin_wall(variant: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90 + variant
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	var bases := [Color(0.62, 0.58, 0.52), Color(0.70, 0.60, 0.48), Color(0.52, 0.52, 0.52)]
	var base: Color = bases[variant % bases.size()]
	_noise_fill(img, base, 0.05, rng)
	_speckle(img, [base.darkened(0.2)], 0.08, rng)
	for x in 32:
		for y in [29, 30, 31]:
			img.set_pixel(x, y, base.darkened(0.35))  # floor slab edge
	for x in range(9, 23):
		for y in range(8, 23):
			var c := Color(0.04, 0.04, 0.05)
			if x == 9 or x == 22 or y == 22:
				c = base.darkened(0.45)
			elif rng.randf() < 0.06:
				c = Color(0.45, 0.55, 0.60)  # glass shard
			img.set_pixel(x, y, c)
	for x in range(7, 25):  # soot plume above the window
		for y in range(0, 8):
			if rng.randf() < (8 - y) * 0.11:
				img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.55))
	return _tex(img)


## Rusty oil drum with a hazard band.
static func barrel() -> ImageTexture:
	return _cached("barrel", _make_barrel)


static func _make_barrel() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	_noise_fill(img, Color(0.45, 0.28, 0.16), 0.06, rng)
	for x in 16:
		for y in [3, 12]:
			img.set_pixel(x, y, Color(0.25, 0.16, 0.10))  # rolling hoops
		for y in range(6, 10):
			img.set_pixel(x, y, Color(0.9, 0.75, 0.1) if (x + y) % 4 < 2 else Color(0.1, 0.1, 0.08))
	_speckle(img, [Color(0.6, 0.35, 0.15)], 0.1, rng)
	return _tex(img)


# --------------------------------------------------------------------------- tank

## Three-colour NATO camouflage (green, brown, black) in big soft-edged blobs,
## with a little grime. Tiles in both directions; one tile is 2.5 m on the tank.
static func camo() -> ImageTexture:
	return _cached("camo", _make_camo)


static func _make_camo() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var green := Color(0.21, 0.26, 0.15)
	var brown := Color(0.31, 0.23, 0.15)
	var black := Color(0.09, 0.09, 0.08)
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			# whole periods across the tile so the pattern wraps
			var a := TAU * x / 64.0
			var b := TAU * y / 64.0
			var k := sin(a * 2.0 + cos(b) * 1.3) + sin(b * 3.0 - a + 0.7) * 0.8 + sin(a + b * 2.0 + 2.1) * 0.6
			var c := green
			if k > 0.75:
				c = brown
			elif k < -0.85:
				c = black
			var v := rng.randf_range(-0.025, 0.025)
			img.set_pixel(x, y, Color(c.r + v, c.g + v, c.b + v))
	_speckle(img, [Color(0.33, 0.30, 0.22)], 0.03, rng)  # dust
	return _tex(img)


## Balkenkreuz: black cross with a white outline on transparent pixels.
static func tank_cross() -> ImageTexture:
	return _cached("cross", _make_tank_cross)


static func _make_tank_cross() -> ImageTexture:
	var img := Image.create(11, 11, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 11:
		for x in 11:
			var dx := absi(x - 5)
			var dy := absi(y - 5)
			if mini(dx, dy) <= 1:
				img.set_pixel(x, y, Color(0.05, 0.05, 0.05))  # arms
			elif mini(dx, dy) <= 2 and maxi(dx, dy) >= 2:
				img.set_pixel(x, y, Color(0.95, 0.95, 0.9))  # white edging
	return ImageTexture.create_from_image(img)


# --------------------------------------------------------------------------- modelled cars

## Livery atlas for the cars modelled in Blender (art/cars/build_cars.py).
## Each painted face is projected from the side, top, front or back into one
## 256x256 image, in Blender space (front +Y, up +Z, ground at 0):
##   rows   0-63  right side, front to the right    rows  64-127 left side
##   rows 128-191 top, front to the right, the car's left side up
##   rows 192-255 front (left half) and back (right half)
## The spec's "atlas" dict says where doors, lights and screens are.
const AL := 2.3  # half length, height and half width the atlas covers
const AH := 1.6
const AW := 1.0


static func _side_px(side: float, y: float, z: float) -> Vector2:
	var u := (y + AL) / (2.0 * AL) if side > 0.0 else (AL - y) / (2.0 * AL)
	return Vector2(u * 256.0, (AH - z) / AH * 64.0 + (0.0 if side > 0.0 else 64.0))


static func _top_px(x: float, y: float) -> Vector2:
	return Vector2((y + AL) / (2.0 * AL) * 256.0, 128.0 + (x + AW) / (2.0 * AW) * 64.0)


static func _end_px(front: bool, x: float, z: float) -> Vector2:
	var u := (AW - x) / (2.0 * AW) * 128.0 if front else 128.0 + (x + AW) / (2.0 * AW) * 128.0
	return Vector2(u, 192.0 + (AH - z) / AH * 64.0)


## Fill the pixel box spanned by two atlas points (any corner order).
static func _box_px(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var r := Rect2i(Vector2i(roundi(minf(a.x, b.x)), roundi(minf(a.y, b.y))),
		Vector2i(maxi(roundi(absf(a.x - b.x)), 1), maxi(roundi(absf(a.y - b.y)), 1)))
	img.fill_rect(r.intersection(Rect2i(0, 0, img.get_width(), img.get_height())), col)


## Box on one side, between two lengths and two heights.
static func _side_box(img: Image, side: float, y0: float, y1: float, z0: float, z1: float, col: Color) -> void:
	_box_px(img, _side_px(side, y0, z0), _side_px(side, y1, z1), col)


## Pixel-font text centred on c, each font pixel s x s, with an optional
## panel and border. `across` turns it a quarter turn for the top of the
## atlas, so it reads across the bonnet when seen from in front.
static func _text_px(img: Image, text: String, c: Vector2, s: int, fg: Color, panel := Color(0, 0, 0, 0),
		border := Color(0, 0, 0, 0), across := false) -> void:
	var w := (text.length() * 4 - 1) * s
	var size := Vector2i(5 * s, w) if across else Vector2i(w, 5 * s)
	var o := Vector2i(roundi(c.x - size.x * 0.5), roundi(c.y - size.y * 0.5))
	if border.a > 0.0:
		img.fill_rect(Rect2i(o - Vector2i(s + 1, s + 1), size + Vector2i(2 * s + 2, 2 * s + 2)), border)
	if panel.a > 0.0:
		img.fill_rect(Rect2i(o - Vector2i(s, s), size + Vector2i(2 * s, 2 * s)), panel)
	for i in text.length():
		var glyph: String = FONT.get(text[i].to_upper(), FONT[" "])
		for row in 5:
			for col in 3:
				if glyph[row * 3 + col] != "1":
					continue
				var t := (i * 4 + col) * s
				var at := Vector2i(row * s, w - s - t) if across else Vector2i(t, row * s)
				img.fill_rect(Rect2i(o + at, Vector2i(s, s)), fg)


static func livery(spec: Dictionary) -> ImageTexture:
	return _cached("livery|" + spec["id"], _make_livery.bind(spec))


static func _make_livery(spec: Dictionary) -> ImageTexture:
	var lv: Dictionary = spec["livery"]
	var at: Dictionary = spec["atlas"]
	var base: Color = lv["base"]
	var a: Color = lv["a"]
	var b: Color = lv["b"]
	var black := Color(0.05, 0.05, 0.06)
	var white := Color(0.96, 0.96, 0.94)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(spec["id"])
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	_noise_fill(img, base, 0.012, rng)
	var doors: Array = at["doors"]  # shut lines: front door, rear door, rear quarter
	var belt: float = at["belt"]
	var fy: float = at["front"]
	var ry: float = at["rear"]
	var light := a.lerp(Color(0.45, 0.7, 0.95), 0.6)
	for s in [-1.0, 1.0]:
		match lv["kind"]:
			"bands":  # Martini-style: dark, light and red bands along the side
				for band in [[0.0, a], [1.0, light], [2.0, b]]:
					var z1: float = at["band"] - band[0] * 0.065
					_side_box(img, s, fy, ry, z1 - 0.065, z1, band[1])
			"split":  # pinstripe at the waist, big name on the front doors
				_side_box(img, s, fy, ry, belt - 0.07, belt - 0.045, b)
				_text_px(img, spec["banner"][0], _side_px(s, ((doors[0] as float) + (doors[1] as float)) * 0.5, 0.68), 2, b)
		# shut lines, handles and the sill
		for dy in doors:
			_side_box(img, s, dy, (dy as float) - 0.02, 0.3, belt, base.darkened(0.45))
		for i in range(doors.size() - 1):
			_side_box(img, s, (doors[i + 1] as float) + 0.14, (doors[i + 1] as float) + 0.04, belt - 0.12, belt - 0.1, black)
		_side_box(img, s, fy, ry, 0.0, 0.27, black.lerp(base, 0.15))
		# door number on the rear door, sponsor low on the front door, fuel cap
		var nc := _side_px(s, ((doors[1] as float) + (doors[2] as float)) * 0.5, belt - 0.26)
		_text_px(img, spec["number"], nc, 3, black, white, black)
		var sp: Array = spec["sponsor"]
		_text_px(img, sp[0], _side_px(s, ((doors[0] as float) + (doors[1] as float)) * 0.5, at["sponsor_z"]), 1, sp[1], sp[2])
		_side_box(img, s, (doors[2] as float) - 0.25, (doors[2] as float) - 0.33, belt - 0.12, belt - 0.05, base.darkened(0.3))
	# top: stripes or a name on the bonnet, roof number
	var bon: Array = at["bonnet"]
	match lv["kind"]:
		"bands":
			for band in [[-0.2, a], [-0.1, light], [0.0, b]]:
				_box_px(img, _top_px(band[0], fy), _top_px((band[0] as float) + 0.09, ry), band[1])
		"split":
			_text_px(img, spec["banner"][0], _top_px(0.0, ((bon[0] as float) + (bon[1] as float)) * 0.5), 2, b,
				Color(0, 0, 0, 0), Color(0, 0, 0, 0), true)
	var roof: Array = at["roof"]
	var rc := _top_px(0.0, ((roof[0] as float) + (roof[1] as float)) * 0.5)
	_box_px(img, rc - Vector2(9, 9), rc + Vector2(9, 9), black)
	_box_px(img, rc - Vector2(8, 8), rc + Vector2(8, 8), white)
	_text_px(img, spec["number"], rc, 2, black)
	# front: grille, headlights, bumper intake and fog lamps
	var hz: Array = at["head"]
	_box_px(img, _end_px(true, -0.33, hz[0]), _end_px(true, 0.33, hz[1]), black)
	for gx in range(-30, 31, 6):
		_box_px(img, _end_px(true, gx * 0.01, hz[0]), _end_px(true, gx * 0.01 + 0.015, hz[1]), Color(0.2, 0.2, 0.22))
	for s in [-1.0, 1.0]:
		_box_px(img, _end_px(true, s * 0.38, hz[0]), _end_px(true, s * 0.8, hz[1]), Color(0.7, 0.7, 0.68))
		_box_px(img, _end_px(true, s * 0.41, (hz[0] as float) + 0.02), _end_px(true, s * 0.6, (hz[1] as float) - 0.02),
			Color(1.0, 0.98, 0.85))
		_box_px(img, _end_px(true, s * 0.62, (hz[0] as float) + 0.02), _end_px(true, s * 0.77, (hz[1] as float) - 0.02),
			Color(1.0, 0.85, 0.45))
		_box_px(img, _end_px(true, s * 0.5, 0.34), _end_px(true, s * 0.68, 0.44), Color(1.0, 0.9, 0.5))
	_box_px(img, _end_px(true, -0.4, 0.25), _end_px(true, 0.4, 0.42), black)
	_paint_tail(img, spec, black, light)
	# underside, and the bottom rows the underside maps to
	img.fill_rect(Rect2i(0, 250, 256, 6), black)
	_bake_light(img)
	return _tex(img)


## Baked-in shading like the hand-painted car skins of the day: sides darken
## towards the sills and catch a highlight under the belt line.
static func _bake_light(img: Image) -> void:
	for y in 128:
		var z := AH * (1.0 - float(y % 64) / 64.0)
		var k := lerpf(0.72, 1.06, smoothstep(0.15, 0.85, z))
		for x in 256:
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k))
	# nose and tail: lit in the middle, falling off round the corners
	for y in range(192, 250):
		var z := AH * (1.0 - float(y - 192) / 64.0)
		for x in 256:
			var across := absf(float(x % 128) / 64.0 - 1.0)
			var k := lerpf(1.04, 0.78, smoothstep(0.6, 0.95, across)) * lerpf(0.86, 1.0, smoothstep(0.2, 0.7, z))
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k))


## The back: livery wrapped round, tail-light clusters, the maker's name on a
## dark panel or garnish between them, a recessed plate on the bumper and a
## black diffuser underneath.
static func _paint_tail(img: Image, spec: Dictionary, black: Color, light: Color) -> void:
	var lv: Dictionary = spec["livery"]
	var at: Dictionary = spec["atlas"]
	var base: Color = lv["base"]
	var tz: Array = at["tail"]
	var bz: float = at["bumper"]
	var t0: float = tz[0]
	var t1: float = tz[1]
	match lv["kind"]:
		"bands":  # stripes carry on across the back, a black light panel above them
			for band in [[0.0, lv["a"]], [1.0, light], [2.0, lv["b"]]]:
				var z1: float = at["band"] - band[0] * 0.065
				_box_px(img, _end_px(false, -1.0, z1 - 0.065), _end_px(false, 1.0, z1), band[1])
			_box_px(img, _end_px(false, -0.86, t0 - 0.01), _end_px(false, 0.86, t1 + 0.01), black)
		"split":  # waist pinstripe wraps round, a garnish between the lights
			var belt: float = at["belt"]
			_box_px(img, _end_px(false, -1.0, belt - 0.07), _end_px(false, 1.0, belt - 0.045), lv["b"])
			_box_px(img, _end_px(false, -0.44, t0 + 0.02), _end_px(false, 0.44, t1 - 0.02), base.darkened(0.6))
	var maker: String = (spec["name"] as String).get_slice(" ", 0)
	_text_px(img, maker, _end_px(false, 0.0, (t0 + t1) * 0.5), 1, Color(0.95, 0.95, 0.9) if lv["kind"] == "bands" else lv["b"])
	for s in [-1.0, 1.0]:
		# cluster: black surround, big red lens, amber indicator and white reverse lamp inboard
		_box_px(img, _end_px(false, s * 0.43, t0), _end_px(false, s * 0.87, t1), black)
		_box_px(img, _end_px(false, s * 0.58, t0 + 0.02), _end_px(false, s * 0.85, t1 - 0.02), Color(0.78, 0.07, 0.05))
		_box_px(img, _end_px(false, s * 0.6, t1 - 0.05), _end_px(false, s * 0.83, t1 - 0.035), Color(1.0, 0.45, 0.4))
		_box_px(img, _end_px(false, s * 0.51, t0 + 0.02), _end_px(false, s * 0.57, t1 - 0.02), Color(0.98, 0.6, 0.12))
		_box_px(img, _end_px(false, s * 0.45, t0 + 0.02), _end_px(false, s * 0.5, t1 - 0.02), Color(0.92, 0.92, 0.88))
	# bumper: shut line, recessed plate, tow eye, diffuser
	_box_px(img, _end_px(false, -0.9, bz), _end_px(false, 0.9, bz - 0.015), base.darkened(0.5))
	var pc := _end_px(false, 0.0, bz - 0.13)
	_text_px(img, spec.get("plate", "RR 98"), pc, 1, black, Color(1.0, 0.85, 0.1), Color(0.12, 0.12, 0.13))
	_box_px(img, _end_px(false, 0.55, bz - 0.15), _end_px(false, 0.62, bz - 0.11), Color(0.2, 0.2, 0.22))
	_box_px(img, _end_px(false, -1.0, 0.0), _end_px(false, 1.0, 0.37), Color(0.08, 0.08, 0.09))
	for x in range(-80, 81, 16):
		_box_px(img, _end_px(false, x * 0.01, 0.24), _end_px(false, x * 0.01 + 0.03, 0.36), Color(0.16, 0.16, 0.18))


## Glass in the same atlas layout: dark tint, diagonal glints and the sun
## strip across the top of the windscreen.
static func glass(spec: Dictionary) -> ImageTexture:
	return _cached("glass|" + spec["id"], _make_glass.bind(spec))


static func _make_glass(spec: Dictionary) -> ImageTexture:
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		for x in 256:
			var c := Color(0.06, 0.08, 0.13).lerp(Color(0.2, 0.26, 0.36), float(y % 64) / 160.0)
			if (x + y) % 37 < 3 or (x + y) % 37 == 6:
				c = c.lightened(0.3)
			img.set_pixel(x, y, c)
	var bn: Array = spec["banner"]
	var top: float = spec["atlas"]["screen"]
	var a := _top_px(-1.0, top - 0.22)
	var b := _top_px(1.0, top + 0.03)
	_box_px(img, a, b, bn[2])
	_text_px(img, bn[0], Vector2((a.x + b.x) * 0.5, 160.0), 1, bn[1])
	return _tex(img)


## Wheel face: tyre sidewall round a rim with five spokes and a hub.
static func rim(col: Color) -> ImageTexture:
	return _cached("rim|" + col.to_html(), _make_rim.bind(col))


static func _make_rim(col: Color) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5)
			var r := d.length() / 16.0
			var ang := fposmod(d.angle() * 5.0 / TAU, 1.0)
			var c := Color(0.07, 0.07, 0.07)  # tyre wall
			if r < 0.68:
				c = col if ang < 0.45 or r < 0.25 or r > 0.6 else col.darkened(0.7)
			if r < 0.12:
				c = col.darkened(0.3)
			if r > 0.68 and r < 0.72:
				c = col.darkened(0.25)
			img.set_pixel(x, y, c)
	return _tex(img)


## Tyre tread: blocks round the tyre.
static func tread() -> ImageTexture:
	return _cached("tread", _make_tread)


static func _make_tread() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	for y in 8:
		for x in 8:
			var groove := x == 0 or (y == 3 and x % 4 != 0) or y == 7
			img.set_pixel(x, y, Color(0.03, 0.03, 0.03) if groove else Color(0.1, 0.1, 0.1))
	return _tex(img)
