class_name Conditions
extends RefCounted
## Weather for a race: the lighting, sky, fog and how much grip the roads
## lose in the rain. The menu picks RANDOM, or a fixed value;
## Game.roll_conditions() turns that into what this race actually gets.

const WEATHERS := ["RANDOM", "CLEAR", "RAIN"]


## Everything the race scene needs to light a stage, for a theme ("",
## "wasteland", "jungle", "circuit") and rain.
static func palette(theme: String, rain: bool) -> Dictionary:
	var p := {
		"sky_top": Color(0.08, 0.30, 0.86), "sky_horizon": Color(0.60, 0.78, 0.98), "sky_ground": Color(0.42, 0.52, 0.48),
		"cloud_hi": Color(0.98, 0.98, 1.0), "cloud_lo": Color(0.72, 0.76, 0.86), "cloud_cover": 0.0,
		"sun_dir": Vector3(-48, -35, 0), "sun_color": Color(1.0, 0.96, 0.86), "sun_energy": 1.15,
		"ambient": Color(0.62, 0.70, 0.85), "ambient_energy": 0.75,
		"fog": Color(0.62, 0.76, 0.96), "fog_density": 0.0008, "headlights": false, "shadows": true,
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
		# thicker, but not so thick the hills lose their shape and colour
		p["fog_density"] = maxf(p["fog_density"] as float, 0.0018) * 1.2
		p["shadows"] = false
		p["headlights"] = true
	return p


## Equirectangular sky from a palette: gradient and chunky clouds.
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
