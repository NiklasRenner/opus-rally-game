class_name CityScenery
extends RefCounted
## Dresses the city street circuit: concrete walls with a catch fence the
## whole way round, office and apartment blocks lining the streets (one mesh
## per facade style), side streets with zebra crossings and working traffic
## lights, street lamps, trees in the pavements, fans along the walls and a
## skyline of towers in the distance. Built by TrackBuilder in place of the
## trees.

const BAY := 3.0  # metres per window bay
const STOREY := 3.2
const TILE := Vector2(BAY * 4.0, STOREY * 4.0)  # a facade texture covers 4 x 4 windows
## [wall, glass, frame width in px, window height in px]
const FACADES := [
	[Color(0.82, 0.78, 0.70), Color(0.20, 0.28, 0.36), 3, 9],  # sandstone offices
	[Color(0.62, 0.30, 0.22), Color(0.16, 0.20, 0.24), 4, 8],  # brick flats
	[Color(0.88, 0.89, 0.90), Color(0.24, 0.36, 0.46), 2, 10],  # white modern
	[Color(0.44, 0.52, 0.58), Color(0.30, 0.52, 0.62), 1, 13],  # glass tower
	[Color(0.34, 0.34, 0.37), Color(0.18, 0.22, 0.30), 2, 11],  # dark steel
	[Color(0.80, 0.66, 0.50), Color(0.22, 0.24, 0.28), 3, 8],  # ochre render
]
const SHOPS := ["CAFE", "PIZZA", "BANK", "HOTEL", "MARKET", "BOOKS", "SUSHI", "PHARMACY", "BAKERY", "CINEMA"]
const SHOP_COLORS := [Color(0.75, 0.1, 0.1), Color(0.1, 0.3, 0.7), Color(0.1, 0.5, 0.25), Color(0.85, 0.55, 0.1),
	Color(0.4, 0.15, 0.5), Color(0.1, 0.1, 0.12)]

var track: TrackBuilder
var _rng := RandomNumberGenerator.new()
var _bodies: StaticBody3D
var _junctions: Array[int] = []  # road samples with a side street, its side in _junction_side
var _junction_side: Array[float] = []
var _walls := SurfaceTool.new()
var _fence := SurfaceTool.new()
var _steel := SurfaceTool.new()  # lamp posts, light poles, fence posts: vertex coloured
var _roofs := SurfaceTool.new()
var _streets := SurfaceTool.new()
var _facades: Array[SurfaceTool] = []
var _crowd: Crowd
var _lights: Array[StandardMaterial3D] = []  # red, amber, green lamp lenses


func _init(t: TrackBuilder) -> void:
	track = t
	_rng.seed = int(t.map["seed"]) + 41


func build() -> void:
	_bodies = StaticBody3D.new()
	_bodies.name = "City"
	_bodies.set_meta("surface", "asphalt")
	track.add_child(_bodies)
	for st in [_walls, _fence, _steel, _roofs, _streets]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in FACADES.size():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_facades.append(st)
	var crowd_rng := RandomNumberGenerator.new()
	crowd_rng.seed = int(track.map["seed"]) + 43
	_crowd = Crowd.new(crowd_rng)
	for c in [Color(1.0, 0.1, 0.05), Color(1.0, 0.7, 0.05), Color(0.1, 1.0, 0.35)]:
		_lights.append(TexGen.flat_material(c, 0.5, true))
	_pick_junctions()
	_side_streets()
	_barriers()
	_buildings()
	_infill()
	_lamps_and_trees()
	_fans()
	_skyline()
	_flush()
	var cycle := LightCycle.new()
	cycle.lenses = _lights
	track.add_child(cycle)


# --------------------------------------------------------------------------- layout

func _n() -> int:
	return track.count()


func _hw(i: int) -> float:
	return track.widths[wrapi(i, 0, _n())] * 0.5


func _near_start(i: int) -> bool:
	return i < StartArea.REACH + 3 or i > _n() - StartArea.REACH - 3


## Side streets branch off the straights every so often, on the side with
## room for them.
func _pick_junctions() -> void:
	var n := _n()
	var i := StartArea.REACH + 14
	while i < n - StartArea.REACH - 14:
		if absf(track._turn(i, 6)) < 0.06:
			for s: float in ([1.0, -1.0] if _rng.randf() < 0.5 else [-1.0, 1.0]):
				if _clear(track.points[i] + track._side(i) * s * (_hw(i) + 50.0), i, _hw(i) + 40.0):
					_junctions.append(i)
					_junction_side.append(s)
					break
			if not _junctions.is_empty() and _junctions[-1] == i:
				i += _rng.randi_range(28, 40)
				continue
		i += 3


## Within `samples` of a side street on side `s`?
func _at_junction(i: int, s: float, samples: int) -> bool:
	for k in _junctions.size():
		if _junction_side[k] == s and absi(i - _junctions[k]) <= samples:
			return true
	return false


## Far enough from every part of the route?
func _clear(p: Vector3, hint: int, dist: float) -> bool:
	return track.distance_to_road(p, track.nearest_index(p, hint)) > dist


# --------------------------------------------------------------------------- streets

## A side street running off at each junction: tarmac with a centre line
## and kerbs, a zebra across the main road and traffic lights on both corners.
func _side_streets() -> void:
	for k in _junctions.size():
		var i := _junctions[k]
		var s := _junction_side[k]
		var xf := track.frame(i)
		var w := 9.0
		var from := _hw(i) + 0.2
		var to := _hw(i) + 70.0
		var y := -0.12
		var a := xf * Vector3(s * from, y, -w * 0.5)
		var b := xf * Vector3(s * to, y, -w * 0.5)
		var c := xf * Vector3(s * to, y, w * 0.5)
		var d := xf * Vector3(s * from, y, w * 0.5)
		var len_v := (to - from) / 10.0
		_streets.set_color(Color.WHITE)
		track._quad_uv(_streets, [a, b, c, d], [Vector2(0, 0), Vector2(0, len_v), Vector2(1, len_v), Vector2(1, 0)], Vector3.UP)
		# the zebra crossing just before the junction, across the circuit
		var zebra := xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.03, -w * 0.5 - 3.0))
		for stripe in int(_hw(i) * 2.0 / 1.0):
			var x0 := -_hw(i) + 0.25 + stripe * 1.0
			_steel.set_color(Color(0.95, 0.95, 0.92))
			track._quad_uv(_steel, [zebra * Vector3(x0, 0, -1.5), zebra * Vector3(x0 + 0.5, 0, -1.5),
				zebra * Vector3(x0 + 0.5, 0, 1.5), zebra * Vector3(x0, 0, 1.5)], [Vector2(0.5, 0), Vector2(0.5, 0),
				Vector2(0.5, 0), Vector2(0.5, 0)], Vector3.UP)
		for z in [-w * 0.5 - 1.0, w * 0.5 + 1.0]:
			_traffic_light(xf * Transform3D(Basis.IDENTITY, Vector3(s * (_hw(i) + 2.6), -0.4, z)), s, z < 0.0)
		_traffic_light(xf * Transform3D(Basis.IDENTITY, Vector3(-s * (_hw(i) + 2.6), -0.4, -w * 0.5 - 1.0)), -s, true)


## A pole with a three-lamp head; `over` hangs a second head out over the
## circuit on an arm, facing the cars coming up to it.
func _traffic_light(xf: Transform3D, s: float, over: bool) -> void:
	var grey := Color(0.25, 0.26, 0.28)
	_cuboid(_steel, xf, Vector3(0.0, 2.6, 0.0), Vector3(0.18, 5.2, 0.18), grey)
	var heads: Array[Transform3D] = [xf * Transform3D(Basis.IDENTITY, Vector3(0, 3.6, 0.2))]
	if over:
		_cuboid(_steel, xf, Vector3(-s * 2.4, 5.0, 0), Vector3(4.8, 0.14, 0.14), grey)
		heads.append(xf * Transform3D(Basis.IDENTITY, Vector3(-s * 4.4, 4.3, 0.1)))
	for h in heads:
		_cuboid(_steel, h, Vector3.ZERO, Vector3(0.42, 1.2, 0.3), Color(0.08, 0.08, 0.09))
		# lenses face +z (back towards the oncoming cars)
		for k in 3:
			var lens := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.28, 0.28)
			lens.mesh = q
			lens.material_override = _lights[k]
			lens.transform = h * Transform3D(Basis.IDENTITY, Vector3(0, 0.36 - k * 0.36, 0.16))
			_bodies.add_child(lens)


## Concrete blocks along both edges of the whole lap with a wire catch fence
## on top, a sponsor board every so often. The start straight has hoardings.
func _barriers() -> void:
	var n := _n()
	var step := 1
	var boards := 0
	for i in range(0, n, step):
		if i < StartArea.REACH or i > n - StartArea.REACH - step:
			continue  # the start straight has its hoardings
		var j := (i + step) % n
		for s: float in [-1.0, 1.0]:
			var off_i := _hw(i) + 1.6
			var off_j := _hw(j) + 1.6
			var a := track.points[i] + track._side(i) * s * off_i
			var b := track.points[j] + track._side(j) * s * off_j
			var mid := (a + b) * 0.5
			# on the inside of a tight corner the offset line folds back over
			# the road: leave those blocks out
			if not _clear(mid, i, _hw(i) + 1.2):
				continue
			var flat := b - a
			flat.y = 0.0
			var xf := Transform3D(Basis.looking_at(flat.normalized(), Vector3.UP), mid + Vector3(0, 0.1, 0))
			var size := Vector3(0.6, 1.4, flat.length() + 0.1)
			var stripe := Color(0.95, 0.95, 0.93) if (i / 2) % 2 == 0 else Color(0.80, 0.80, 0.78)
			_cuboid(_walls, xf, Vector3.ZERO, size, stripe, Vector2(2.0, 1.4))
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = size
			cs.shape = shape
			cs.transform = xf
			_bodies.add_child(cs)
			# fence panel from the top of the wall, posts every few blocks
			var top := Vector3(0, 0.7, 0)
			track._quad_uv(_fence, [xf * (top + Vector3(0, 0, -size.z * 0.5)), xf * (top + Vector3(0, 0, size.z * 0.5)),
				xf * (top + Vector3(0, 2.6, size.z * 0.5)), xf * (top + Vector3(0, 2.6, -size.z * 0.5))],
				[Vector2(0, 2), Vector2(size.z / 1.3, 2), Vector2(size.z / 1.3, 0), Vector2(0, 0)], -track._side(i) * s)
			if i % 6 == 0:
				_cuboid(_steel, xf, Vector3(s * 0.1, 2.0, 0), Vector3(0.1, 2.6, 0.1), Color(0.5, 0.52, 0.55))
			if i % 18 == 8:
				var sp: Array = StartArea.SPONSORS[boards % StartArea.SPONSORS.size()]
				boards += 1
				var tex := StartArea._panel(sp[0], 2.9 / 0.9, sp[1], sp[2], sp[1], 9)
				var mi := MeshInstance3D.new()
				var q := QuadMesh.new()
				q.size = Vector2(2.9, 0.9)
				mi.mesh = q
				mi.material_override = TexGen.material(tex, 0.8)
				mi.transform = xf * Transform3D(Basis(Vector3.UP, -s * PI * 0.5), Vector3(-s * 0.31, 0.1, 0))
				_bodies.add_child(mi)


# --------------------------------------------------------------------------- buildings

## Blocks along both sides, set back past the pavement, one after another
## with the odd gap; none where a side street or the start is, or where
## another part of the route runs close behind.
func _buildings() -> void:
	var n := _n()
	for s: float in [-1.0, 1.0]:
		var i := StartArea.REACH + 6
		while i < n - StartArea.REACH - 6:
			var width := _rng.randf_range(12.0, 26.0)
			var samples := int(width / TrackBuilder.SPACING)
			var mid := i + samples / 2
			if _at_junction(mid, s, samples / 2 + 4) or absf(track._turn(mid, samples / 2 + 1)) > 0.5:
				i += 3
				continue
			var depth := _rng.randf_range(12.0, 22.0)
			var setback := _hw(mid) + 9.0 + _rng.randf_range(0.0, 2.0)
			var xf := track.frame(mid)
			var centre := xf * Vector3(s * (setback + depth * 0.5), 0, 0)
			var ok := true
			for corner in [Vector3(-width * 0.5, 0, -depth * 0.5), Vector3(width * 0.5, 0, -depth * 0.5),
					Vector3(-width * 0.5, 0, depth * 0.5), Vector3(width * 0.5, 0, depth * 0.5), Vector3.ZERO]:
				var p := centre + xf.basis * Vector3(corner.z * s, 0, corner.x)
				if not _clear(p, mid, _hw(mid) + 7.5) or track._near_start(p):
					ok = false
			if ok:
				var storeys := _rng.randi_range(3, 7) if _rng.randf() < 0.7 else _rng.randi_range(9, 18)
				var bxf := Transform3D(xf.basis, centre + Vector3(0, track.points[mid].y - 0.4, 0))
				_block(bxf, Vector3(depth, storeys * STOREY, width), s)
			i += samples + (_rng.randi_range(0, 2) if _rng.randf() < 0.75 else _rng.randi_range(4, 7))


## One block: facade walls, a flat roof with plant on it, and on the side
## facing the street a shop sign under an awning at ground level.
func _block(xf: Transform3D, size: Vector3, s: float) -> void:
	xf.origin.y = _ground(xf, size) - 0.3
	var style := _rng.randi() % FACADES.size()
	if size.y > 30.0 and _rng.randf() < 0.6:
		style = 3  # the tall ones are mostly glass
	var st := _facades[style]
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var corners := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	var u := _rng.randf_range(0.0, 4.0)
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		var l := a.distance_to(b)
		var nrm: Vector3
		if k % 2 == 0:
			nrm = xf.basis * Vector3(0, 0, signf(a.z))
		else:
			nrm = xf.basis * Vector3(signf(a.x), 0, 0)
		var vb := size.y / TILE.y
		st.set_color(Color.WHITE)
		track._quad_uv(st, [xf * (a + Vector3(0, -0.6, 0)), xf * (b + Vector3(0, -0.6, 0)), xf * (b + Vector3(0, size.y, 0)),
			xf * (a + Vector3(0, size.y, 0))],
			[Vector2(u, vb + 0.6 / TILE.y), Vector2(u + l / TILE.x, vb + 0.6 / TILE.y), Vector2(u + l / TILE.x, 0), Vector2(u, 0)], nrm)
		u += l / TILE.x
	# roof: a parapet slab, then a plant room, AC boxes or a water tank
	var roof := Color(0.36, 0.36, 0.38)
	_cuboid(_roofs, xf, Vector3(0, size.y + 0.2, 0), Vector3(size.x + 0.4, 0.4, size.z + 0.4), roof.lightened(0.15))
	_cuboid(_roofs, xf, Vector3(0, size.y + 0.42, 0), Vector3(size.x - 0.6, 0.06, size.z - 0.6), roof)
	for k in _rng.randi_range(1, 3):
		var at := Vector3(_rng.randf_range(-0.3, 0.3) * size.x, size.y, _rng.randf_range(-0.3, 0.3) * size.z)
		var plant := Vector3(_rng.randf_range(2.0, 5.0), _rng.randf_range(1.2, 3.0), _rng.randf_range(2.0, 5.0))
		_cuboid(_roofs, xf, at + Vector3(0, plant.y * 0.5 + 0.4, 0), plant, Color(0.62, 0.62, 0.60))
	if size.y > 40.0:
		_cuboid(_steel, xf, Vector3(0, size.y + 6.0, 0), Vector3(0.25, 12.0, 0.25), Color(0.7, 0.7, 0.72))
	# the street side faces -s along local x
	var front := -s * (hx + 0.02)
	if size.y < 30.0 and _rng.randf() < 0.75:
		var name: String = SHOPS[_rng.randi() % SHOPS.size()]
		var col: Color = SHOP_COLORS[_rng.randi() % SHOP_COLORS.size()]
		var w := minf(size.z * 0.7, 10.0)
		var sign_mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(w, 1.0)
		sign_mi.mesh = q
		sign_mi.material_override = TexGen.material(StartArea._panel(name, w / 1.0, Color(1, 1, 1), col, Color(1, 0.85, 0.1), 9), 0.8)
		sign_mi.transform = xf * Transform3D(Basis(Vector3.UP, -s * PI * 0.5), Vector3(front - s * 0.05, 3.6, 0))
		_bodies.add_child(sign_mi)
		_cuboid(_roofs, xf, Vector3(front - s * 0.9, 2.9, 0), Vector3(1.8, 0.12, w), col.lightened(0.1))
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = xf.translated_local(Vector3(0, size.y * 0.5, 0))
	_bodies.add_child(cs)


## The rest of the city: blocks on a street grid filling the land inside the
## lap and round it, leaving the parks as lawns.
func _infill() -> void:
	var origin := track._grid_origin()
	var pitch := 40.0
	var span := track._world_half - 90.0
	var x := track._center.x - span
	while x < track._center.x + span:
		var z := track._center.y - span
		while z < track._center.y + span:
			var p := Vector3(x + _rng.randf_range(-3, 3), 0, z + _rng.randf_range(-3, 3))
			var gx := int(round((p.x - origin.x) / TrackBuilder.CELL))
			var gz := int(round((p.z - origin.y) / TrackBuilder.CELL))
			if not track.city_park(gx, gz) and _rng.randf() < 0.85 and track._road_dist(p.x, p.z) > 44.0 					and _clear(p, track.nearest_index(p, 0), 46.0):
				var size := Vector3(_rng.randf_range(18.0, 28.0), 0, _rng.randf_range(18.0, 28.0))
				size.y = STOREY * (_rng.randi_range(3, 8) if _rng.randf() < 0.7 else _rng.randi_range(10, 24))
				p.y = track.terrain_height(p.x, p.z) - 0.4
				_block(Transform3D(Basis.IDENTITY, p), size, 1.0 if _rng.randf() < 0.5 else -1.0)
			z += pitch
		x += pitch


## The lowest ground under a block's footprint (a grid of points over it),
## so no corner of it is left hanging over a dip.
func _ground(xf: Transform3D, size: Vector3) -> float:
	var low := INF
	for gx in 5:
		for gz in 5:
			var p := xf * Vector3((gx / 4.0 - 0.5) * size.x, 0, (gz / 4.0 - 0.5) * size.z)
			low = minf(low, track.terrain_height(p.x, p.z))
	return low


# --------------------------------------------------------------------------- street furniture

## Lamps on both sides every so often, leaning out over the road; trees in
## the pavement between them, but not in front of a side street.
func _lamps_and_trees() -> void:
	var n := _n()
	var pole := Color(0.30, 0.32, 0.34)
	var lamp_mat := TexGen.flat_material(Color(1.0, 0.97, 0.86), 0.5, true)
	var head := BoxMesh.new()
	head.size = Vector3(0.5, 0.18, 1.0)
	for i in range(0, n, 12):
		if _near_start(i):
			continue
		for s: float in [-1.0, 1.0]:
			var k := i + (6 if s > 0.0 else 0)
			var xf := track.frame(k)
			var base := Vector3(s * (_hw(k) + 2.5), -0.4, 0)
			if not _at_junction(k, s, 3) and _clear(xf * base, k, _hw(k) + 2.0):
				_cuboid(_steel, xf, base + Vector3(0, 3.8, 0), Vector3(0.16, 7.6, 0.16), pole)
				_cuboid(_steel, xf, base + Vector3(-s * 0.9, 7.6, 0), Vector3(1.8, 0.12, 0.12), pole)
				var mi := MeshInstance3D.new()
				mi.mesh = head
				mi.material_override = lamp_mat
				mi.transform = xf * Transform3D(Basis.IDENTITY, base + Vector3(-s * 1.8, 7.5, 0))
				_bodies.add_child(mi)
			var t := wrapi(k + 3, 0, n)
			if _at_junction(t, s, 5) or _rng.randf() < 0.35:
				continue
			var txf := track.frame(t)
			var p := txf * Vector3(s * (_hw(t) + 5.5), 0, 0)
			if not _clear(p, t, _hw(t) + 4.0):
				continue
			p.y = track.points[t].y - 0.4
			var tree := MeshInstance3D.new()
			tree.mesh = Trees.leafy(_rng.randi_range(0, 3))
			tree.transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.7, 0.95)), p)
			track._scatter_add(tree)
	track._scatter_flush(_bodies)


## Fans behind the walls along the straights, a few deep.
func _fans() -> void:
	var n := _n()
	var i := StartArea.REACH + 8
	while i < n - StartArea.REACH - 8:
		var s := 1.0 if _rng.randf() < 0.5 else -1.0
		if not _at_junction(i, s, 8):
			for k in range(i - 6, i + 7):
				var xf := track.frame(k)
				for row in 3:
					var off := _hw(k) + 3.0 + row * 0.8
					if _rng.randf() < 0.75 - row * 0.15:
						var p := Vector3(s * (off + _rng.randf_range(-0.2, 0.2)), -0.4 + row * 0.2, _rng.randf_range(-1.2, 1.2))
						if not _clear(xf * p, k, _hw(k) + 2.6):
							continue  # that's the road again, round a corner
						_crowd.person(xf * Transform3D(Basis(Vector3.UP, s * PI * 0.5 + _rng.randf_range(-0.4, 0.4)), p),
							_rng.randf() < 0.5)
		i += _rng.randi_range(30, 55)


## Towers on the horizon all round, shaded per face and tinted by the haze
## like the mountains on the other stages (no fog, it would flatten them).
func _skyline() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var haze: Color = Conditions.palette("city", track.rain)["fog"]
	var light := Vector3(-0.55, 0.65, 0.5).normalized()
	var cols := [Color(0.42, 0.46, 0.52), Color(0.56, 0.56, 0.54), Color(0.32, 0.36, 0.42), Color(0.62, 0.60, 0.56)]
	var reach := track._world_half
	for k in 150:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(reach + 150.0, reach + 700.0)
		var at := Vector3(track._center.x + cos(a) * r, -5.0, track._center.y + sin(a) * r)
		var h := _rng.randf_range(40.0, 160.0) * (1.6 if _rng.randf() < 0.15 else 1.0)
		var size := Vector3(_rng.randf_range(20.0, 45.0), h, _rng.randf_range(20.0, 45.0))
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), at + Vector3(0, h * 0.5, 0))
		var base: Color = cols[_rng.randi() % cols.size()]
		for face in 5:
			var n: Vector3 = [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD, Vector3.UP][face]
			var wn: Vector3 = xf.basis * n
			var c := (base * (0.6 + 0.4 * maxf(wn.dot(light), 0.0))).lerp(haze, 0.45)
			st.set_color(Color(c.r, c.g, c.b))
			_face(st, xf, Vector3.ZERO, size, n, Vector2.ZERO)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_fog = true
	var mi := MeshInstance3D.new()
	mi.name = "Skyline"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	track.add_child(mi)


# --------------------------------------------------------------------------- meshes

## A box at `at` (local to xf) into a SurfaceTool, all six faces, in one
## vertex colour; `tile` metres per texture repeat on the sides (0 = no UVs).
func _cuboid(st: SurfaceTool, xf: Transform3D, at: Vector3, size: Vector3, col: Color, tile := Vector2.ZERO) -> void:
	st.set_color(col)
	for n in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]:
		_face(st, xf, at, size, n, tile)


func _face(st: SurfaceTool, xf: Transform3D, at: Vector3, size: Vector3, n: Vector3, tile: Vector2) -> void:
	var h := size * 0.5
	# two axes spanning the face
	var u := Vector3(n.z, 0, -n.x) if absf(n.y) < 0.5 else Vector3.RIGHT
	var v := Vector3.UP if absf(n.y) < 0.5 else Vector3.BACK
	var c := at + n * h
	var du := u * h
	var dv := v * h
	var lu := absf(u.dot(size))
	var lv := absf(v.dot(size))
	var tu := lu / tile.x if tile.x > 0.0 else 0.0
	var tv := lv / tile.y if tile.y > 0.0 else 0.0
	track._quad_uv(st, [xf * (c - du - dv), xf * (c + du - dv), xf * (c + du + dv), xf * (c - du + dv)],
		[Vector2(0, tv), Vector2(tu, tv), Vector2(tu, 0), Vector2(0, 0)], xf.basis * n)


func _flush() -> void:
	var wall_mat := TexGen.material(TexGen.concrete(), 1.0)
	wall_mat.vertex_color_use_as_albedo = true
	_commit(_walls, wall_mat, "Walls")
	var fence_mat := TexGen.material(_fence_tex(), 0.6)
	fence_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fence_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_commit(_fence, fence_mat, "CatchFence")
	var steel := StandardMaterial3D.new()
	steel.vertex_color_use_as_albedo = true
	steel.roughness = 0.5
	_commit(_steel, steel, "StreetFurniture")
	var roof := steel.duplicate() as StandardMaterial3D
	roof.roughness = 0.9
	_commit(_roofs, roof, "Roofs")
	var street := TexGen.material(TexGen.road("asphalt"), 0.9)
	street.vertex_color_use_as_albedo = true
	_commit(_streets, street, "SideStreets")
	for f in FACADES.size():
		var m := TexGen.material(_facade_tex(f), 0.7)
		_commit(_facades[f], m, "Facades%d" % f)
	var crowd := _crowd.make()
	if crowd:
		track.add_child(crowd)


func _commit(st: SurfaceTool, mat: Material, node_name: String) -> void:
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	track.add_child(mi)


# --------------------------------------------------------------------------- textures

## Four bays by four storeys of a facade: wall, window frames, glass with a
## sky sheen, some windows lit or with the blinds down.
static func _facade_tex(style: int) -> ImageTexture:
	return TexGen.cached("facade%d" % style, func() -> ImageTexture:
		var spec: Array = FACADES[style]
		var wall: Color = spec[0]
		var glass: Color = spec[1]
		var frame: int = spec[2]
		var win_h: int = spec[3]
		var r := RandomNumberGenerator.new()
		r.seed = 90 + style
		var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
		for y in 64:
			for x in 64:
				var v := r.randf_range(-0.025, 0.025)
				img.set_pixel(x, y, Color(wall.r + v, wall.g + v, wall.b + v))
		for by in 4:
			for bx in 4:
				var x0 := bx * 16 + frame
				var y0 := by * 16 + 3
				var pane := glass
				var roll := r.randf()
				if roll < 0.12:
					pane = Color(0.95, 0.85, 0.55)  # lit
				elif roll < 0.3:
					pane = glass.lerp(Color(0.85, 0.85, 0.80), 0.55)  # blinds down
				for y in range(y0, mini(y0 + win_h, by * 16 + 15)):
					for x in range(x0, bx * 16 + 16 - frame):
						var c := pane
						if y - y0 < 3 and x - x0 < 5:
							c = c.lightened(0.18)  # sky caught in the glass
						if style == 3 and (x - x0) % 5 == 4:
							c = wall  # mullions
						img.set_pixel(x, y, c)
				for x in range(bx * 16, bx * 16 + 16):
					img.set_pixel(x, mini(by * 16 + 15, 63), wall.darkened(0.2))  # floor line
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img))


## Diamond wire mesh with a top rail.
static func _fence_tex() -> ImageTexture:
	return TexGen.cached("city_fence", func() -> ImageTexture:
		var img := Image.create(16, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var wire := Color(0.62, 0.64, 0.66)
		for y in 32:
			for x in 16:
				if (x + y) % 8 == 0 or (x - y + 64) % 8 == 0 or y < 2:
					img.set_pixel(x, y, wire)
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img))


## Runs every traffic light through red, green and amber together.
class LightCycle extends Node:
	var lenses: Array[StandardMaterial3D] = []
	const ON := [Color(1.0, 0.1, 0.05), Color(1.0, 0.7, 0.05), Color(0.1, 1.0, 0.35)]

	func _process(_delta: float) -> void:
		var t := fmod(Time.get_ticks_msec() / 1000.0, 12.0)
		var lit := 0 if t < 5.0 else (2 if t < 10.5 else 1)
		for k in 3:
			lenses[k].albedo_color = ON[k] if k == lit else (ON[k] as Color).darkened(0.8)
