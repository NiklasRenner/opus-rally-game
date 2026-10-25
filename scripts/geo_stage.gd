class_name GeoStage
extends RefCounted
## A stage lifted from a real road: the route and its height profile from
## OpenStreetMap, the land round it from a satellite elevation model, baked
## into data/stages/<id>.json and .bin by tools/real_stage/bake_stage.py.
## The map names the file with "geo". TrackBuilder takes the route from here
## and asks for the terrain heights: the real ground, with the road cut into
## it (banks no steeper than CUT/FILL), only where the near grid reaches the
## road's band; beyond that a coarse, unsolid mesh of the real mountains runs
## out to the horizon. Also builds guard posts along the drops and a forest
## over the slopes.

const CUT := 1.2  # steepest bank cut up from the road edge (rise per metre)
const FILL := 1.0  # and built down from it
const BANK_START := 3.0  # metres of level ground past the verge before a bank
const REACH := 64.0  # how far a bank can reach from the road
const DROP := 4.0  # ground this far below the road just past the verge makes the side a drop

var track: TrackBuilder
var data: Dictionary
var points: Array[Vector2] = []
var profile := PackedFloat32Array()
var profile_step := 2.0
var lead := 0  # control points before the start line
var tail := 0  # and after the finish line
var near_x0 := 0.0
var near_z0 := 0.0
var near_n := 0
var band := 300.0
## Per near grid cell: the real ground (game metres, 0 at the start line) and
## the distance to the road in 4 m steps.
var dem := PackedFloat32Array()
var band_dist := PackedByteArray()
var far_x0 := 0.0
var far_z0 := 0.0
var far_n := 0
var far_cell := 96.0
var far := PackedFloat32Array()
## Per road sample: +1 the ground drops away on the right, -1 on the left, 0 neither.
var side := PackedFloat32Array()

static var _cache := {}


## The stage baked under data/stages/<id> (read once, then shared).
static func open(id: String) -> GeoStage:
	if not _cache.has(id):
		var g := GeoStage.new()
		g._load("res://data/stages/" + id)
		_cache[id] = g
	return _cache[id]


func _load(path: String) -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(path + ".json"))
	for p in data["points"]:
		points.append(Vector2(p[0], p[1]))
	profile = PackedFloat32Array(data["profile"])
	profile_step = data["profile_step"]
	lead = data["lead"]
	tail = data["tail"]
	var nr: Dictionary = data["near"]
	near_x0 = nr["x0"]
	near_z0 = nr["z0"]
	near_n = nr["n"]
	band = nr["band"]
	var fr: Dictionary = data["far"]
	far_x0 = fr["x0"]
	far_z0 = fr["z0"]
	far_n = fr["n"]
	far_cell = fr["cell"]
	var raw := FileAccess.get_file_as_bytes(path + ".bin")
	var lo: float = data["height_min"]
	var nn := near_n * near_n
	dem.resize(nn)
	for k in nn:
		dem[k] = lo + raw.decode_u16(k * 2) * 0.1
	band_dist = raw.slice(nn * 2, nn * 3)
	far.resize(far_n * far_n)
	for k in far_n * far_n:
		far[k] = lo + raw.decode_u16(nn * 3 + k * 2) * 0.1


## Height of the road a fraction of the way along the whole route (lead-in
## to run-out), from the profile.
func road_height(route_frac: float, route_length: float) -> float:
	var f := clampf(route_frac * route_length / profile_step, 0.0, profile.size() - 1.001)
	var i := int(f)
	var t := f - i
	var a := profile[maxi(i - 1, 0)]
	var b := profile[i]
	var c := profile[i + 1]
	var d := profile[mini(i + 2, profile.size() - 1)]
	var v := TrackBuilder._catmull(Vector2(0, a), Vector2(0, b), Vector2(0, c), Vector2(0, d), t)
	return v.y


func band_distance(k: int) -> float:
	return band_dist[k] * 4.0


# --------------------------------------------------------------------------- terrain

## Terrain heights for TrackBuilder's grid (the same grid as the baked one).
## The real ground, held between two limits from every road sample nearby:
## no higher than a cut bank rising from its verge, no lower than an
## embankment falling from it, so the road sits in the hillside on a level
## shelf. Both limits are continuous, so stacked hairpins don't leave steps;
## where they cross (two roads close above each other) the ground takes the
## middle.
func heights() -> PackedFloat32Array:
	var gn := near_n
	var cell := TrackBuilder.CELL
	var hi := PackedFloat32Array()
	hi.resize(gn * gn)
	hi.fill(INF)
	var lo := PackedFloat32Array()
	lo.resize(gn * gn)
	lo.fill(-INF)
	var pts := track.points
	var r := int(ceil(REACH / cell))
	for i in range(0, pts.size(), 2):
		var p := pts[i]
		var e := track.widths[i] * 0.5 + TrackBuilder.VERGE + BANK_START
		var y := p.y - 0.3
		var cx := int(round((p.x - near_x0) / cell))
		var cz := int(round((p.z - near_z0) / cell))
		for gz in range(maxi(cz - r, 0), mini(cz + r, gn - 1) + 1):
			var dz := near_z0 + gz * cell - p.z
			for gx in range(maxi(cx - r, 0), mini(cx + r, gn - 1) + 1):
				var dx := near_x0 + gx * cell - p.x
				var d := sqrt(dx * dx + dz * dz)
				if d > REACH:
					continue
				var x := maxf(d - e, 0.0)
				var steep := 0.03 * x * x  # past the reach the limits are out of the way
				var k := gz * gn + gx
				hi[k] = minf(hi[k], y + CUT * x + steep)
				lo[k] = maxf(lo[k], y - FILL * x - steep)
	var out := PackedFloat32Array()
	out.resize(gn * gn)
	for k in gn * gn:
		var h := dem[k]
		if lo[k] > hi[k]:
			h = (lo[k] + hi[k]) * 0.5
		else:
			h = clampf(h, lo[k], hi[k])
		out[k] = h
	return out


## Is near grid cell (gx, gz) drawn? Inside the band round the road.
func cell_drawn(gx: int, gz: int) -> bool:
	var gn := near_n
	for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		if band_dist[mini(gz + o.y, gn - 1) * gn + mini(gx + o.x, gn - 1)] * 4.0 < band:
			return true
	return false


## Which side of the road the ground falls away on, per sample: the ground
## a little past the verge well below the road.
func find_drops() -> void:
	side.resize(track.count())
	side.fill(0.0)
	for i in track.count():
		var p := track.points[i]
		var out := track.widths[i] * 0.5 + TrackBuilder.VERGE + 5.0
		for s in [-1.0, 1.0]:
			var q: Vector3 = p + track._side(i) * s * out
			if track.ground_height(q.x, q.z) < p.y - DROP:
				side[i] = s
	# smooth out flickers: a drop shorter than 4 samples isn't one
	var i := 0
	while i < side.size():
		var j := i
		while j + 1 < side.size() and side[j + 1] == side[i]:
			j += 1
		if side[i] != 0.0 and j - i < 4:
			for k in range(i, j + 1):
				side[k] = 0.0
		i = j + 1


## Is there no room for a tree or a fan at p? Over a drop close to the road,
## or on a bank too steep to stand on.
func blocked(p: Vector3, hint: int) -> bool:
	var i := track.nearest_index(p, hint)
	if side[i] != 0.0:
		var sd := track._side(i)
		var across := ((p.x - track.points[i].x) * sd.x + (p.z - track.points[i].z) * sd.z) * side[i]
		if across > 0.0 and across < track.widths[i] * 0.5 + TrackBuilder.VERGE + 6.0:
			return true
	return slope(p.x, p.z) > 1.3


## Steepness of the terrain (rise per metre) round a point.
func slope(x: float, z: float) -> float:
	var h := track.ground_height(x, z)
	var s := 0.0
	for o in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
		s = maxf(s, absf(track.ground_height(x + o.x, z + o.y) - h) / 3.0)
	return s


# --------------------------------------------------------------------------- build

func build() -> void:
	_build_far()
	var n := track.count()
	var i := 0
	while i < n:
		if side[i] == 0.0:
			i += 1
			continue
		var j := i
		while j + 1 < n and side[j + 1] == side[i]:
			j += 1
		CliffRoad.guard_posts(track, i, j, side[i])
		i = j + 1
	_build_forest()


## The real mountains out to the horizon: the coarse grid, flat shaded, with
## a hole where the near terrain covers it. Its cells that only partly
## overlap the near terrain sit a little lower so the near ground wins.
func _build_far() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var per := roundi(far_cell / TrackBuilder.CELL)  # near cells per far cell
	var ox := roundi((near_x0 - far_x0) / far_cell)
	var oz := roundi((near_z0 - far_z0) / far_cell)
	var span := (near_n - 1) / per
	var fn := far_n
	for z in fn - 1:
		for x in fn - 1:
			var sink := 0.0
			var nx := x - ox
			var nz := z - oz
			if nx >= 0 and nz >= 0 and nx < span and nz < span:
				var covered := 0
				var cells := 0
				for gz in range(nz * per, (nz + 1) * per):
					for gx in range(nx * per, (nx + 1) * per):
						cells += 1
						if cell_drawn(gx, gz):
							covered += 1
				if covered == cells:
					continue
				if covered > 0:
					sink = 1.2
			for g in [Vector2i(x, z), Vector2i(x + 1, z), Vector2i(x + 1, z + 1),
					Vector2i(x, z), Vector2i(x + 1, z + 1), Vector2i(x, z + 1)]:
				var h := far[g.y * fn + g.x] - sink
				st.set_color(_far_color(g.x, g.y, h))
				st.set_uv(Vector2(g.x, g.y) * 0.5)
				st.add_vertex(Vector3(far_x0 + g.x * far_cell, h, far_z0 + g.y * far_cell))
	st.generate_normals()
	var mat := TexGen.material(TexGen.grass(), 1.0)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "FarTerrain"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	track.add_child(mi)


## Forest green on the slopes, grey rock where it's steep, snow up high.
func _far_color(gx: int, gz: int, h: float) -> Color:
	var fn := far_n
	var steep := 0.0
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q := Vector2i(clampi(gx + o.x, 0, fn - 1), clampi(gz + o.y, 0, fn - 1))
		steep = maxf(steep, absf(far[q.y * fn + q.x] - h) / far_cell)
	var k := gz * fn + gx
	var forest := Color(0.22, 0.36, 0.20).lerp(Color(0.30, 0.42, 0.22), clampf(sin(k * 0.37) * 0.5 + 0.5, 0.0, 1.0) * 0.5)
	var rock := Color(0.55, 0.53, 0.50)
	var c := forest.lerp(rock, smoothstep(0.7, 1.1, steep))
	var snow_line: float = track.map.get("snow_line", INF)
	if h > snow_line:
		c = c.lerp(Color(0.93, 0.95, 1.0), smoothstep(snow_line, snow_line + 320.0, h) * (1.0 - 0.6 * smoothstep(0.5, 1.0, steep)))
	return c


## Pines over the hillsides of the band round the road (scenery: the ones
## close enough to hit are TrackBuilder's), thinning out on steep rock and
## up in the snow.
func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(track.map["seed"]) + 77
	var noise := FastNoiseLite.new()
	noise.seed = int(track.map["seed"]) + 3
	noise.frequency = 0.012
	var snow_line: float = track.map.get("snow_line", INF)
	var span := (near_n - 1) * TrackBuilder.CELL
	var target := int(track.map.get("forest_band", 3000))
	var placed := 0
	for tries in target * 6:
		if placed >= target:
			break
		var x := near_x0 + rng.randf() * span
		var z := near_z0 + rng.randf() * span
		var gx := int((x - near_x0) / TrackBuilder.CELL)
		var gz := int((z - near_z0) / TrackBuilder.CELL)
		var d := band_distance(gz * near_n + gx)
		if d < 40.0 or d > band - 12.0:
			continue
		if noise.get_noise_2d(x, z) < -0.25:
			continue  # clearings
		var y := track.ground_height(x, z)
		if slope(x, z) > 1.1 or (y > snow_line and rng.randf() < smoothstep(snow_line, snow_line + 60.0, y)):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = Trees.pine(rng.randi_range(0, 3))
		mi.position = Vector3(x, y - 0.3, z)
		mi.scale = Vector3.ONE * rng.randf_range(1.0, 1.8)
		mi.rotation.y = rng.randf() * TAU
		track._scatter_add(mi)
		placed += 1
