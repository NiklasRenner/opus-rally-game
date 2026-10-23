class_name Conditions
extends RefCounted
## Weather for a race: the lighting, sky, fog and how much grip the roads
## lose in the rain. The menu picks RANDOM, or a fixed value;
## Game.roll_conditions() turns that into what this race actually gets.
## The palette still knows dusk and night, but races are always in the day
## for now (Game.race_time_of_day).

const WEATHERS := ["RANDOM", "CLEAR", "RAIN"]


## Everything the race scene needs to light a stage, for a theme ("",
## "wasteland", "jungle", "circuit"), a time ("DAY", "DUSK", "NIGHT") and rain.
static func palette(theme: String, time: String, rain: bool) -> Dictionary:
	var p := {
		"sky_top": Color(0.08, 0.30, 0.86), "sky_horizon": Color(0.60, 0.78, 0.98), "sky_ground": Color(0.42, 0.52, 0.48),
		"cloud_hi": Color(0.98, 0.98, 1.0), "cloud_lo": Color(0.72, 0.76, 0.86), "cloud_cover": 0.0,
		"stars": false, "moon": false, "sun_glow": Color(0, 0, 0, 0),
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
	match time:
		"DUSK":
			p.merge({"sky_top": (p["sky_top"] as Color).lerp(Color(0.18, 0.16, 0.42), 0.7),
				"sky_horizon": (p["sky_horizon"] as Color).lerp(Color(1.0, 0.52, 0.22), 0.75),
				"cloud_hi": Color(1.0, 0.66, 0.42), "cloud_lo": Color(0.45, 0.30, 0.42),
				"sun_glow": Color(1.0, 0.75, 0.35, 1.0),
				"sun_dir": Vector3(-11, -70, 0), "sun_color": Color(1.0, 0.62, 0.32), "sun_energy": 0.95,
				"ambient": (p["ambient"] as Color).lerp(Color(0.70, 0.52, 0.55), 0.6), "ambient_energy": 0.55,
				"fog": (p["fog"] as Color).lerp(Color(0.85, 0.55, 0.38), 0.7), "headlights": true}, true)
		"NIGHT":
			p.merge({"sky_top": Color(0.01, 0.02, 0.06), "sky_horizon": Color(0.06, 0.09, 0.18),
				"sky_ground": Color(0.02, 0.03, 0.04), "cloud_hi": Color(0.16, 0.18, 0.26), "cloud_lo": Color(0.05, 0.06, 0.10),
				"stars": true, "moon": true, "sun_dir": Vector3(-38, 140, 0), "sun_color": Color(0.55, 0.65, 1.0),
				"sun_energy": 0.22, "ambient": Color(0.30, 0.36, 0.55), "ambient_energy": 0.32,
				"fog": Color(0.03, 0.04, 0.08), "fog_density": maxf(p["fog_density"], 0.002), "headlights": true}, true)
			if theme == "wasteland":
				p["sky_horizon"] = Color(0.30, 0.12, 0.05)  # the fires never went out
				p["fog"] = Color(0.10, 0.05, 0.03)
	if rain:
		var grey := Color(0.46, 0.48, 0.52)
		if time == "NIGHT":
			grey = Color(0.05, 0.06, 0.08)
		elif time == "DUSK":
			grey = Color(0.42, 0.34, 0.36)
		p["sky_top"] = (p["sky_top"] as Color).lerp(grey.darkened(0.25), 0.85)
		p["sky_horizon"] = (p["sky_horizon"] as Color).lerp(grey.lightened(0.15), 0.7)
		p["cloud_hi"] = grey.lightened(0.1)
		p["cloud_lo"] = grey.darkened(0.35)
		p["cloud_cover"] = 1.0
		p["stars"] = false
		p["moon"] = false
		p["sun_glow"] = Color(0, 0, 0, 0)
		p["sun_energy"] = (p["sun_energy"] as float) * 0.45
		p["ambient"] = (p["ambient"] as Color).lerp(grey.lightened(0.3), 0.5)
		p["fog"] = (p["fog"] as Color).lerp(grey, 0.7)
		p["fog_density"] = maxf(p["fog_density"] as float, 0.0028) * 1.4
		p["shadows"] = false
		if time == "DAY":
			p["headlights"] = true
	return p


## Equirectangular sky from a palette: gradient, chunky clouds, and at night
## stars and a moon, at dusk a low sun glow.
static func sky(p: Dictionary) -> ImageTexture:
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
	var glow: Color = p["sun_glow"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for y in h:
		var lat := 0.5 - float(y) / h  # +0.5 top, -0.5 bottom
		for x in w:
			var c: Color
			if lat < 0.0:
				c = horizon.lerp(ground, clampf(-lat * 6.0, 0.0, 1.0))
			else:
				c = horizon.lerp(top, pow(clampf(lat * 2.4, 0.0, 1.0), 0.6))
				if glow.a > 0.0:
					# low sun: a warm patch on the horizon
					var dx := absf(wrapf(float(x) / w - 0.30, -0.5, 0.5))
					c = c.lerp(glow, clampf(1.0 - Vector2(dx * 3.0, lat * 5.0).length(), 0.0, 1.0) * 0.8)
				var a := TAU * float(x) / w
				var n := noise.get_noise_3d(cos(a), sin(a), lat * 5.0)
				var band := clampf(1.0 - absf(lat - 0.12) * 5.0, 0.0, 1.0)
				band = lerpf(band, 1.0, cover)
				var cloud := clampf((n + 0.05 + cover * 0.5) * 3.0, 0.0, 1.0) * band
				if cloud > 0.0:
					var shade := cloud_hi.lerp(cloud_lo, clampf(-n * 2.0 + 0.4, 0.0, 1.0))
					c = c.lerp(shade, cloud)
			img.set_pixel(x, y, c)
	if p["stars"]:
		for i in 700:
			var sx := rng.randi_range(0, w - 1)
			var sy := rng.randi_range(0, int(h * 0.46))
			var b := rng.randf_range(0.45, 1.0)
			img.set_pixel(sx, sy, img.get_pixel(sx, sy).lerp(Color(b, b, b * 0.95 + 0.05), 0.85))
	if p["moon"]:
		var mc := Vector2(w * 0.62, h * 0.24)
		for y in range(int(mc.y) - 8, int(mc.y) + 9):
			for x in range(int(mc.x) - 8, int(mc.x) + 9):
				var d := Vector2(x, y).distance_to(mc)
				if d < 6.5:
					var crater := 0.85 if (x * 7 + y * 3) % 11 == 0 else 1.0
					img.set_pixel(x, y, Color(0.92, 0.92, 0.84) * crater)
				elif d < 8.5:
					img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color(0.5, 0.55, 0.7), 0.4))
	return ImageTexture.create_from_image(img)
