class_name Mountains
extends RefCounted
## Faceted background mountains: a peak, two jittered rings of ridge points
## and a ragged base, coloured by height (low slopes, rock, then snow or
## whatever stands in for it), shaded per face from a fixed light and
## textured with a small pixel detail map (rock strata, ash layers, forest
## canopy) that multiplies the colour.
## They're unshaded and skip the stage fog, which would wash them out to flat
## shapes at this distance; a fixed share of the haze colour is mixed in
## instead. A new theme only needs an entry in STYLES (and, if none of the
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
	mat.disable_fog = true
	return mat


## Add one mountain standing at `at` (its base centre), `h` tall and about
## `base` wide at the foot, to `st`.
static func add(st: SurfaceTool, rng: RandomNumberGenerator, at: Vector3, h: float, base: float,
		sty: Dictionary, haze: Color) -> void:
	var sides := 9
	var snow_line := rng.randf_range(0.6, 0.72)
	var rings: Array = [[at + Vector3(rng.randf_range(-20, 20), h, rng.randf_range(-20, 20))]]
	for ring in [[0.32, 0.66], [0.66, 0.3], [1.0, 0.0]]:
		var pts: Array = []
		var twist := rng.randf_range(0.0, TAU / sides)
		for s in sides:
			var ang := TAU * s / sides + twist + rng.randf_range(-0.12, 0.12)
			var rr: float = base * ring[0] * rng.randf_range(0.75, 1.15)
			# ridges: every other point stands proud, the gullies between sink
			var y: float = h * ring[1] * (rng.randf_range(1.0, 1.25) if s % 2 == 0 else rng.randf_range(0.7, 0.95))
			pts.append(at + Vector3(cos(ang) * rr, y if (ring[1] as float) > 0.0 else -8.0, sin(ang) * rr))
		rings.append(pts)
	for ring in 3:
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
	var c: Color = sty["low"]
	if y > snow_line:
		c = sty["top"]
	elif y > snow_line - 0.08 and rng.randf() < 0.5:
		c = (sty["top"] as Color).lerp(sty["rock"], 0.5)  # ragged edge of the snow
	elif y > 0.2:
		c = sty["rock"]
	# steep faces show bare rock even low down
	if n.y < 0.45 and y > 0.12 and y <= snow_line:
		c = (sty["rock"] as Color).darkened(0.12)
	c = (c * (0.62 + 0.38 * maxf(n.dot(LIGHT.normalized()), 0.0))).lerp(haze, 0.4)
	# the detail map runs level across the face and straight up it, so the
	# strata stay horizontal whichever way the face looks
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
	# chunky 2 x 2 grain under everything
	for y in range(0, 64, 2):
		for x in range(0, 64, 2):
			var g := rng.randf_range(0.86, 1.0)
			img.fill_rect(Rect2i(x, y, 2, 2), Color(g, g, g))
	match kind:
		"ash":
			# soft layers of ash and cinder, washed into streaks down the slope
			var y0 := 0
			var dark := false
			while y0 < 64:
				var th := rng.randi_range(3, 6)
				if dark:
					for y in range(y0, mini(y0 + th, 64)):
						for x in 64:
							_mul(img, x, y, 0.84)
				y0 += th
				dark = not dark
			for i in 10:
				var x := rng.randi_range(0, 63)
				var y := rng.randi_range(0, 63)
				for s in rng.randi_range(5, 14):
					_mul(img, x, (y + s) % 64, 0.78)
		"forest":
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
		_:
			# rock strata: dark bedding lines with a lit ledge above, stepping
			# a pixel up or down now and then, and cracks running down
			var y := 3
			while y < 64:
				var wave := 0
				for x in 64:
					if x % 9 == 0 and rng.randf() < 0.5:
						wave = clampi(wave + rng.randi_range(-1, 1), -1, 1)
					_mul(img, x, posmod(y + wave, 64), 0.72)
					_grey(img, x, posmod(y + wave - 1, 64), 1.0)
				y += rng.randi_range(8, 12)
			for i in 9:
				var x := rng.randi_range(0, 63)
				var cy := rng.randi_range(0, 63)
				for s in rng.randi_range(4, 10):
					x = posmod(x + (rng.randi_range(-1, 1) if s % 3 == 0 else 0), 64)
					_mul(img, x, (cy + s) % 64, 0.7)
	return TexGen._tex(img)


static func _mul(img: Image, x: int, y: int, f: float) -> void:
	var c := img.get_pixel(x, y)
	img.set_pixel(x, y, Color(c.r * f, c.g * f, c.b * f))


static func _grey(img: Image, x: int, y: int, g: float) -> void:
	img.set_pixel(x, y, Color(g, g, g))
