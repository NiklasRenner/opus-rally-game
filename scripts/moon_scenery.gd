class_name MoonScenery
extends RefCounted
## Dresses the Moon stage: boulders strewn over the plain (one MultiMesh per
## rock shape), and the lunar base along the map's "base" ranges: pressure
## domes, habitat modules joined by tunnels, landers on their pads, dish
## antennas, solar arrays, a parked rover and comms masts with blinking
## beacons. Built by TrackBuilder in place of the trees.

var track: TrackBuilder
var _rng := RandomNumberGenerator.new()
var _bodies: StaticBody3D
var _white: StandardMaterial3D
var _grey: StandardMaterial3D
var _dark: StandardMaterial3D
var _foil: StandardMaterial3D
var _glass: StandardMaterial3D
var _panel: StandardMaterial3D
var _beacon: StandardMaterial3D


func _init(t: TrackBuilder) -> void:
	track = t
	_rng.seed = int(t.map["seed"]) + 31


func build() -> void:
	_bodies = StaticBody3D.new()
	_bodies.name = "MoonBase"
	_bodies.set_meta("surface", "regolith")
	track.add_child(_bodies)
	_white = TexGen.material(_hull_tex(), 0.6, Color(0.96, 0.96, 0.94))
	_grey = TexGen.flat_material(Color(0.55, 0.56, 0.58), 0.6)
	_dark = TexGen.flat_material(Color(0.12, 0.12, 0.14), 0.5)
	_foil = TexGen.material(_foil_tex(), 0.35)
	_foil.metallic = 0.6
	_glass = TexGen.flat_material(Color(1.0, 0.86, 0.45), 0.5, true)
	_panel = TexGen.material(_solar_tex(), 0.3)
	_panel.metallic_specular = 0.9
	_beacon = TexGen.flat_material(Color(1.0, 0.15, 0.1), 0.5, true)
	_rocks()
	var ranges: Array = track.map.get("base", [])
	for r in ranges:
		_base(r[0], r[1])
	var blink := Blinker.new()
	blink.mat = _beacon
	track.add_child(blink)


# --------------------------------------------------------------------------- rocks

## Boulders and stones over the whole plain: big ones solid, the small ones
## just scenery. They keep off the road and out of the base.
func _rocks() -> void:
	var shapes: Array[ArrayMesh] = []
	for v in 5:
		shapes.append(_rock_mesh(v))
	var n := track.count()
	var col := SphereShape3D.new()
	col.radius = 1.0
	var target := int(900 * (track.map["forest"] as float))
	var placed := 0
	var tries := 0
	while placed < target and tries < target * 8:
		tries += 1
		var i := _rng.randi_range(0, n - 1)
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var off := _rng.randf_range(7.0, 160.0) * (1.0 if _rng.randf() < 0.6 else 2.2)
		var p := track.points[i] + track._side(i) * side * (track.widths[i] * 0.5 + off)
		p += Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6))
		var clear := track.widths[i] * 0.5 + TrackBuilder.VERGE + 2.0
		if track._road_dist(p.x, p.z) < clear or track._near_start(p) or _in_base(i):
			continue
		if track.distance_to_road(p, track.nearest_index(p, i)) < clear:
			continue
		var size := _rng.randf_range(0.3, 1.2) if _rng.randf() < 0.8 else _rng.randf_range(1.6, 4.0)
		p.y = track.terrain_height(p.x, p.z) - size * 0.25
		var mi := MeshInstance3D.new()
		mi.mesh = shapes[_rng.randi() % shapes.size()]
		mi.transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).rotated(Vector3.RIGHT, _rng.randf_range(-0.3, 0.3))
			.scaled(Vector3(size, size * _rng.randf_range(0.55, 0.9), size)), p)
		track._scatter_add(mi)
		if size > 1.4 and off < 60.0:
			var cs := CollisionShape3D.new()
			cs.shape = col
			cs.transform = Transform3D(Basis().scaled(Vector3.ONE * size * 0.7), p + Vector3(0, size * 0.2, 0))
			_bodies.add_child(cs)
		placed += 1
	track._scatter_flush(_bodies)


## A faceted boulder: a squashed, jittered ball with flat-shaded grey faces,
## lighter on top where the sun catches it.
func _rock_mesh(variant: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = 400 + variant
	var rings := 4
	var segs := 7
	var pts: Array = []
	for ring in rings + 1:
		var lat := PI * (float(ring) / rings - 0.5)
		var row: Array = []
		for s in segs:
			var lon := TAU * s / segs
			var j := r.randf_range(0.75, 1.2) if ring > 0 and ring < rings else 1.0
			row.append(Vector3(cos(lat) * cos(lon) * j, sin(lat) * (0.7 if ring > 0 else 1.0), cos(lat) * sin(lon) * j))
		pts.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := Color(0.46, 0.46, 0.46).lerp(Color(0.36, 0.35, 0.34), r.randf())
	for ring in rings:
		for s in segs:
			var a: Vector3 = pts[ring][s]
			var b: Vector3 = pts[ring][(s + 1) % segs]
			var c: Vector3 = pts[ring + 1][s]
			var d: Vector3 = pts[ring + 1][(s + 1) % segs]
			for tri in [[a, c, b], [b, c, d]]:
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				var nrm := (p1 - p0).cross(p2 - p0).normalized()
				if nrm.dot(p0 + p1 + p2) < 0.0:
					nrm = -nrm  # facing out from the middle
				var shade := base * (0.75 + 0.35 * clampf(nrm.y, 0.0, 1.0)) * r.randf_range(0.92, 1.08)
				st.set_color(Color(shade.r, shade.g, shade.b))
				track._tri_uv(st, tri, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], nrm)
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	mesh.surface_set_material(0, m)
	return mesh


func _in_base(i: int) -> bool:
	var f := float(i) / track.count()
	for r in track.map.get("base", []):
		if f > (r[0] as float) - 0.01 and f < (r[1] as float) + 0.01:
			return true
	return false


# --------------------------------------------------------------------------- the base

## Lines a stretch of the route with base buildings, alternating sides and
## kinds so it reads as one settlement.
func _base(from: float, to: float) -> void:
	var n := track.count()
	var i := int(n * from)
	var kinds := ["dome", "habitat", "lander", "dish", "solar", "dome", "rover", "mast", "habitat", "solar"]
	var k := _rng.randi() % kinds.size()
	while i < int(n * to):
		for s: float in [-1.0, 1.0]:
			if _rng.randf() < 0.25:
				continue
			var kind: String = kinds[k % kinds.size()]
			k += 1
			var reach: float = {"dome": 9.0, "habitat": 6.0, "lander": 9.0, "dish": 5.0, "solar": 7.0, "rover": 3.0,
				"mast": 2.0}[kind]
			var off := track.widths[i] * 0.5 + TrackBuilder.VERGE + 5.0 + reach + _rng.randf_range(0.0, 6.0)
			var pos: Vector3 = track.points[i] + track._side(i) * s * off
			if track._road_dist(pos.x, pos.z) < off - 1.5 or track._near_start(pos):
				continue
			pos.y = track.terrain_height(pos.x, pos.z)
			var xf := Transform3D(track.frame(i).basis, pos)
			match kind:
				"dome": _dome(xf, _rng.randf_range(6.0, 9.0), s)
				"habitat": _habitat(xf, s)
				"lander": _lander(xf)
				"dish": _dish(xf, s)
				"solar": _solar(xf)
				"rover": _rover(xf.rotated_local(Vector3.UP, _rng.randf_range(-0.8, 0.8)))
				"mast": _mast(xf)
		i += _rng.randi_range(7, 11)


func _dome(xf: Transform3D, r: float, s: float) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r
	sphere.is_hemisphere = true
	sphere.radial_segments = 12
	sphere.rings = 4
	_mesh(sphere, _white, xf.translated_local(Vector3(0, -0.2, 0)))
	var ring := CylinderMesh.new()
	ring.top_radius = r + 0.3
	ring.bottom_radius = r + 0.5
	ring.height = 0.8
	ring.radial_segments = 12
	_mesh(ring, _grey, xf.translated_local(Vector3(0, 0.0, 0)))
	# a row of lit portholes round the dome and an airlock facing the road
	for k in 8:
		var a := TAU * k / 8.0
		var p := Vector3(cos(a) * r * 0.93, r * 0.3, sin(a) * r * 0.93)
		_mesh(_box(Vector3(0.6, 0.5, 0.6)), _glass, xf.translated_local(p))
	var lock_at := Vector3(-s * (r + 1.2), 1.2, 0)
	_mesh(_box(Vector3(2.8, 2.6, 2.6)), _white, xf.translated_local(lock_at))
	_mesh(_box(Vector3(0.1, 1.8, 1.2)), _dark, xf.translated_local(lock_at + Vector3(-s * 1.42, -0.2, 0)))
	_solid(xf.translated_local(Vector3(0, r * 0.35, 0)), Vector3(r * 1.5, r * 0.8, r * 1.5))


## Two cylinder modules lying side by side, joined by a short tunnel, with a
## strip of windows and a radiator panel on the roof.
func _habitat(xf: Transform3D, s: float) -> void:
	var tube := CylinderMesh.new()
	tube.top_radius = 1.8
	tube.bottom_radius = 1.8
	tube.height = 9.0
	tube.radial_segments = 10
	tube.rings = 1
	var lie := Basis(Vector3.RIGHT, PI * 0.5)
	for m in [-1.0, 1.0]:
		var at := Vector3(s * m * 2.6, 2.0, 0)
		_mesh(tube, _white, Transform3D(xf.basis * lie, xf * at))
		for w in 4:
			_mesh(_box(Vector3(0.5, 0.4, 0.7)), _glass, xf.translated_local(at + Vector3(-s * 1.8, 0.4, -3.0 + w * 2.0)))
		for e in [-1.0, 1.0]:
			_mesh(_box(Vector3(0.4, 0.4, 0.4)), _grey, xf.translated_local(at + Vector3(0, -1.8, e * 3.6)))
	_mesh(_box(Vector3(5.2, 1.4, 1.6)), _grey, xf.translated_local(Vector3(0, 2.0, 0)))
	_mesh(_box(Vector3(3.0, 0.1, 6.0)), _panel, xf.translated_local(Vector3(s * 2.6, 4.2, 0)))
	_solid(xf.translated_local(Vector3(0, 2.0, 0)), Vector3(9.0, 4.0, 9.0))


## A lander on a marked pad: gold-foil descent stage on four splayed legs,
## the grey ascent stage on top.
func _lander(xf: Transform3D) -> void:
	var pad := CylinderMesh.new()
	pad.top_radius = 8.0
	pad.bottom_radius = 8.4
	pad.height = 0.3
	pad.radial_segments = 16
	_mesh(pad, TexGen.material(_pad_tex(), 0.9), xf.translated_local(Vector3(0, 0.05, 0)))
	var body := xf.translated_local(Vector3(0, 0, 0)).rotated_local(Vector3.UP, _rng.randf() * TAU)
	_mesh(_box(Vector3(3.6, 2.0, 3.6)), _foil, body.translated_local(Vector3(0, 2.6, 0)))
	var top := CylinderMesh.new()
	top.top_radius = 1.3
	top.bottom_radius = 1.8
	top.height = 2.2
	top.radial_segments = 6
	_mesh(top, _grey, body.translated_local(Vector3(0, 4.7, 0)))
	_mesh(_box(Vector3(0.7, 0.6, 0.1)), _dark, body.translated_local(Vector3(0, 4.9, 1.6)))
	_mesh(_box(Vector3(0.1, 1.6, 0.1)), _grey, body.translated_local(Vector3(0.6, 6.4, 0)))
	for k in 4:
		var a := TAU * k / 4.0 + PI * 0.25
		var foot := Vector3(cos(a) * 3.4, 0.25, sin(a) * 3.4)
		var hip := Vector3(cos(a) * 1.6, 2.4, sin(a) * 1.6)
		var leg := CylinderMesh.new()
		leg.top_radius = 0.1
		leg.bottom_radius = 0.1
		leg.height = foot.distance_to(hip)
		leg.radial_segments = 5
		var up := (hip - foot).normalized()
		var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
		var bas := Basis(side, up, side.cross(up))  # the cylinder runs along its y
		_mesh(leg, _grey, body * Transform3D(bas, (foot + hip) * 0.5))
		var disc := CylinderMesh.new()
		disc.top_radius = 0.5
		disc.bottom_radius = 0.5
		disc.height = 0.1
		disc.radial_segments = 8
		_mesh(disc, _grey, body.translated_local(foot))
	_solid(xf.translated_local(Vector3(0, 3.0, 0)), Vector3(5.5, 6.0, 5.5))


func _dish(xf: Transform3D, s: float) -> void:
	_mesh(_box(Vector3(0.6, 4.0, 0.6)), _grey, xf.translated_local(Vector3(0, 2.0, 0)))
	var dish := CylinderMesh.new()
	dish.top_radius = 3.6
	dish.bottom_radius = 0.6
	dish.height = 1.0
	dish.radial_segments = 14
	dish.rings = 1
	# aimed up at the Earth
	var aim := Basis(Vector3.RIGHT, -0.6).rotated(Vector3.UP, -s * 0.8)
	_mesh(dish, _white, Transform3D(xf.basis * aim, xf * Vector3(0, 4.6, 0)))
	_mesh(_box(Vector3(0.15, 2.2, 0.15)), _grey, Transform3D(xf.basis * aim, xf * Vector3(0, 4.6, 0)).translated_local(Vector3(0, 1.4, 0)))
	_mesh(_box(Vector3(1.6, 1.0, 1.6)), _grey, xf.translated_local(Vector3(0, 0.5, 0)))
	_solid(xf.translated_local(Vector3(0, 2.0, 0)), Vector3(1.6, 4.0, 1.6))


## A row of solar panels on posts, tilted to the low sun.
func _solar(xf: Transform3D) -> void:
	for k in 3:
		var at := Vector3(0, 0, (k - 1) * 4.6)
		_mesh(_box(Vector3(0.2, 1.6, 0.2)), _grey, xf.translated_local(at + Vector3(0, 0.8, 0)))
		var tilt := Transform3D(xf.basis * Basis(Vector3.FORWARD, 0.55), xf * (at + Vector3(0, 1.8, 0)))
		_mesh(_box(Vector3(4.2, 0.08, 4.2)), _panel, tilt)
	_solid(xf.translated_local(Vector3(0, 1.2, 0)), Vector3(3.6, 2.4, 13.6))


## A little open rover parked by the road: chassis, four wire wheels, seats,
## a high-gain antenna on a pole.
func _rover(xf: Transform3D) -> void:
	_mesh(_box(Vector3(1.9, 0.25, 3.0)), _grey, xf.translated_local(Vector3(0, 0.8, 0)))
	_mesh(_box(Vector3(1.6, 0.5, 0.5)), _foil, xf.translated_local(Vector3(0, 1.2, 1.1)))
	for sx in [-0.45, 0.45]:
		_mesh(_box(Vector3(0.6, 0.6, 0.12)), _dark, xf.translated_local(Vector3(sx, 1.2, -0.1)))
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.42
	wheel.bottom_radius = 0.42
	wheel.height = 0.3
	wheel.radial_segments = 8
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_mesh(wheel, _dark, Transform3D(xf.basis * Basis(Vector3.FORWARD, PI * 0.5), xf * Vector3(sx * 1.05, 0.42, sz * 1.1)))
	_mesh(_box(Vector3(0.06, 1.4, 0.06)), _grey, xf.translated_local(Vector3(0.6, 1.6, 1.3)))
	var dish := CylinderMesh.new()
	dish.top_radius = 0.5
	dish.bottom_radius = 0.05
	dish.height = 0.2
	dish.radial_segments = 8
	_mesh(dish, _white, xf.translated_local(Vector3(0.6, 2.35, 1.3)))
	_solid(xf.translated_local(Vector3(0, 0.8, 0)), Vector3(2.2, 1.6, 3.2))


## A comms mast: a lattice tower of stacked boxes with a beacon on top.
func _mast(xf: Transform3D) -> void:
	var h := _rng.randf_range(14.0, 22.0)
	for k in int(h / 2.0):
		_mesh(_box(Vector3(0.9 - k * 0.03, 1.9, 0.9 - k * 0.03)), _grey if k % 2 == 0 else _white,
			xf.translated_local(Vector3(0, 1.0 + k * 2.0, 0)))
	_mesh(_box(Vector3(0.5, 0.5, 0.5)), _beacon, xf.translated_local(Vector3(0, h + 0.4, 0)))
	_solid(xf.translated_local(Vector3(0, h * 0.5, 0)), Vector3(1.0, h, 1.0))


# --------------------------------------------------------------------------- helpers

func _mesh(mesh: Mesh, mat: Material, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	_bodies.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = size
	return bm


func _solid(xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = xf
	_bodies.add_child(cs)


## White hull plating with panel seams and a few rivets.
static func _hull_tex() -> ImageTexture:
	return TexGen.cached("moon_hull", func() -> ImageTexture:
		var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
		img.fill(Color(0.92, 0.92, 0.90))
		for k in 32:
			img.set_pixel(k, 0, Color(0.66, 0.66, 0.66))
			img.set_pixel(k, 16, Color(0.72, 0.72, 0.72))
			img.set_pixel(0, k, Color(0.66, 0.66, 0.66))
			img.set_pixel(16, (k + 8) % 32, Color(0.74, 0.74, 0.74))
		for p in [Vector2i(3, 3), Vector2i(12, 3), Vector2i(3, 12), Vector2i(20, 19), Vector2i(28, 28)]:
			img.set_pixel(p.x, p.y, Color(0.6, 0.6, 0.62))
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img))


## Crinkled gold foil.
static func _foil_tex() -> ImageTexture:
	return TexGen.cached("moon_foil", func() -> ImageTexture:
		var r := RandomNumberGenerator.new()
		r.seed = 11
		var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
		for y in 32:
			for x in 32:
				var c := Color(0.86, 0.66, 0.24) * r.randf_range(0.7, 1.15)
				if (x + y * 2 + r.randi_range(0, 2)) % 7 == 0:
					c = Color(1.0, 0.92, 0.6)
				img.set_pixel(x, y, Color(c.r, c.g, c.b))
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img))


## Blue solar cells in a silver frame.
static func _solar_tex() -> ImageTexture:
	return TexGen.cached("moon_solar", func() -> ImageTexture:
		var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
		for y in 32:
			for x in 32:
				var c := Color(0.08, 0.14, 0.38) if (x % 8 != 0 and y % 8 != 0) else Color(0.7, 0.72, 0.76)
				if x % 8 == 3 and y % 8 == 2:
					c = Color(0.25, 0.35, 0.65)  # glint
				img.set_pixel(x, y, c)
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img))


## Landing pad: grey concrete with a yellow ring and an H.
static func _pad_tex() -> ImageTexture:
	return TexGen.cached("moon_pad", func() -> ImageTexture:
		var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
		var yel := Color(0.95, 0.75, 0.1)
		for y in 32:
			for x in 32:
				var d := Vector2(x - 15.5, y - 15.5).length()
				var c := Color(0.42, 0.42, 0.42)
				if d > 12.0 and d < 14.0:
					c = yel
				if (x in [10, 11, 20, 21] and y > 8 and y < 23) or (y in [15, 16] and x > 10 and x < 21):
					c = Color(0.95, 0.95, 0.92)
				img.set_pixel(x, y, c)
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img))


## Flashes the beacons on the masts.
class Blinker extends Node:
	var mat: StandardMaterial3D

	func _process(_delta: float) -> void:
		var on := fmod(Time.get_ticks_msec() / 1000.0, 1.4) < 0.25
		mat.albedo_color = Color(1.0, 0.15, 0.1) if on else Color(0.25, 0.05, 0.04)
