class_name CliffRoad
extends RefCounted
## The mountain pass ("alpine" theme): a road blasted into a mountainside,
## with a sheer drop on its downhill side and a rock wall on the uphill one.
## The map's "cliffs" list says which side the drop is on along the stage;
## where none is listed (the valley, the hairpins, the col) the ground is the
## usual rolling kind. Shapes the terrain for TrackBuilder, then builds the
## rock walls (solid), the cliff faces under the road edge (not solid: a car
## that goes over falls, and the race puts it back), stone guard posts and
## armco on the drop side, and a waterfall.

const REACH := 110.0  # how far a road's height reaches into the ground around it
const WALL_H := 7.5  # rock wall above the road, before its ragged top
const WALL_BACK := 16.0  # the wall's top runs back this far before it meets the slope

var track: TrackBuilder
## Per road sample: +1 the drop is on the right, -1 on the left, 0 no cliff.
var side := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _rock_mat: StandardMaterial3D


func _init(t: TrackBuilder) -> void:
	track = t
	_rng.seed = int(t.map["seed"]) + 57
	_noise.seed = int(t.map["seed"])
	_noise.frequency = 0.035
	_noise.fractal_octaves = 2
	side.resize(t.count())
	side.fill(0.0)
	for c in t.map.get("cliffs", []):
		for i in range(t.index_at(c[0] as float), t.index_at(c[1] as float) + 1):
			side[i] = c[2]


## Offset of a point across the road at sample i, positive towards the drop
## (0 where there's no cliff).
func _toward_drop(i: int, x: float, z: float) -> float:
	var sd := track._side(i)
	return ((x - track.points[i].x) * sd.x + (z - track.points[i].z) * sd.z) * side[i]


## Is there no room for a tree, a fan or a house at p? True inside or under
## a rock wall (its whole footprint, back to the slope behind), and out over
## a drop close to the road. `hint` is a road sample near p.
func blocked(p: Vector3, hint: int) -> bool:
	for o in range(-24, 25):
		var i := track.wrap_index(hint + o)
		if side[i] == 0.0:
			continue
		var t := track.tangents[i]
		var flat := Vector2(t.x, t.z).normalized()
		var rel := Vector2(p.x - track.points[i].x, p.z - track.points[i].z)
		if absf(rel.dot(flat)) > TrackBuilder.SPACING:
			continue  # not alongside this sample
		var across := _toward_drop(i, p.x, p.z)
		var e := track.widths[i] * 0.5 + TrackBuilder.VERGE
		if across < 0.0 and -across < e + WALL_BACK + 2.0:
			return true  # in the rock
		if across > 0.0 and across < e + 6.0:
			return true  # on the lip or in mid-air
	return false


## The lie of the land with no road: the valley floor, rising into the
## massif on the far side ("massif": [x where it starts, slope]), with some
## lumps on it.
func _massif(x: float, z: float) -> float:
	var m: Array = track.map.get("massif", [0.0, 0.0])
	var floor_y: float = track.map.get("valley_floor", 0.0)
	var lumps := (_noise.get_noise_2d(x * 0.2, z * 0.2) * 0.5 + 0.5) * 14.0
	return floor_y + maxf((m[0] as float) - x, 0.0) * (m[1] as float) + lumps


## Terrain heights for TrackBuilder's grid (its nearest-road arrays are filled
## in already). Away from the road the ground is a blend of the heights of
## the roads around it, counting each road only on its uphill side, so the
## slope under a cliff falls away to the road or valley below rather than
## being held up by the road above. Near the road: the drop side plunges
## from just past the verge, the wall side stays low behind the rock wall
## and then climbs.
func heights() -> PackedFloat32Array:
	var gn := track._grid_n
	var cell := TrackBuilder.CELL
	var origin := track._grid_origin()
	var pts := track.points
	var wsum := PackedFloat32Array()
	wsum.resize(gn * gn)
	wsum.fill(0.0)
	var hsum := wsum.duplicate()
	var r := int(ceil(REACH / cell))
	for i in range(0, pts.size(), 4):
		var p := pts[i]
		var sd := track._side(i)
		var c := side[i]
		var cx := int(round((p.x - origin.x) / cell))
		var cz := int(round((p.z - origin.y) / cell))
		for gz in range(maxi(cz - r, 0), mini(cz + r, gn - 1) + 1):
			for gx in range(maxi(cx - r, 0), mini(cx + r, gn - 1) + 1):
				var dx := origin.x + gx * cell - p.x
				var dz := origin.y + gz * cell - p.z
				var d2 := dx * dx + dz * dz
				if d2 > REACH * REACH:
					continue
				if c != 0.0 and (dx * sd.x + dz * sd.z) * c > 1.0:
					continue  # out over this road's drop
				var f := 1.0 - sqrt(d2) / REACH
				var w := f * f / (d2 + 400.0)
				wsum[gz * gn + gx] += w
				hsum[gz * gn + gx] += w * p.y
	var out := PackedFloat32Array()
	out.resize(gn * gn)
	var wm := 1.0 / (70.0 * 70.0)
	for gz in gn:
		for gx in gn:
			var k := gz * gn + gx
			var wx := origin.x + gx * cell
			var wz := origin.y + gz * cell
			var land := (hsum[k] + wm * _massif(wx, wz)) / (wsum[k] + wm)
			var d: float = track._dist[k]
			var h := land
			if d < 1e8:
				var i: int = track._road_i[k]
				var y := pts[i].y
				var e := track.widths[i] * 0.5 + TrackBuilder.VERGE
				var rough := _noise.get_noise_2d(wx, wz) * 5.0 * smoothstep(e, e + 24.0, d)
				if side[i] != 0.0 and _toward_drop(i, wx, wz) > 0.0:
					# the drop: sheer from the verge down to the land below
					h = minf(maxf(land + rough, y - 1.5 - 6.0 * maxf(d - e, 0.0)), y - 1.5)
				elif side[i] != 0.0:
					# behind the rock wall: low until clear of the verge, then up
					if d < e + cell:
						h = y - 0.3
					else:
						var wall := y + WALL_H * (1.0 - smoothstep(e + WALL_BACK - 4.0, e + 30.0, d)) + absf(rough)
						h = maxf(lerpf(y - 0.3, land + rough, smoothstep(e, e + 45.0, d)), wall)
				else:
					h = lerpf(y - 0.3, land + rough, smoothstep(e + 3.0, 60.0, d))
			out[k] = h
	return out


## Height of the terrain mesh itself at a point (the grid's triangles
## interpolated, not the nearest grid point), for things that stand on
## steep ground.
func ground(x: float, z: float) -> float:
	var gn := track._grid_n
	var cell := TrackBuilder.CELL
	var origin := track._grid_origin()
	var fx := clampf((x - origin.x) / cell, 0.0, gn - 1.001)
	var fz := clampf((z - origin.y) / cell, 0.0, gn - 1.001)
	var gx := int(fx)
	var gz := int(fz)
	fx -= gx
	fz -= gz
	var hs := track._heights
	var h00 := hs[gz * gn + gx]
	var h10 := hs[gz * gn + gx + 1]
	var h01 := hs[(gz + 1) * gn + gx]
	var h11 := hs[(gz + 1) * gn + gx + 1]
	# the same diagonal split as TrackBuilder's terrain triangles
	if fx >= fz:
		return h00 + fx * (h10 - h00) + fz * (h11 - h10)
	return h00 + fz * (h01 - h00) + fx * (h11 - h01)


## Rock: grey-brown with darker strata, cracks and lichen.
static func rock_tex() -> ImageTexture:
	return TexGen.cached("cliff_rock", _make_rock)


static func _make_rock() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	var base := Color(0.56, 0.53, 0.49)
	for y in 32:
		# strata: bands of slightly different stone
		var band := 0.92 + 0.12 * sin(y * 0.9 + sin(y * 0.37) * 2.0)
		for x in 32:
			var c := base * band * rng.randf_range(0.88, 1.08)
			img.set_pixel(x, y, Color(c.r, c.g, c.b))
	for k in 7:
		# cracks running down the face
		var x := rng.randi_range(0, 31)
		var y := rng.randi_range(0, 20)
		for s in rng.randi_range(5, 12):
			img.set_pixel(x, y, Color(0.26, 0.24, 0.22))
			y = mini(y + 1, 31)
			x = wrapi(x + rng.randi_range(-1, 1), 0, 32)
	for k in 26:
		img.set_pixel(rng.randi_range(0, 31), rng.randi_range(0, 31), Color(0.52, 0.58, 0.36))  # lichen
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	return tex


# --------------------------------------------------------------------------- build

func build() -> void:
	_rock_mat = TexGen.material(rock_tex(), 1.0)
	_rock_mat.vertex_color_use_as_albedo = true
	_rock_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var n := track.count()
	var i := 0
	while i < n:
		if side[i] == 0.0:
			i += 1
			continue
		var j := i
		while j + 1 < n and side[j + 1] == side[i]:
			j += 1
		_wall(i, j, -side[i])
		_cliff_face(i, j, side[i])
		_guard_posts(i, j, side[i])
		i = j + 1
	if track.map.has("waterfall"):
		_waterfall(track.index_at(track.map["waterfall"] as float))


## Ragged top height of the rock wall at sample i, taller round the waterfall.
func _wall_height(i: int) -> float:
	var h := WALL_H + (_noise.get_noise_1d(i * 7.0) * 0.5 + 0.5) * 6.0
	if track.map.has("waterfall"):
		var at := track.index_at(track.map["waterfall"] as float)
		h += 16.0 * (1.0 - smoothstep(4.0, 14.0, absf(i - at)))
	return h


## The rock wall along samples i0..i1 on side s (+1 right): a solid lump of
## rock. A jagged face from the verge's outer edge up to the top, leaning back
## a little, the top running back to meet the slope, a back face down to the
## ground and closed ends, all solid, so there's no seeing or driving round
## behind it. It ramps down towards its ends to meet the ground beyond.
func _wall(i0: int, i1: int, s: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var prev: Array = []
	var v := 0.0
	for i in range(i0, i1 + 1):
		var p := track.points[i]
		var sd := track._side(i) * s
		var e := track.widths[i] * 0.5 + TrackBuilder.VERGE
		var ramp := 0.3 + 0.7 * smoothstep(0.0, 8.0, minf(i - i0, i1 - i))
		var top := _wall_height(i) * ramp
		var jag := func(k: float) -> float: return _noise.get_noise_2d(i * 5.0, k * 40.0) * 0.6
		# profile across the road: [offset out from the centre, height above it]
		var prof := [[e - 0.05, -0.6], [e + 0.35 + jag.call(1.0), top * 0.3], [e + 0.8 + jag.call(2.0), top * 0.65],
			[e + 1.4 + jag.call(3.0), top], [e + 4.0 + jag.call(4.0), top + 0.8], [e + WALL_BACK, 0.0], [e + WALL_BACK, 0.0]]
		var last := prof.size() - 1
		var col: Array = []
		for k in prof.size():
			var q: Vector3 = p + sd * (prof[k][0] as float)
			q.y = p.y + (prof[k][1] as float)
			if k == last - 1:
				q.y = maxf(ground(q.x, q.z), p.y + top * 0.5) - 0.3  # down onto the slope behind
			elif k == last:
				q.y = minf(ground(q.x, q.z), p.y) - 1.0  # and on down into the ground
			col.append(q)
		if not prev.is_empty():
			for k in last:
				var a: Vector3 = prev[k]
				var b: Vector3 = prev[k + 1]
				var c: Vector3 = col[k]
				var d: Vector3 = col[k + 1]
				var shade := 0.82 + 0.1 * mini(k, 3)  # darker low down, sunlit at the top
				_rock_quad(st, a, b, c, d, v, shade)
				faces.append_array(PackedVector3Array([a, b, d, a, d, c]))
		if i == i0 or i == i1:
			_end_cap(st, col, faces)
		prev = col
		v += TrackBuilder.SPACING / 4.0
	_add(st, faces, "RockWall")


## Close the end of a rock wall: its cross-section as a fan of triangles.
func _end_cap(st: SurfaceTool, col: Array, faces: PackedVector3Array) -> void:
	var c0: Vector3 = col[0]
	for k in range(1, col.size() - 1):
		var a: Vector3 = col[k]
		var b: Vector3 = col[k + 1]
		for q in [c0, a, b]:
			st.set_color(Color(0.86, 0.86, 0.86))
			st.set_uv(Vector2((q.x + q.z) / 4.0, q.y / 4.0))
			st.add_vertex(q)
		faces.append_array(PackedVector3Array([c0, a, b]))


## The cliff under the road edge along i0..i1 on side s: from the verge's
## outer edge straight down to the ground below, bulging out and in.
func _cliff_face(i0: int, i1: int, s: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev: Array = []
	var v := 0.0
	for i in range(i0, i1 + 1):
		var p := track.points[i]
		var sd := track._side(i) * s
		var e := track.widths[i] * 0.5 + TrackBuilder.VERGE
		var foot := p + sd * (e + 3.0)
		var bottom := ground(foot.x, foot.z) - 1.5
		var depth := p.y - 0.5 - bottom
		var col: Array = []
		for k in 5:
			var f := k / 4.0
			var out := e + f * 2.2 + (_noise.get_noise_2d(i * 6.0, k * 30.0) * 0.8 if k > 0 and k < 4 else 0.0)
			var q: Vector3 = p + sd * out
			q.y = p.y - 0.5 - depth * f
			col.append(q)
		if not prev.is_empty():
			for k in 4:
				_rock_quad(st, prev[k], prev[k + 1], col[k], col[k + 1], v, 0.9 - 0.08 * k)
		prev = col
		v += TrackBuilder.SPACING / 4.0
	_add(st, PackedVector3Array(), "CliffFace")


func _rock_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, v: float, shade: float) -> void:
	var dv := TrackBuilder.SPACING / 4.0
	var uv := [Vector2(v, a.y / 4.0), Vector2(v, b.y / 4.0), Vector2(v + dv, c.y / 4.0), Vector2(v + dv, d.y / 4.0)]
	var col := Color(shade, shade, shade)
	for t in [[a, uv[0]], [b, uv[1]], [d, uv[3]], [a, uv[0]], [d, uv[3]], [c, uv[2]]]:
		st.set_color(col)
		st.set_uv(t[1])
		st.add_vertex(t[0])


func _add(st: SurfaceTool, faces: PackedVector3Array, node_name: String) -> void:
	st.generate_normals()
	var body := StaticBody3D.new()
	body.name = node_name
	body.set_meta("surface", "grass")
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _rock_mat
	body.add_child(mi)
	if not faces.is_empty():
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		cs.shape = shape
		body.add_child(cs)
	track.add_child(body)


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
			+ Vector3(0, -0.5 + 0.4, 0))
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


## A waterfall spilling over the rock wall at sample i, under the road and on
## down the cliff: falling water on both faces and spray where it lands. The
## road there is wet (the map's surface sections).
func _waterfall(i: int) -> void:
	var shader := Shader.new()
	shader.code = "shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
void fragment() {
	vec4 c = texture(tex, vec2(UV.x, UV.y * 0.25 - TIME * 1.6));
	float edge = smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x);
	ALBEDO = c.rgb;
	ALPHA = c.a * edge;
}
"
	var img := Image.create(16, 32, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for y in 32:
		for x in 16:
			var streak := sin(x * 1.7 + rng.randf() * 0.6) * 0.5 + 0.5
			var a := 0.45 + 0.4 * streak
			img.set_pixel(x, y, Color(0.80, 0.88, 0.96, a).lerp(Color(1, 1, 1, 0.95), rng.randf() * 0.5 * streak))
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tex", ImageTexture.create_from_image(img))
	var c := side[i]
	if c == 0.0:
		return
	var p := track.points[i]
	var sd := track._side(i)
	var e := track.widths[i] * 0.5 + TrackBuilder.VERGE
	var along := track.frame(i).basis.z
	# down the wall face (wall side is -c), then down the cliff (c)
	var wall_top := p + sd * (-c) * (e - 0.1) + Vector3(0, _wall_height(i) + 0.5, 0)
	var wall_foot := p + sd * (-c) * (e - 0.6) + Vector3(0, -0.4, 0)
	var lip := p + sd * c * (e + 0.3) + Vector3(0, -0.6, 0)
	var foot := p + sd * c * (e + 3.5)
	foot.y = ground(foot.x, foot.z)
	for seg in [[wall_top, wall_foot], [lip, foot]]:
		var top: Vector3 = seg[0]
		var bot: Vector3 = seg[1]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var w := along * 3.2
		var vlen := top.distance_to(bot) / 4.0
		for q in [[top - w, Vector2(0, 0)], [top + w, Vector2(1, 0)], [bot + w * 1.3, Vector2(1, vlen)],
				[top - w, Vector2(0, 0)], [bot + w * 1.3, Vector2(1, vlen)], [bot - w * 1.3, Vector2(0, vlen)]]:
			st.set_uv(q[1])
			st.add_vertex(q[0])
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		track.add_child(mi)
	# spray drifting up where it hits the bottom
	var spray := CPUParticles3D.new()
	spray.amount = 40
	spray.lifetime = 2.0
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	spray.emission_box_extents = Vector3(4, 1, 4)
	spray.direction = Vector3.UP
	spray.spread = 40.0
	spray.initial_velocity_min = 1.0
	spray.initial_velocity_max = 3.0
	spray.gravity = Vector3(0, -0.6, 0)
	spray.scale_amount_min = 2.0
	spray.scale_amount_max = 4.0
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = TexGen.puff()
	pm.albedo_color = Color(0.9, 0.95, 1.0, 0.35)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = pm
	spray.mesh = quad
	spray.position = foot + Vector3(0, 1, 0)
	track.add_child(spray)
