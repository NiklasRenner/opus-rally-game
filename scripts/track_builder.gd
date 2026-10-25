class_name TrackBuilder
extends Node3D
## Builds a stage procedurally from a map definition (maps.gd): a spline road
## (a closed lap, or open from a start to a finish on a point-to-point stage)
## split into surface sections, hilly terrain that follows the road's
## elevation, barriers, trees, houses and spectators.

const SPACING := 3.0
const LEAD_IN := 60.0  # point-to-point: metres of road behind the start line
const RUN_OUT := 150.0  # and past the finish, to stop in
const CLIFF_ARMCO_TURN := 0.3  # corners this sharp get armco along a drop, gentler ones guard posts
const CELL := 8.0
const VERGE := 2.6  # sloped shoulder outside the road edge
const WIDTH := {"asphalt": 10.0, "gravel": 8.5, "wet": 10.0, "ice": 9.0, "grass": 8.0, "mud": 8.0, "ford": 9.0,
	"wood": 7.5, "regolith": 11.0, "dust": 11.0, "cobbles": 10.0}

## Current map definition (see maps.gd), set before build().
var map: Dictionary = Maps.LIST[0]
var rain := false  # wet weather: shiny dark roads, darker grass
var _control_points: Array = []
var _sections: Array = []
var _elevation_keys: Array = []
var _jumps: Array = []

var points := PackedVector3Array()
var tangents := PackedVector3Array()
var surfaces := PackedStringArray()
var widths := PackedFloat32Array()
var total_length := 0.0
## false on a point-to-point stage: the road has two ends and indices don't wrap
var loop := true
var start_index := 0  # sample of the start line
var finish_index := 0  # sample of the finish line (the start line on a loop)
var stage_length := 0.0  # metres from the start line to the finish line

var _center := Vector2(333, -153)
var _world_half := 560.0  # terrain grid half size, grown to fit big stages
var _grid_n := 0
var _dist := PackedFloat32Array()
var _road_h := PackedFloat32Array()
var _heights := PackedFloat32Array()
var _scatter := {}  # mesh -> Array[Transform3D], drawn as one MultiMesh each
var _crater_list: Array = []  # [x, z, radius, depth] on the Moon
var _road_i := PackedInt32Array()  # per terrain cell: the nearest road sample
var _rng := RandomNumberGenerator.new()
var _cliff: CliffRoad  # the mountain pass's drops and rock walls ("alpine" theme)
var _geo: GeoStage  # a stage built from a real road and its terrain ("geo" maps)


func build() -> void:
	prepare()
	if _geo:
		_geo.track = self
	elif _theme() == "alpine":
		_cliff = CliffRoad.new(self)
	_build_road()
	_build_terrain()
	if _cliff:
		_cliff.build()
	if _geo:
		_geo.find_drops()
	_build_barriers()
	if not loop:
		_build_road_ends()
	_build_start_line()
	_build_section_signs()
	_build_village()
	_build_spectators()
	match _theme():
		"moon":
			MoonScenery.new(self).build()
		"city":
			CityScenery.new(self).build()
		_:
			if _geo:
				_geo.build()  # before the trees, which draw its forest too
			_build_trees()
	_build_cones()
	if _theme() != "city" and not _geo:
		_build_mountains()  # the city has its skyline instead, a real stage the real mountains
	_build_water()
	_build_bridges()
	if _theme() in ["circuit", "city"]:
		_build_kerbs()
	if map.has("landmark"):
		_build_pyramid(map["landmark"])
	if map.has("tunnel"):
		_build_tunnel()
	if _theme() == "wasteland":
		_build_wrecks()


## Reads the map and samples the route only (no geometry). The menu uses
## this for its track preview.
func prepare() -> void:
	_geo = GeoStage.open(map["geo"]) if map.has("geo") else null
	_control_points = _geo.points if _geo else map["points"]
	_sections = map["sections"]
	_elevation_keys = map.get("elevation", [])
	_jumps = map.get("jumps", [])
	_rng.seed = map["seed"]
	loop = not map.get("point_to_point", false)
	# centre the terrain grid on the route
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in _control_points:
		mn = mn.min(p)
		mx = mx.max(p)
	_center = (mn + mx) * 0.5
	_world_half = maxf(560.0, maxf(mx.x - mn.x, mx.y - mn.y) * 0.5 + 170.0)
	if _geo:
		# the baked terrain's own grid
		_world_half = (_geo.near_n - 1) * CELL * 0.5
		_center = Vector2(_geo.near_x0, _geo.near_z0) + Vector2(_world_half, _world_half)
	points.clear()
	tangents.clear()
	surfaces.clear()
	widths.clear()
	_sample_spline()


## "" for the normal countryside look, "wasteland", "jungle", "circuit",
## "moon", "city" or "alpine".
func _theme() -> String:
	return map.get("theme", "")


## What's under the wheels off the road: grass, the Moon's dust, or the
## city's pavements.
func _offroad() -> String:
	return {"moon": "dust", "city": "asphalt"}.get(_theme(), "grass")


## Inside one of the map's water areas (harbour, sea)?
func _in_water(x: float, z: float, margin := 0.0) -> bool:
	for r in map.get("water", []):
		if x > (r[0] as float) - margin and x < (r[2] as float) + margin and z > (r[1] as float) - margin and z < (r[3] as float) + margin:
			return true
	return false


func count() -> int:
	return points.size()


## A sample index brought onto the road: wrapped round a loop, held at the
## ends of a point-to-point road.
func wrap_index(i: int) -> int:
	return wrapi(i, 0, points.size()) if loop else clampi(i, 0, points.size() - 1)


## Samples from a to b going forwards (wrapping round a loop).
func ahead(a: int, b: int) -> int:
	return wrapi(b - a, 0, points.size()) if loop else b - a


## How far along the stage sample i is, 0 at the start line and 1 at the
## finish (beyond them on a point-to-point stage's lead-in and run-out).
func frac_of(i: int) -> float:
	if loop:
		return float(i) / points.size()
	return float(i - start_index) / maxf(finish_index - start_index, 1.0)


## The sample a fraction of the way along the stage (see frac_of).
func index_at(frac: float) -> int:
	if loop:
		return int(frac * points.size())
	return clampi(start_index + int(frac * (finish_index - start_index)), 0, points.size() - 1)


## Road frame at sample i (wrapped): origin on the centreline, -z along the
## road (level), +x to the right.
func frame(i: int) -> Transform3D:
	i = wrap_index(i)
	var flat := tangents[i]
	flat.y = 0.0
	return Transform3D(Basis.looking_at(flat.normalized(), Vector3.UP), points[i])


func get_spawn_transform(i: int) -> Transform3D:
	return frame(i).translated(Vector3(0, 1.0, 0))


## Nearest centreline sample. Searches a window around `hint` first and
## falls back to a full scan when the car is far away (off-road, reset).
func nearest_index(pos: Vector3, hint: int) -> int:
	var n := points.size()
	var best := hint
	var best_d := INF
	for o in range(-25, 26):
		var i := wrap_index(hint + o)
		var d := Vector2(points[i].x - pos.x, points[i].z - pos.z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	if best_d > 30.0 * 30.0:
		for i in n:
			var d := Vector2(points[i].x - pos.x, points[i].z - pos.z).length_squared()
			if d < best_d:
				best_d = d
				best = i
	return best


func distance_to_road(pos: Vector3, idx: int) -> float:
	return Vector2(points[idx].x - pos.x, points[idx].z - pos.z).length()


# --------------------------------------------------------------------------- spline

static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Smooth interpolation of the elevation keyframes plus the jump bump:
## periodic on a loop, held level past the last key on a point-to-point stage.
func _elevation(frac: float) -> float:
	var keys: Array = _elevation_keys
	var n := keys.size()
	if not loop:
		frac = clampf(frac, 0.0, 1.0)
	var k := n - 1
	for i in n:
		if frac >= (keys[i][0] as float):
			k = i
	var a: Array = keys[k]
	var b: Array = keys[(k + 1) % n] if loop or k + 1 < n else a
	var f0: float = a[0]
	var f1: float = b[0] if k + 1 < n else 1.0
	var t := clampf((frac - f0) / maxf(f1 - f0, 0.0001), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	var h := lerpf(a[1], b[1], t)
	for jump in _jumps:
		var jd := (frac - (jump[0] as float)) * stage_length / (jump[2] as float)
		if absf(jd) < 1.0:
			h += (jump[1] as float) * (0.5 + 0.5 * cos(jd * PI))
	return h


func _sample_spline() -> void:
	var cp: Array = _control_points.duplicate()
	# control points before the start line and after the finish
	var lead := 1
	var tail := 1
	if _geo:
		lead = _geo.lead  # the real road carries on past both ends
		tail = _geo.tail
	elif not loop:
		# straight lead-in behind the start line and a run-out past the finish
		var m0 := cp.size()
		cp.push_front((cp[0] as Vector2) - ((cp[1] as Vector2) - (cp[0] as Vector2)).normalized() * LEAD_IN)
		cp.push_back((cp[m0] as Vector2) + ((cp[m0] as Vector2) - (cp[m0 - 1] as Vector2)).normalized() * RUN_OUT)
	var n := cp.size()
	var dense: Array[Vector2] = []
	for i in (n if loop else n - 1):
		var p0: Vector2 = cp[wrapi(i - 1, 0, n)] if loop or i > 0 else 2.0 * (cp[0] as Vector2) - (cp[1] as Vector2)
		var p1: Vector2 = cp[i]
		var p2: Vector2 = cp[wrapi(i + 1, 0, n)]
		var p3: Vector2 = cp[wrapi(i + 2, 0, n)] if loop or i + 2 < n else 2.0 * (cp[n - 1] as Vector2) - (cp[n - 2] as Vector2)
		for k in 40:
			dense.append(_catmull(p0, p1, p2, p3, k / 40.0))
	if not loop:
		dense.append(cp[n - 1])
	var segs := dense.size() if loop else dense.size() - 1
	var lengths: Array[float] = [0.0]
	for i in range(1, segs + 1):
		lengths.append(lengths[i - 1] + dense[i - 1].distance_to(dense[i % dense.size()]))
	total_length = lengths[lengths.size() - 1]
	# the start and finish lines sit on the first and last of the map's points
	var s_start := 0.0 if loop else lengths[40 * lead]
	var s_finish := total_length if loop else lengths[(n - 1 - tail) * 40]
	stage_length = s_finish - s_start
	var count_pts := int(total_length / SPACING)
	var step := total_length / count_pts
	if not loop:
		count_pts += 1  # both ends of the road
	start_index = roundi(s_start / step)
	finish_index = roundi(s_finish / step) if not loop else 0
	var j := 0
	for k in count_pts:
		var s := minf(k * step, total_length)
		while j + 1 < segs and lengths[j + 1] < s:
			j += 1
		var t := clampf((s - lengths[j]) / maxf(lengths[j + 1] - lengths[j], 0.0001), 0.0, 1.0)
		var p := dense[j].lerp(dense[(j + 1) % dense.size()], t)
		var frac := (s - s_start) / stage_length
		points.append(Vector3(p.x, _geo.road_height(s / total_length, total_length) if _geo else _elevation(frac), p.y))
		var surf: String = _sections[0][1]
		for sec in _sections:
			if frac >= sec[0]:
				surf = sec[1]
		surfaces.append(surf)
	for i in count_pts:
		tangents.append((points[wrap_index(i + 1)] - points[wrap_index(i - 1)]).normalized())
	# road width eases between surfaces instead of stepping
	for i in count_pts:
		var acc := 0.0
		for o in range(-6, 7):
			acc += WIDTH[surfaces[wrap_index(i + o)]]
		widths.append(acc / 13.0 * (map.get("width", 1.0) as float))
	if _geo:
		# real mountain roads are widened round their hairpins (a car needs
		# the room); ease it in over the corner
		var widen := PackedFloat32Array()
		for i in count_pts:
			widen.append(smoothstep(1.0, 2.0, absf(_turn(i, 4))))
		for i in count_pts:
			var m := 0.0
			for o in range(-5, 6):
				m = maxf(m, widen[wrap_index(i + o)] * (1.0 - absf(o) / 6.0))
			widths[i] *= 1.0 + 0.5 * m


func _side(i: int) -> Vector3:
	var t := tangents[i]
	t.y = 0.0
	return t.normalized().cross(Vector3.UP).normalized()


## How far the road turns (radians, + = left) between `reach` samples before
## and after sample i.
func _turn(i: int, reach: int) -> float:
	var t0 := tangents[wrap_index(i - reach)]
	var t1 := tangents[wrap_index(i + reach)]
	return Vector3(t0.x, 0, t0.z).signed_angle_to(Vector3(t1.x, 0, t1.z), Vector3.UP)


# --------------------------------------------------------------------------- road

func _build_road() -> void:
	var tools := {}
	var verge := SurfaceTool.new()
	verge.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	var v := 0.0
	var down := Vector3(0, -0.5, 0)
	for i in (n if loop else n - 1):
		var b := wrap_index(i + 1)
		var surf: String = surfaces[i]
		if not tools.has(surf):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[surf] = st
		var st2: SurfaceTool = tools[surf]
		var la := points[i] - _side(i) * widths[i] * 0.5
		var ra := points[i] + _side(i) * widths[i] * 0.5
		var lb := points[b] - _side(b) * widths[b] * 0.5
		var rb := points[b] + _side(b) * widths[b] * 0.5
		var seg := points[i].distance_to(points[b]) / 10.0
		# wound so faces point up (Godot: clockwise = front)
		_quad(st2, la, ra, lb, rb, Vector2(0, v), Vector2(1, v), Vector2(0, v + seg), Vector2(1, v + seg))
		# sloped shoulders hide the seam between road and terrain
		var lla := la - _side(i) * VERGE + down
		var llb := lb - _side(b) * VERGE + down
		var rra := ra + _side(i) * VERGE + down
		var rrb := rb + _side(b) * VERGE + down
		_quad(verge, lla, la, llb, lb, Vector2(0, v), Vector2(0.3, v), Vector2(0, v + seg), Vector2(0.3, v + seg))
		_quad(verge, ra, rra, rb, rrb, Vector2(0.3, v), Vector2(0, v), Vector2(0.3, v + seg), Vector2(0, v + seg))
		v += seg
	for surf in tools:
		var st3: SurfaceTool = tools[surf]
		st3.generate_normals()
		var arrays := st3.commit_to_arrays()
		var mat := TexGen.material(_road_tex(surf), 0.12 if surf == "wet" else 0.9)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if rain and surf != "ford":
			mat.roughness = 0.12 if surf in ["asphalt", "wet", "wood", "ice"] else 0.35
			mat.metallic_specular = 0.9
			mat.albedo_color = Color(0.70, 0.72, 0.78)
		_add_static(arrays, mat, surf, "Road_" + surf)
	verge.generate_normals()
	var vmat := TexGen.material(TexGen.concrete() if _theme() == "city" else _road_tex(_offroad()), 1.0)
	vmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_static(verge.commit_to_arrays(), vmat, _offroad(), "Verges")


func _road_tex(surf: String) -> ImageTexture:
	return TexGen.road_wasted(surf) if _theme() == "wasteland" else TexGen.road(surf)


## Two triangles for a quad given left/right at the start (a) and end (b).
func _quad(st: SurfaceTool, la: Vector3, ra: Vector3, lb: Vector3, rb: Vector3,
		ula: Vector2, ura: Vector2, ulb: Vector2, urb: Vector2) -> void:
	for q in [[la, ula], [rb, urb], [ra, ura], [la, ula], [lb, ulb], [rb, urb]]:
		st.set_uv(q[1])
		st.add_vertex(q[0])


## `arrays` must be a non-indexed triangle list; its vertices double as the
## collision faces (built directly so it also works with a headless server).
func _add_static(arrays: Array, mat: Material, surf: String, node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.set_meta("surface", surf)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(arrays[Mesh.ARRAY_VERTEX])
	shape.backface_collision = true
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body


# --------------------------------------------------------------------------- terrain

func _build_terrain() -> void:
	_grid_n = int(_world_half * 2.0 / CELL) + 1
	var gn := _grid_n
	_dist.resize(gn * gn)
	_dist.fill(1e9)
	_road_h.resize(gn * gn)
	_road_h.fill(0.0)
	_road_i.resize(gn * gn)
	_road_i.fill(0)
	var origin := _grid_origin()
	var r := 12
	for pi in points.size():
		var p := points[pi]
		var cx := int(round((p.x - origin.x) / CELL))
		var cz := int(round((p.z - origin.y) / CELL))
		for z in range(maxi(cz - r, 0), mini(cz + r, gn - 1) + 1):
			for x in range(maxi(cx - r, 0), mini(cx + r, gn - 1) + 1):
				var d := Vector2(origin.x + x * CELL - p.x, origin.y + z * CELL - p.z).length()
				var k := z * gn + x
				if d < _dist[k]:
					_dist[k] = d
					_road_h[k] = p.y
					_road_i[k] = pi
	# cells far from the road get the height of the nearest stamped cell's road (diffuse a bit)
	var noise := FastNoiseLite.new()
	noise.seed = 42
	noise.frequency = 0.007
	noise.fractal_octaves = 3
	_heights.resize(gn * gn)
	var alpine := _cliff.heights() if _cliff else (_geo.heights() if _geo else PackedFloat32Array())
	for z in gn:
		for x in gn:
			var k := z * gn + x
			var wx := origin.x + x * CELL
			var wz := origin.y + z * CELL
			# near the road the ground sits just under it; further out it fades to
			# a common base level so the stamp boundary leaves no step
			var base := _road_h[k] if _dist[k] < 1e8 else 0.0
			var far_base := lerpf(base * 0.7, 5.6, smoothstep(55.0, 95.0, _dist[k]))
			var n01 := noise.get_noise_2d(wx, wz) * 0.5 + 0.5
			var edge := smoothstep(VERGE + 6.0, 70.0, _dist[k])
			var hills := (n01 * n01) * 38.0 - 4.0
			if _theme() == "moon":
				hills *= 0.35  # the mare is flat; the craters make the relief
			var rim := smoothstep(_world_half - 110.0, _world_half, maxf(absf(wx - _center.x), absf(wz - _center.y)))
			_heights[k] = lerpf(base - 0.3, far_base + hills + 3.0, edge) + rim * 60.0
			if _geo:
				_heights[k] = alpine[k]  # the real mountains carry on beyond the grid
			elif _cliff:
				_heights[k] = alpine[k] + rim * 60.0
			elif _theme() == "city":
				# flat streets and plazas between the blocks
				_heights[k] = lerpf(base - 0.3, base * 0.8, smoothstep(30.0, 90.0, _dist[k])) + rim * 30.0
			elif _theme() == "moon":
				_heights[k] += _craters(wx, wz) * smoothstep(VERGE + 3.0, 24.0, _dist[k])
				if _dist[k] < 1e8 and _flat_ground(frac_of(_road_i[k])):
					# level pads for the base buildings and the start, no hills or craters
					_heights[k] = lerpf(base - 0.3, _heights[k], smoothstep(50.0, 75.0, _dist[k]))
			var sink := _water_depth(wx, wz)
			if sink > 0.0:
				_heights[k] = lerpf(_heights[k], _water_level() - 5.0, sink)
	var covered := PackedByteArray()
	if _geo:
		# the banks along the road take over from the grid near it; the grid
		# ducks under them where the two overlap
		covered = _geo.build_banks()
		for k in gn * gn:
			if covered[k]:
				_heights[k] -= 2.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in gn - 1:
		for x in gn - 1:
			if _geo and not _geo.cell_drawn(x, z):
				continue  # out past the band round the road: the distant mesh
			if _geo and covered[z * gn + x] and covered[z * gn + x + 1] and covered[(z + 1) * gn + x] \
					and covered[(z + 1) * gn + x + 1]:
				continue  # under the banks
			var ids := [Vector2i(x, z), Vector2i(x + 1, z), Vector2i(x + 1, z + 1),
				Vector2i(x, z), Vector2i(x + 1, z + 1), Vector2i(x, z + 1)]
			for g in ids:
				var k: int = g.y * gn + g.x
				var h := _heights[k]
				var wp := Vector3(origin.x + g.x * CELL, h, origin.y + g.y * CELL)
				st.set_color(_alpine_color(g.x, g.y) if _cliff or _geo else _terrain_color(h - _road_h[k] * 0.7, k))
				st.set_uv(Vector2(wp.x, wp.z) / 8.0)
				st.add_vertex(wp)
	st.generate_normals()
	var ground_tex: Texture2D = {"moon": TexGen.road("dust"), "city": TexGen.concrete()}.get(_theme(), TexGen.grass())
	var mat := TexGen.material(ground_tex, 1.0, Color(0.8, 0.84, 0.82) if rain else Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_static(st.commit_to_arrays(), mat, _offroad(), "Terrain")


## Is the ground beside this part of the lap (a fraction) kept level? The
## start, and on the Moon the stretches lined with the base.
func _flat_ground(frac: float) -> bool:
	if frac < 0.03 or frac > 0.97:
		return true
	for r in map.get("base", []):
		if frac > (r[0] as float) - 0.015 and frac < (r[1] as float) + 0.015:
			return true
	return false


## Height change from the Moon's craters at a point: a bowl sunk below the
## plain with a raised rim round it. The map lists the big ones; a field of
## small ones is scattered from the stage seed.
func _craters(x: float, z: float) -> float:
	if _crater_list.is_empty():
		_crater_list = map.get("craters", []).duplicate()
		var r := RandomNumberGenerator.new()
		r.seed = int(map["seed"]) + 21
		for k in int(map.get("crater_field", 0)):
			var rad := r.randf_range(6.0, 30.0) * (1.0 if r.randf() < 0.8 else 2.2)
			_crater_list.append([_center.x + r.randf_range(-1, 1) * _world_half, _center.y + r.randf_range(-1, 1) * _world_half,
				rad, rad * r.randf_range(0.18, 0.3)])
	var h := 0.0
	for c in _crater_list:
		var d := Vector2(x - (c[0] as float), z - (c[1] as float)).length() / (c[2] as float)
		if d > 1.8:
			continue
		var depth: float = c[3]
		h += -depth * maxf(1.0 - d * d, 0.0) + depth * 0.4 * exp(-pow((d - 1.0) / 0.28, 2.0))
	return h


func _grid_origin() -> Vector2:
	return _center - Vector2(_world_half, _world_half)


func _terrain_color(h: float, k: int) -> Color:
	if _theme() == "moon":
		# grey plains, darker down in the crater bowls, bright on the rims
		var mare := Color(0.50, 0.50, 0.49).lerp(Color(0.42, 0.42, 0.43), clampf(sin(k * 0.37) * 0.5 + 0.5, 0.0, 1.0) * 0.6)
		if h < -0.8:
			mare = mare.lerp(Color(0.30, 0.30, 0.32), clampf((-0.8 - h) / 4.0, 0.0, 1.0))
		elif h > 1.5:
			mare = mare.lerp(Color(0.66, 0.66, 0.64), clampf((h - 1.5) / 8.0, 0.0, 1.0))
		return mare
	if _theme() == "city":
		# paved streets and squares, with a park here and there
		var paved := Color(0.70, 0.69, 0.66).lerp(Color(0.62, 0.61, 0.60), clampf(sin(k * 0.37) * 0.5 + 0.5, 0.0, 1.0))
		return Color(0.36, 0.52, 0.24) if city_park(k % _grid_n, k / _grid_n) and _dist[k] > 40.0 else paved
	if _theme() == "wasteland":
		var ash := Color(0.40, 0.37, 0.32)
		var scorch := Color(0.24, 0.21, 0.18)
		var c2 := ash.lerp(scorch, clampf(sin(k * 0.37) * 0.5 + 0.5, 0.0, 1.0) * 0.5)
		if h < -0.5:
			c2 = c2.lerp(Color(0.30, 0.32, 0.18), 0.6)  # sludge on the shore
		if h > 20.0:
			c2 = c2.lerp(Color(0.48, 0.42, 0.36), clampf((h - 20.0) / 15.0, 0.0, 1.0))
		return c2
	if _theme() == "jungle":
		var lush := Color(0.20, 0.42, 0.14)
		var c3 := lush.lerp(Color(0.30, 0.50, 0.12), clampf(sin(k * 0.37) * 0.5 + 0.5, 0.0, 1.0) * 0.6)
		if h < 0.6:
			c3 = c3.lerp(Color(0.34, 0.26, 0.16), clampf((0.6 - h) / 1.5, 0.0, 1.0))  # muddy river banks
		if h > 22.0:
			c3 = c3.lerp(Color(0.40, 0.42, 0.30), clampf((h - 22.0) / 14.0, 0.0, 1.0))
		return c3
	var grass := Color(0.40, 0.58, 0.22)
	var dry := Color(0.64, 0.56, 0.32)
	var rock := Color(0.62, 0.55, 0.46)
	var c := grass.lerp(dry, clampf(sin(k * 0.37) * 0.5 + 0.5, 0.0, 1.0) * 0.35)
	if h > 16.0:
		c = c.lerp(rock, clampf((h - 16.0) / 12.0, 0.0, 1.0))
	if h > 48.0:
		c = c.lerp(Color(0.95, 0.96, 1.0), clampf((h - 48.0) / 10.0, 0.0, 1.0))
	return c


## Is this terrain cell (grid x, z) part of a city park? Parks come in
## blocks of 64 m.
## The mountain pass: grass where it's flat enough, bare rock and scree on
## the steep ground, snow up high.
func _alpine_color(gx: int, gz: int) -> Color:
	var gn := _grid_n
	var k := gz * gn + gx
	var h := _heights[k]
	var steep := 0.0
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q := Vector2i(clampi(gx + o.x, 0, gn - 1), clampi(gz + o.y, 0, gn - 1))
		steep = maxf(steep, absf(_heights[q.y * gn + q.x] - h) / CELL)
	return alpine_tint(h, steep, k)


## The mountain colours for ground at height h, this steep (rise per metre);
## k varies the grass a little.
func alpine_tint(h: float, steep: float, k: int) -> Color:
	var grass := Color(0.40, 0.56, 0.24).lerp(Color(0.56, 0.58, 0.30), clampf(sin(k * 0.37) * 0.5 + 0.5, 0.0, 1.0) * 0.4)
	var rock := Color(0.58, 0.55, 0.50).lerp(Color(0.46, 0.44, 0.42), clampf(sin(k * 0.53) * 0.5 + 0.5, 0.0, 1.0))
	var c := grass.lerp(rock, smoothstep(0.55, 1.1, steep))
	var snow_line: float = map.get("snow_line", INF)
	if h > snow_line:
		c = c.lerp(Color(0.93, 0.95, 1.0), smoothstep(snow_line, snow_line + 14.0, h) * (1.0 - 0.5 * smoothstep(1.0, 2.0, steep)))
	return c


func city_park(gx: int, gz: int) -> bool:
	return posmod(gx / 8 * 7 + gz / 8 * 13 + int(map["seed"]), 9) == 0


func terrain_height(x: float, z: float) -> float:
	if _geo:
		return _geo.surface_height(x, z)
	if _cliff:
		return ground_height(x, z)  # the mountainside is too steep for the nearest grid point
	var k := _grid_index(x, z)
	return _heights[k]


## Height of the terrain mesh itself at a point (the grid's triangles
## interpolated, not the nearest grid point), for things that stand on
## steep ground.
func ground_height(x: float, z: float) -> float:
	var gn := _grid_n
	var origin := _grid_origin()
	var fx := clampf((x - origin.x) / CELL, 0.0, gn - 1.001)
	var fz := clampf((z - origin.y) / CELL, 0.0, gn - 1.001)
	var gx := int(fx)
	var gz := int(fz)
	fx -= gx
	fz -= gz
	var h00 := _heights[gz * gn + gx]
	var h10 := _heights[gz * gn + gx + 1]
	var h01 := _heights[(gz + 1) * gn + gx]
	var h11 := _heights[(gz + 1) * gn + gx + 1]
	# the same diagonal split as the terrain triangles
	if fx >= fz:
		return h00 + fx * (h10 - h00) + fz * (h11 - h10)
	return h00 + fz * (h01 - h00) + fx * (h11 - h01)


## No room for a tree, a fan or a house at p (a rock wall, over a drop, a
## bank too steep)? `hint` is a road sample near p.
func _blocked(p: Vector3, hint: int) -> bool:
	if _cliff:
		return _cliff.blocked(p, hint)
	return _geo != null and _geo.blocked(p, hint)


func _road_dist(x: float, z: float) -> float:
	return _dist[_grid_index(x, z)]


func _grid_index(x: float, z: float) -> int:
	var origin := _grid_origin()
	var gx := clampi(int(round((x - origin.x) / CELL)), 0, _grid_n - 1)
	var gz := clampi(int(round((z - origin.y) / CELL)), 0, _grid_n - 1)
	return gz * _grid_n + gx


# --------------------------------------------------------------------------- barriers

## Crashable barriers on the outside of sharper corners: stone walls on
## tarmac, hay bales on gravel.
func _build_barriers() -> void:
	if _theme() == "city":
		return  # the street circuit is walled the whole way round (CityScenery)
	var styles := {
		"asphalt": {"size": Vector3(0.9, 1.1, 3.4), "mat": _box_material(TexGen.stone_wall(), 1.0)},
		"gravel": {"size": Vector3(1.2, 1.2, 2.6), "mat": _box_material(TexGen.hay(), 1.0)},
		"wet": {"size": Vector3(0.3, 0.8, 3.4), "mat": _box_material(TexGen.armco(), 0.35)},
		"ice": {"size": Vector3(2.0, 1.3, 3.6), "mat": _box_material(TexGen.snow(), 0.6)},
		"grass": {"size": Vector3(0.25, 1.0, 3.2), "mat": _box_material(TexGen.planks(), 1.0)},
	}
	if _theme() == "wasteland":
		var rusty := _box_material(TexGen.armco(), 0.6)
		rusty.albedo_color = Color(0.85, 0.6, 0.45)
		var slab := _box_material(TexGen.concrete(), 1.0)
		styles["asphalt"] = {"size": Vector3(0.3, 0.8, 3.4), "mat": rusty}
		styles["wet"] = styles["asphalt"]
		styles["gravel"] = {"size": Vector3(0.8, 1.0, 3.0), "mat": slab}
	var logs := {"size": Vector3(0.8, 0.8, 3.4), "mat": TexGen.material(TexGen.bark(), 1.0), "log": true}
	styles["mud"] = logs
	if _theme() == "jungle":
		styles["gravel"] = logs
		styles["grass"] = logs
	elif _theme() == "circuit":
		styles["asphalt"] = styles["wet"]  # armco round the whole lap
	elif _theme() == "moon":
		# bags of regolith stacked into berms, the way the base crews build them
		var bags := {"size": Vector3(1.4, 1.0, 3.2), "mat": _box_material(TexGen.road("dust"), 1.0)}
		(bags["mat"] as StandardMaterial3D).albedo_color = Color(0.86, 0.84, 0.78)
		styles["regolith"] = bags
		styles["dust"] = bags
	var walls := StaticBody3D.new()
	walls.name = "Barriers"
	walls.set_meta("surface", "grass")
	add_child(walls)
	var n := points.size()
	for i in n:
		if near_line(i, StartArea.REACH + 3):
			continue  # the start area has its own hoardings
		var turn := _turn(i, 4)
		if absf(turn) < 0.16:
			continue
		var surf: String = surfaces[i]
		if not styles.has(surf):
			continue  # bridges and fords have their own edges
		var style: Dictionary = styles[surf]
		# positive turn = turning left, so the outside is the right (+side)
		var out_sign := 1.0 if turn > 0.0 else -1.0
		var edge := widths[i] * 0.5 + VERGE + 0.4
		var drop_side := _cliff.side[i] if _cliff else (_geo.side[i] if _geo else 0.0)
		var drop := drop_side != 0.0
		if drop:
			if out_sign != drop_side:
				continue  # the outside of the corner is the rock wall
			if absf(turn) < CLIFF_ARMCO_TURN:
				continue  # guard posts (CliffRoad) on the gentler bends
			style = styles["wet"]  # armco along the drop
			edge = widths[i] * 0.5 + VERGE - 0.5  # on the verge, it's thin air past it
		var size: Vector3 = style["size"]
		var pos := points[i] + _side(i) * out_sign * (edge + size.x * 0.5)
		pos.y = points[i].y - 0.45 + size.y * 0.5
		var xf := Transform3D(frame(i).basis, pos)
		if _geo:
			# on a falling hillside: walls and bales reach down into the
			# ground, armco stands on a post
			var low := _lowest_ground(xf, size)
			var bottom := pos.y - size.y * 0.5
			if low < bottom - 0.05:
				if size.x < 0.5:
					_armco_post(walls, xf, bottom, low)
				else:
					var ext := bottom - low + 0.3
					size = Vector3(size.x, size.y + ext, size.z)
					pos.y -= ext * 0.5
					xf.origin = pos
		var mi := MeshInstance3D.new()
		if style.get("log", false):
			# a felled log lying along the corner
			var cyl := CylinderMesh.new()
			cyl.top_radius = size.x * 0.5
			cyl.bottom_radius = size.x * 0.55
			cyl.height = size.z
			cyl.radial_segments = 7
			cyl.rings = 1
			mi.mesh = cyl
			mi.transform = xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.FORWARD, _rng.randf() * 0.3),
				Vector3.ZERO)
		else:
			var box := BoxMesh.new()
			box.size = size
			mi.mesh = box
			mi.transform = xf
		mi.material_override = style["mat"]
		walls.add_child(mi)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.transform = xf
		walls.add_child(cs)
		# chevron boards on the outside of tight corners
		if absf(turn) > 0.3 and i % 6 == 0 and not drop:
			_chevron(points[i] + _side(i) * out_sign * (widths[i] * 0.5 + VERGE + 2.5), -xf.basis.z, out_sign)


## Lowest ground under a box at xf (its footprint's corners and middle).
func _lowest_ground(xf: Transform3D, size: Vector3) -> float:
	var low := INF
	for c in [Vector2(0, 0), Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
		var q: Vector3 = xf * Vector3(c.x * size.x, 0, c.y * size.z)
		low = minf(low, terrain_height(q.x, q.z))
	return low


## A steel post under a length of armco, from the ground up to its rail.
func _armco_post(body: StaticBody3D, xf: Transform3D, top: float, ground: float) -> void:
	var h := top - ground + 0.4
	var box := BoxMesh.new()
	box.size = Vector3(0.14, h, 0.14)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = TexGen.flat_material(Color(0.55, 0.57, 0.6), 0.5)
	mi.transform = Transform3D(xf.basis, Vector3(xf.origin.x, top - h * 0.5 + 0.1, xf.origin.z))
	body.add_child(mi)


## A point-to-point road just stops: a row of bales across each end, with a
## chevron board to warn you at the bottom of the run-out.
func _build_road_ends() -> void:
	var body := StaticBody3D.new()
	body.name = "RoadEnds"
	body.set_meta("surface", "grass")
	add_child(body)
	var bale := BoxMesh.new()
	bale.size = Vector3(2.6, 1.2, 1.2)
	var mat := _box_material(TexGen.hay(), 1.0)
	var shape := BoxShape3D.new()
	shape.size = bale.size
	for i in [1, points.size() - 2]:
		var xf := frame(i)
		var span := widths[i] + VERGE * 2.0
		var x := -span * 0.5 + 1.3
		while x < span * 0.5:
			for row in 2:
				var at := xf * Vector3(x, -0.45 + 0.6 + row * 1.2, 0)
				var bx := Transform3D(xf.basis, at)
				var mi := MeshInstance3D.new()
				mi.mesh = bale
				mi.material_override = mat
				mi.transform = bx
				body.add_child(mi)
				var cs := CollisionShape3D.new()
				cs.shape = shape
				cs.transform = bx
				body.add_child(cs)
			x += 2.65
	var end := points.size() - 2
	_chevron(points[end] + Vector3(0, 1.4, 0) - frame(end).basis.z * 1.5, -frame(end).basis.z, 1.0)


## BoxMesh packs its six faces into a 3 x 2 atlas; scale UVs so every face
## shows the whole texture.
func _box_material(tex: Texture2D, roughness: float) -> StandardMaterial3D:
	var m := TexGen.material(tex, roughness)
	m.uv1_scale = Vector3(3, 2, 1)
	return m


func _chevron(pos: Vector3, tangent: Vector3, out_sign: float) -> void:
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 0.8, 0.08)
	board.mesh = bm
	board.material_override = TexGen.material(TexGen.stripes(Color(1.0, 0.82, 0.1), Color(0.08, 0.08, 0.08), 4), 0.8)
	var ground := pos.y - 0.45
	if _geo:
		ground = terrain_height(pos.x, pos.z)
		pos.y = maxf(pos.y, ground + 0.45)  # up a cut bank it stands on the bank
	board.position = pos + Vector3(0, 1.6, 0)
	add_child(board)
	board.look_at(board.position + tangent, Vector3.UP)
	var label := Label3D.new()
	label.text = "<<" if out_sign > 0.0 else ">>"
	label.font_size = 64
	label.outline_size = 12
	label.modulate = Color(0.1, 0.1, 0.1)
	label.outline_modulate = Color(1.0, 0.85, 0.1)
	label.position = Vector3(0, 0, 0.05)
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	board.add_child(label)
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	# from the board down into the ground, however far below it is
	var top := pos.y + 1.6
	pm.size = Vector3(0.12, top - ground + 0.3, 0.12)
	post.mesh = pm
	post.material_override = TexGen.flat_material(Color(0.85, 0.85, 0.85))
	post.position = Vector3(pos.x, (top + ground - 0.3) * 0.5, pos.z)
	add_child(post)


# --------------------------------------------------------------------------- dressing

func _build_start_line() -> void:
	if loop:
		StartArea.new(self).build()
	else:
		StartArea.new(self, start_index, "start").build()
		StartArea.new(self, finish_index, "finish").build()


## Inside the space kept free round the start/finish dressing?
func _near_start(p: Vector3) -> bool:
	for i in [start_index, finish_index]:
		if Vector2(p.x - points[i].x, p.z - points[i].z).length() < StartArea.CLEAR_RADIUS:
			return true
	return false


## Within `reach` samples of the start or finish line? A point-to-point
## road's lead-in and run-out count too.
func near_line(i: int, reach: int) -> bool:
	if not loop and (i < start_index or i > finish_index):
		return true
	for at in [start_index, finish_index]:
		if mini(wrapi(i - at, 0, points.size()), wrapi(at - i, 0, points.size())) <= reach:
			return true
	return false


func _build_section_signs() -> void:
	for sec in _sections:
		var i := index_at(float(sec[0]))
		if i == start_index:
			continue
		var surf: String = sec[1]
		var info := Surfaces.get_surface(surf)
		var label := Label3D.new()
		label.text = info["label"]
		label.font_size = 128
		label.outline_size = 20
		label.modulate = info["hud"]
		label.outline_modulate = Color(0.05, 0.05, 0.1)
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		var k := wrap_index(i - 10)
		label.position = points[k] + _side(k) * (widths[k] * 0.5 + VERGE + 1.5) + Vector3(0, 3.2, 0)
		add_child(label)


## Low-poly houses lining the village sections: textured plaster walls with
## shuttered windows, tiled gable roofs, a door facing the road.
func _build_village() -> void:
	var ranges: Array = map["village"]
	if ranges.is_empty():
		return
	if not (ranges[0] is Array):
		ranges = [ranges]
	var ruins := _theme() == "wasteland"
	var temples := _theme() == "jungle"
	var temple_mat := TexGen.material(TexGen.stone_wall(), 1.0, Color(0.72, 0.80, 0.62))
	var wall_mats: Array[StandardMaterial3D] = []
	var gable_mats: Array[StandardMaterial3D] = []
	for v in TexGen.WALL_COLORS.size():
		wall_mats.append(TexGen.material(TexGen.house_wall(v), 0.95))
		gable_mats.append(TexGen.flat_material(TexGen.WALL_COLORS[v], 0.95))
	var roof_mat := TexGen.material(TexGen.roof_tiles(), 0.85)
	roof_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var door_mat := TexGen.material(TexGen.door(), 0.8)
	var chimney_mat := TexGen.material(TexGen.stone_wall(), 1.0)
	var ruin_mats: Array[StandardMaterial3D] = []
	for v in 3:
		var m := TexGen.material(TexGen.ruin_wall(v), 1.0)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		ruin_mats.append(m)
	var rubble_mat := TexGen.material(TexGen.concrete(), 1.0, Color(0.6, 0.57, 0.52))
	var bodies := StaticBody3D.new()
	bodies.name = "Village"
	add_child(bodies)
	for range_f in ranges:
		var i := index_at(range_f[0] as float)
		while i < index_at(range_f[1] as float):
			for s in [-1.0, 1.0]:
				if _rng.randf() < 0.3:
					continue
				var storeys := (_rng.randi_range(2, 5) if ruins else (1 if _rng.randf() < 0.45 else 2))
				var size := Vector3(_rng.randf_range(6, 10), storeys * 3.0, _rng.randf_range(6, 9))
				var off := widths[i] * 0.5 + VERGE + 3.0 + size.x * 0.5
				var pos: Vector3 = points[i] + _side(i) * s * off
				# keep clear of other parts of the route and of the water
				if _road_dist(pos.x, pos.z) < off - 1.0 or _in_water(pos.x, pos.z, size.x * 0.6 + 2.0) or _near_start(pos):
					continue
				if _blocked(pos, i):
					continue
				var bas := frame(i).basis
				var house := Node3D.new()
				house.transform = Transform3D(bas, pos)
				add_child(house)
				if temples:
					size.y = _place_temple(house, size, temple_mat)
				elif ruins:
					_place_ruin(house, size, ruin_mats[_rng.randi() % ruin_mats.size()], rubble_mat, s)
				else:
					_place_house(house, size, s, wall_mats, gable_mats, roof_mat, door_mat, chimney_mat)
				var cs := CollisionShape3D.new()
				var shape := BoxShape3D.new()
				shape.size = size
				cs.shape = shape
				cs.transform = Transform3D(bas, pos + Vector3(0, size.y * 0.5 - 0.5, 0))
				bodies.add_child(cs)
			i += _rng.randi_range(4, 6)


func _place_house(house: Node3D, size: Vector3, s: float, wall_mats: Array[StandardMaterial3D],
		gable_mats: Array[StandardMaterial3D], roof_mat: Material, door_mat: Material, chimney_mat: Material) -> void:
	var v := _rng.randi() % wall_mats.size()
	var mi := MeshInstance3D.new()
	mi.mesh = _house_mesh(size, wall_mats[v], roof_mat, gable_mats[v])
	house.add_child(mi)
	# door on the road side (local -s * x)
	var dq := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.1, 2.2)
	dq.mesh = qm
	dq.material_override = door_mat
	dq.position = Vector3(-s * (size.x * 0.5 + 0.03), 0.5, _rng.randf_range(-0.25, 0.25) * size.z)
	dq.rotation.y = -s * PI * 0.5
	house.add_child(dq)
	if _rng.randf() < 0.6:
		var ch := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(0.7, 2.0, 0.7)
		ch.mesh = cb
		ch.material_override = chimney_mat
		ch.position = Vector3(_rng.randf_range(-0.25, 0.25) * size.x, size.y + 2.0, size.z * 0.3)
		house.add_child(ch)


## A bombed-out apartment block: four walls that end at ragged heights,
## no roof, a heap of rubble at its foot.
func _place_ruin(house: Node3D, size: Vector3, wall_mat: Material, rubble_mat: Material, s: float) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		var cols := int(maxf(1.0, roundf(a.distance_to(b) / 3.0)))
		var n := (a + b).normalized()
		for c in cols:
			var p0 := a.lerp(b, float(c) / cols)
			var p1 := a.lerp(b, float(c + 1) / cols)
			# each 3 m column of wall broke off at its own height
			var top := size.y - floorf(_rng.randf() * _rng.randf() * size.y / 3.0) * 3.0 - _rng.randf_range(0.0, 1.4)
			top = maxf(top, 2.0)
			var v0 := (size.y + 0.6) / 3.0
			var v1 := (size.y - top) / 3.0
			_quad_uv(st, [p0 + Vector3(0, -0.6, 0), p1 + Vector3(0, -0.6, 0), p1 + Vector3(0, top, 0), p0 + Vector3(0, top, 0)],
				[Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)], n)
	st.set_material(wall_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	house.add_child(mi)
	# a floor slab hanging on at mid height
	if size.y > 6.0:
		var slab := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(size.x * 0.9, 0.3, size.z * 0.6)
		slab.mesh = sm
		slab.material_override = rubble_mat
		slab.position = Vector3(0, 3.0 * _rng.randi_range(1, int(size.y / 3.0) - 1), -size.z * 0.15)
		slab.rotation.x = _rng.randf_range(-0.15, 0.15)
		house.add_child(slab)
	for r in 3:
		var rb := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(_rng.randf_range(1.0, 2.5), _rng.randf_range(0.5, 1.2), _rng.randf_range(1.0, 2.5))
		rb.mesh = bm
		rb.material_override = rubble_mat
		rb.position = Vector3(-s * (hx + 0.6), 0.0, _rng.randf_range(-hz, hz))
		rb.rotation = Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3))
		house.add_child(rb)


## Jungle ruins: a stepped stone shrine with a doorway and fallen blocks.
## Returns the height so the caller can size the collision box.
func _place_temple(house: Node3D, size: Vector3, mat: Material) -> float:
	var tiers := _rng.randi_range(2, 3)
	var y := -0.6
	var dims := Vector3(size.x, 0, size.z)
	for t in tiers:
		var h := _rng.randf_range(1.6, 2.4)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(dims.x, h, dims.z)
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(0, y + h * 0.5, 0)
		house.add_child(mi)
		y += h
		dims *= 0.72
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(1.4, 1.8, 0.1)
	door.mesh = dm
	door.material_override = TexGen.flat_material(Color(0.06, 0.07, 0.05))
	door.position = Vector3(0, y - 1.4, dims.z * 0.5 / 0.72 + 0.03)
	house.add_child(door)
	for r in 3:
		var rb := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(_rng.randf_range(0.8, 1.6), _rng.randf_range(0.6, 1.0), _rng.randf_range(0.8, 1.6))
		rb.mesh = bm2
		rb.material_override = mat
		rb.position = Vector3(_rng.randf_range(-1, 1) * size.x * 0.7, -0.3, _rng.randf_range(-1, 1) * size.z * 0.7)
		rb.rotation = Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf() * TAU, _rng.randf_range(-0.4, 0.4))
		house.add_child(rb)
	return y + 0.6


## House walls (UVs tile one 3 m storey per texture repeat), a gable roof
## running along local z, and plain gable ends.
func _house_mesh(size: Vector3, wall_mat: Material, roof_mat: Material, gable_mat: Material) -> ArrayMesh:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var y0 := -0.6
	var y1 := size.y
	var ridge := y1 + minf(size.x * 0.32, 2.8)
	var mesh := ArrayMesh.new()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		var tiles := maxf(1.0, roundf(a.distance_to(b) / 3.0))
		var vb := (y1 - y0) / 3.0
		_quad_uv(st, [a + Vector3(0, y0, 0), b + Vector3(0, y0, 0), b + Vector3(0, y1, 0), a + Vector3(0, y1, 0)],
			[Vector2(0, vb), Vector2(tiles, vb), Vector2(tiles, 0), Vector2(0, 0)], (a + b).normalized())
	st.set_material(wall_mat)
	st.commit(mesh)

	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var eave := 0.5
	var slope_len := Vector2(hx + eave, ridge - y1 + 0.25).length()
	for sx in [-1.0, 1.0]:
		var lo := Vector3(sx * (hx + eave), y1 - 0.25, 0)
		var hi := Vector3(0, ridge, 0)
		var dz := Vector3(0, 0, hz + 0.35)
		var out := (lo - hi).cross(dz).normalized()
		if out.y < 0.0:
			out = -out
		_quad_uv(st, [lo - dz, lo + dz, hi + dz, hi - dz],
			[Vector2(0, slope_len / 1.5), Vector2(size.z / 2.0, slope_len / 1.5), Vector2(size.z / 2.0, 0), Vector2(0, 0)], out)
	st.set_material(roof_mat)
	st.commit(mesh)

	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sz in [-1.0, 1.0]:
		var n := Vector3(0, 0, sz)
		_tri_uv(st, [Vector3(-hx, y1, sz * hz), Vector3(hx, y1, sz * hz), Vector3(0, ridge, sz * hz)],
			[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], n)
	st.set_material(gable_mat)
	st.commit(mesh)
	return mesh


func _quad_uv(st: SurfaceTool, v: Array, uv: Array, n: Vector3) -> void:
	_tri_uv(st, [v[0], v[1], v[2]], [uv[0], uv[1], uv[2]], n)
	_tri_uv(st, [v[0], v[2], v[3]], [uv[0], uv[2], uv[3]], n)


## Adds a triangle wound so its front face points along `n`.
func _tri_uv(st: SurfaceTool, v: Array, uv: Array, n: Vector3) -> void:
	var order := [0, 2, 1] if Geo.flipped(v[0], v[1], v[2], n) else [0, 1, 2]
	for k in order:
		st.set_normal(n)
		st.set_uv(uv[k])
		st.add_vertex(v[k])


## Little crowds behind tape at hairpins and at the jump.
func _build_spectators() -> void:
	if _theme() in ["wasteland", "moon"]:
		return  # nobody left to watch, or nobody without a spacesuit
	var n := points.size()
	# the crowd draws from its own generator; the stage's one still takes one
	# number per person as before, so trees and houses stay where they were
	var crowd_rng := RandomNumberGenerator.new()
	crowd_rng.seed = int(map["seed"]) + 11
	var crowd := Crowd.new(crowd_rng)
	var spots: Array[int] = []
	for i in n:
		if absf(_turn(i, 5)) > 1.0 and (spots.is_empty() or i - spots[spots.size() - 1] > 25):
			spots.append(i)
	for jump in _jumps:
		spots.append(index_at(jump[0] as float) + 4)
	for i in spots:
		var turn := _turn(i, 5)
		var inside := -1.0 if turn > 0.0 else 1.0  # crowd on the inside: safer and visible
		if absf(turn) < 0.3:
			inside = 1.0
		for c in 14:
			var k := wrap_index(i + _rng.randi_range(-6, 6))
			var off := widths[k] * 0.5 + VERGE + _rng.randf_range(4.0, 8.0)
			var pos := points[k] + _side(k) * inside * off
			pos.y = terrain_height(pos.x, pos.z) if _road_dist(pos.x, pos.z) > 14.0 or _cliff or _geo else points[k].y - 0.45
			var face := points[k] + Vector3(0, pos.y - points[k].y, 0)
			var hop := _rng.randi() % 3 == 0
			# inside a tight corner another part of the road can pass close by
			var near := nearest_index(pos, k)
			if distance_to_road(pos, near) < widths[near] * 0.5 + VERGE + 1.5 or _blocked(pos, near):
				continue
			if _geo and _geo.slope(pos.x, pos.z) > 0.45:
				continue  # nobody stands on a bank that steep
			crowd.person(Transform3D(Basis.looking_at(face - pos, Vector3.UP), pos), hop)
	var mi := crowd.make()
	if mi:
		add_child(mi)


func _build_trees() -> void:
	var col_shape := CylinderShape3D.new()
	col_shape.radius = 0.4
	col_shape.height = 3.0
	var trees := StaticBody3D.new()
	trees.name = "Trees"
	trees.set_meta("surface", "grass")
	add_child(trees)
	var wasteland := _theme() == "wasteland"
	var jungle := _theme() == "jungle"
	var landmark: Vector2 = Vector2(map["landmark"][0], map["landmark"][1]) if map.has("landmark") else Vector2(INF, INF)
	var placed := 0
	var tries := 0
	var n := points.size()
	var target_trees := int(650 * (map["forest"] as float))
	while placed < target_trees and tries < target_trees * 14:
		tries += 1
		var i := _rng.randi_range(0, n - 1)
		var forest := surfaces[i] == "gravel" or (map["forest"] as float) > 1.2
		# the gravel sections run through forest: denser and closer trees
		var off := _rng.randf_range(9.0, 45.0) if forest else _rng.randf_range(16.0, 110.0)
		if jungle:
			off = _rng.randf_range(7.0, 55.0)
		if forest == false and _rng.randf() < 0.4:
			continue
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var p := points[i] + _side(i) * side * off + Vector3(_rng.randf_range(-5, 5), 0, _rng.randf_range(-5, 5))
		var min_clear := widths[i] * 0.5 + VERGE + 2.5
		if _road_dist(p.x, p.z) < min_clear or _in_water(p.x, p.z) or Vector2(p.x, p.z).distance_to(landmark) < 34.0 				or _near_start(p):
			continue
		var nearest := nearest_index(p, i)
		if distance_to_road(p, nearest) < min_clear:
			continue
		if _blocked(p, nearest):
			continue  # inside a rock wall or over the edge
		p.y = terrain_height(p.x, p.z) - 0.2
		var mi := MeshInstance3D.new()
		if wasteland:
			mi.mesh = Trees.dead(_rng.randi_range(0, 3))
		elif jungle:
			var roll := _rng.randf()
			mi.mesh = Trees.palm(_rng.randi_range(0, 3)) if roll < 0.4 else (Trees.jungle(_rng.randi_range(0, 3))
				if roll < 0.8 else Trees.leafy(_rng.randi_range(0, 1)))
		elif _rng.randf() < (0.88 if forest else 0.45):
			mi.mesh = Trees.pine(_rng.randi_range(0, 3))
		else:
			mi.mesh = Trees.leafy(_rng.randi_range(0, 3))
		mi.position = p
		mi.scale = Vector3.ONE * _rng.randf_range(0.8, 1.5)
		mi.rotation.y = _rng.randf() * TAU
		_scatter_add(mi)
		if off < 40.0:
			var cs := CollisionShape3D.new()
			cs.shape = col_shape
			cs.position = p + Vector3(0, 1.5, 0)
			trees.add_child(cs)
		placed += 1
	if wasteland:
		_scatter_flush(trees)
		return
	# bushes along the verges (no collision, they're just scenery)
	for b in int((420 if jungle else 220) * (map["forest"] as float)):
		var i := _rng.randi_range(0, n - 1)
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var off := widths[i] * 0.5 + VERGE + _rng.randf_range(3.0, 14.0)
		var p := points[i] + _side(i) * side * off
		if _road_dist(p.x, p.z) < widths[i] * 0.5 + VERGE + 2.0 or _in_water(p.x, p.z) or _near_start(p):
			continue
		if _blocked(p, nearest_index(p, i)):
			continue
		p.y = terrain_height(p.x, p.z) - 0.1
		var mi := MeshInstance3D.new()
		mi.mesh = Trees.fern(_rng.randi_range(0, 3)) if jungle and _rng.randf() < 0.7 else Trees.bush(_rng.randi_range(0, 2))
		mi.position = p
		mi.scale = Vector3.ONE * _rng.randf_range(0.7, 1.4)
		mi.rotation.y = _rng.randf() * TAU
		_scatter_add(mi)
	_scatter_flush(trees)


## Queue a placed scenery mesh for batching (and free the temporary node).
func _scatter_add(mi: MeshInstance3D) -> void:
	if not _scatter.has(mi.mesh):
		_scatter[mi.mesh] = []
	_scatter[mi.mesh].append(mi.transform)
	mi.free()


func _scatter_flush(parent: Node3D) -> void:
	for mesh in _scatter:
		var xfs: Array = _scatter[mesh]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		parent.add_child(mmi)
	_scatter.clear()


func _build_cones() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = 0.28
	mesh.height = 0.75
	mesh.radial_segments = 6
	var mat := TexGen.material(TexGen.stripes(Color(1.0, 0.4, 0.05), Color(1, 1, 1), 8), 0.7)
	var shape := CylinderShape3D.new()
	shape.radius = 0.25
	shape.height = 0.75
	if _theme() == "wasteland":
		# rusty oil drums instead of cones, some still glowing
		mesh = CylinderMesh.new()
		mesh.top_radius = 0.3
		mesh.bottom_radius = 0.3
		mesh.height = 0.9
		mesh.radial_segments = 8
		mat = TexGen.material(TexGen.barrel(), 0.8)
		shape.radius = 0.3
		shape.height = 0.9
	for k in range(4, 30, 4):
		for s in [-1.0, 1.0]:
			var cone := RigidBody3D.new()
			cone.mass = 4.0
			cone.collision_layer = 8
			cone.collision_mask = 1 | 2 | 8
			cone.set_meta("surface", "asphalt")
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			cone.add_child(mi)
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cone.add_child(cs)
			var c := wrap_index(start_index + k)
			cone.position = points[c] + _side(c) * s * (widths[c] * 0.5 - 0.5) + Vector3(0, 0.45, 0)
			add_child(cone)
			if _theme() == "wasteland" and _rng.randf() < 0.5:
				glow_lid(mi)


## Glowing green lid on a wasteland oil drum.
func glow_lid(barrel: MeshInstance3D) -> void:
	var lid := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.26
	cm.bottom_radius = 0.26
	cm.height = 0.04
	cm.radial_segments = 8
	lid.mesh = cm
	lid.material_override = TexGen.flat_material(Color(0.5, 1.0, 0.2), 0.5, true)
	lid.position.y = 0.46
	barrel.add_child(lid)


## Ranges of faceted peaks on the skyline (see Mountains), each one to three
## overlapping mountains spread along the horizon.
func _build_mountains() -> void:
	var sty := Mountains.style(_theme())
	var mat := Mountains.material(sty)
	var haze: Color = Conditions.palette(_theme(), rain)["fog"]
	var tall := 2.0 if _theme() == "alpine" else 1.0  # the pass is ringed by big peaks
	# own generator, so what's built after the mountains doesn't move
	var rng := RandomNumberGenerator.new()
	rng.seed = int(map["seed"]) + 13
	for k in 22:
		var a := TAU * k / 22.0 + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(900.0, 1150.0) * _world_half / 560.0
		var pos := Vector3(_center.x + cos(a) * r, -10.0, _center.y + sin(a) * r)
		if _in_water(pos.x, pos.z, 200.0):
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# one main peak and up to two lower ones beside it
		var along := Vector3(-sin(a), 0, cos(a))
		var peaks := rng.randi_range(1, 3)
		for m in peaks:
			var h := rng.randf_range(160.0, 360.0) * (1.0 if m == 0 else rng.randf_range(0.55, 0.8)) * tall
			var off := along * (0.0 if m == 0 else rng.randf_range(-1.0, 1.0) * 220.0) + Vector3(cos(a), 0, sin(a)) * m * 60.0
			Mountains.add(st, rng, off, h, rng.randf_range(180.0, 300.0) * (h / 300.0 + 0.3), sty, haze, along)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = pos
		add_child(mi)
	for i in 22 * 13:  # what the old cone mountains drew from the stage's generator
		_rng.randf()


# --------------------------------------------------------------------------- water, tunnel, wrecks

func _water_level() -> float:
	return map.get("water_level", -1.5)


## 0 outside the water areas, rising to 1 a few metres in from their edge.
func _water_depth(x: float, z: float) -> float:
	var best := 0.0
	for r in map.get("water", []):
		var inside := minf(minf(x - (r[0] as float), (r[2] as float) - x), minf(z - (r[1] as float), (r[3] as float) - z))
		best = maxf(best, smoothstep(-2.0, 14.0, inside))
	return best


func _build_water() -> void:
	if not map.has("water"):
		return
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	if _theme() == "wasteland":
		mat.albedo_color = Color(0.20, 0.26, 0.10)  # oily, faintly green
		mat.emission_enabled = true
		mat.emission = Color(0.05, 0.10, 0.02)
	elif _theme() == "jungle":
		# muddy river: see-through enough to make out the ford's stones
		mat.albedo_color = Color(0.17, 0.20, 0.10, 0.84)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		mat.albedo_color = Color(0.12, 0.30, 0.55)
	mat.roughness = 0.12
	mat.metallic_specular = 0.9
	if _theme() == "jungle":
		mat.roughness = 0.45
		mat.metallic_specular = 0.25
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(_center.x, _water_level(), _center.y)
	add_child(mi)


## Wooden bridges over rivers: wherever the route is on the "wood" surface,
## plank railings both sides (solid) and posts down into the water.
func _build_bridges() -> void:
	var n := points.size()
	var body: StaticBody3D = null
	var wood := TexGen.material(TexGen.planks(), 1.0)
	var dark := TexGen.material(TexGen.bark(), 1.0)
	for i in n:
		if surfaces[i] != "wood":
			continue
		if body == null:
			body = StaticBody3D.new()
			body.name = "Bridges"
			body.set_meta("surface", "wood")
			add_child(body)
		var b := wrap_index(i + 1)
		var seg := points[i].distance_to(points[b])
		var dir := (points[b] - points[i]).normalized()
		for s in [-1.0, 1.0]:
			var edge: Vector3 = (points[i] + points[b]) * 0.5 + _side(i) * s * (widths[i] * 0.5 + 0.2)
			var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), edge + Vector3(0, 0.55, 0))
			for part in [[Vector3(0.2, 0.18, seg + 0.05), Vector3(0, 0.35, 0), wood], [Vector3(0.12, 0.12, seg + 0.05), Vector3(0, -0.1, 0), wood]]:
				var mi := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = part[0]
				mi.mesh = bm
				mi.material_override = part[2]
				mi.transform = xf * Transform3D(Basis(), part[1])
				body.add_child(mi)
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(0.3, 1.2, seg + 0.05)
			cs.shape = shape
			cs.transform = xf
			body.add_child(cs)
			if i % 2 == 0:
				# post from the rail down into the river bed
				var depth := points[i].y - (_water_level() - 4.0)
				var post := MeshInstance3D.new()
				var pm := BoxMesh.new()
				pm.size = Vector3(0.3, depth + 1.0, 0.3)
				post.mesh = pm
				post.material_override = dark
				post.position = points[i] + _side(i) * s * (widths[i] * 0.5 + 0.2) + Vector3(0, 0.5 - (depth + 1.0) * 0.5 + 0.5, 0)
				body.add_child(post)
		# cross beam under the deck
		var beam := MeshInstance3D.new()
		var beam_mesh := BoxMesh.new()
		beam_mesh.size = Vector3(widths[i] + 0.8, 0.35, 0.4)
		beam.mesh = beam_mesh
		beam.material_override = dark
		beam.transform = frame(i).translated(Vector3(0, -0.35, 0))
		body.add_child(beam)


## Red and white kerbs on the edges of the circuit's corners.
func _build_kerbs() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	var red := Color(0.85, 0.12, 0.10)
	var white := Color(0.95, 0.95, 0.92)
	for i in n:
		if absf(_turn(i, 3)) < 0.09 or surfaces[i] == "gravel":
			continue
		var b := wrap_index(i + 1)
		for s in [-1.0, 1.0]:
			for k in 3:
				var f0 := k / 3.0
				var f1 := (k + 1) / 3.0
				var pa := points[i].lerp(points[b], f0)
				var pb := points[i].lerp(points[b], f1)
				var sa: Vector3 = _side(i).lerp(_side(b), f0).normalized() * s
				var sb: Vector3 = _side(i).lerp(_side(b), f1).normalized() * s
				var ia: Vector3 = pa + sa * (widths[i] * 0.5 - 0.3) + Vector3(0, 0.03, 0)
				var oa: Vector3 = pa + sa * (widths[i] * 0.5 + 0.9) + Vector3(0, -0.02, 0)
				var ib: Vector3 = pb + sb * (widths[i] * 0.5 - 0.3) + Vector3(0, 0.03, 0)
				var ob: Vector3 = pb + sb * (widths[i] * 0.5 + 0.9) + Vector3(0, -0.02, 0)
				var c := red if (i * 3 + k) % 2 == 0 else white
				for v in [ia, oa, ob, ia, ob, ib]:
					st.set_color(c)
					st.add_vertex(v)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.7
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "Kerbs"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## A big stepped pyramid deep in the jungle, seen over the treetops.
func _build_pyramid(at: Array) -> void:
	var x: float = at[0]
	var z: float = at[1]
	var base: float = at[2] if at.size() > 2 else 34.0
	var ground := terrain_height(x, z) - 1.0
	var mat := TexGen.material(TexGen.stone_wall(), 1.0, Color(0.72, 0.78, 0.60))
	mat.uv1_scale = Vector3(6, 4, 1)
	var stairs := TexGen.flat_material(Color(0.46, 0.48, 0.38), 1.0)
	var body := StaticBody3D.new()
	body.name = "Pyramid"
	add_child(body)
	var w := base
	var y := ground
	for t in 6:
		var h := 4.0
		for part in [[Vector3(w, h, w), Vector3.ZERO, mat], [Vector3(4.0, h, 2.0), Vector3(0, 0, w * 0.5 + 0.8), stairs]]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = part[0]
			mi.mesh = bm
			mi.material_override = part[2]
			mi.position = Vector3(x, y + h * 0.5, z) + (part[1] as Vector3)
			body.add_child(mi)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(w, h, w)
		cs.shape = shape
		cs.position = Vector3(x, y + h * 0.5, z)
		body.add_child(cs)
		y += h
		w -= 5.0
	var shrine := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(5.0, 4.0, 5.0)
	shrine.mesh = sm
	shrine.material_override = mat
	shrine.position = Vector3(x, y + 2.0, z)
	body.add_child(shrine)
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(1.6, 2.4, 0.1)
	door.mesh = dm
	door.material_override = TexGen.flat_material(Color(0.05, 0.06, 0.04))
	door.position = Vector3(x, y + 1.2, z + 2.53)
	body.add_child(door)
	# vines and trees growing out of the terraces
	for k in 12:
		var tier := _rng.randi_range(0, 3)
		var r := (base - 5.0 * tier) * 0.5 - 1.2  # on the terrace above this tier
		var along := _rng.randf_range(-r, r)
		var off := [Vector2(r, along), Vector2(-r, along), Vector2(along, r), Vector2(along, -r)][k % 4] as Vector2
		var mi := MeshInstance3D.new()
		mi.mesh = Trees.fern(k % 4) if k % 3 else Trees.palm(k % 4)
		mi.position = Vector3(x + off.x, ground + 4.0 * (tier + 1) - 0.1, z + off.y)
		mi.scale = Vector3.ONE * (1.4 if k % 3 else 0.7)
		body.add_child(mi)


## The tunnel under the old hotel: thick walls, a roof that has caved in
## here and there (letting light through), rubble against the walls and a
## few dim lamps still burning.
func _build_tunnel() -> void:
	var span: Array = map["tunnel"]
	var i0 := index_at(span[0] as float)
	var i1 := index_at(span[1] as float)
	var concrete := TexGen.material(TexGen.concrete(), 1.0, Color(0.7, 0.68, 0.64))
	var roof_mat := TexGen.material(TexGen.concrete(), 1.0, Color(0.45, 0.43, 0.40))
	roof_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lamp_mat := TexGen.flat_material(Color(1.0, 0.7, 0.35), 0.5, true)
	var body := StaticBody3D.new()
	body.name = "Tunnel"
	body.set_meta("surface", "asphalt")
	add_child(body)
	const H := 6.0
	var step := 2
	var i := i0
	while i < i1:
		var j := mini(i + step, i1)
		var mid := (points[i] + points[j]) * 0.5
		var flat := (points[j] - points[i])
		var seg_len := flat.length() + 0.4
		flat.y = 0.0
		var bas := Basis.looking_at(flat.normalized(), Vector3.UP)
		var side := _side(i)
		var hw := widths[i] * 0.5 + 1.2
		for s in [-1.0, 1.0]:
			var wall := Transform3D(bas, mid + side * s * (hw + 0.5) + Vector3(0, H * 0.5 - 0.6, 0))
			_tunnel_box(body, Vector3(1.0, H + 1.2, seg_len), wall, concrete, true)
		var collapsed := _rng.randf() < 0.16 and i > i0 + 6 and j < i1 - 6
		if collapsed:
			# a slab hanging down into the hole, and rubble along one wall
			var s2 := 1.0 if _rng.randf() < 0.5 else -1.0
			var hang := Transform3D(bas.rotated(flat.normalized(), s2 * 0.5), mid + side * s2 * (hw * 0.6) + Vector3(0, H - 0.8, 0))
			_tunnel_box(body, Vector3(hw * 0.9, 0.5, seg_len * 0.8), hang, roof_mat, false)
			var rub := Transform3D(bas.rotated(Vector3.UP, _rng.randf_range(-0.3, 0.3)), mid + side * s2 * (hw - 0.8) + Vector3(0, 0.2, 0))
			_tunnel_box(body, Vector3(1.4, 1.0, seg_len * 0.7), rub, roof_mat, true)
		else:
			_tunnel_box(body, Vector3(hw * 2.0 + 2.0, 0.8, seg_len), Transform3D(bas, mid + Vector3(0, H + 0.4, 0)), roof_mat, false)
			if (i - i0) % 8 == 0:
				_tunnel_box(body, Vector3(0.8, 0.12, 0.4), Transform3D(bas, mid + Vector3(0, H - 0.05, 0)), lamp_mat, false)
		i = j


func _tunnel_box(body: StaticBody3D, size: Vector3, xf: Transform3D, mat: Material, solid: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = xf
	body.add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.transform = xf
		body.add_child(cs)


## Burnt-out cars abandoned at the roadside: the same models as the
## playable ones, rusted, some on their roofs.
func _build_wrecks() -> void:
	var n := points.size()
	var body := StaticBody3D.new()
	body.name = "Wrecks"
	body.set_meta("surface", "grass")
	add_child(body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 1.2, 4.0)
	var rust := [Color(0.62, 0.36, 0.2), Color(0.45, 0.3, 0.2), Color(0.7, 0.52, 0.34), Color(0.36, 0.32, 0.28)]
	var placed := 0
	var tries := 0
	# wrecks are the rally cars, faded under rust and dented
	var shells := Cars.LIST.filter(func(c: Dictionary) -> bool: return c.get("type", "car") == "car")
	while placed < 26 and tries < 300:
		tries += 1
		var i := _rng.randi_range(10, n - 10)
		if map.has("tunnel") and frac_of(i) > (map["tunnel"][0] as float) - 0.01 and frac_of(i) < (map["tunnel"][1] as float) + 0.01:
			continue
		var s := 1.0 if _rng.randf() < 0.5 else -1.0
		var off := widths[i] * 0.5 + VERGE + _rng.randf_range(1.5, 5.0)
		var p := points[i] + _side(i) * s * off
		if _road_dist(p.x, p.z) < off - 1.0 or _in_water(p.x, p.z, 3.0):
			continue
		var m := CarModel.new()
		m.spec = shells[_rng.randi() % shells.size()]
		add_child(m)
		m.build()
		_burn_out(m, rust[_rng.randi() % rust.size()])
		var flipped := _rng.randf() < 0.25
		var bas := frame(i).basis.rotated(Vector3.UP, _rng.randf_range(-0.8, 0.8))
		if flipped:
			bas = bas * Basis(Vector3.FORWARD, PI)
		var y := terrain_height(p.x, p.z)
		m.transform = Transform3D(bas, Vector3(p.x, y + (0.95 if flipped else 0.55), p.z))
		for k in 3:  # crumpled where it went off
			var hit := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.2, 0.5), _rng.randf_range(-2.0, 2.0))
			m.dent(m.to_global(hit), (m.global_position - m.to_global(hit)).normalized(), 0.35, 0.9)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(bas, Vector3(p.x, y + 0.6, p.z))
		body.add_child(cs)
		placed += 1


## Fade a wreck under rust: every surface keeps its texture but turns rusty
## and matte, and the lamps go dark.
func _burn_out(node: Node, rust: Color) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var gi := mi as MeshInstance3D
		if gi.mesh == null:
			continue
		for i in gi.mesh.get_surface_count():
			var m := gi.get_active_material(i) as StandardMaterial3D
			if m == null:
				continue
			var r := m.duplicate() as StandardMaterial3D
			r.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			r.albedo_color = m.albedo_color * (rust if m.albedo_texture else Color(0.25, 0.22, 0.2))
			r.roughness = 1.0
			r.metallic = 0.0
			gi.set_surface_override_material(i, r)
