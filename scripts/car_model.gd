class_name CarModel
extends Node3D
## Low-poly rally car lofted from the side profile in its Cars spec: rings of
## points every few centimetres from nose to tail, with flared arches cut out
## around the wheels, flat shaded and painted per face with the livery.
## Panels dent at runtime: vertices near an impact are pushed inward and
## scuffed darker; bolt-on parts (bumpers, light pod, wing, mirrors) fall off
## once their damage zone passes a threshold.

const MAX_DENT := 0.42
const BOTTOM := -0.24  # underside of the shell
const WHEEL_Y := -0.38  # wheel centre at rest
const WHEEL_Z := [-1.32, 1.28]
const ARCH_R := 0.47
const STEP := 0.13  # ring spacing along the car
const GLASS := Color(0.07, 0.09, 0.15)

## Ring edge -> paint region: 0 rocker, 1 lower door, 2 mid door, 3 stripe
## band under the belt line, 4 side glass / shoulder, 5 top, -1 underside.
## Region 6 is the nose and tail caps.
const EDGE_REGION := [0, 1, 2, 3, 4, 5, 5, 5, 5, 5, 4, 3, 2, 1, 0, -1]
const TOP_X := [0.3, 0.11]  # extra points across the roof/bonnet for stripes

var spec: Dictionary = Cars.LIST[0]

var _deformables: Array[Dictionary] = []
var _parts := {}
var _body_mat: StandardMaterial3D
# karts and F1: driver's head and steering wheel follow the steering
var _head: Node3D
var _steering: Node3D
# tank only: animated bits
var _turret: Node3D
var _track_mat: StandardMaterial3D
var _road_wheels: Array[Node3D] = []

static var _wind := 0.0


func build() -> void:
	_body_mat = StandardMaterial3D.new()
	_body_mat.vertex_color_use_as_albedo = true
	_body_mat.roughness = 0.32
	_body_mat.metallic_specular = 0.75
	_head = null
	_steering = null
	if kind() == "kart":
		_build_kart()
		return
	_build_shell()
	if is_tank():
		_build_tank()
		return
	if kind() == "f1":
		_build_f1()
		return
	_build_details()
	_build_parts()


func kind() -> String:
	return spec.get("type", "car")


func is_tank() -> bool:
	return kind() == "tank"


func _bottom() -> float:
	return spec.get("bottom", BOTTOM)


func _arches() -> bool:
	return spec.get("arches", true)


# --------------------------------------------------------------------------- shell

func _keys() -> Array:
	return spec["profile"]


## (top, belt) at z, linearly interpolated between the profile keys.
func _profile(z: float) -> Vector2:
	var keys := _keys()
	if z <= (keys[0][0] as float):
		return Vector2(keys[0][1], keys[0][2])
	for i in range(1, keys.size()):
		var k: Array = keys[i]
		if z <= (k[0] as float):
			var p: Array = keys[i - 1]
			var t := (z - (p[0] as float)) / ((k[0] as float) - (p[0] as float))
			return Vector2(lerpf(p[1], k[1], t), lerpf(p[2], k[2], t))
	var last: Array = keys[keys.size() - 1]
	return Vector2(last[1], last[2])


func front_z() -> float:
	return _front_z()


func _front_z() -> float:
	return _keys()[0][0]


func _rear_z() -> float:
	return _keys()[_keys().size() - 1][0]


func _half_width(z: float) -> float:
	var w: float = (spec["width"] as float) * 0.5
	if spec.has("plan"):
		w = _plan(z) * 0.5
	for wz in (WHEEL_Z if _arches() else []):
		var dz := absf(z - (wz as float))
		w += (spec["flare"] as float) * clampf(1.0 - (dz - ARCH_R * 0.75) / 0.3, 0.0, 1.0)
	# round off the corners in plan view
	var end := minf(z - _front_z(), _rear_z() - z)
	return w * lerpf(0.88, 1.0, smoothstep(0.0, 0.3, end))


## Body width at z from the optional plan keys.
func _plan(z: float) -> float:
	var keys: Array = spec["plan"]
	if z <= (keys[0][0] as float):
		return keys[0][1]
	for i in range(1, keys.size()):
		var k: Array = keys[i]
		if z <= (k[0] as float):
			var p: Array = keys[i - 1]
			return lerpf(p[1], k[1], (z - (p[0] as float)) / ((k[0] as float) - (p[0] as float)))
	return keys[keys.size() - 1][1]


## Body heights at z: bottom (raised into arches over the wheels), sill,
## mid door, stripe line, belt line, top.
func _heights(z: float) -> Array[float]:
	var pr := _profile(z)
	var top := pr.x
	var belt := pr.y
	var bot := _bottom()
	for wz in (WHEEL_Z if _arches() else []):
		var dz := absf(z - (wz as float))
		if dz < ARCH_R:
			bot = maxf(bot, WHEEL_Y + sqrt(ARCH_R * ARCH_R - dz * dz))
	bot = minf(bot, belt - 0.2)
	var sill := minf(bot + 0.07, belt - 0.14)
	var stripe := belt - 0.09
	var out: Array[float] = [bot, sill, lerpf(sill, stripe, 0.5), stripe, belt, maxf(top, belt + 0.03)]
	return out


func _ring(z: float) -> PackedVector3Array:
	var h := _heights(z)
	var w := _half_width(z)
	var cab := smoothstep(0.08, 0.3, h[5] - h[4])
	var tx := w * lerpf(0.9, spec["taper"], cab)
	var right := [Vector2(w * 0.86, h[0]), Vector2(w, h[1]), Vector2(w, h[2]), Vector2(w, h[3]),
		Vector2(w, h[4]), Vector2(tx, h[5])]
	for x in TOP_X:
		right.append(Vector2(minf(x, tx * 0.9), h[5] + 0.02 * (1.0 - x / tx)))  # slight crown
	var ring := PackedVector3Array()
	for p in right:
		ring.append(Vector3(p.x, p.y, z))
	for i in range(right.size() - 1, -1, -1):
		ring.append(Vector3(-right[i].x, right[i].y, z))
	return ring


func _stations() -> Array[float]:
	var zs: Array[float] = []
	for k in _keys():
		zs.append(k[0])
	var z := _front_z()
	while z < _rear_z():
		zs.append(z)
		z += STEP
	for wz in WHEEL_Z:
		zs.append((wz as float) - ARCH_R)
		zs.append((wz as float) + ARCH_R)
	var bp: float = spec["b_pillar"]
	zs.append(bp - 0.07)
	zs.append(bp + 0.07)
	zs.sort()
	var out: Array[float] = []
	for s in zs:
		if s < _front_z() - 0.001 or s > _rear_z() + 0.001:
			continue
		if out.is_empty() or s - out[out.size() - 1] > 0.035:
			out.append(s)
		elif is_equal_approx(s, _rear_z()):
			out[out.size() - 1] = s
	return out


func _build_shell() -> void:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var zs := _stations()
	var rings: Array[PackedVector3Array] = []
	for z in zs:
		rings.append(_ring(z))
	var rn := rings[0].size()
	for j in zs.size() - 1:
		var ra := rings[j]
		var rb := rings[j + 1]
		var zc := (zs[j] + zs[j + 1]) * 0.5
		var h := _heights(zc)
		var axis_y := (h[0] + h[4]) * 0.5
		for e in rn:
			var e2 := (e + 1) % rn
			var cen := (ra[e] + ra[e2] + rb[e] + rb[e2]) * 0.25
			var outward := cen - Vector3(0, axis_y, cen.z)
			var col := _paint(EDGE_REGION[e], cen, _quad_normal(ra[e], ra[e2], rb[e], outward), h)
			_add_quad(verts, colors, ra[e], ra[e2], rb[e2], rb[e], outward, col)
	# nose and tail caps
	for cap in [[rings[0], zs[0], Vector3.FORWARD], [rings[rings.size() - 1], zs[zs.size() - 1], Vector3.BACK]]:
		var ring: PackedVector3Array = cap[0]
		var h := _heights(cap[1])
		var c := Vector3(0, (h[0] + h[5]) * 0.5, cap[1])
		for e in rn:
			var a := ring[e]
			var b := ring[(e + 1) % rn]
			var cen := (a + b + c) / 3.0
			_add_tri(verts, colors, a, b, c, cap[2], _paint(6, cen, cap[2], h))
	_add_deformable(self, verts, colors, Vector3.ZERO)


func _quad_normal(a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> Vector3:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		return outward.normalized()
	n = n.normalized()
	return n if n.dot(outward) >= 0.0 else -n


func _livery(key: String) -> Variant:
	return spec["livery"][key]


## Colour for one face of the shell.
func _paint(region: int, c: Vector3, n: Vector3, h: Array[float]) -> Color:
	var base: Color = _livery("base")
	var trim: Color = spec["trim"]
	var cab: bool = h[5] - h[4] > 0.2 and spec.get("glass", true)
	var bp: float = spec["b_pillar"]
	if region == -1:
		return Color(0.1, 0.1, 0.11)
	if region == 4 and cab:
		return spec["roof"] if absf(c.z - bp) < 0.07 else GLASS
	if region == 5 and cab:
		return GLASS if absf(n.z) > 0.42 else spec["roof"]
	var kind: String = _livery("kind")
	var a: Color = _livery("a")
	var b: Color = _livery("b")
	var top_or_nose := region == 5 or (region == 6 and c.z < 0.0)
	match kind:
		"camo":  # blotchy three-colour camouflage
			if region in [1, 2, 3, 4, 5, 6]:
				var k := sin(c.x * 3.1 + c.z * 1.7) + sin(c.z * 2.3 - c.y * 5.0 + c.x * 1.3)
				if k > 0.7:
					return a
				if k < -0.8:
					return b
		"bands":  # Martini-style: two bands along the side, stripe over the bonnet
			if region == 2:
				return a
			if region == 3:
				return b
			if top_or_nose and absf(c.x) < 0.28:
				return a
		"split":  # two-tone with a pinstripe at the waist
			if region <= 1:
				return a
			if region == 3:
				return b
		"nose":  # two-tone with a bonnet panel in the stripe colour
			if region <= 1:
				return a
			if region == 3:
				return b
			if top_or_nose and c.z < (spec["a_pillar"] as float) and absf(c.x) < 0.32:
				return a
		"stripes":  # twin stripes nose to tail, side stripe under the windows
			if region == 3:
				return a
			if top_or_nose and absf(c.x) > 0.1 and absf(c.x) < 0.32:
				return a
			if region == 1:
				return b
	if region == 0:
		return trim
	return base


func _add_quad(verts: PackedVector3Array, colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, outward: Vector3, col: Color) -> void:
	_add_tri(verts, colors, a, b, c, outward, col)
	_add_tri(verts, colors, a, c, d, outward, col)


func _add_tri(verts: PackedVector3Array, colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3,
		outward: Vector3, col: Color) -> void:
	var cr := (b - a).cross(c - a)
	if cr.length_squared() < 1e-12:
		return
	if cr.dot(outward) * winding() < 0.0:
		var t := b
		b = c
		c = t
	verts.append_array([a, b, c])
	colors.append_array([col, col, col])


## +1 if Godot's front faces have cross(b - a, c - a) pointing outward, else -1.
static func winding() -> float:
	if _wind == 0.0:
		var arr := BoxMesh.new().get_mesh_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var cr := (v[idx[1]] - v[idx[0]]).cross(v[idx[2]] - v[idx[0]])
		_wind = 1.0 if cr.dot(n[idx[0]]) > 0.0 else -1.0
	return _wind


# --------------------------------------------------------------------------- details

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _lamp(parent: Node3D, radius: float, pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.05
	cm.radial_segments = 8
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = TexGen.flat_material(col, 0.2, true)
	mi.rotation.x = PI * 0.5
	mi.position = pos
	parent.add_child(mi)


# Orientations for flat decals (QuadMesh faces +Z): text reads left to right
# for someone looking at that face of the car.
const FACE_FRONT := Basis(Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1))
const FACE_BACK := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
const FACE_RIGHT := Basis(Vector3(0, 0, -1), Vector3.UP, Vector3.RIGHT)
const FACE_LEFT := Basis(Vector3(0, 0, 1), Vector3.UP, Vector3.LEFT)


## A textured sticker. Give width or height (the other < 0) to keep the
## texture's pixel aspect.
func _decal(tex: Texture2D, size: Vector2, pos: Vector3, bas: Basis, glow := false, parent: Node3D = null) -> MeshInstance3D:
	if size.y < 0.0:
		size.y = size.x * tex.get_height() / tex.get_width()
	elif size.x < 0.0:
		size.x = size.y * tex.get_width() / tex.get_height()
	var qm := QuadMesh.new()
	qm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	var m := TexGen.material(tex, 0.45)
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.transform = Transform3D(bas, pos)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(mi)
	return mi


## Fixed details that don't dent: grille, lights, plate, mud flaps, exhaust,
## door numbers and sponsor stickers.
func _build_details() -> void:
	var fz := _front_z()
	var rz := _rear_z()
	var hf := _heights(fz)
	var hr := _heights(rz)
	var dark := TexGen.flat_material(Color(0.06, 0.06, 0.08), 0.6)
	var ly := lerpf(-0.03, hf[5], 0.5)
	var hw := _half_width(fz)
	_decal(TexGen.grille(), Vector2(hw * 0.72, 0.13), Vector3(0, ly, fz - 0.012), FACE_FRONT)
	var flap_mat := TexGen.flat_material(spec["flaps"], 0.9)
	var black := Color(0.05, 0.05, 0.07)
	var white := Color(0.97, 0.97, 0.95)
	for s in [-1.0, 1.0]:
		var lx: float = s * hw * 0.68
		if spec["lights"] == "round":
			_lamp(self, 0.085, Vector3(lx - s * 0.05, ly, fz - 0.03), Color(1.0, 0.97, 0.82))
			_lamp(self, 0.07, Vector3(lx + s * 0.11, ly, fz - 0.03), Color(1.0, 0.75, 0.3))
		else:
			_decal(TexGen.headlight(), Vector2(0.38, 0.14), Vector3(lx, ly, fz - 0.015), FACE_FRONT, true)
		var tw := _half_width(rz)
		_decal(TexGen.taillight(), Vector2(0.38, 0.13), Vector3(s * tw * 0.66, lerpf(-0.03, hr[5], 0.55), rz + 0.012),
			FACE_BACK, true)
		# mud flaps behind each wheel
		for wz in WHEEL_Z:
			_box(self, Vector3(0.3, 0.3, 0.02), Vector3(s * 0.8, -0.45, (wz as float) + ARCH_R - 0.06), flap_mat)
		var bas := FACE_RIGHT if s > 0.0 else FACE_LEFT
		# door number and a sponsor sticker on the rear quarter
		var dz: float = (spec["b_pillar"] as float) - 0.42
		var dh := _heights(dz)
		_decal(TexGen.pixel_text(spec["number"], black, white, black), Vector2(-1, 0.27),
			Vector3(s * (_half_width(dz) + 0.012), (dh[1] + dh[3]) * 0.5, dz), bas)
		if spec.has("sponsor"):
			var sp: Array = spec["sponsor"]
			var qz: float = lerpf(spec["b_pillar"], WHEEL_Z[1], 0.3)
			var qh := _heights(qz)
			_decal(TexGen.pixel_text(sp[0], sp[1], sp[2]), Vector2(-1, 0.08),
				Vector3(s * (_half_width(qz) + 0.012), lerpf(qh[1], qh[3], 0.65), qz), bas)
	# rear plate
	_decal(TexGen.pixel_text(spec.get("plate", "RR 98"), black, Color(1.0, 0.85, 0.1), black), Vector2(0.5, -1),
		Vector3(0, lerpf(-0.03, hr[5], 0.3), rz + 0.015), FACE_BACK)
	_build_glass_banner()
	_build_bonnet_plate()
	var ex := MeshInstance3D.new()
	var em := CylinderMesh.new()
	em.top_radius = 0.05
	em.bottom_radius = 0.05
	em.height = 0.2
	em.radial_segments = 6
	ex.mesh = em
	ex.material_override = TexGen.flat_material(Color(0.5, 0.5, 0.52), 0.4)
	ex.rotation.x = PI * 0.5
	ex.position = Vector3(-0.5, BOTTOM + 0.02, rz + 0.05)
	add_child(ex)
	# bonnet scoop
	var sz: float = spec["scoop"]
	if sz != 0.0:
		var top := _heights(sz)[5]
		_box(self, Vector3(0.5, 0.08, 0.36), Vector3(0, top + 0.03, sz), TexGen.flat_material(_livery("base"), 0.4))
		_box(self, Vector3(0.4, 0.05, 0.02), Vector3(0, top + 0.04, sz - 0.18), dark)


## Sun strip across the top of the windscreen with the team name.
func _build_glass_banner() -> void:
	if not spec.has("banner"):
		return
	var keys := _keys()
	var a_z: float = spec["a_pillar"]
	var b: Array = []
	for k in keys:
		if (k[0] as float) > a_z + 0.01:
			b = k
			break
	var pa := Vector2(a_z, _profile(a_z).x)
	var pb := Vector2(b[0], b[1])
	var p := pa.lerp(pb, 0.86)
	var d := (pb - pa).normalized()  # (dz, dy) up the glass
	var up := Vector3(0, d.y, d.x)
	var normal := Vector3(0, d.x, -d.y)
	var width := _half_width(p.x) * 2.0 * (spec["taper"] as float) * 0.95
	var bn: Array = spec["banner"]
	_decal(TexGen.pixel_text(bn[0], bn[1], bn[2]), Vector2(width, 0.12), Vector3(0, p.y, p.x) + normal * 0.035,
		Basis(Vector3(-1, 0, 0), up, normal))


## Classic rally plate on the bonnet, readable from the chase camera.
func _build_bonnet_plate() -> void:
	var fz := _front_z() + 0.15
	var a_z: float = spec["a_pillar"]
	var z := lerpf(fz, a_z, 0.3)
	var fwd := Vector3(0, _profile(fz).x - _profile(a_z).x, fz - a_z).normalized()
	var normal := Vector3.RIGHT.cross(fwd)
	_decal(TexGen.pixel_text("RETRO RALLY", Color(0.05, 0.05, 0.07), Color(0.97, 0.97, 0.95), Color(0.85, 0.1, 0.08)),
		Vector2(0.66, -1), Vector3(0, _heights(z)[5] + 0.02, z) + normal * 0.02, Basis(Vector3.RIGHT, fwd, normal))


func _build_parts() -> void:
	var fz := _front_z()
	var rz := _rear_z()
	var w: float = (spec["width"] as float) + 0.04
	var trim: Color = spec["trim"]
	_add_part("bumper_f", "front", 0.30, Vector3(0, BOTTOM + 0.08, fz - 0.05), Vector3(w, 0.24, 0.26),
		trim, Vector3i(6, 1, 1))
	_add_part("bumper_r", "rear", 0.35, Vector3(0, BOTTOM + 0.08, rz + 0.05), Vector3(w, 0.24, 0.26),
		trim, Vector3i(6, 1, 1))

	var wing: Array = spec["wing"]
	if not wing.is_empty():
		var wz: float = wing[0]
		var lift: float = wing[1]
		var chord: float = wing[2]
		var y := _heights(wz)[5] + lift
		var wing_w := _half_width(wz) * 2.0 * ((spec["taper"] as float) if lift < 0.08 else 0.95)
		var foil := _add_part("spoiler", "rear", 0.55, Vector3(0, y, wz), Vector3(wing_w, 0.06, chord),
			_livery("base"), Vector3i(6, 1, 2))
		if lift >= 0.08:
			var strut_mat := TexGen.flat_material(trim)
			var plate_mat := TexGen.flat_material(_livery("a"))
			for sx in [-0.5, 0.5]:
				_box(foil, Vector3(0.06, lift, 0.18), Vector3(sx * wing_w * 0.8, -lift * 0.5, 0.0), strut_mat)
			for sx in [-1.0, 1.0]:
				_box(foil, Vector3(0.03, 0.14, chord), Vector3(sx * wing_w * 0.5, 0.04, 0.0), plate_mat)

	var lamps: int = spec["pod"]
	if lamps > 0:
		var top := _heights(fz)[5]
		var pod := _add_part("lights", "front", 0.2, Vector3(0, top + 0.06, fz + 0.02),
			Vector3(lamps * 0.28 + 0.06, 0.2, 0.1), Color(0.1, 0.1, 0.1), Vector3i(4, 1, 1))
		for i in lamps:
			_lamp(pod, 0.11, Vector3((i - (lamps - 1) * 0.5) * 0.28, 0, -0.06), Color(1.0, 0.95, 0.65))

	var mz: float = (spec["a_pillar"] as float) + 0.2
	var mh := _heights(mz)
	for s in [-1.0, 1.0]:
		_add_part("mirror_l" if s < 0 else "mirror_r", "left" if s < 0 else "right", 0.2,
			Vector3(s * (_half_width(mz) + 0.08), mh[4] + 0.1, mz), Vector3(0.16, 0.11, 0.1),
			spec["roof"], Vector3i(1, 1, 1))


## One tyre with its rim, axle along X. With `override` (the ghost) the
## rim is left out and the tyre uses that material.
static func make_wheel(radius: float, width: float, rim_color: Color, override: Material = null) -> Node3D:
	var root := Node3D.new()
	var tyre := CylinderMesh.new()
	tyre.top_radius = radius
	tyre.bottom_radius = radius
	tyre.height = width
	tyre.radial_segments = 10 if radius > 0.2 else 8
	tyre.rings = 1
	var parts := [[tyre, override if override else TexGen.flat_material(Color(0.08, 0.08, 0.09), 0.9)]]
	if override == null:
		var rim := CylinderMesh.new()
		rim.top_radius = radius * 0.59
		rim.bottom_radius = radius * 0.59
		rim.height = width + 0.01
		rim.radial_segments = 6
		rim.rings = 1
		parts.append([rim, TexGen.flat_material(rim_color, 0.4)])
	for part in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.material_override = part[1]
		mi.rotation.z = PI * 0.5
		if override:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


## Wheels for cars that don't drive (the ghost, the menu turntable).
func add_display_wheels(override: Material = null) -> void:
	if is_tank():
		return  # tracks and road wheels are part of the model
	var wl := Cars.wheels(spec)
	var pos := Cars.wheel_positions(spec)
	for i in 4:
		var r: float = wl["rf"] if i < 2 else wl["rr"]
		var wheel := make_wheel(r, wl["wf"] if i < 2 else wl["wr"], spec["rims"], override)
		wheel.position = pos[i] + Vector3(0, WHEEL_Y + 0.05 + r - Cars.WHEEL_RADIUS, 0)
		add_child(wheel)


# --------------------------------------------------------------------------- damage

func _add_deformable(parent: Node3D, verts: PackedVector3Array, colors: PackedColorArray, pos: Vector3) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var mi := MeshInstance3D.new()
	mi.mesh = ArrayMesh.new()
	mi.position = pos
	parent.add_child(mi)
	var d := {"mi": mi, "arrays": arrays, "base": verts.duplicate(), "verts": verts, "colors": colors,
		"detached": false}
	_deformables.append(d)
	_rebuild(d)
	return mi


## A box as a flat-shaded triangle soup, so it dents like the shell.
func _box_soup(size: Vector3, sub: Vector3i) -> PackedVector3Array:
	var bm := BoxMesh.new()
	bm.size = size
	bm.subdivide_width = sub.x
	bm.subdivide_height = sub.y
	bm.subdivide_depth = sub.z
	var arr := bm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var out := PackedVector3Array()
	for i in idx:
		out.append(v[i])
	return out


func _add_part(part_name: String, zone: String, threshold: float, pos: Vector3, size: Vector3,
		col: Color, sub: Vector3i, parent: Node3D = null) -> Node3D:
	var root := Node3D.new()
	root.name = part_name
	root.position = pos
	(parent if parent else self).add_child(root)
	var verts := _box_soup(size, sub)
	var colors := PackedColorArray()
	colors.resize(verts.size())
	colors.fill(col)
	_add_deformable(root, verts, colors, Vector3.ZERO)
	_parts[part_name] = {"node": root, "zone": zone, "threshold": threshold, "size": size, "detached": false}
	return root


## Flat normals for a triangle soup wound so that front faces point outward.
static func _flat_normals(verts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(verts.size())
	var s := winding()
	for i in range(0, verts.size(), 3):
		var n := ((verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i]) * s).normalized()
		out[i] = n
		out[i + 1] = n
		out[i + 2] = n
	return out


func _rebuild(d: Dictionary) -> void:
	var arrays: Array = d["arrays"]
	arrays[Mesh.ARRAY_VERTEX] = d["verts"]
	arrays[Mesh.ARRAY_NORMAL] = _flat_normals(d["verts"])
	arrays[Mesh.ARRAY_COLOR] = d["colors"]
	var mi: MeshInstance3D = d["mi"]
	var mesh: ArrayMesh = mi.mesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _body_mat)


## Push vertices near `point` (global) along `dir` (global, pointing into the car).
func dent(point: Vector3, dir: Vector3, amount: float, radius: float) -> void:
	for d in _deformables:
		if d["detached"]:
			continue
		var mi: MeshInstance3D = d["mi"]
		var inv := mi.global_transform.affine_inverse()
		var lp := inv * point
		var ldir := (inv.basis * dir).normalized()
		var verts: PackedVector3Array = d["verts"]
		var base: PackedVector3Array = d["base"]
		var colors: PackedColorArray = d["colors"]
		var changed := false
		for i in verts.size():
			var dist := verts[i].distance_to(lp)
			if dist >= radius:
				continue
			var f := 1.0 - dist / radius
			f *= f
			var nv := verts[i] + ldir * amount * f
			var off := nv - base[i]
			if off.length() > MAX_DENT:
				nv = base[i] + off.limit_length(MAX_DENT)
			verts[i] = nv
			colors[i] = colors[i].lerp(Color(0.28, 0.27, 0.26), clampf(f * amount * 2.5, 0.0, 0.5))
			changed = true
		if changed:
			d["verts"] = verts
			d["colors"] = colors
			_rebuild(d)


## Full repair: throw the model away and build a fresh one.
func reset_damage() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_deformables.clear()
	_parts.clear()
	build()


## Detach bolt-on parts whose zone damage passed their threshold.
func update_parts(zones: Dictionary, car_velocity: Vector3) -> Array[String]:
	var dropped: Array[String] = []
	for part_name in _parts:
		var p: Dictionary = _parts[part_name]
		if p["detached"]:
			continue
		if (zones[p["zone"]] as float) >= (p["threshold"] as float):
			_detach(part_name, car_velocity)
			dropped.append(part_name)
	return dropped


func _detach(part_name: String, car_velocity: Vector3) -> void:
	var p: Dictionary = _parts[part_name]
	p["detached"] = true
	var node: Node3D = p["node"]
	for d in _deformables:
		if node.is_ancestor_of(d["mi"]):
			d["detached"] = true
	var gt := node.global_transform
	var rb := RigidBody3D.new()
	rb.mass = 6.0
	rb.collision_layer = 4
	rb.collision_mask = 1 | 4
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = p["size"]
	cs.shape = bs
	rb.add_child(cs)
	# drop the part into the world (car's parent), not into the car
	get_parent().get_parent().add_child(rb)
	rb.global_transform = gt
	node.reparent(rb, true)
	var kick := (gt.origin - global_position).normalized()
	rb.linear_velocity = car_velocity * 0.85 + kick * 3.0 + Vector3.UP * 2.5
	rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	get_tree().create_timer(30.0).timeout.connect(rb.queue_free)


# --------------------------------------------------------------------------- open wheelers

## A box stretched from a to b (frame tubes, suspension arms, limbs).
func _rod(parent: Node3D, a: Vector3, b: Vector3, thick: float, mat: Material) -> MeshInstance3D:
	var mi := _box(parent, Vector3(thick, thick, a.distance_to(b)), (a + b) * 0.5, mat)
	var d := (b - a).normalized()
	mi.basis = Basis.looking_at(d, Vector3.FORWARD if absf(d.y) > 0.95 else Vector3.UP)
	return mi


## Driver's helmet with a dark visor; turns with the steering in animate().
func _helmet(pos: Vector3, col: Color, r: float) -> void:
	_head = Node3D.new()
	_head.position = pos
	add_child(_head)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	mi.material_override = TexGen.flat_material(col, 0.3)
	_head.add_child(mi)
	_box(_head, Vector3(r * 1.45, r * 0.42, r * 0.7), Vector3(0, r * 0.08, -r * 0.68),
		TexGen.flat_material(Color(0.05, 0.06, 0.1), 0.1))


## Wheel centre height in model space for a tyre of radius r.
func _hub_y(r: float) -> float:
	return WHEEL_Y + r - Cars.WHEEL_RADIUS


## Go-kart: tube frame, floor tray, plastic nose and side pods (these dent and
## fall off), seat, side engine and a driver sitting out in the open.
func _build_kart() -> void:
	var base: Color = _livery("base")
	var suit: Color = _livery("b")
	var tube := TexGen.flat_material(Color(0.6, 0.6, 0.63), 0.4)
	var dark := TexGen.flat_material(Color(0.06, 0.06, 0.08), 0.7)
	var suit_mat := TexGen.flat_material(suit, 0.8)
	var wl := Cars.wheels(spec)
	var zf: float = wl["zf"]
	var zr: float = wl["zr"]
	var x: float = wl["x"]
	var y := -0.6
	for s in [-1.0, 1.0]:
		_rod(self, Vector3(s * 0.26, y, zf - 0.2), Vector3(s * 0.3, y, zr + 0.12), 0.04, tube)
		_rod(self, Vector3(s * 0.26, y, zf), Vector3(s * (x - 0.07), _hub_y(wl["rf"]), zf), 0.035, tube)
	_rod(self, Vector3(-x + 0.1, _hub_y(wl["rr"]), zr), Vector3(x - 0.1, _hub_y(wl["rr"]), zr), 0.045, tube)
	_box(self, Vector3(0.6, 0.03, 1.0), Vector3(0, -0.63, -0.08), dark)

	# bodywork
	_add_part("nose", "front", 0.3, Vector3(0, -0.56, zf - 0.33), Vector3(1.0, 0.15, 0.3), base, Vector3i(4, 1, 1))
	var board := _box(self, Vector3(0.36, 0.26, 0.03), Vector3(0, -0.45, zf - 0.06), TexGen.flat_material(base, 0.5))
	board.rotation.x = 0.45
	var tilt := Basis(Vector3.RIGHT, 0.45)
	_decal(TexGen.pixel_text(spec["number"], Color(0.05, 0.05, 0.07), Color(0.97, 0.97, 0.95), Color(0.05, 0.05, 0.07)),
		Vector2(-1, 0.17), board.position + tilt * Vector3(0, 0, -0.02), tilt * FACE_FRONT)
	for s in [-1.0, 1.0]:
		var pod := _add_part("pod_l" if s < 0 else "pod_r", "left" if s < 0 else "right", 0.4,
			Vector3(s * 0.5, -0.57, -0.1), Vector3(0.2, 0.15, 0.5), _livery("a"), Vector3i(1, 1, 2))
		var sp: Array = spec["sponsor"]
		_decal(TexGen.pixel_text(sp[0], sp[1], sp[2]), Vector2(0.4, -1), Vector3(s * 0.102, 0, 0),
			FACE_RIGHT if s > 0 else FACE_LEFT, false, pod)
	_add_part("bumper_r", "rear", 0.35, Vector3(0, -0.56, zr + 0.3), Vector3(1.15, 0.08, 0.08), spec["trim"],
		Vector3i(4, 1, 1))

	# seat, engine, steering
	_box(self, Vector3(0.4, 0.06, 0.36), Vector3(0, -0.58, 0.12), dark)
	var back := _box(self, Vector3(0.4, 0.42, 0.06), Vector3(0, -0.4, 0.32), dark)
	back.rotation.x = 0.35
	var metal := TexGen.flat_material(Color(0.35, 0.35, 0.38), 0.4)
	_box(self, Vector3(0.2, 0.24, 0.26), Vector3(0.43, -0.48, 0.3), metal)
	_box(self, Vector3(0.24, 0.06, 0.2), Vector3(0.43, -0.34, 0.3), dark)
	_rod(self, Vector3(0.43, -0.42, 0.42), Vector3(0.3, -0.45, 0.72), 0.05, metal)
	_box(self, Vector3(0.12, 0.12, 0.3), Vector3(0.3, -0.45, 0.82), metal)
	_rod(self, Vector3(0, -0.57, -0.55), Vector3(0, -0.36, -0.29), 0.035, dark)
	_steering = Node3D.new()
	_steering.position = Vector3(0, -0.35, -0.28)
	_steering.rotation.x = -0.65
	add_child(_steering)
	var rim := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.13
	cm.bottom_radius = 0.13
	cm.height = 0.025
	cm.radial_segments = 8
	cm.rings = 1
	rim.mesh = cm
	rim.material_override = dark
	rim.rotation.x = PI * 0.5
	_steering.add_child(rim)
	_box(_steering, Vector3(0.24, 0.035, 0.03), Vector3(0, 0, 0.02), TexGen.flat_material(base, 0.5))

	# driver
	var torso := _box(self, Vector3(0.38, 0.42, 0.22), Vector3(0, -0.3, 0.22), suit_mat)
	torso.rotation.x = 0.3
	_box(self, Vector3(0.39, 0.06, 0.23), Vector3(0, -0.36, 0.2), TexGen.flat_material(Color(0.97, 0.97, 0.95), 0.8)).rotation.x = 0.3
	for s in [-1.0, 1.0]:
		_rod(self, Vector3(s * 0.1, -0.53, 0.08), Vector3(s * 0.1, -0.55, -0.48), 0.12, suit_mat)
		_box(self, Vector3(0.1, 0.12, 0.08), Vector3(s * 0.1, -0.53, -0.53), dark)
		_rod(self, Vector3(s * 0.2, -0.14, 0.18), Vector3(s * 0.12, -0.33, -0.26), 0.09, suit_mat)
	_helmet(Vector3(0, 0.02, 0.27), spec.get("helmet", base), 0.15)


## F1 single-seater: the lofted shell is the tub; this adds the cockpit and
## driver, side pods, wings, suspension arms and the airbox.
func _build_f1() -> void:
	var base: Color = _livery("base")
	var a: Color = _livery("a")
	var dark := TexGen.flat_material(Color(0.06, 0.06, 0.08), 0.7)
	var base_mat := TexGen.flat_material(base, 0.4)
	var a_mat := TexGen.flat_material(a, 0.4)
	var wl := Cars.wheels(spec)
	var black := Color(0.05, 0.05, 0.07)
	var white := Color(0.97, 0.97, 0.95)

	# cockpit opening, driver, airbox intake
	var cz := -0.3
	var top := _heights(cz)[5]
	_box(self, Vector3(0.4, 0.03, 0.66), Vector3(0, top + 0.005, cz), dark)
	_helmet(Vector3(0, top + 0.09, cz + 0.14), spec.get("helmet", base), 0.15)
	_box(self, Vector3(0.18, 0.12, 0.05), Vector3(0, 0.22, 0.15), dark)

	# side pods with radiator intakes and the sponsor
	var sp: Array = spec["sponsor"]
	for s in [-1.0, 1.0]:
		var pod := _add_part("pod_l" if s < 0 else "pod_r", "left" if s < 0 else "right", 0.45,
			Vector3(s * 0.56, -0.44, 0.35), Vector3(0.4, 0.3, 1.3), base, Vector3i(1, 1, 3))
		_box(pod, Vector3(0.32, 0.2, 0.02), Vector3(0, 0.0, -0.655), dark)
		_box(pod, Vector3(0.41, 0.06, 1.31), Vector3(0, -0.1, 0), a_mat)
		var face := FACE_RIGHT if s > 0 else FACE_LEFT
		_decal(TexGen.pixel_text(sp[0], sp[1], sp[2]), Vector2(0.7, -1), Vector3(s * 0.206, 0.05, 0.05), face, false, pod)
		# race number on the engine cover
		var nz := 0.5
		_decal(TexGen.pixel_text(spec["number"], black, white, black), Vector2(-1, 0.2),
			Vector3(s * (_half_width(nz) + 0.01), 0.14, nz), face)
		_add_part("mirror_l" if s < 0 else "mirror_r", "left" if s < 0 else "right", 0.2,
			Vector3(s * 0.36, top + 0.1, -0.62), Vector3(0.12, 0.07, 0.06), base, Vector3i(1, 1, 1))

	# front wing hung under the nose
	var fw := _add_part("front_wing", "front", 0.3, Vector3(0, -0.6, -2.38), Vector3(1.9, 0.035, 0.32), a,
		Vector3i(6, 1, 1))
	for s in [-1.0, 1.0]:
		_box(fw, Vector3(0.03, 0.2, 0.42), Vector3(s * 0.95, 0.07, 0.02), base_mat)
		var flap := _box(fw, Vector3(0.66, 0.03, 0.14), Vector3(s * 0.58, 0.07, 0.12), a_mat)
		flap.rotation.x = 0.35
		_box(fw, Vector3(0.03, 0.2, 0.12), Vector3(s * 0.1, 0.1, 0.0), dark)
	# nose number
	var nz := -1.95
	var fwd := Vector3(0, _profile(nz - 0.2).x - _profile(nz + 0.2).x, -0.4).normalized()
	var normal := Vector3.RIGHT.cross(fwd)
	_decal(TexGen.pixel_text(spec["number"], black, white, black), Vector2(0.2, -1),
		Vector3(0, _heights(nz)[5] + 0.015, nz) + normal * 0.01, Basis(Vector3.RIGHT, fwd, normal))

	# rear wing on its end plates
	var rw := _add_part("rear_wing", "rear", 0.5, Vector3(0, 0.12, 1.98), Vector3(1.0, 0.04, 0.32), a,
		Vector3i(4, 1, 1))
	var lower := _box(rw, Vector3(1.0, 0.03, 0.2), Vector3(0, -0.15, 0.08), a_mat)
	lower.rotation.x = -0.3
	_box(rw, Vector3(0.05, 0.42, 0.12), Vector3(0, -0.25, 0.04), dark)
	for s in [-1.0, 1.0]:
		_box(rw, Vector3(0.03, 0.62, 0.55), Vector3(s * 0.51, -0.17, 0.02), base_mat)
		_decal(TexGen.pixel_text(sp[0], sp[1], sp[2]), Vector2(0.48, -1), Vector3(s * 0.53, -0.05, 0.02),
			FACE_RIGHT if s > 0 else FACE_LEFT, false, rw)
	_box(self, Vector3(0.12, 0.06, 0.02), Vector3(0, -0.42, 2.065), TexGen.flat_material(Color(1.0, 0.15, 0.1), 0.3, true))

	# wishbones from the tub to each hub
	var x: float = wl["x"]
	for axle in [[wl["zf"], wl["rf"], wl["wf"]], [wl["zr"], wl["rr"], wl["wr"]]]:
		var z: float = axle[0]
		var hy := _hub_y(axle[1])
		var hx: float = x - (axle[2] as float) * 0.5
		for s in [-1.0, 1.0]:
			var hub := Vector3(s * hx, hy, z)
			var inner: float = _half_width(z) * 0.9 * s
			_rod(self, hub + Vector3(0, 0.08, 0), Vector3(inner, hy + 0.12, z - 0.15), 0.03, dark)
			_rod(self, hub + Vector3(0, 0.08, 0), Vector3(inner, hy + 0.12, z + 0.15), 0.03, dark)
			_rod(self, hub - Vector3(0, 0.06, 0), Vector3(inner, hy - 0.04, z - 0.15), 0.03, dark)
			_rod(self, hub - Vector3(0, 0.06, 0), Vector3(inner, hy - 0.04, z + 0.15), 0.03, dark)


# --------------------------------------------------------------------------- tank

const TRACK_X := 0.82  # centre of each track, under the hull sides
const TRACK_W := 0.46
## Side profile of a track loop (z, y), wound round the idler and sprocket.
const TRACK_LOOP := [Vector2(-1.6, -0.71), Vector2(1.6, -0.71), Vector2(1.98, -0.46), Vector2(1.86, -0.24),
	Vector2(-1.86, -0.24), Vector2(-2.06, -0.44)]
const LINK := 0.22  # track link length in metres (one texture repeat)


## Hull is the lofted shell; this adds tracks, road wheels, turret and gun.
func _build_tank() -> void:
	var base: Color = _livery("base")
	var dark := TexGen.flat_material(Color(0.08, 0.08, 0.08), 0.9)
	_track_mat = TexGen.material(TexGen.track_links(), 0.95)
	var wheel_mat := TexGen.flat_material(base.darkened(0.15), 0.7)
	var hub_mat := TexGen.flat_material(Color(0.12, 0.12, 0.1), 0.6)
	_road_wheels.clear()
	for s in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = _track_mesh(s * TRACK_X, dark)
		add_child(mi)
		# road wheels on the outside of the track, plus drive sprocket and idler
		var xs: float = s * (TRACK_X + TRACK_W * 0.5 + 0.04)
		var spots := [[-1.95, -0.44, 0.17], [1.86, -0.44, 0.19]]
		for k in 5:
			spots.append([lerpf(-1.35, 1.35, k / 4.0), -0.5, 0.21])
		for sp in spots:
			var wheel := Node3D.new()
			wheel.position = Vector3(xs, sp[1], sp[0])
			add_child(wheel)
			for part in [[sp[2], 0.1, wheel_mat], [(sp[2] as float) * 0.45, 0.13, hub_mat]]:
				var w := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = part[0]
				cm.bottom_radius = part[0]
				cm.height = part[1]
				cm.radial_segments = 8
				cm.rings = 1
				w.mesh = cm
				w.material_override = part[2]
				w.rotation.z = PI * 0.5
				wheel.add_child(w)
			_road_wheels.append(wheel)

	# turret: tapered box that dents like the hull, on a ring that can swivel
	_turret = Node3D.new()
	_turret.name = "Turret"
	_turret.position = Vector3(0, 0.5, 0.15)
	add_child(_turret)
	var verts := _box_soup(Vector3(1.3, 0.44, 1.7), Vector3i(3, 1, 4))
	for i in verts.size():
		var v := verts[i]
		if v.y > 0.0:
			v.x *= 0.78
			v.z = v.z * 0.8 + 0.08
		if v.z < -0.5:
			v.x *= 0.85  # pointed front
		verts[i] = v
	var colors := PackedColorArray()
	var flat: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.1]  # heights that read as "no glass"
	for i in range(0, verts.size(), 3):
		var c := (verts[i] + verts[i + 1] + verts[i + 2]) / 3.0
		var col := _paint(5, c + _turret.position, Vector3.UP, flat)
		colors.append_array([col, col, col])
	_add_deformable(_turret, verts, colors, Vector3.ZERO)
	_box(_turret, Vector3(0.5, 0.34, 0.24), Vector3(0, 0.0, -0.78), TexGen.flat_material(base.darkened(0.2), 0.7))
	var cupola := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.22
	cy.bottom_radius = 0.26
	cy.height = 0.16
	cy.radial_segments = 8
	cupola.mesh = cy
	cupola.material_override = TexGen.flat_material(base, 0.7)
	cupola.position = Vector3(0.28, 0.3, 0.35)
	_turret.add_child(cupola)
	_add_part("gun", "front", 0.6, Vector3(0, 0.02, -1.85), Vector3(0.14, 0.14, 2.1), base.darkened(0.25),
		Vector3i(1, 1, 6), _turret)
	_box(_turret.get_node("gun"), Vector3(0.22, 0.22, 0.3), Vector3(0, 0, -1.0), TexGen.flat_material(base.darkened(0.35)))
	for s in [-1.0, 1.0]:
		var num := Label3D.new()
		num.text = spec["number"]
		num.font_size = 72
		num.outline_size = 10
		num.modulate = Color(0.95, 0.95, 0.9)
		num.outline_modulate = Color(0.1, 0.1, 0.08)
		num.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		num.rotation.y = PI * 0.5 * s
		num.position = Vector3(s * 0.67, -0.08, 0.2)
		_turret.add_child(num)

	# bolt-ons that can be knocked off
	_add_part("stowage", "rear", 0.35, Vector3(0, 0.2, 2.0), Vector3(1.3, 0.3, 0.28), Color(0.3, 0.26, 0.18),
		Vector3i(3, 1, 1))
	for s in [-1.0, 1.0]:
		_add_part("fender_l" if s < 0 else "fender_r", "left" if s < 0 else "right", 0.45,
			Vector3(s * 0.88, -0.18, -1.95), Vector3(0.5, 0.05, 0.5), base, Vector3i(1, 1, 1))
		_lamp(self, 0.07, Vector3(s * 0.62, 0.12, -1.86), Color(1.0, 0.95, 0.75))
	var ex := MeshInstance3D.new()
	var em := CylinderMesh.new()
	em.top_radius = 0.08
	em.bottom_radius = 0.08
	em.height = 0.3
	em.radial_segments = 6
	ex.mesh = em
	ex.material_override = dark
	ex.rotation.x = PI * 0.5
	ex.position = Vector3(-0.6, 0.12, 2.2)
	add_child(ex)


## One track: the loop profile extruded across the track width. Links run
## along u, so scrolling the material's UV offset moves them round the loop.
func _track_mesh(cx: float, side_mat: Material) -> ArrayMesh:
	var x0 := cx - TRACK_W * 0.5
	var x1 := cx + TRACK_W * 0.5
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := TRACK_LOOP.size()
	var centre := Vector2.ZERO
	for p in TRACK_LOOP:
		centre += p / n
	var u := 0.0
	for i in n:
		var a: Vector2 = TRACK_LOOP[i]
		var b: Vector2 = TRACK_LOOP[(i + 1) % n]
		var u1 := u + a.distance_to(b) / LINK
		var mid := (a + b) * 0.5 - centre
		var out := Vector3(0, mid.y, mid.x).normalized()
		_tri_uv(st, [Vector3(x0, a.y, a.x), Vector3(x1, a.y, a.x), Vector3(x1, b.y, b.x)],
			[Vector2(u, 0), Vector2(u, 1), Vector2(u1, 1)], out)
		_tri_uv(st, [Vector3(x0, a.y, a.x), Vector3(x1, b.y, b.x), Vector3(x0, b.y, b.x)],
			[Vector2(u, 0), Vector2(u1, 1), Vector2(u1, 0)], out)
		u = u1
	st.set_material(_track_mat)
	st.commit(mesh)
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in [x0, x1]:
		var nrm := Vector3(signf(x - cx), 0, 0)
		var c3 := Vector3(x, centre.y, centre.x)
		for i in n:
			var a: Vector2 = TRACK_LOOP[i]
			var b: Vector2 = TRACK_LOOP[(i + 1) % n]
			_tri_uv(st, [c3, Vector3(x, a.y, a.x), Vector3(x, b.y, b.x)], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], nrm)
	st.set_material(side_mat)
	st.commit(mesh)
	return mesh


## Adds a triangle wound so its front face points along `n`.
func _tri_uv(st: SurfaceTool, v: Array, uv: Array, n: Vector3) -> void:
	var order := [0, 1, 2]
	var cr := (v[1] - v[0] as Vector3).cross(v[2] - v[0])
	if cr.dot(n) * winding() < 0.0:
		order = [0, 2, 1]
	for k in order:
		st.set_normal(n)
		st.set_uv(uv[k])
		st.add_vertex(v[k])


## Per-frame animation: the driver looks into the corner and turns the wheel
## (kart, F1); the tank's tracks and road wheels roll with the ground speed and
## the turret leans into the steering.
func animate(delta: float, forward_speed: float, steer: float) -> void:
	if _head:
		_head.rotation.y = lerpf(_head.rotation.y, -steer * 0.45, clampf(delta * 6.0, 0.0, 1.0))
	if _steering:
		_steering.rotation.z = -steer * 1.4
	if not is_tank() or _turret == null:
		return
	_track_mat.uv1_offset.x = fmod(_track_mat.uv1_offset.x - forward_speed * delta / LINK, 1.0)
	for w in _road_wheels:
		w.rotation.x -= forward_speed * delta / 0.21
	_turret.rotation.y = lerpf(_turret.rotation.y, -steer * 0.35, clampf(delta * 3.0, 0.0, 1.0))
