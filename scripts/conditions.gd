class_name Conditions
extends RefCounted
## Weather for a race: the lighting, sky, fog and how much grip the roads
## lose in the rain. The menu picks RANDOM, or a fixed value;
## Game.roll_conditions() turns that into what this race actually gets.

const WEATHERS := ["RANDOM", "CLEAR", "RAIN"]


## Everything the race scene needs to light a stage, for a theme ("",
## "wasteland", "jungle", "circuit", "moon", "city") and rain.
static func palette(theme: String, rain: bool) -> Dictionary:
	var p := {
		"sky_top": Color(0.08, 0.30, 0.86), "sky_horizon": Color(0.60, 0.78, 0.98), "sky_ground": Color(0.42, 0.52, 0.48),
		"cloud_hi": Color(0.98, 0.98, 1.0), "cloud_lo": Color(0.72, 0.76, 0.86), "cloud_cover": 0.0,
		"sun_dir": Vector3(-48, -35, 0), "sun_color": Color(1.0, 0.96, 0.86), "sun_energy": 1.15,
		"ambient": Color(0.62, 0.70, 0.85), "ambient_energy": 0.75,
		"fog": Color(0.62, 0.76, 0.96), "fog_density": 0.0011, "headlights": false, "shadows": true,
	}
	match theme:
		"wasteland":
			# nuclear dusk: rust-brown overhead, a sick orange glow on the horizon
			p.merge({"sky_top": Color(0.22, 0.17, 0.14), "sky_horizon": Color(0.88, 0.55, 0.26),
				"sky_ground": Color(0.35, 0.28, 0.22), "cloud_hi": Color(0.62, 0.50, 0.40), "cloud_lo": Color(0.24, 0.20, 0.18),
				"sun_color": Color(1.0, 0.72, 0.45), "sun_energy": 1.0, "ambient": Color(0.70, 0.58, 0.46),
				"ambient_energy": 0.6, "fog": Color(0.62, 0.45, 0.30), "fog_density": 0.0035}, true)
		"jungle":
			# steamy: pale hazy sky, green-grey mist that closes in
			p.merge({"sky_top": Color(0.22, 0.46, 0.78), "sky_horizon": Color(0.78, 0.86, 0.82),
				"sky_ground": Color(0.30, 0.42, 0.30), "cloud_cover": 0.15, "sun_color": Color(1.0, 0.95, 0.80),
				"ambient": Color(0.56, 0.70, 0.60), "fog": Color(0.66, 0.78, 0.70), "fog_density": 0.0042}, true)
		"moon":
			# no air: a black sky full of stars, the Earth hanging over the
			# horizon, a hard low sun, inky shadows and no haze to speak of
			p.merge({"space": true, "sky_top": Color(0.0, 0.0, 0.01), "sky_horizon": Color(0.02, 0.02, 0.03),
				"sky_ground": Color(0.12, 0.12, 0.12), "sun_dir": Vector3(-24, -62, 0), "sun_color": Color(1.0, 0.99, 0.96),
				"sun_energy": 1.45, "ambient": Color(0.42, 0.48, 0.62), "ambient_energy": 0.32,
				"fog": Color(0.16, 0.16, 0.17), "fog_density": 0.0002}, true)
		"city":
			# a warm afternoon with a little smog over the rooftops
			p.merge({"sky_top": Color(0.16, 0.38, 0.80), "sky_horizon": Color(0.80, 0.82, 0.84),
				"sky_ground": Color(0.40, 0.40, 0.42), "cloud_cover": 0.1, "sun_dir": Vector3(-40, -55, 0),
				"sun_color": Color(1.0, 0.93, 0.80), "ambient": Color(0.66, 0.68, 0.76), "fog": Color(0.72, 0.74, 0.78),
				"fog_density": 0.0016}, true)
	if rain:
		var grey := Color(0.46, 0.48, 0.52)
		p["sky_top"] = (p["sky_top"] as Color).lerp(grey.darkened(0.25), 0.85)
		p["sky_horizon"] = (p["sky_horizon"] as Color).lerp(grey.lightened(0.15), 0.7)
		p["cloud_hi"] = grey.lightened(0.1)
		p["cloud_lo"] = grey.darkened(0.35)
		p["cloud_cover"] = 1.0
		p["sun_energy"] = (p["sun_energy"] as float) * 0.45
		p["ambient"] = (p["ambient"] as Color).lerp(grey.lightened(0.3), 0.5)
		p["fog"] = (p["fog"] as Color).lerp(grey, 0.7)
		p["fog_density"] = maxf(p["fog_density"] as float, 0.0028) * 1.4
		p["shadows"] = false
		p["headlights"] = true
	return p


## Equirectangular sky from a palette: gradient and chunky clouds.
static func sky(p: Dictionary) -> ImageTexture:
	if p.get("space", false):
		return _space_sky(p)
	var w := 512
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 1.6
	noise.fractal_octaves = 4
	var top: Color = p["sky_top"]
	var horizon: Color = p["sky_horizon"]
	var ground: Color = p["sky_ground"]
	var cloud_hi: Color = p["cloud_hi"]
	var cloud_lo: Color = p["cloud_lo"]
	var cover: float = p["cloud_cover"]
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
				band = lerpf(band, 1.0, cover)
				var cloud := clampf((n + 0.05 + cover * 0.5) * 3.0, 0.0, 1.0) * band
				if cloud > 0.0:
					var shade := cloud_hi.lerp(cloud_lo, clampf(-n * 2.0 + 0.4, 0.0, 1.0))
					c = c.lerp(shade, cloud)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Where the Earth hangs in the Moon's sky, as a direction.
const EARTH_DIR := Vector3(0.1, 0.28, -0.96)  # low over the first straight


## The Moon's sky: black, stars of a few brightnesses, the Milky Way as a
## faint band, and the Earth half lit, with blue seas, green and brown land
## and white cloud. Twice the usual size so the stars stay points.
static func _space_sky(p: Dictionary) -> ImageTexture:
	var w := 1024
	var h := 512
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(p["sky_top"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 1969
	var ground: Color = p["sky_ground"]
	for y in range(h / 2, h):
		for x in w:
			img.set_pixel(x, y, (p["sky_horizon"] as Color).lerp(ground, clampf((y - h * 0.5) / 30.0, 0.0, 1.0)))
	# the Milky Way: a faint tilted band of haze and many dim stars
	for k in 9000:
		var x := rng.randi_range(0, w - 1)
		var band := sin(TAU * x / w) * 0.22 * h + h * 0.24
		var y := int(band + rng.randfn(0.0, 16.0))
		if y < 0 or y >= h / 2:
			continue
		var c := img.get_pixel(x, y)
		img.set_pixel(x, y, c.lerp(Color(0.55, 0.55, 0.62), rng.randf_range(0.04, 0.16)))
	for k in 2600:
		var x := rng.randi_range(0, w - 1)
		var y := rng.randi_range(0, h / 2 - 2)
		var b := pow(rng.randf(), 3.0)
		var tint := [Color(1, 1, 1), Color(0.8, 0.88, 1.0), Color(1.0, 0.92, 0.78)][rng.randi() % 3] as Color
		img.set_pixel(x, y, Color(0.15, 0.15, 0.17).lerp(tint, 0.25 + 0.75 * b))
		if b > 0.7:  # the bright ones get a little cross
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + o
				if q.x >= 0 and q.x < w and q.y >= 0 and q.y < h / 2:
					img.set_pixel(q.x, q.y, img.get_pixel(q.x, q.y).lerp(tint, 0.45))
	_paint_earth(img)
	return ImageTexture.create_from_image(img)


static func _paint_earth(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var d := EARTH_DIR.normalized()
	var radius := 0.075  # angular radius, radians (about seven times the real thing)
	# a frame round the Earth's direction to place each pixel on its disc
	var right := Vector3.UP.cross(d).normalized()
	var up := d.cross(right)
	# sunlit from the same side as the stage's sun, so the terminator reads
	var light := Vector3(-0.9, 0.1, 0.4).normalized()
	var land := FastNoiseLite.new()
	land.seed = 3
	land.frequency = 2.2
	var clouds := FastNoiseLite.new()
	clouds.seed = 8
	clouds.frequency = 4.0
	# Godot reads a panorama with u = atan2(x, -z) / TAU (wrapped)
	var lon0 := atan2(d.x, -d.z)
	var lat0 := asin(d.y)
	var span := radius * 1.3
	for y in range(int((0.5 - (lat0 + span) / PI) * h), int((0.5 - (lat0 - span) / PI) * h) + 1):
		for x in range(int((lon0 - span / cos(lat0)) / TAU * w) - 1, int((lon0 + span / cos(lat0)) / TAU * w) + 2):
			var lon := (float(x) + 0.5) / w * TAU
			var lat := (0.5 - (float(y) + 0.5) / h) * PI
			var dir := Vector3(sin(lon) * cos(lat), sin(lat), -cos(lon) * cos(lat))
			var u := dir.dot(right) / radius
			var v := dir.dot(up) / radius
			var r2 := u * u + v * v
			if r2 > 1.0 or dir.dot(d) < 0.0:
				continue
			var n := Vector3(u, v, sqrt(1.0 - r2))  # on the visible half of the globe
			var c := Color(0.10, 0.26, 0.62)  # sea
			var l := land.get_noise_3d(n.x, n.y, n.z)
			if l > 0.12:
				c = Color(0.24, 0.46, 0.20) if l < 0.32 else Color(0.56, 0.46, 0.30)
			if absf(n.y) > 0.86:
				c = Color(0.92, 0.94, 0.98)  # ice caps
			var cl := clouds.get_noise_3d(n.x * 1.3, n.y, n.z)
			if cl > 0.18:
				c = c.lerp(Color(0.96, 0.97, 1.0), clampf((cl - 0.18) * 4.0, 0.0, 0.9))
			var lit := clampf(n.dot(light) * 1.6 + 0.15, 0.0, 1.0)
			c = Color(0.02, 0.03, 0.06).lerp(c, lit)
			# thin blue air at the rim
			c = c.lerp(Color(0.45, 0.65, 1.0), clampf((r2 - 0.8) * 3.0, 0.0, 0.5) * lit)
			img.set_pixel(posmod(x, w), y, c)
