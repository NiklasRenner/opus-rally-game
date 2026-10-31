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
const BANK_WIDTH := 44.0  # how far the banks along the road reach out from its centre
## Rings of a bank's cross-section, as fractions of the way out from the verge.
const BANK_RINGS := [0.0, 0.07, 0.17, 0.32, 0.5, 0.72, 1.0]
const WALL_DROP := 6.0  # ground this far below the verge 3 m out gets a retaining wall instead of a bank
const BUCKET := 4.0  # spatial hash for height queries on the banks
const BUILT_FORMAT := 1  # bump when what save_built() writes changes
const SOURCES := ["res://scripts/geo_stage.gd", "res://scripts/track_builder.gd"]  # the code the built ground comes from

var track: TrackBuilder
var data: Dictionary
var points: Array[Vector2] = []
var profile := PackedFloat32Array()
var profile_step := 2.0
var cambers := PackedFloat32Array()  # the road's camber along the route, profile_step apart (empty: flat)
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
## The banks' triangles (and the road's, for height queries), and which of
## them lie in each BUCKET square.
var _tris := PackedVector3Array()
var _hash := {}
var _on_road := PackedByteArray()  # per triangle: 1 the road's, 0 a bank's
var _tri_at := PackedInt32Array()  # per triangle: the road sample it belongs to
var _box := PackedFloat32Array()  # per triangle: min x, max x, min z, max z (a little over)
var _bank_arrays: Array = []  # the banks' mesh
var _id := ""

static var _cache := {}


## The stage baked under data/stages/<id> (read once, then shared).
static func open(id: String) -> GeoStage:
	if not _cache.has(id):
		var g := GeoStage.new()
		g._id = id
		g._load("res://data/stages/" + id)
		_cache[id] = g
	return _cache[id]


func _load(path: String) -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(path + ".json"))
	for p in data["points"]:
		points.append(Vector2(p[0], p[1]))
	profile = PackedFloat32Array(data["profile"])
	profile_step = data["profile_step"]
	cambers = PackedFloat32Array(data.get("camber", []))
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


## The road's camber (rise per metre to its right) a fraction of the way
## along the whole route.
func camber_at(route_frac: float, route_length: float) -> float:
	if cambers.is_empty():
		return 0.0
	var f := clampf(route_frac * route_length / profile_step, 0.0, cambers.size() - 1.001)
	var i := int(f)
	return lerpf(cambers[i], cambers[i + 1], f - i)


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
	hi.fill(1e6)
	var lo := PackedFloat32Array()
	lo.resize(gn * gn)
	lo.fill(-1e6)
	var pts := track.points
	var r := int(ceil(REACH / cell))
	for i in range(0, pts.size(), 2):
		var p := pts[i]
		var e := track.widths[i] * 0.5 + TrackBuilder.VERGE + BANK_START
		var y := p.y - 0.3 - absf(track.camber[i]) * track.widths[i] * 0.5  # (the lower edge of a cambered road)
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


## The real ground under a point, from the baked grid (no road cut).
func natural(x: float, z: float) -> float:
	return _bilinear(dem, x, z)


func _bilinear(grid: PackedFloat32Array, x: float, z: float) -> float:
	var gn := near_n
	var fx := clampf((x - near_x0) / TrackBuilder.CELL, 0.0, gn - 1.001)
	var fz := clampf((z - near_z0) / TrackBuilder.CELL, 0.0, gn - 1.001)
	var gx := int(fx)
	var gz := int(fz)
	fx -= gx
	fz -= gz
	var a := lerpf(grid[gz * gn + gx], grid[gz * gn + gx + 1], fx)
	var b := lerpf(grid[(gz + 1) * gn + gx], grid[(gz + 1) * gn + gx + 1], fx)
	return lerpf(a, b, fz)


## The banks: a mesh that follows the road out to BANK_WIDTH on each side,
## so the verge runs straight into the hillside however coarse the grid is.
## Each cross-section starts at the verge's outer edge, climbs a cut bank or
## falls down an embankment (no steeper than CUT/FILL) to the real ground,
## and ends just under TrackBuilder's grid. Where the ground drops away too
## steeply for an embankment, a stone retaining wall holds the road up.
## Sections are cut short on the inside of tight bends and where another
## part of the road passes close by, so neighbouring banks never fold over.
## Builds the mesh and its collision (see also fit_grid()).
func build_banks() -> void:
	# (the stage is shared between loads: start from nothing each time)
	_tris.clear()
	_hash.clear()
	_on_road.clear()
	_tri_at.clear()
	_box.clear()
	var n := track.count()
	var pts := track.points
	var caps := [_bank_caps(-1.0), _bank_caps(1.0)]
	var walls := [_walls(-1.0, caps[0]), _walls(1.0, caps[1])]
	# every section's ring points: sections[side][i] = Array[Vector3]
	var sections := [[], []]
	for si in 2:
		var s := -1.0 if si == 0 else 1.0
		var cap: PackedFloat32Array = caps[si]
		var wall: PackedByteArray = walls[si]
		for i in n:
			var p := pts[i]
			var sd := track._side(i) * s
			var e := track.widths[i] * 0.5 + TrackBuilder.VERGE
			var y0 := track.road_y(i, s * e) - 0.5
			var ring: Array[Vector3] = []
			var base := y0  # where the slope below starts (the foot of a wall)
			var base_x := 0.0
			for k in BANK_RINGS.size():
				var f: float = BANK_RINGS[k]
				var x := (cap[i] - e) * f
				if wall[i] and k > 0:
					# the wall's foot just out from the verge, the bank beyond it
					x = 0.35 + (cap[i] - e - 0.35) * (f - (BANK_RINGS[1] as float)) / (1.0 - (BANK_RINGS[1] as float))
				var q := p + sd * (e + x)
				var h := y0
				if k > 0:
					var nat := natural(q.x, q.z)
					if k == 1 and wall[i]:
						h = clampf(nat, y0 - 18.0, y0 - 1.0)
						base = h
						base_x = x
					else:
						h = clampf(nat, base - FILL * (x - base_x), y0 + CUT * x)
					# out at the edge it eases onto the grid, finishing just under it
					var g := track.ground_height(q.x, q.z) - 0.25
					h = lerpf(h, g, smoothstep(0.45, 1.0, f))
				q.y = h
				ring.append(q)
			# a bank only climbs (a cutting) or only falls (an embankment), so
			# it never folds back over itself; the outer ring stays on the grid
			# and the rings inside it give way to it. Which way is the outer
			# ring's call: going by a bump near the road instead would drag the
			# whole bank up or down to the grid in one step at the verge.
			var falling := ring[ring.size() - 1].y < y0
			for k in range(2, BANK_RINGS.size() - 1):
				var prev := ring[k - 1].y
				ring[k].y = minf(ring[k].y, prev) if falling else maxf(ring[k].y, prev)
			for k in range(BANK_RINGS.size() - 2, 0, -1):
				var next := ring[k + 1].y
				ring[k].y = maxf(ring[k].y, next) if falling else minf(ring[k].y, next)
			sections[si].append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for si in 2:
		var wall: PackedByteArray = walls[si]
		for i in n - 1:
			var ra: Array[Vector3] = sections[si][i]
			var rb: Array[Vector3] = sections[si][i + 1]
			for k in BANK_RINGS.size() - 1:
				var stone := k == 0 and wall[i] and wall[i + 1]
				# face the sky; a near-vertical step (a wall) faces the open air
				# instead: outwards over a fall, back towards the road up a cutting
				var out := track._side(i) * (-1.0 if si == 0 else 1.0)
				var face := Vector3.UP
				var run := Vector2(ra[k + 1].x - ra[k].x, ra[k + 1].z - ra[k].z).length()
				if absf(ra[k + 1].y - ra[k].y) > 3.0 * run:
					face += out * (2.0 if ra[k + 1].y < ra[k].y else -2.0)
				_bank_quad(st, faces, ra[k], ra[k + 1], rb[k], rb[k + 1], i, stone, face)
	# the road and its verges, for height queries only
	for i in n - 1:
		var la: Array[Vector3] = sections[0][i]
		var lb: Array[Vector3] = sections[0][i + 1]
		var ra2: Array[Vector3] = sections[1][i]
		var rb2: Array[Vector3] = sections[1][i + 1]
		var e := track.widths[i] * 0.5 + TrackBuilder.VERGE
		var lift := func(v: Vector3, y: float) -> Vector3: return Vector3(v.x, y, v.z)
		# (the edges at the tarmac's edge heights: a cambered road's surface
		# carried on out over the verges)
		var lya := pts[i].y - track.camber[i] * e
		var rya := pts[i].y + track.camber[i] * e
		var lyb := pts[i + 1].y - track.camber[i + 1] * e
		var ryb := pts[i + 1].y + track.camber[i + 1] * e
		_add_tri(lift.call(la[0], lya), lift.call(ra2[0], rya), lift.call(rb2[0], ryb), i, true)
		_add_tri(lift.call(la[0], lya), lift.call(rb2[0], ryb), lift.call(lb[0], lyb), i, true)
	st.generate_normals()
	_bank_arrays = st.commit_to_arrays()
	_add_banks()


func _add_banks() -> void:
	var mat := TexGen.material(TexGen.grass(), 1.0, Color(0.8, 0.84, 0.82) if track.rain else Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	track._add_static(_bank_arrays, mat, "grass", "Banks")


# --------------------------------------------------------------------------- the built terrain, baked

## Building the ground round the road (the banks, the grid fitted to them)
## takes seconds, so it's baked to data/stages/<id>.built by
## tools/bake_terrain.gd and read back instead. The bake remembers what it
## was built from (the SOURCES, the stage data and the map entry); if any of that has changed since, it's out of date and
## the ground is built afresh (and a warning says to bake again).

## What the built ground depends on, as one string. Without the scripts'
## source (an exported game may not carry it) only the data and the map.
func built_key(with_source := true) -> String:
	var parts := PackedStringArray([str(BUILT_FORMAT), _id, var_to_str(track.map)])
	parts.append(FileAccess.get_md5("res://data/stages/%s.bin" % _id))
	var texts := ["res://data/stages/%s.json" % _id]
	if with_source:
		texts.append_array(SOURCES)
	for f in texts:
		# (line endings vary with the checkout)
		parts.append(FileAccess.get_file_as_string(f).replace("\r", "").md5_text())
	return "|".join(parts).md5_text()


## The baked ground if there is one and it's up to date, else {}.
func load_built() -> Dictionary:
	var path := "res://data/stages/%s.built" % _id
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var built: Variant = f.get_var()
	if not (built is Dictionary):
		return {}
	var source := SOURCES.all(func(src): return FileAccess.file_exists(src))
	if built.get("key" if source else "data_key", "") != built_key(source):
		push_warning("%s is out of date: building the ground afresh (bake it again with tools/bake_terrain.gd)" % path)
		return {}
	_bank_arrays = built["banks"]
	_tris = built["tris"]
	_hash = built["hash"]
	_on_road = built["on_road"]
	_tri_at = built["tri_at"]
	_box = built["box"]
	_add_banks()
	return built


## Write the ground just built (the grid's heights and its mesh) out for
## load_built().
func save_built(heights: PackedFloat32Array, terrain: Array) -> Error:
	var path := ProjectSettings.globalize_path("res://data/stages/%s.built" % _id)
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return FileAccess.get_open_error()
	f.store_var({"key": built_key(), "data_key": built_key(false), "heights": heights, "terrain": terrain, "banks": _bank_arrays, "tris": _tris,
		"hash": _hash, "on_road": _on_road, "tri_at": _tri_at, "box": _box})
	return OK


## Fit TrackBuilder's grid to the banks (its heights, in place): a grid
## point under a bank moves to just below the bank's surface, one under the
## road well below it, so wherever the grid shows past a bank's edge it
## meets it without a gap or a step. Returns, per grid cell, 1 where banks
## and road cover the whole cell, so it needn't be drawn.
func fit_grid(heights: PackedFloat32Array) -> PackedByteArray:
	var gn := near_n
	var cell := TrackBuilder.CELL
	var under := PackedByteArray()  # 1 under a bank or the road
	under.resize(gn * gn)
	var on_road := PackedByteArray()  # 1 under the road itself
	on_road.resize(gn * gn)
	for gz in gn:
		for gx in gn:
			var k := gz * gn + gx
			var c := _cover(near_x0 + gx * cell, near_z0 + gz * cell)
			if c.x < 0.0:
				continue
			under[k] = 1
			on_road[k] = 1 if c.x > 0.5 else 0
			heights[k] = c.y - 2.0 if c.x > 0.5 else c.y - 0.3
	# a cell part on the road and part off it can still rise through the road
	# from a corner up a cut bank or on another leg of the road: pull those
	# corners down until it stays under the road wherever the road covers it
	# (what covers each cell's sample points doesn't change from pass to
	# pass, so it's looked up once, and only for cells the road reaches)
	var road_cells := PackedInt32Array()
	var road_covers: Array[PackedVector3Array] = []
	for gz in gn - 1:
		for gx in gn - 1:
			var k := gz * gn + gx
			if not (under[k] or under[k + 1] or under[k + gn] or under[k + gn + 1]):
				continue
			# no road within reach of any corner, none in the cell (half its
			# diagonal, the widest road's half and half a sample apart)
			if minf(minf(track._dist[k], track._dist[k + 1]), minf(track._dist[k + gn], track._dist[k + gn + 1])) > 16.0:
				continue
			var covers := PackedVector3Array()
			covers.resize(25)
			var any_road := false
			for oi in 25:
				var c := _cover(near_x0 + (gx + 0.1 + 0.2 * (oi % 5)) * cell, near_z0 + (gz + 0.1 + 0.2 * (oi / 5)) * cell)
				covers[oi] = c
				any_road = any_road or c.x > 0.5
			if any_road:
				road_cells.append(k)
				road_covers.append(covers)
	for _pass in 3:
		for ci in road_cells.size():
			var k := road_cells[ci]
			var covers := road_covers[ci]
			var corners := [k, k + 1, k + gn, k + gn + 1]
			# (only corners under the banks: one out on the open hillside
			# would leave a dip in it, and under a bank it doesn't show)
			var free: Array = corners.filter(func(c): return under[c] and not on_road[c])
			if free.is_empty():
				free = corners.filter(func(c): return on_road[c])  # two legs of the road at different heights
			for oi in 25:
				var c := covers[oi]
				if c.x < 0.5:
					continue
				var o := Vector2(0.1 + 0.2 * (oi % 5), 0.1 + 0.2 * (oi / 5))
				var over := _cell_height(heights, k, o.x, o.y) - (c.y - 0.3)
				if over <= 0.0:
					continue
				# the free corners carry part of the point's height each; lower
				# them all by enough to bring it under
				var w := 0.0
				for f in free:
					w += _corner_weight(corners.find(f), o.x, o.y)
				if w < 0.5:
					continue
				for f in free:
					heights[f] -= over / w
	var hidden := PackedByteArray()
	hidden.resize(gn * gn)
	for gz in gn - 1:
		for gx in gn - 1:
			var k := gz * gn + gx
			if not (under[k] and under[k + 1] and under[k + gn] and under[k + gn + 1]):
				continue
			# corners covered isn't enough: a gap between the banks of two
			# different stretches of road can run through the cell. Hide it
			# only if one stretch covers it all.
			var whole := true
			var lo := 1 << 30
			var hi := -1
			for o in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0.0), Vector2(0.0, 0.5),
					Vector2(1.0, 0.5), Vector2(0.5, 1.0), Vector2(0.5, 0.5), Vector2(0.25, 0.25), Vector2(0.75, 0.25),
					Vector2(0.25, 0.75), Vector2(0.75, 0.75)]:
				var c := _cover(near_x0 + (gx + o.x) * cell, near_z0 + (gz + o.y) * cell)
				if c.x < 0.0:
					whole = false
					break
				lo = mini(lo, int(c.z))
				hi = maxi(hi, int(c.z))
			if hi - lo > 12:
				whole = false
			if whole:
				hidden[k] = 1
	return hidden


## The grid's surface in cell k (its corner gz * near_n + gx) at (fx, fz)
## across it, split along the same diagonal as TrackBuilder's triangles.
func _cell_height(heights: PackedFloat32Array, k: int, fx: float, fz: float) -> float:
	var gn := near_n
	var h00 := heights[k]
	var h10 := heights[k + 1]
	var h01 := heights[k + gn]
	var h11 := heights[k + gn + 1]
	if fx >= fz:
		return h00 + fx * (h10 - h00) + fz * (h11 - h10)
	return h00 + fz * (h01 - h00) + fx * (h11 - h01)


## How much corner c (0 = 00, 1 = 10, 2 = 01, 3 = 11) weighs in
## _cell_height() at (fx, fz).
func _corner_weight(c: int, fx: float, fz: float) -> float:
	if fx >= fz:
		return [1.0 - fx, fx - fz, 0.0, fz][c]
	return [1.0 - fz, 0.0, fz - fx, fx][c]


## How far out (from the centreline) the banks on side s reach at each
## sample: BANK_WIDTH, less on the inside of a tight bend (short of its
## centre) and halfway to any other part of the road on that side.
func _bank_caps(s: float) -> PackedFloat32Array:
	var n := track.count()
	var pts := track.points
	var buckets := {}
	for j in n:
		var key := Vector2i(floori(pts[j].x / 32.0), floori(pts[j].z / 32.0))
		if not buckets.has(key):
			buckets[key] = PackedInt32Array()
		buckets[key].append(j)
	var cap := PackedFloat32Array()
	cap.resize(n)
	for i in n:
		var p := pts[i]
		var sd := track._side(i) * s
		var e := track.widths[i] * 0.5 + TrackBuilder.VERGE
		var c := BANK_WIDTH
		var turn := track._turn(i, 4)
		if turn * s < 0.0:  # turning towards this side (+ turn is left, side -1)
			c = minf(c, 0.7 * 8.0 * TrackBuilder.SPACING / maxf(absf(turn), 0.01))
		# a bank only a metre or two wide can't climb or fall without a step,
		# so the bend gets at least 4 m where that still keeps it off the road
		# (round the tightest bends it would fold back over it); another part
		# of the road nearby still has the last word
		if c < e + 4.0 and track.clear_of_road(p + sd * (e + 4.0), TrackBuilder.VERGE):
			c = e + 4.0
		var key := Vector2i(floori(p.x / 32.0), floori(p.z / 32.0))
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				for j in buckets.get(key + Vector2i(dx, dz), PackedInt32Array()):
					if absi(j - i) < 20:
						continue
					var rel := Vector2(pts[j].x - p.x, pts[j].z - p.z)
					var across := rel.x * sd.x + rel.y * sd.z
					if across <= 0.0:
						continue
					var other_e := track.widths[j] * 0.5 + TrackBuilder.VERGE
					c = minf(c, maxf(rel.length() - other_e, 0.0) * 0.5 + e * 0.5)
		cap[i] = maxf(c, e + 0.5)
	# ease the caps along the road so the sections fan smoothly
	var out := cap.duplicate()
	for i in n:
		var m := INF
		for o in range(-5, 6):
			m = minf(m, cap[clampi(i + o, 0, n - 1)] + absf(o) * 1.5)
		out[i] = m
	return out


## Samples where side s gets a retaining wall: the ground 3 m past the verge
## far below it, and still well below at the bank's outer edge (cap), so a
## dip right by the road (the inside of a hairpin, a gully) gets a bank, not
## a wall down into a trench. Runs shorter than 4 samples are dropped.
func _walls(s: float, cap: PackedFloat32Array) -> PackedByteArray:
	var n := track.count()
	var w := PackedByteArray()
	w.resize(n)
	for i in n:
		var p := track.points[i]
		var q := p + track._side(i) * s * (track.widths[i] * 0.5 + TrackBuilder.VERGE + 3.0)
		var sd := track._side(i) * s
		var far := p + sd * cap[i]
		var y := track.road_y(i, s * track.widths[i])
		var low := track.ground_height(far.x, far.z) < y - 0.5 - WALL_DROP * 0.5
		w[i] = 1 if low and natural(q.x, q.z) < y - 0.5 - WALL_DROP else 0
	var i := 0
	while i < n:
		var j := i
		while j + 1 < n and w[j + 1] == w[i]:
			j += 1
		if w[i] == 1 and j - i < 4:
			for k in range(i, j + 1):
				w[k] = 0
		i = j + 1
	return w


func _bank_quad(st: SurfaceTool, faces: PackedVector3Array, a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3,
		i: int, stone: bool, face: Vector3) -> void:
	for tri in [[a0, a1, b1], [a0, b1, b0]]:
		var t: Array = tri
		if Geo.flipped(t[0], t[1], t[2], face):
			t = [t[0], t[2], t[1]]
		for v in t:
			var q: Vector3 = v
			var col: Color
			if stone:
				col = Color(0.66, 0.63, 0.58)
			else:
				var run := Vector2(a1.x - a0.x, a1.z - a0.z).length()
				col = track.alpine_tint(q.y, absf(a1.y - a0.y) / maxf(run, 0.1), i + int(q.x * 0.1))
			st.set_color(col)
			st.set_uv(Vector2(q.x, q.z) / 8.0 if not stone else Vector2(q.x + q.z, q.y) / 4.0)
			st.add_vertex(q)
			faces.append(q)
		_add_tri(t[0], t[1], t[2], i)


## Remember a triangle for surface_height.
func _add_tri(a: Vector3, b: Vector3, c: Vector3, at: int, road := false) -> void:
	var idx := _tris.size() / 3
	_tris.append_array(PackedVector3Array([a, b, c]))
	_on_road.append(1 if road else 0)
	_tri_at.append(at)
	_box.append_array(PackedFloat32Array([minf(a.x, minf(b.x, c.x)) - 0.05, maxf(a.x, maxf(b.x, c.x)) + 0.05,
		minf(a.z, minf(b.z, c.z)) - 0.05, maxf(a.z, maxf(b.z, c.z)) + 0.05]))
	var x0 := floori(minf(a.x, minf(b.x, c.x)) / BUCKET)
	var x1 := floori(maxf(a.x, maxf(b.x, c.x)) / BUCKET)
	var z0 := floori(minf(a.z, minf(b.z, c.z)) / BUCKET)
	var z1 := floori(maxf(a.z, maxf(b.z, c.z)) / BUCKET)
	for bz in range(z0, z1 + 1):
		for bx in range(x0, x1 + 1):
			var key := Vector2i(bx, bz)
			if not _hash.has(key):
				_hash[key] = PackedInt32Array()
			_hash[key].append(idx)


## Height of the visible ground at a point: the banks or the road where they
## are, else the grid.
func surface_height(x: float, z: float) -> float:
	var c := _cover(x, z)
	return c.y if c.x >= 0.0 else track.ground_height(x, z)


## What covers a point: (1, height, sample) the road, (0, height, sample) a
## bank, (-1, 0, 0) neither. The highest wins where they overlap.
func _cover(x: float, z: float) -> Vector3:
	var best := Vector3(-1.0, -INF, 0.0)
	for t in _hash.get(Vector2i(floori(x / BUCKET), floori(z / BUCKET)), PackedInt32Array()):
		var bi: int = t * 4
		if x < _box[bi] or x > _box[bi + 1] or z < _box[bi + 2] or z > _box[bi + 3]:
			continue
		var a := _tris[t * 3]
		var b := _tris[t * 3 + 1]
		var c := _tris[t * 3 + 2]
		var v0 := Vector2(b.x - a.x, b.z - a.z)
		var v1 := Vector2(c.x - a.x, c.z - a.z)
		var v2 := Vector2(x - a.x, z - a.z)
		var den := v0.x * v1.y - v1.x * v0.y
		if absf(den) < 1e-6:
			continue
		var u := (v2.x * v1.y - v1.x * v2.y) / den
		var w := (v0.x * v2.y - v2.x * v0.y) / den
		if u < -0.001 or w < -0.001 or u + w > 1.002:
			continue
		var h := a.y + u * (b.y - a.y) + w * (c.y - a.y)
		if h > best.y:
			best = Vector3(_on_road[t], h, _tri_at[t])
	return best if best.x >= 0.0 else Vector3(-1.0, 0.0, 0.0)


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
		var out := track.widths[i] * 0.5 + TrackBuilder.VERGE + 4.0
		for s in [-1.0, 1.0]:
			var q: Vector3 = p + track._side(i) * s * out
			if surface_height(q.x, q.z) < p.y - DROP:
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


const SLOPE_TAPS: Array[Vector2] = [Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]


## Steepness of the terrain (rise per metre) round a point (`h`: its
## height, if the caller has it already).
func slope(x: float, z: float, h := NAN) -> float:
	if is_nan(h):
		h = surface_height(x, z)
	var s := 0.0
	for o in SLOPE_TAPS:
		s = maxf(s, absf(surface_height(x + o.x, z + o.y) - h) / 2.0)
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
		_guard_posts(i, j, side[i])
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
		var y := surface_height(x, z)
		if slope(x, z, y) > 1.1 or track._in_water(x, z) or (y > snow_line and rng.randf() < smoothstep(snow_line, snow_line + 60.0, y)):
			continue
		var mesh := Trees.pine(rng.randi_range(0, 3))
		var size := rng.randf_range(1.0, 1.8)
		var turn := rng.randf() * TAU
		track._scatter_xf(mesh, Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * size), Vector3(x, y - 0.3, z)))
		placed += 1


## White stone posts with a black band along the drop, every 15 m; enough to
## knock a panel off, not enough to stop a car going over. The sharper
## corners get armco instead (TrackBuilder's barriers).
func _guard_posts(i0: int, i1: int, s: float) -> void:
	var body := StaticBody3D.new()
	body.name = "GuardPosts"
	body.set_meta("surface", "grass")
	track.add_child(body)
	var stone := TexGen.flat_material(Color(0.92, 0.91, 0.86), 0.9)
	var band := TexGen.flat_material(Color(0.1, 0.1, 0.1), 0.9)
	var post := BoxMesh.new()
	post.size = Vector3(0.45, 0.8, 0.45)
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.47, 0.16, 0.47)
	var shape := BoxShape3D.new()
	shape.size = post.size
	for i in range(i0 + 2, i1 - 1, 5):
		if absf(track._turn(i, 4)) >= TrackBuilder.CLIFF_ARMCO_TURN or track.near_line(i, StartArea.REACH + 3):
			continue
		var xf := Transform3D(track.frame(i).basis, track.points[i] + track._side(i) * s * (track.widths[i] * 0.5 + TrackBuilder.VERGE - 0.45)
			+ Vector3(0, track.road_y(i, s * track.widths[i]) - track.points[i].y - 0.5 + 0.4, 0))
		var mi := MeshInstance3D.new()
		mi.mesh = post
		mi.material_override = stone
		mi.transform = xf
		body.add_child(mi)
		var bi := MeshInstance3D.new()
		bi.mesh = stripe
		bi.material_override = band
		bi.transform = xf.translated_local(Vector3(0, 0.22, 0))
		body.add_child(bi)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = xf
		body.add_child(cs)
