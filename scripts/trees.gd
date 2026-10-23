class_name Trees
extends RefCounted
## Low-poly tree meshes, built once and shared by every tree on a stage:
## pines with jagged, drooping tiers, round leafy trees made of lumpy blobs,
## bushes, and charred dead trees for the wasteland. Flat shaded with vertex
## colours (lighter on top, darker underneath) over the pixel foliage texture.
## The jungle set (palms, tall canopy trees hung with vines, ferns) is two-sided
## so thin fronds show from both sides.

const PINE_DARK := Color(0.12, 0.28, 0.13)
const PINE_LIGHT := Color(0.30, 0.52, 0.22)
const LEAF_DARK := Color(0.20, 0.36, 0.12)
const LEAF_LIGHT := Color(0.46, 0.64, 0.22)
const AUTUMN_DARK := Color(0.50, 0.24, 0.08)
const AUTUMN_LIGHT := Color(0.86, 0.56, 0.16)
const BARK := Color(0.36, 0.24, 0.14)
const CHAR := Color(0.13, 0.11, 0.10)
const JUNGLE_DARK := Color(0.07, 0.24, 0.09)
const JUNGLE_LIGHT := Color(0.28, 0.55, 0.16)
const PALM_DARK := Color(0.16, 0.36, 0.10)
const PALM_LIGHT := Color(0.50, 0.68, 0.20)
const PALM_TRUNK := Color(0.46, 0.38, 0.28)
const VINE := Color(0.14, 0.30, 0.08)

static var _cache := {}
static var _mat: StandardMaterial3D
static var _mat2: StandardMaterial3D


static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = TexGen.material(TexGen.foliage(3), 1.0)
		_mat.vertex_color_use_as_albedo = true
	return _mat


## Same look, both faces drawn (fronds, vines).
static func material_two_sided() -> StandardMaterial3D:
	if _mat2 == null:
		_mat2 = material().duplicate()
		_mat2.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat2


static func palm(variant: int) -> ArrayMesh:
	return _cached("palm%d" % variant, _make_palm.bind(variant))


static func jungle(variant: int) -> ArrayMesh:
	return _cached("jungle%d" % variant, _make_jungle.bind(variant))


static func fern(variant: int) -> ArrayMesh:
	return _cached("fern%d" % variant, _make_fern.bind(variant))


static func pine(variant: int) -> ArrayMesh:
	return _cached("pine%d" % variant, _make_pine.bind(variant))


static func leafy(variant: int) -> ArrayMesh:
	return _cached("leafy%d" % variant, _make_leafy.bind(variant))


static func bush(variant: int) -> ArrayMesh:
	return _cached("bush%d" % variant, _make_bush.bind(variant))


static func dead(variant: int) -> ArrayMesh:
	return _cached("dead%d" % variant, _make_dead.bind(variant))


static func _cached(key: String, make: Callable) -> ArrayMesh:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


# --------------------------------------------------------------------------- builders

static func _make_pine(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + variant
	var st := _begin()
	_prism(st, Vector3.ZERO, Vector3(0, 2.8, 0), 0.3, 0.18, 6, BARK)
	var tiers := 4 + variant % 2
	for t in tiers:
		var f := float(t) / tiers
		var base := 1.5 + t * 1.45
		var radius := lerpf(3.1, 1.0, f) * rng.randf_range(0.9, 1.1)
		var height := lerpf(2.8, 2.2, f)
		var tip := Vector3(rng.randf_range(-0.12, 0.12), base + height, rng.randf_range(-0.12, 0.12))
		var ring: Array[Vector3] = []
		var k := 10
		var twist := rng.randf() * TAU
		for i in k:
			var a := twist + TAU * i / k + rng.randf_range(-0.12, 0.12)
			var long := i % 2 == 0
			var r := radius * (1.0 if long else 0.7)
			ring.append(Vector3(cos(a) * r, base - (0.45 if long else 0.0) + rng.randf_range(-0.1, 0.1), sin(a) * r))
		var shade := PINE_DARK.lerp(PINE_LIGHT, 0.25 + f * 0.6)
		for i in k:
			var a := ring[i]
			var b := ring[(i + 1) % k]
			var c := shade.lightened(rng.randf_range(0.0, 0.12)) if i % 3 != 0 else shade.darkened(0.12)
			_tri(st, a, b, tip, c)
			# underside of the tier, dark
			_tri(st, b, a, Vector3(0, base + 0.5, 0), PINE_DARK.darkened(0.35), true)
	return _commit(st)


static func _make_leafy(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 200 + variant
	var st := _begin()
	var top := Vector3(rng.randf_range(-0.2, 0.2), 3.0, rng.randf_range(-0.2, 0.2))
	_prism(st, Vector3.ZERO, top, 0.32, 0.2, 6, BARK)
	for b in 3:
		var a := TAU * b / 3.0 + rng.randf()
		var end := top + Vector3(cos(a) * 1.3, 1.0, sin(a) * 1.3)
		_prism(st, top - Vector3(0, 0.5, 0), end, 0.14, 0.07, 4, BARK)
	var dark := AUTUMN_DARK if variant == 2 else LEAF_DARK
	var light := AUTUMN_LIGHT if variant == 2 else LEAF_LIGHT
	var blobs := [[Vector3(0, 4.6, 0), 2.3]]
	for b in 3 + variant % 2:
		var a := TAU * b / 3.0 + rng.randf()
		blobs.append([Vector3(cos(a) * 1.4, rng.randf_range(3.6, 5.0), sin(a) * 1.4), rng.randf_range(1.4, 1.8)])
	for blob in blobs:
		_blob(st, blob[0], blob[1], Vector3(1.0, 0.82, 1.0), dark, light, rng)
	return _commit(st)


static func _make_bush(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 300 + variant
	var st := _begin()
	_blob(st, Vector3(0, 0.45, 0), 1.0, Vector3(1.2, 0.7, 1.0), LEAF_DARK, LEAF_LIGHT, rng)
	_blob(st, Vector3(0.6, 0.35, 0.3), 0.7, Vector3(1.0, 0.8, 1.0), LEAF_DARK, LEAF_LIGHT, rng)
	return _commit(st)


static func _make_dead(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 400 + variant
	var st := _begin()
	var top := Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(4.5, 6.0), rng.randf_range(-0.4, 0.4))
	_prism(st, Vector3.ZERO, top, 0.3, 0.08, 5, CHAR)
	for b in 4 + variant % 2:
		var h := rng.randf_range(0.35, 0.8)
		var start := top * h
		var a := rng.randf() * TAU
		var end := start + Vector3(cos(a) * rng.randf_range(1.2, 2.2), rng.randf_range(0.6, 1.6), sin(a) * rng.randf_range(1.2, 2.2))
		_prism(st, start, end, 0.12 * (1.0 - h * 0.5), 0.03, 4, CHAR.lightened(rng.randf_range(0.0, 0.1)))
		if rng.randf() < 0.6:  # a fork
			var fork := end + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(0.4, 0.9), rng.randf_range(-0.8, 0.8))
			_prism(st, start.lerp(end, 0.6), fork, 0.05, 0.02, 3, CHAR)
	return _commit(st)


static func _make_palm(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 500 + variant
	var st := _begin()
	# leaning, curving trunk in segments, ringed light and dark
	var height := rng.randf_range(7.0, 10.0)
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(1.0, 2.6)
	var prev := Vector3.ZERO
	var segs := 6
	for k in range(1, segs + 1):
		var f := float(k) / segs
		var p := lean * f * f + Vector3(0, height * f, 0)
		_prism(st, prev, p, lerpf(0.28, 0.16, f - 1.0 / segs), lerpf(0.28, 0.16, f), 6,
			PALM_TRUNK if k % 2 == 0 else PALM_TRUNK.darkened(0.15))
		prev = p
	var crown := prev
	var fronds := 7 + variant % 3
	for k in fronds:
		var a := TAU * k / fronds + rng.randf_range(-0.2, 0.2)
		_frond(st, crown, a, rng.randf_range(3.2, 4.2), 0.75, rng.randf_range(0.5, 0.9), 2.2, PALM_DARK, PALM_LIGHT, rng)
	for k in 3:
		var a := TAU * k / 3.0
		_blob(st, crown + Vector3(cos(a) * 0.25, -0.3, sin(a) * 0.25), 0.18, Vector3.ONE,
			Color(0.30, 0.22, 0.10), Color(0.42, 0.34, 0.16), rng)
	return _commit(st, material_two_sided())


static func _make_jungle(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 600 + variant
	var st := _begin()
	var height := rng.randf_range(9.0, 12.0)
	var top := Vector3(rng.randf_range(-0.4, 0.4), height, rng.randf_range(-0.4, 0.4))
	_prism(st, Vector3.ZERO, top, 0.55, 0.3, 7, BARK.lightened(0.15))
	# buttress roots flaring out at the base
	for b in 4:
		var a := TAU * b / 4.0 + rng.randf() * 0.5
		var d := Vector3(cos(a), 0, sin(a))
		_side_tri(st, d * 0.3 + Vector3(0, 2.2, 0), d * 1.6 + Vector3(0, -0.1, 0), d * 0.3 + Vector3(0, -0.1, 0),
			d * 0.3 + Vector3(0, 1.0, 0) + d.cross(Vector3.UP) * 0.5, BARK.darkened(0.1))
		_side_tri(st, d * 0.3 + Vector3(0, 2.2, 0), d * 0.3 + Vector3(0, -0.1, 0), d * 1.6 + Vector3(0, -0.1, 0),
			d * 0.3 + Vector3(0, 1.0, 0) - d.cross(Vector3.UP) * 0.5, BARK.darkened(0.1))
	# wide flat canopy on a few branches
	var crowns := [top + Vector3(0, 1.2, 0)]
	for b in 3:
		var a := TAU * b / 3.0 + rng.randf()
		var end := top + Vector3(cos(a) * 2.6, rng.randf_range(0.2, 1.2), sin(a) * 2.6)
		_prism(st, top - Vector3(0, 1.5, 0), end, 0.2, 0.1, 4, BARK)
		crowns.append(end + Vector3(0, 0.6, 0))
	for c in crowns:
		_blob(st, c, rng.randf_range(2.2, 2.9), Vector3(1.0, 0.5, 1.0), JUNGLE_DARK, JUNGLE_LIGHT, rng)
	# vines hanging from under the canopy
	for v in 7 + variant % 3:
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.2, 3.4)
		var p := Vector3(cos(a) * r, top.y + rng.randf_range(-0.3, 0.6), sin(a) * r)
		var length := rng.randf_range(3.0, 7.5)
		var sway := Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
		var last := p
		for k in range(1, 5):
			var f := k / 4.0
			var q := p + Vector3(0, -length * f, 0) + sway * sin(f * PI)
			_prism(st, last, q, 0.05, 0.04, 3, VINE)
			if k < 4 and rng.randf() < 0.7:
				var leaf := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
				_side_tri(st, q, q + leaf + Vector3(0, -0.35, 0), q + leaf * 1.6 + Vector3(0, -0.1, 0), q + Vector3(0, -2, 0),
					JUNGLE_LIGHT.darkened(0.2))
			last = q
	return _commit(st, material_two_sided())


static func _make_fern(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 700 + variant
	var st := _begin()
	var fronds := 6 + variant % 3
	for k in fronds:
		var a := TAU * k / fronds + rng.randf_range(-0.25, 0.25)
		_frond(st, Vector3(0, 0.1, 0), a, rng.randf_range(1.2, 1.8), 0.32, rng.randf_range(1.2, 1.8), 2.0,
			JUNGLE_DARK, JUNGLE_LIGHT.lightened(0.1), rng)
	return _commit(st, material_two_sided())


## One drooping palm/fern frond from `base` along heading `angle`: a strip
## that rises (lift) then falls (droop), leaflets angled down in a V.
static func _frond(st: SurfaceTool, base: Vector3, angle: float, length: float, width: float, lift: float,
		droop: float, dark: Color, light: Color, rng: RandomNumberGenerator) -> void:
	var d := Vector3(cos(angle), 0, sin(angle))
	var side := Vector3(-d.z, 0, d.x)
	var segs := 5
	var prev_c := base
	var prev_l := base
	var prev_r := base
	for k in range(1, segs + 1):
		var f := float(k) / segs
		var c := base + d * length * f + Vector3(0, lift * f * length * 0.5 - droop * f * f * length * 0.5, 0)
		var w := width * sin(f * PI) * (1.0 - f * 0.3)
		var l := c - side * w + Vector3(0, -w * 0.35, 0)
		var r := c + side * w + Vector3(0, -w * 0.35, 0)
		var col := dark.lerp(light, f * 0.8 + rng.randf_range(0.0, 0.15))
		_side_tri(st, prev_c, prev_l, l, prev_c + Vector3(0, -3, 0), col)
		_side_tri(st, prev_c, l, c, prev_c + Vector3(0, -3, 0), col)
		_side_tri(st, prev_c, c, r, prev_c + Vector3(0, -3, 0), col.darkened(0.08))
		_side_tri(st, prev_c, r, prev_r, prev_c + Vector3(0, -3, 0), col.darkened(0.08))
		prev_c = c
		prev_l = l
		prev_r = r


# --------------------------------------------------------------------------- geometry helpers

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _commit(st: SurfaceTool, mat: StandardMaterial3D = null) -> ArrayMesh:
	var mesh := st.commit()
	mesh.surface_set_material(0, mat if mat else material())
	return mesh


## One flat-shaded triangle, wound so its front face points away from the
## tree's axis (or toward it when `inward` is set, e.g. undersides).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, inward := false) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		return
	n = n.normalized()
	var cen := (a + b + c) / 3.0
	var out := Vector3(cen.x, 0, cen.z)
	if inward:
		out = Vector3.DOWN
	elif out.length_squared() < 0.01:
		out = Vector3.UP
	if n.dot(out) < 0.0:
		n = -n
	var verts := [a, b, c]
	if (b - a).cross(c - a).dot(n) * CarModel.winding() < 0.0:
		verts = [a, c, b]
	for v in verts:
		st.set_normal(n)
		st.set_color(col)
		st.set_uv(Vector2(v.x + v.z, v.y) * 0.5)
		st.add_vertex(v)


## A tapered n-sided prism from p0 to p1 (trunks and branches).
static func _prism(st: SurfaceTool, p0: Vector3, p1: Vector3, r0: float, r1: float, sides: int, col: Color) -> void:
	var axis := (p1 - p0).normalized()
	var u := axis.cross(Vector3.FORWARD if absf(axis.y) > 0.9 else Vector3.UP).normalized()
	var v := axis.cross(u)
	var ring0: Array[Vector3] = []
	var ring1: Array[Vector3] = []
	for i in sides:
		var a := TAU * i / sides
		var d := u * cos(a) + v * sin(a)
		ring0.append(p0 + d * r0)
		ring1.append(p1 + d * r1)
	for i in sides:
		var j := (i + 1) % sides
		var c := col.darkened(0.15) if i % 2 == 0 else col
		_side_tri(st, ring0[i], ring0[j], ring1[j], (p0 + p1) * 0.5, c)
		_side_tri(st, ring0[i], ring1[j], ring1[i], (p0 + p1) * 0.5, c)


## Triangle facing away from `centre` (for prisms that aren't vertical).
static func _side_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, centre: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		return
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - centre) < 0.0:
		n = -n
	var verts := [a, b, c]
	if (b - a).cross(c - a).dot(n) * CarModel.winding() < 0.0:
		verts = [a, c, b]
	for p in verts:
		st.set_normal(n)
		st.set_color(col)
		st.set_uv(Vector2(p.x + p.z, p.y) * 0.5)
		st.add_vertex(p)


## Lumpy ball of foliage: a once-subdivided octahedron with jittered radius,
## coloured by how much each face points up.
static func _blob(st: SurfaceTool, centre: Vector3, radius: float, squash: Vector3, dark: Color, light: Color,
		rng: RandomNumberGenerator) -> void:
	var o := [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	var faces := [[0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2], [1, 4, 2], [1, 3, 4], [1, 5, 3], [1, 2, 5]]
	var jitter := {}
	var place := func(d: Vector3) -> Vector3:
		var key := d.snapped(Vector3.ONE * 0.01)
		if not jitter.has(key):
			jitter[key] = rng.randf_range(0.85, 1.12)
		return centre + d * radius * (jitter[key] as float) * squash
	for f in faces:
		var a: Vector3 = o[f[0]]
		var b: Vector3 = o[f[1]]
		var c: Vector3 = o[f[2]]
		var ab := (a + b).normalized()
		var bc := (b + c).normalized()
		var ca := (c + a).normalized()
		for t in [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]]:
			var p0: Vector3 = place.call(t[0])
			var p1: Vector3 = place.call(t[1])
			var p2: Vector3 = place.call(t[2])
			var up := ((t[0] + t[1] + t[2]) as Vector3).normalized().y
			var col := dark.lerp(light, clampf(up * 0.6 + 0.45, 0.0, 1.0)).lightened(rng.randf_range(0.0, 0.08))
			_side_tri(st, p0, p1, p2, centre, col)
