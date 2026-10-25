extends SceneTree
## Scans a built stage's ground for flaws you'd otherwise only find by
## driving round: holes (no ground mesh under a point near the road), spikes
## (a point standing far proud of, or sunk far below, the ground either side
## of it) and inside-out faces (a ground triangle facing down, which renders
## dark). Looks along the whole route, out to REACH metres either side.
##
##   godot --headless -s tools/stage_check.gd -- turini [more map ids]
##
## Prints a summary and the worst spots (as a fraction along the stage and
## metres across the road, + right); exits with 1 if it found anything.
## With DEBUG_AT=<fraction> set it also prints the ground across the road
## there, and the heights round each spike.

const REACH := 40.0
const STEP := 2.0  # metres between samples across the road
const SPIKE := 2.5  # metres a point may stand off the line between its neighbours
const GROUND := ["Terrain", "Banks", "Verges"]  # plus every Road_*
const BUCKET := 8.0

var _tris := PackedVector3Array()
var _hash := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids := OS.get_cmdline_user_args()
	var bad := 0
	for id in ids:
		bad += _check(id)
	quit(1 if bad > 0 else 0)


func _check(id: String) -> int:
	_tris.clear()
	_hash.clear()
	var tb := TrackBuilder.new()
	tb.map = Maps.get_map(id)
	get_root().add_child(tb)
	tb.build()
	var flipped: Array = []
	for body in tb.get_children():
		if not (body.name in GROUND or str(body.name).begins_with("Road_")):
			continue
		for mi in body.get_children():
			if mi is MeshInstance3D:
				_collect(mi.mesh, flipped, str(body.name))
	var holes: Array = []
	var spikes: Array = []
	for i in range(0, tb.count(), 2):
		var p := tb.points[i]
		var sd := tb._side(i)
		var prof: Array = []
		var o := -REACH
		while o <= REACH + 0.01:
			var q := p + sd * o
			var h := _height(q.x, q.z)
			if h == -INF:
				holes.append([tb.frac_of(i), o])
			prof.append(h)
			o += STEP
		for k in range(1, prof.size() - 1):
			var a: float = prof[k - 1]
			var b: float = prof[k]
			var c: float = prof[k + 1]
			if a == -INF or b == -INF or c == -INF:
				continue
			var off := b - (a + c) * 0.5
			# a sharp lump or pit: off the line by more than SPIKE, and not just a
			# steep bank (both neighbours on the same side of it)
			if absf(off) > SPIKE and signf(b - a) != signf(c - b):
				spikes.append([tb.frac_of(i), -REACH + k * STEP, off, prof.slice(maxi(k - 3, 0), k + 4).map(func(h): return snappedf(h - p.y, 0.1))])
	var dbg := OS.get_environment("DEBUG_AT")
	if dbg != "":
		var i := tb.index_at(float(dbg))
		var line := ""
		var o := -REACH
		while o <= REACH + 0.01:
			var q := tb.points[i] + tb._side(i) * o
			line += "%+.0f:%.1f " % [o, _height(q.x, q.z) - tb.points[i].y]
			o += STEP
		print(line)
	print("%s: %d holes, %d spikes, %d inside-out faces" % [id, holes.size(), spikes.size(), flipped.size()])
	for h in holes.slice(0, 8):
		print("  hole  at %.3f, %+.0f m" % [h[0], h[1]])
	spikes.sort_custom(func(x, y): return absf(x[2]) > absf(y[2]))
	for s in spikes.slice(0, 8):
		print("  spike at %.3f, %+.0f m: %+.1f m" % [s[0], s[1], s[2]])
		if dbg != "":
			print("    ", s[3])
	for f in flipped.slice(0, 8):
		var at: Vector3 = f[0]
		var i := tb.nearest_index(at, 0)
		print("  face  at %.3f (%.0f, %.0f, %.0f) in %s" % [tb.frac_of(i), at.x, at.y, at.z, f[1]])
	tb.queue_free()
	return holes.size() + spikes.size() + flipped.size()


## Add a mesh's triangles to the lookup; note any facing down.
func _collect(mesh: Mesh, flipped: Array, what: String) -> void:
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := idx.size() if idx.size() > 0 else v.size()
		for t in range(0, count, 3):
			var ia := idx[t] if idx.size() > 0 else t
			var ib := idx[t + 1] if idx.size() > 0 else t + 1
			var ic := idx[t + 2] if idx.size() > 0 else t + 2
			var a := v[ia]
			var b := v[ib]
			var c := v[ic]
			var nn := (n[ia] + n[ib] + n[ic]) if n.size() > 0 else Vector3.UP
			var geo := (b - a).cross(c - a)
			# a face that isn't near vertical but whose normal points down
			if geo.length() > 0.01 and absf(geo.normalized().y) > 0.3 and nn.y < -0.05:
				flipped.append([(a + b + c) / 3.0, what])
			_add(a, b, c)


func _add(a: Vector3, b: Vector3, c: Vector3) -> void:
	var idx := _tris.size() / 3
	_tris.append_array(PackedVector3Array([a, b, c]))
	for bz in range(floori(minf(a.z, minf(b.z, c.z)) / BUCKET), floori(maxf(a.z, maxf(b.z, c.z)) / BUCKET) + 1):
		for bx in range(floori(minf(a.x, minf(b.x, c.x)) / BUCKET), floori(maxf(a.x, maxf(b.x, c.x)) / BUCKET) + 1):
			var key := Vector2i(bx, bz)
			if not _hash.has(key):
				_hash[key] = PackedInt32Array()
			_hash[key].append(idx)


## Highest ground mesh at a point, -INF if there's none.
func _height(x: float, z: float) -> float:
	var best := -INF
	for t in _hash.get(Vector2i(floori(x / BUCKET), floori(z / BUCKET)), PackedInt32Array()):
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
		best = maxf(best, a.y + u * (b.y - a.y) + w * (c.y - a.y))
	return best
