class_name SkidMarks
extends Node3D
## Marks the tyres leave on the stage: black rubber on tarmac, deep ruts with
## ridges of thrown-up gravel, brown mud tracks on grass and mud, white
## scratches on ice. Each kind is one MultiMesh of short strip segments in a
## ring buffer, so old marks are recycled once the buffer is full.

const KINDS := {
	"rubber": {"count": 3000, "width": 0.24, "min_len": 0.35},
	"rut": {"count": 5000, "width": 0.48, "min_len": 0.5},
	"mud": {"count": 5000, "width": 0.40, "min_len": 0.5},
	"scrape": {"count": 1500, "width": 0.12, "min_len": 0.5},
}

var _layers := {}  # kind -> {"mm": MultiMesh, "next": int}
var _last := {}  # wheel id -> {"kind": String, "pos": Vector3}


func _ready() -> void:
	for kind in KINDS:
		var k: Dictionary = KINDS[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _strip_mesh(kind, k["width"])
		mm.instance_count = k["count"]
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_layers[kind] = {"mm": mm, "next": 0}


## A wheel touching the ground at `pos`. kind from Surfaces ("none" or "" to
## lift off), strength 0..1 sets how dark the new segment is.
func track(wheel: int, kind: String, pos: Vector3, normal: Vector3, strength: float) -> void:
	if not _layers.has(kind) or strength <= 0.02:
		_last.erase(wheel)
		return
	var last: Dictionary = _last.get(wheel, {})
	if last.is_empty() or last["kind"] != kind or (last["pos"] as Vector3).distance_to(pos) > 2.5:
		_last[wheel] = {"kind": kind, "pos": pos}
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
	mm.set_instance_transform(i, xf)
	mm.set_instance_color(i, Color(1, 1, 1, clampf(strength, 0.15, 1.0)))
	layer["next"] = (i + 1) % mm.instance_count
	mm.visible_instance_count = maxi(mm.visible_instance_count, i + 1)
	_last[wheel]["pos"] = pos


## One unit-long segment along local Z. Ruts and mud get a dark groove with
## lighter raised ridges either side so they read as dug into the road.
func _strip_mesh(kind: String, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	match kind:
		"rubber":
			_strip(st, -hw, hw, 0.03, 0.03, Color(0.04, 0.04, 0.05, 0.85), Color(0.04, 0.04, 0.05, 0.85))
		"scrape":
			_strip(st, -hw, hw, 0.03, 0.03, Color(0.95, 0.98, 1.0, 0.7), Color(0.95, 0.98, 1.0, 0.7))
		"rut", "mud":
			var groove := Color(0.17, 0.12, 0.07, 0.92) if kind == "rut" else Color(0.16, 0.10, 0.05, 0.92)
			var ridge := Color(0.70, 0.60, 0.44, 0.9) if kind == "rut" else Color(0.38, 0.27, 0.15, 0.9)
			var g := hw * 0.55
			_strip(st, -hw, -g, 0.02, 0.07, ridge.darkened(0.15), ridge)
			_strip(st, -g, g, 0.025, 0.025, groove, groove)
			_strip(st, g, hw, 0.07, 0.02, ridge, ridge.darkened(0.15))
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0 if kind != "rubber" else 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	return mesh


## Flat strip from x0 to x1 (heights y0, y1 at each edge), z from -0.5 to 0.5.
func _strip(st: SurfaceTool, x0: float, x1: float, y0: float, y1: float, c0: Color, c1: Color) -> void:
	var a := Vector3(x0, y0, -0.5)
	var b := Vector3(x1, y1, -0.5)
	var c := Vector3(x1, y1, 0.5)
	var d := Vector3(x0, y0, 0.5)
	for v in [[a, c0], [b, c1], [c, c1], [a, c0], [c, c1], [d, c0]]:
		st.set_color(v[1])
		st.add_vertex(v[0])
