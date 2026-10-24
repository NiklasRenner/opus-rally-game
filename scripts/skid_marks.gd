class_name SkidMarks
extends Node3D
## Marks the tyres leave on the stage: black rubber with a tread pattern on
## tarmac, dark damp lines on a wet road, deep ruts with ridges of thrown-up
## gravel, glossy mud grooves, flattened turf on grass and white scratches on
## ice. Each kind is one MultiMesh of short strip segments in a ring buffer,
## so old marks are recycled once the buffer is full. The oldest part of each
## buffer fades out gradually (worked out in the shader from the instance's
## age), so marks thin away behind you instead of vanishing in chunks.

## count: segments kept. width: metres. min_len: shortest segment. tex_len:
## metres of mark one copy of the texture covers. ridge: height of the
## thrown-up edges (0 = a flat stain). gloss: 0 matte .. 1 shiny.
const KINDS := {
	"rubber": {"count": 4000, "width": 0.26, "min_len": 0.35, "tex_len": 0.45, "ridge": 0.0, "gloss": 0.35},
	"wet": {"count": 2500, "width": 0.28, "min_len": 0.35, "tex_len": 0.6, "ridge": 0.0, "gloss": 0.9},
	"rut": {"count": 16000, "width": 0.50, "min_len": 0.5, "tex_len": 0.5, "ridge": 0.07, "gloss": 0.0},
	"mud": {"count": 8000, "width": 0.42, "min_len": 0.5, "tex_len": 0.5, "ridge": 0.08, "gloss": 0.6},
	"turf": {"count": 8000, "width": 0.40, "min_len": 0.5, "tex_len": 0.6, "ridge": 0.04, "gloss": 0.0},
	"scrape": {"count": 2500, "width": 0.22, "min_len": 0.5, "tex_len": 0.8, "ridge": 0.0, "gloss": 0.6},
}

## Fraction of a full buffer, oldest first, over which marks fade out.
const FADE := 0.4

const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform float tex_len = 1.0;
uniform float roughness_v = 1.0;
uniform float fade = 0.4;
uniform int buf_head = 0;
uniform int buf_count = 1;

varying float v_alpha;

void vertex() {
	// custom: x = metres along the mark where this segment starts, y = its
	// length, z = how dark it is
	float age = float((buf_head - INSTANCE_ID - 1 + buf_count) % buf_count) / float(buf_count);
	v_alpha = INSTANCE_CUSTOM.z * (1.0 - smoothstep(1.0 - fade, 1.0, age));
	UV.y = (INSTANCE_CUSTOM.x + UV.y * INSTANCE_CUSTOM.y) / tex_len;
}

void fragment() {
	vec4 c = texture(tex, UV) * COLOR;
	ALBEDO = c.rgb;
	ALPHA = c.a * v_alpha;
	ROUGHNESS = roughness_v;
}
"""

static var _shader: Shader

var _layers := {}  # kind -> {"mm": MultiMesh, "mat": ShaderMaterial, "next": int}
var _last := {}  # wheel id -> {"kind": String, "pos": Vector3, "v": float}


func _ready() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	for kind in KINDS:
		var k: Dictionary = KINDS[kind]
		var mat := ShaderMaterial.new()
		mat.shader = _shader
		mat.set_shader_parameter("tex", _texture(kind))
		mat.set_shader_parameter("tex_len", k["tex_len"])
		mat.set_shader_parameter("roughness_v", 1.0 - 0.85 * (k["gloss"] as float))
		mat.set_shader_parameter("fade", FADE)
		mat.set_shader_parameter("buf_count", k["count"])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.use_colors = true  # without it the compatibility renderer zeroes COLOR
		mm.mesh = _strip_mesh(kind, k["width"], k["ridge"], mat)
		mm.instance_count = k["count"]
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_layers[kind] = {"mm": mm, "mat": mat, "next": 0}


## A wheel touching the ground at `pos`. kind from Surfaces ("none" or "" to
## lift off), strength 0..1 sets how dark the new segment is.
func track(wheel: int, kind: String, pos: Vector3, normal: Vector3, strength: float) -> void:
	if not _layers.has(kind) or strength <= 0.02:
		_last.erase(wheel)
		return
	var last: Dictionary = _last.get(wheel, {})
	if last.is_empty() or last["kind"] != kind or (last["pos"] as Vector3).distance_to(pos) > 2.5:
		_last[wheel] = {"kind": kind, "pos": pos, "v": randf() * 4.0}
		return
	var from: Vector3 = last["pos"]
	var length := from.distance_to(pos)
	if length < (KINDS[kind]["min_len"] as float):
		return
	var dir := (pos - from) / length
	var side := normal.cross(dir).normalized()
	var up := dir.cross(side).normalized()
	var xf := Transform3D(Basis(side, up, dir * length), (from + pos) * 0.5)
	var layer: Dictionary = _layers[kind]
	var mm: MultiMesh = layer["mm"]
	var i: int = layer["next"]
	var v: float = last["v"]
	mm.set_instance_transform(i, xf)
	mm.set_instance_color(i, Color.WHITE)
	mm.set_instance_custom_data(i, Color(v, length, clampf(strength, 0.15, 1.0), 0.0))
	layer["next"] = (i + 1) % mm.instance_count
	mm.visible_instance_count = maxi(mm.visible_instance_count, i + 1)
	(layer["mat"] as ShaderMaterial).set_shader_parameter("buf_head", layer["next"])
	last["pos"] = pos
	last["v"] = fmod(v + length, 1000.0)


## One unit-long segment along local Z, UV.x across and UV.y along it. Marks
## with a ridge get a groove with raised, lighter edges either side so they
## read as dug into the ground; flat ones are a single strip.
func _strip_mesh(kind: String, width: float, ridge: float, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	var lift := 0.03
	if ridge <= 0.0:
		var c: Color = {
			"rubber": Color(0.05, 0.05, 0.06, 0.9),
			"wet": Color(0.03, 0.04, 0.07, 0.55),
			"scrape": Color(0.55, 0.68, 0.84, 0.8),  # blue-grey so it shows on white ice
		}[kind]
		_strip(st, -hw, hw, hw, lift, lift, c, c)
	else:
		var groove: Color = {
			"rut": Color(0.30, 0.23, 0.15, 0.92),
			"mud": Color(0.17, 0.10, 0.05, 0.95),
			"turf": Color(0.22, 0.28, 0.11, 0.9),
		}[kind]
		var crest: Color = {
			"rut": Color(0.78, 0.68, 0.52, 0.95),
			"mud": Color(0.40, 0.28, 0.16, 0.95),
			"turf": Color(0.36, 0.26, 0.14, 0.9),
		}[kind]
		var g := hw * 0.55
		_strip(st, -hw, -g, hw, lift - 0.01, lift + ridge, crest.darkened(0.2), crest)
		_strip(st, -g, g, hw, lift, lift, groove, groove)
		_strip(st, g, hw, hw, lift + ridge, lift - 0.01, crest, crest.darkened(0.2))
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh


## Flat strip from x0 to x1 (heights y0, y1 at each edge), z from -0.5 to 0.5.
func _strip(st: SurfaceTool, x0: float, x1: float, hw: float, y0: float, y1: float, c0: Color, c1: Color) -> void:
	var u0 := (x0 + hw) / (hw * 2.0)
	var u1 := (x1 + hw) / (hw * 2.0)
	var a := [Vector3(x0, y0, -0.5), c0, Vector2(u0, 0)]
	var b := [Vector3(x1, y1, -0.5), c1, Vector2(u1, 0)]
	var c := [Vector3(x1, y1, 0.5), c1, Vector2(u1, 1)]
	var d := [Vector3(x0, y0, 0.5), c0, Vector2(u0, 1)]
	for vtx in [a, b, c, a, c, d]:
		st.set_color(vtx[1])
		st.set_uv(vtx[2])
		st.add_vertex(vtx[0])


# --------------------------------------------------------------------------- textures
# Small greyscale pixel textures, x across the mark and y along it. The strip's
# vertex colours give the hue; these add the tread, stones and ragged edges.

static func _texture(kind: String) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var img: Image
	match kind:
		"rubber", "wet":
			img = _tread(rng, 0.45 if kind == "rubber" else 0.25)
		"scrape":
			img = _scratches(rng)
		_:
			img = _churned(rng, kind)
	return ImageTexture.create_from_image(img)


## A tyre's print: lengthwise streaks, blocks of tread in two staggered rows
## and soft shoulders.
static func _tread(rng: RandomNumberGenerator, gap: float) -> Image:
	var img := Image.create(8, 16, false, Image.FORMAT_RGBA8)
	var shade := []
	for x in 8:
		shade.append(rng.randf_range(0.8, 1.0))
	for y in 16:
		for x in 8:
			var a := 1.0
			if x == 0 or x == 7:
				a = 0.35
			elif x == 1 or x == 6:
				a = 0.75
			var row := 0 if x < 4 else 2
			if x > 0 and x < 7 and x != 3 and x != 4 and (y + row) % 4 == 0:
				a *= gap  # tread gap
			if rng.randf() < 0.08:
				a *= 0.6
			var s: float = shade[x]
			img.set_pixel(x, y, Color(s, s, s, a))
	return img


## Thin bright scratches cut into ice, broken here and there, over a little
## powdered frost.
static func _scratches(rng: RandomNumberGenerator) -> Image:
	var img := Image.create(8, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 8:
			var a := 0.12 if rng.randf() < 0.3 else 0.0
			if x in [1, 4, 6] and rng.randf() > 0.12:
				a = 0.9 if x == 4 else 0.65
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return img


## Churned ground: speckled stones or clods, a tread print pressed into the
## groove and ragged edges where the ridges crumble away.
static func _churned(rng: RandomNumberGenerator, kind: String) -> Image:
	var img := Image.create(8, 16, false, Image.FORMAT_RGBA8)
	var speck := 0.35 if kind == "rut" else 0.22
	for y in 16:
		for x in 8:
			var v := 0.82 + rng.randf_range(-0.06, 0.06)
			var roll := rng.randf()
			if roll < speck * 0.5:
				v = 0.5  # stone in shadow / clod
			elif roll < speck:
				v = 1.0  # lit stone / torn turf
			var a := 1.0
			if x == 0 or x == 7:
				a = 0.0 if rng.randf() < 0.45 else 0.7
			elif (x == 3 or x == 4) and y % 4 < 2:
				v *= 0.75  # tread pressed into the groove
			img.set_pixel(x, y, Color(v, v, v, a))
	return img
