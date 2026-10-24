class_name Mountains
extends RefCounted
## Faceted background mountains: a peak, two jittered rings of ridge points
## and a ragged base, coloured by height (low slopes, rock, then snow or
## whatever stands in for it), shaded per face from a fixed light and
## textured with a small pixel detail map (blotchy rock with gullies and
## scree, ash, forest canopy) that multiplies the colour.
## They're unshaded and take the stage fog like everything else, so they're
## always at least as hazy as the hills in front of them; `haze` adds a
## little extra tint on top. A new theme only needs an entry in STYLES (and, if none of the
## detail maps suit it, a new one in _detail()).

const STYLES := {
	"": {"low": Color(0.36, 0.44, 0.40), "rock": Color(0.42, 0.46, 0.56), "top": Color(0.94, 0.96, 1.0), "detail": "rock"},
	"wasteland": {"low": Color(0.34, 0.26, 0.20), "rock": Color(0.40, 0.31, 0.24), "top": Color(0.54, 0.47, 0.40),
		"detail": "ash"},  # ash, not snow
	"jungle": {"low": Color(0.18, 0.32, 0.20), "rock": Color(0.24, 0.38, 0.27), "top": Color(0.32, 0.46, 0.32),
		"detail": "forest"},  # forest right to the top
	"moon": {"low": Color(0.40, 0.40, 0.40), "rock": Color(0.52, 0.52, 0.51), "top": Color(0.70, 0.70, 0.68),
		"detail": "ash"},  # bare grey highlands, layered dust
}
const TILE := 110.0  # metres of mountainside per repeat of the detail map
const LIGHT := Vector3(-0.55, 0.65, 0.5)


static func style(theme: String) -> Dictionary:
	return STYLES.get(theme, STYLES[""])


static func material(sty: Dictionary) -> StandardMaterial3D:
	var mat := TexGen.material(detail(sty["detail"]), 1.0)
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## Add one mountain standing at `at` (its base centre), `h` tall and about
## `base` wide at the foot, to `st`. Not a cone: it's stretched along a
## ridge line (`along`, or a random one if that's zero), its height wobbles
## round the compass so shoulders and subpeaks stand up out of it, and
## alternate points form spurs and gullies.
static func add(st: SurfaceTool, rng: RandomNumberGenerator, at: Vector3, h: float, base: float,
		sty: Dictionary, haze: Color, along := Vector3.ZERO) -> void:
	var sides := 13
	var snow_line := rng.randf_range(0.42, 0.54)
	var ridge := rng.randf_range(0.0, PI)  # direction the mountain is drawn out along
	if along != Vector3.ZERO:
		ridge = atan2(along.z, along.x) + rng.randf_range(-0.35, 0.35)
	var stretch := rng.randf_range(1.15, 1.8)
	var waves := [rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU)]
	var summit := at + Vector3(rng.randf_range(-0.1, 0.1) * base, h, rng.randf_range(-0.1, 0.1) * base)
	var rings: Array = [[summit]]
	# [radius, height] as fractions of base and h, summit to foot
	for ring in [[0.16, 0.86], [0.36, 0.64], [0.58, 0.42], [0.8, 0.2], [1.0, 0.0]]:
		var pts: Array = []
		var twist := rng.randf_range(0.0, TAU / sides)
		for s in sides:
			var ang := TAU * s / sides + twist + rng.randf_range(-0.15, 0.15)
			# height around the compass: shoulders and subpeaks
			var swell := 1.0 + 0.22 * sin(2.0 * ang + waves[0]) + 0.14 * sin(3.0 * ang + waves[1])
			# spurs stand proud, the gullies between sink
			var spur := rng.randf_range(1.0, 1.2) if s % 2 == 0 else rng.randf_range(0.72, 0.92)
			var y: float = minf(h * ring[1] * swell * spur, h * 0.97)
			var rr: float = base * ring[0] * rng.randf_range(0.8, 1.15) * (1.0 + 0.18 * sin(2.0 * ang + waves[2]))
			var d := Vector2(cos(ang), sin(ang)) * rr
			d = d.rotated(-ridge)
			d.x *= stretch
			d = d.rotated(ridge)
			pts.append(at + Vector3(d.x, y if (ring[1] as float) > 0.0 else -8.0, d.y))
		rings.append(pts)
	for ring in rings.size() - 1:
		var inner: Array = rings[ring]
		var outer: Array = rings[ring + 1]
		for s in sides:
			var o0: Vector3 = outer[s]
			var o1: Vector3 = outer[(s + 1) % sides]
			if ring == 0:
				_tri(st, rng, [inner[0], o1, o0], at.y, h, snow_line, sty, haze)
			else:
				var i0: Vector3 = inner[s]
				var i1: Vector3 = inner[(s + 1) % sides]
				_tri(st, rng, [i0, i1, o0], at.y, h, snow_line, sty, haze)
				_tri(st, rng, [i1, o1, o0], at.y, h, snow_line, sty, haze)


static func _tri(st: SurfaceTool, rng: RandomNumberGenerator, v: Array, foot: float, h: float, snow_line: float,
		sty: Dictionary, haze: Color) -> void:
	var n := ((v[1] - v[0]) as Vector3).cross(v[2] - v[0]).normalized()
	if n.y < 0.0:
		n = -n
	var y := (((v[0] as Vector3).y + (v[1] as Vector3).y + (v[2] as Vector3).y) / 3.0 - foot) / h
	# snow lies lower on gentle faces and slides off steep ones, so the cap
	# reaches down the ridges and gullies instead of ending in a flat line
	var line := snow_line + (0.55 - n.y) * 0.35 + rng.randf_range(-0.06, 0.06)
	var c: Color = sty["low"]
	if y > line:
		c = sty["top"]
	elif y > line - 0.07:
		c = (sty["top"] as Color).lerp(sty["rock"], 0.55)  # thin, broken snow
	elif y > 0.18 + rng.randf_range(-0.06, 0.06):
		c = sty["rock"]
	# steep faces show bare rock even low down
	if n.y < 0.45 and y > 0.1 and y <= line - 0.07:
		c = (sty["rock"] as Color).darkened(0.12)
	c = (c * (0.62 + 0.38 * maxf(n.dot(LIGHT.normalized()), 0.0))).lerp(haze, 0.15)
	# the detail map runs level across the face and straight down it, so
	# gullies and scree run downhill whichever way the face looks
	var across_x := absf(n.x) < absf(n.z)
	for p in v:
		var q := p as Vector3
		st.set_color(Color(c.r, c.g, c.b))
		st.set_uv(Vector2((q.x if across_x else q.z) / TILE, -q.y / TILE))
		st.add_vertex(q)


# --------------------------------------------------------------------------- detail maps

## Greyscale detail that multiplies the face colour: "rock", "ash" or "forest".
static func detail(kind: String) -> ImageTexture:
	return TexGen.cached("mountain_" + kind, _detail.bind(kind))


static func _detail(kind: String) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + 31
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	if kind == "forest":
		# treetops: rounded clumps, lit on top, shadowed underneath
		img.fill(Color(0.78, 0.78, 0.78))
		for i in 90:
			var cx := rng.randi_range(0, 63)
			var cy := rng.randi_range(0, 63)
			var r := rng.randi_range(2, 3)
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if dx * dx + dy * dy <= r * r:
						var g := 1.0 if dy < 0 else (0.9 if dy == 0 else 0.82)
						img.set_pixel(posmod(cx + dx, 64), posmod(cy + dy, 64), Color(g, g, g))
			img.set_pixel(posmod(cx + 1, 64), posmod(cy + r + 1, 64), Color(0.6, 0.6, 0.6))
		return TexGen._tex(img)
	# rock and ash: blotchy patches of lighter and darker stone in 2 x 2
	# pixels, a few broken slanting seams, gullies wandering down and fans of
	# scree spreading out below them
	var ash := kind == "ash"
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	var blotch := noise.get_seamless_image(64, 64)
	for y in range(0, 64, 2):
		for x in range(0, 64, 2):
			var n := blotch.get_pixel(x, y).r
			var g := 0.8 + 0.2 * snappedf(n, 0.25) + rng.randf_range(-0.03, 0.03)
			img.fill_rect(Rect2i(x, y, 2, 2), Color(g, g, g))
	# seams: short slanting runs, each broken into pieces
	for i in (14 if ash else 8):
		var x := rng.randi_range(0, 63)
		var y := rng.randi_range(0, 63)
		var slope := rng.randf_range(-0.35, 0.35)
		var fy := float(y)
		for s in rng.randi_range(6, 18):
			fy += slope
			if rng.randf() < 0.8:
				_mul(img, posmod(x + s, 64), posmod(int(fy), 64), 0.8 if ash else 0.76)
	# gullies down the slope, widening into a fan of scree at the bottom
	for i in (6 if ash else 7):
		var x := rng.randi_range(0, 63)
		var y := rng.randi_range(0, 63)
		var length := rng.randi_range(12, 26)
		for s in length:
			if rng.randf() < 0.35:
				x += rng.randi_range(-1, 1)
			_mul(img, posmod(x, 64), posmod(y + s, 64), 0.7)
			if s > length - 7:
				var spread := s - (length - 7)
				for k in 2:
					var sx := x + rng.randi_range(-spread, spread)
					_grey(img, posmod(sx, 64), posmod(y + s + 1, 64), rng.randf_range(0.88, 1.0))
	return TexGen._tex(img)


static func _mul(img: Image, x: int, y: int, f: float) -> void:
	var c := img.get_pixel(x, y)
	img.set_pixel(x, y, Color(c.r * f, c.g * f, c.b * f))


static func _grey(img: Image, x: int, y: int, g: float) -> void:
	img.set_pixel(x, y, Color(g, g, g))
