class_name TyreFx
extends Node3D
## What one tyre throws up: billowing puffs (tyre smoke, dust, spray, powder
## snow) and small flying bits (stones, mud clods, torn grass, droplets).
## Chunky pixel sprites in a few shaded variants, the way late-90s arcade
## racers drew them. The car moves this node to the bottom of its wheel and
## calls show_surface() every frame.

## puff: [colour a, colour b] picked between at random, life (s), size (m)
## at birth and at death, speed, rise (upward pull, negative falls).
## bits: [colour a, colour b], how many relative to the puffs (0 = none),
## speed, size. kick: how steeply things are thrown up (0 flat .. 1 straight).
const LOOKS := {
	"smoke": {"puff": [Color(1.0, 1.0, 1.0), Color(0.88, 0.88, 0.92)], "life": 1.6, "size": [0.9, 3.0],
		"speed": 1.8, "rise": 0.5, "alpha": 0.85, "bits": [], "bit_ratio": 0.0, "kick": 0.25},
	"dust": {"puff": [Color(0.95, 0.85, 0.66), Color(0.84, 0.72, 0.52)], "life": 1.3, "size": [0.8, 2.8],
		"speed": 2.4, "rise": 0.3, "alpha": 0.8, "bits": [Color(0.55, 0.50, 0.44), Color(0.85, 0.78, 0.64)],
		"bit_ratio": 0.8, "bit_speed": 5.0, "bit_size": 0.09, "kick": 0.6},
	"mud": {"puff": [Color(0.45, 0.33, 0.20), Color(0.36, 0.25, 0.14)], "life": 0.8, "size": [0.5, 1.4],
		"speed": 2.0, "rise": -0.5, "alpha": 0.7, "bits": [Color(0.22, 0.14, 0.07), Color(0.36, 0.25, 0.13)],
		"bit_ratio": 1.0, "bit_speed": 6.0, "bit_size": 0.13, "kick": 0.7},
	"turf": {"puff": [Color(0.62, 0.56, 0.36), Color(0.50, 0.46, 0.30)], "life": 0.9, "size": [0.5, 1.6],
		"speed": 2.0, "rise": 0.1, "alpha": 0.55, "bits": [Color(0.28, 0.48, 0.16), Color(0.36, 0.25, 0.13)],
		"bit_ratio": 0.9, "bit_speed": 5.0, "bit_size": 0.1, "kick": 0.7},
	"spray": {"puff": [Color(0.86, 0.90, 0.96), Color(0.74, 0.80, 0.88)], "life": 0.8, "size": [0.7, 2.4],
		"speed": 3.0, "rise": -0.3, "alpha": 0.5, "bits": [Color(0.85, 0.92, 1.0), Color(0.70, 0.80, 0.92)],
		"bit_ratio": 0.6, "bit_speed": 4.0, "bit_size": 0.06, "kick": 0.45},
	"splash": {"puff": [Color(0.94, 0.97, 1.0), Color(0.80, 0.88, 0.94)], "life": 0.9, "size": [0.7, 2.4],
		"speed": 4.0, "rise": -2.0, "alpha": 0.85, "bits": [Color(0.90, 0.96, 1.0), Color(0.62, 0.76, 0.86)],
		"bit_ratio": 1.0, "bit_speed": 6.5, "bit_size": 0.1, "kick": 0.85},
	"powder": {"puff": [Color(0.97, 0.99, 1.0), Color(0.84, 0.90, 0.97)], "life": 1.2, "size": [0.7, 2.4],
		"speed": 2.2, "rise": 0.0, "alpha": 0.8, "bits": [Color(1, 1, 1), Color(0.78, 0.88, 1.0)],
		"bit_ratio": 0.5, "bit_speed": 4.0, "bit_size": 0.06, "kick": 0.5},
}

const SURFACE_LOOK := {"asphalt": "smoke", "wood": "smoke", "gravel": "dust", "mud": "mud", "grass": "turf",
	"wet": "spray", "ford": "splash", "ice": "powder", "snow": "powder"}

const PUFFS := 36
const BITS := 28

static var _puff_tex: ImageTexture
static var _bit_tex: ImageTexture

var _puffs: CPUParticles3D
var _bits: CPUParticles3D
var _look := ""
var _puff_acc := 0.0
var _bit_acc := 0.0


func _ready() -> void:
	if _puff_tex == null:
		_puff_tex = _make_puff_tex()
		_bit_tex = _make_bit_tex()
	_puffs = _emitter(_puff_tex, PUFFS, 4)
	_bits = _emitter(_bit_tex, BITS, 2)
	_bits.spread = 30.0
	add_child(_puffs)
	add_child(_bits)


## surface: the Surfaces id under the tyre. amount 0..1 (0 stops it). spray:
## a wet road in the rain, which throws water whatever the surface.
func show_surface(surface: String, amount: float, spray := false) -> void:
	var look: String = "spray" if spray else SURFACE_LOOK.get(surface, "dust")
	if look != _look:
		_look = look
		_apply(LOOKS[look])
	# CPU particles can't thin out their emission, so a light amount lets the
	# emitters run only some of the frames (spread evenly, like dithering)
	_puff_acc += clampf(amount, 0.0, 1.0)
	_puffs.emitting = _puff_acc >= 1.0
	_puff_acc = fmod(_puff_acc, 1.0)
	_bit_acc += clampf(amount * (LOOKS[look]["bit_ratio"] as float), 0.0, 1.0)
	_bits.emitting = _bit_acc >= 1.0
	_bit_acc = fmod(_bit_acc, 1.0)


func _apply(l: Dictionary) -> void:
	var cols: Array = l["puff"]
	_puffs.color_initial_ramp = _pair(cols[0], cols[1])
	var a: float = l["alpha"]
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.12, 0.6, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, a), Color(1, 1, 1, a * 0.55), Color(1, 1, 1, 0)])
	_puffs.color_ramp = fade
	_puffs.lifetime = l["life"]
	var size: Array = l["size"]
	_puffs.scale_amount_min = 0.8
	_puffs.scale_amount_max = 1.2
	var grow := Curve.new()
	grow.max_value = 4.0
	grow.add_point(Vector2(0.0, size[0]))
	grow.add_point(Vector2(0.35, lerpf(size[0], size[1], 0.65)), 0.0, 0.0)
	grow.add_point(Vector2(1.0, size[1]))
	_puffs.scale_amount_curve = grow
	var kick: float = l["kick"]
	# the car drives along -Z, so +Z throws things out behind the tyre
	_puffs.direction = Vector3(0, kick, 1.0 - kick * 0.5)
	_puffs.initial_velocity_min = (l["speed"] as float) * 0.5
	_puffs.initial_velocity_max = l["speed"]
	_puffs.gravity = Vector3(0, l["rise"], 0)
	var bits: Array = l["bits"]
	if bits.is_empty():
		return
	_bits.color_initial_ramp = _pair(bits[0], bits[1])
	_bits.direction = Vector3(0, kick + 0.3, 1.0 - kick * 0.4)
	_bits.initial_velocity_min = (l["bit_speed"] as float) * 0.5
	_bits.initial_velocity_max = l["bit_speed"]
	var s: float = l["bit_size"]
	_bits.scale_amount_min = s * 0.6 / 0.1
	_bits.scale_amount_max = s * 1.4 / 0.1


func _emitter(tex: Texture2D, amount: int, frames: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.7
	p.local_coords = false
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.15
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1) if frames == 4 else Vector2(0.1, 0.1)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# without it the compatibility renderer draws idle particles as black
	# sprites at the emitter (and ignores their size)
	mat.billboard_keep_scale = true
	mat.particles_anim_h_frames = frames
	mat.particles_anim_v_frames = 1
	mat.particles_anim_loop = false
	quad.material = mat
	p.mesh = quad
	p.spread = 22.0
	p.gravity = Vector3(0, -14.0, 0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	# each particle keeps one random sprite variant for its whole life
	p.anim_offset_max = 1.0
	p.anim_speed_min = 0.0
	p.anim_speed_max = 0.0
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.color_ramp = fade
	return p


static func _pair(a: Color, b: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	return g


## Four 16 x 16 cloud puffs side by side: a few overlapping blobs each, lit
## from the top left with a darker underside, hard pixel edges and a ring of
## dithered pixels round the outside.
static func _make_puff_tex() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1997
	var img := Image.create(64, 16, false, Image.FORMAT_RGBA8)
	for f in 4:
		var blobs := []
		for b in 4:
			var r := rng.randf_range(3.0, 5.0) if b > 0 else 5.5
			var c := Vector2(7.5, 8.0) + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 2.5)) * (0.0 if b == 0 else 1.0)
			blobs.append([c, r])
		for y in 16:
			for x in 16:
				var p := Vector2(x, y)
				var inside := -1.0  # how far inside the nearest blob edge, in pixels
				var light := 0.0
				for bl in blobs:
					var c: Vector2 = bl[0]
					var r: float = bl[1]
					var d := r - p.distance_to(c)
					if d > inside:
						inside = d
						light = clampf((c - p).dot(Vector2(0.7, 0.7)) / r, -1.0, 1.0)
				if inside < -0.6 or (inside < 0.6 and (x + y) % 2 == 0):
					continue
				var shade := 0.82 + 0.18 * light
				if inside < 1.2:
					shade -= 0.06
				shade = snappedf(shade, 0.06)  # a few flat steps, not a smooth ramp
				img.set_pixel(f * 16 + x, y, Color(shade, shade, shade, 1.0 if inside >= 0.6 else 0.6))
	return ImageTexture.create_from_image(img)


## Two 4 x 4 bits: a lit chip with a dark corner and a rounder clod.
static func _make_bit_tex() -> ImageTexture:
	var img := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	var rows := ["1110", "1111", "1112", "0122", "0110", "1111", "1112", "0120"]
	for f in 2:
		for y in 4:
			var row: String = rows[f * 4 + y]
			for x in 4:
				var ch := row[x]
				if ch == "0":
					continue
				var v := 1.0 if ch == "1" else 0.6
				img.set_pixel(f * 4 + x, y, Color(v, v, v, 1.0))
	return ImageTexture.create_from_image(img)
