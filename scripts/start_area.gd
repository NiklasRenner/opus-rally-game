class_name StartArea
extends RefCounted
## Dresses the start/finish line like a late-90s arcade rally: a truss gantry
## with a banner, a live timing board and start lights, the chequered line and
## pole box, sponsor hoardings, flags and bunting, and a crowd hopping up and
## down. Each stage theme ("" countryside, "circuit", "jungle", "wasteland")
## gets its own take on it. Built by TrackBuilder; all low poly with pixel
## textures, the crowd in one mesh.

## Trees and houses keep this far from the line so the dressing has room.
const CLEAR_RADIUS := 34.0
const REACH := 12  # road samples either side of the line that get hoardings

## [name, text colour, board colour]
const SPONSORS := [
	["PIXOIL", Color(1.0, 0.85, 0.1), Color(0.78, 0.06, 0.05)],
	["VOLTEX", Color(1.0, 1.0, 1.0), Color(0.06, 0.26, 0.78)],
	["MAXGRIP", Color(1.0, 0.85, 0.1), Color(0.08, 0.08, 0.1)],
	["BLITZ", Color(0.06, 0.06, 0.1), Color(1.0, 0.8, 0.05)],
	["KAIZEN", Color(1.0, 1.0, 1.0), Color(0.1, 0.55, 0.22)],
	["TURBO-X", Color(1.0, 1.0, 1.0), Color(0.92, 0.38, 0.05)],
	["AURA", Color(0.08, 0.1, 0.45), Color(0.95, 0.95, 0.95)],
	["ZOOM", Color(1.0, 0.9, 0.2), Color(0.45, 0.1, 0.6)],
]
const FLAG_SHADER := "shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tex : source_color, filter_nearest;
void vertex() {
	float ph = MODEL_MATRIX[3].x * 0.31 + MODEL_MATRIX[3].z * 0.17;
	VERTEX.z += sin(TIME * 6.0 - UV.x * 4.0 + ph) * 0.2 * UV.x;
}
void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
	ROUGHNESS = 0.9;
}
"

static var _flag_shader: Shader

var track: TrackBuilder
var theme := ""
var _rng := RandomNumberGenerator.new()
var _root: Node3D
var _bodies: StaticBody3D
var _crowd: Crowd
var _bunting: SurfaceTool
var _pennants := 0
var _stand_side := 0.0  # side of the road with a grandstand, 0 = none
var _stand_from := 0
var _stand_to := 0


func _init(t: TrackBuilder) -> void:
	track = t
	theme = t.map.get("theme", "")
	_rng.seed = int(t.map["seed"]) + 7


func build() -> void:
	_root = Node3D.new()
	_root.name = "StartArea"
	track.add_child(_root)
	_bodies = StaticBody3D.new()
	_bodies.name = "StartBarriers"
	_bodies.set_meta("surface", "grass")
	_root.add_child(_bodies)
	_crowd = Crowd.new(_rng)
	_bunting = SurfaceTool.new()
	_bunting.begin(Mesh.PRIMITIVE_TRIANGLES)
	_line()
	_gantry()
	match theme:
		"circuit":
			_grandstand(_pick_side(), -11, -2, 6, true)
		"":
			var s := _pick_side()
			_grandstand(s, -9, -4, 3, false)
			_tent(-s, 3, "RALLY HQ")
			_tent(-s, -7, "TIMING")
		"jungle":
			_tent(1.0, 4, "CAMP")
			_tent(-1.0, -6, "BASE")
	_hoardings()
	_flags_and_crowd()
	_flush()


# --------------------------------------------------------------------------- helpers

func _n() -> int:
	return track.count()


func _frame(k: int) -> Transform3D:
	return track.frame(k)


func _hw(k: int) -> float:
	return track.widths[wrapi(k, 0, _n())] * 0.5


## Height of the ground below road level at a distance `off` from the centre:
## flat on the road, down the sloped shoulder, then level.
func _drop(k: int, off: float) -> float:
	return -0.5 * clampf((absf(off) - _hw(k)) / TrackBuilder.VERGE, 0.0, 1.0)


## Stands well clear of other parts of the route?
func _clear(p: Vector3, off: float) -> bool:
	for q in track.points:
		if Vector2(q.x - p.x, q.z - p.z).length() < off - 1.5:
			return false
	return true


## The side whose grandstand would sit furthest from the rest of the route.
func _pick_side() -> float:
	var best := 1.0
	var best_d := -INF
	for s in [1.0, -1.0]:
		var xf := _frame(-6)
		var p := xf * Vector3(s * (_hw(-6) + 12.0), 0, 0)
		var d := INF
		for q in track.points:
			d = minf(d, Vector2(q.x - p.x, q.z - p.z).length())
		if d > best_d + 0.5:
			best_d = d
			best = s
	return best


func _mesh(mesh: Mesh, mat: Material, xf: Transform3D, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	(parent if parent else _root).add_child(mi)
	return mi


func _box_mesh(size: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = size
	return bm


func _quad_mesh(size: Vector2) -> QuadMesh:
	var qm := QuadMesh.new()
	qm.size = size
	return qm


## Solid box for the car to hit, in world space.
func _solid(xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = xf
	_bodies.add_child(cs)


func _tiled(tex: Texture2D, roughness: float, uv: Vector3, tint := Color.WHITE) -> StandardMaterial3D:
	var m := TexGen.material(tex, roughness, tint)
	m.uv1_scale = uv
	return m


# --------------------------------------------------------------------------- pixel art

## Banner/board face: text centred on a coloured panel with edge stripes, sized
## to `aspect` so the pixels stay square. Optional chequered ends, and holes
## torn in it for the wasteland.
static func _panel(text: String, aspect: float, fg: Color, bg: Color, edge: Color, h := 11, chequer := false,
		torn := 0) -> ImageTexture:
	var key := "panel|%s|%.2f|%s|%s|%s|%d|%s|%d" % [text, aspect, fg.to_html(), bg.to_html(), edge.to_html(), h, chequer, torn]
	return TexGen.cached(key, _make_panel.bind(text, aspect, fg, bg, edge, h, chequer, torn))


static func _make_panel(text: String, aspect: float, fg: Color, bg: Color, edge: Color, h: int, chequer: bool,
		torn: int) -> ImageTexture:
	var w := maxi(int(round(h * aspect)), text.length() * 4 + 1)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(bg)
	for x in w:
		img.set_pixel(x, 0, edge)
		img.set_pixel(x, h - 1, edge)
	if chequer:
		for y in range(1, h - 1):
			for x in 8:
				var c := Color(0.95, 0.95, 0.95) if (x / 2 + (y - 1) / 2) % 2 == 0 else Color(0.05, 0.05, 0.05)
				img.set_pixel(x, y, c)
				img.set_pixel(w - 1 - x, y, c)
	TexGen.draw_text(img, text, (w - (text.length() * 4 - 1)) / 2, (h - 5) / 2, fg)
	if torn > 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = torn
		for k in 6 + w / 8:
			var cx := rng.randi_range(0, w - 1)
			var cy := 0 if rng.randf() < 0.5 else h - 1
			var r := rng.randi_range(1, 3)
			for y in range(cy - r, cy + r + 1):
				for x in range(cx - r - 1, cx + r + 2):
					if x >= 0 and x < w and y >= 0 and y < h and rng.randf() < 0.8:
						img.set_pixel(x, y, Color(0, 0, 0, 0))
		# soot and rust streaks
		for k in w * h / 10:
			var x := rng.randi_range(0, w - 1)
			var y := rng.randi_range(0, h - 1)
			if img.get_pixel(x, y).a > 0.0:
				img.set_pixel(x, y, img.get_pixel(x, y).darkened(rng.randf_range(0.2, 0.5)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Small flag designs (10 x 6), "torn" ones frayed at the fly end.
static func _flag_tex(kind: int, a: Color, b: Color, c: Color, torn := false) -> ImageTexture:
	var key := "flag|%d|%s|%s|%s|%s" % [kind, a.to_html(), b.to_html(), c.to_html(), torn]
	return TexGen.cached(key, _make_flag.bind(kind, a, b, c, torn))


static func _make_flag(kind: int, a: Color, b: Color, c: Color, torn: bool) -> ImageTexture:
	var img := Image.create(10, 6, false, Image.FORMAT_RGBA8)
	for y in 6:
		for x in 10:
			var col := a
			match kind:
				0:  # chequered
					col = Color(0.95, 0.95, 0.95) if (x / 2 + y / 2) % 2 == 0 else Color(0.05, 0.05, 0.05)
				1:  # vertical tricolour
					col = [a, b, c][mini(x * 3 / 10, 2)]
				2:  # horizontal bands
					col = [a, b, c][y / 2]
				3:  # diagonal stripe
					col = b if absi(x - y * 2 + 1) <= 1 else a
			img.set_pixel(x, y, col)
	if torn:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([kind, a, b])
		for y in 6:
			for x in range(10 - rng.randi_range(1, 4), 10):
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


## Amber LED digits over the unlit segments of an "8".
static func paint_led(img: Image, text: String) -> void:
	img.fill(Color(0.05, 0.04, 0.03))
	var x0 := (img.get_width() - (text.length() * 4 - 1)) / 2
	var y0 := (img.get_height() - 5) / 2
	for i in text.length():
		if text[i] >= "0" and text[i] <= "9":
			TexGen.draw_text(img, "8", x0 + i * 4, y0, Color(0.22, 0.1, 0.03))
		TexGen.draw_text(img, text[i], x0 + i * 4, y0, Color(1.0, 0.62, 0.1))


# --------------------------------------------------------------------------- line and gantry

func _line() -> void:
	var w := track.widths[0]
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, 2.0)
	var flat := _frame(0)
	_mesh(pm, TexGen.material(TexGen.checker(), 0.9), flat.translated_local(Vector3(0, 0.03, 0)))
	# pole box painted round the car's starting spot
	var paint := TexGen.flat_material(Color(0.92, 0.92, 0.88), 0.9)
	var box := _frame(-4)
	for s in [-1.0, 1.0]:
		var side := PlaneMesh.new()
		side.size = Vector2(0.2, 5.0)
		_mesh(side, paint, box.translated_local(Vector3(s * 1.5, 0.025, 0.2)))
	var front := PlaneMesh.new()
	front.size = Vector2(3.2, 0.2)
	_mesh(front, paint, box.translated_local(Vector3(0, 0.025, -2.3)))


func _gantry() -> void:
	var g := Node3D.new()
	g.name = "Gantry"
	g.transform = _frame(0)
	_root.add_child(g)
	var tx := _hw(0) + TrackBuilder.VERGE + 0.6  # tower centres
	var top := 7.8
	var foot := -0.8
	var span := tx * 2.0 - 1.1  # between the towers
	var jungle := theme == "jungle"
	var wasted := theme == "wasteland"
	# per theme: truss colour, banner colours
	var truss_col := {"": Color(0.85, 0.12, 0.1), "circuit": Color(0.78, 0.8, 0.84), "wasteland": Color(0.55, 0.32, 0.2)}
	var banner_fg := {"": Color(1.0, 0.85, 0.1), "circuit": Color(1, 1, 1), "jungle": Color(1.0, 0.85, 0.15),
		"wasteland": Color(0.85, 0.1, 0.04)}
	var banner_bg := {"": Color(0.08, 0.22, 0.72), "circuit": Color(0.8, 0.06, 0.06), "jungle": Color(0.1, 0.32, 0.12),
		"wasteland": Color(0.36, 0.34, 0.31)}
	var edge := Color(0.95, 0.95, 0.95) if not wasted else Color(0.3, 0.28, 0.25)
	var truss := TexGen.material(_truss_tex(), 0.6, truss_col.get(theme, Color.WHITE))
	truss.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	truss.cull_mode = BaseMaterial3D.CULL_DISABLED
	var bark := TexGen.material(TexGen.bark(), 1.0)
	var concrete := _tiled(TexGen.concrete(), 1.0, Vector3(3, 2, 1))
	var tower_h := top - foot
	for s in [-1.0, 1.0]:
		var at := Vector3(s * tx, foot + tower_h * 0.5, 0)
		if jungle:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.38
			cyl.bottom_radius = 0.46
			cyl.height = tower_h
			cyl.radial_segments = 7
			cyl.rings = 1
			_mesh(cyl, bark, Transform3D(Basis.IDENTITY, at), g)
		else:
			var tm := truss.duplicate() as StandardMaterial3D
			tm.uv1_scale = Vector3(3, 2.0 * tower_h / 1.1, 1)
			_mesh(_box_mesh(Vector3(1.1, tower_h, 1.1)), tm, Transform3D(Basis.IDENTITY, at), g)
			_mesh(_box_mesh(Vector3(1.6, 0.9, 1.6)), concrete, Transform3D(Basis.IDENTITY, Vector3(s * tx, foot + 0.3, 0)), g)
		_solid(g.transform * Transform3D(Basis.IDENTITY, at), Vector3(1.2, tower_h, 1.2))
		# a flag on top of each tower
		_flag(g.transform * Vector3(s * tx, top, 0), s, _flag_tex(0, Color.WHITE, Color.WHITE, Color.WHITE, wasted), 2.0)
	# the beam and its banner, front and back
	var beam_y := top - 0.75
	var banner_h := 1.3
	var front := _panel("START / FINISH", span / banner_h, banner_fg.get(theme, Color.WHITE), banner_bg.get(theme, Color.BLACK),
		edge, 11, true, 31 if wasted else 0)
	var back := _panel("RETRO RALLY", span / banner_h, banner_fg.get(theme, Color.WHITE), banner_bg.get(theme, Color.BLACK),
		edge, 11, true, 47 if wasted else 0)
	var front_mat := TexGen.material(front, 0.8)
	var back_mat := TexGen.material(back, 0.8)
	for m in [front_mat, back_mat]:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	if jungle:
		var log_mesh := CylinderMesh.new()
		log_mesh.top_radius = 0.32
		log_mesh.bottom_radius = 0.32
		log_mesh.height = tx * 2.0 + 1.2
		log_mesh.radial_segments = 7
		log_mesh.rings = 1
		_mesh(log_mesh, bark, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, top - 0.2, 0)), g)
		beam_y = top - 1.2  # the banner hangs under the log
		_mesh(_quad_mesh(Vector2(span, banner_h)), front_mat, Transform3D(Basis.IDENTITY, Vector3(0, beam_y, 0.02)), g)
		_mesh(_quad_mesh(Vector2(span, banner_h)), back_mat,
			Transform3D(Basis(Vector3.UP, PI), Vector3(0, beam_y, -0.02)), g)
	else:
		var bm := truss.duplicate() as StandardMaterial3D
		bm.uv1_scale = Vector3(3.0 * (span + 2.2) / 1.5, 2, 1)
		_mesh(_box_mesh(Vector3(span + 2.2, 1.5, 0.9)), bm, Transform3D(Basis.IDENTITY, Vector3(0, beam_y, 0)), g)
		_mesh(_quad_mesh(Vector2(span, banner_h)), front_mat, Transform3D(Basis.IDENTITY, Vector3(0, beam_y, 0.47)), g)
		_mesh(_quad_mesh(Vector2(span, banner_h)), back_mat,
			Transform3D(Basis(Vector3.UP, PI), Vector3(0, beam_y, -0.47)), g)
	# live clock on top
	var housing := TexGen.material(TexGen.planks(), 1.0) if jungle else TexGen.flat_material(Color(0.12, 0.12, 0.14), 0.5)
	var clock_y := top + 0.7 if not jungle else top + 0.55
	_mesh(_box_mesh(Vector3(4.6, 1.3, 0.5)), housing, Transform3D(Basis.IDENTITY, Vector3(0, clock_y, 0)), g)
	var board := TimingBoard.new()
	board.setup(Vector2(4.2, 0.95))
	board.position = Vector3(0, clock_y, 0)
	g.add_child(board)
	# start lights hanging under the beam, facing the grid
	var lights := StartLights.new()
	lights.position = Vector3(0, beam_y - banner_h * 0.5 - 0.5, 0.05)
	g.add_child(lights)
	lights.setup(housing)
	_gantry_feet(g, tx)


## A pixel truss panel: frame and X bracing, see-through between.
static func _truss_tex() -> ImageTexture:
	return TexGen.cached("truss", _make_truss)


static func _make_truss() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 16:
		for x in 16:
			var frame := x < 2 or x > 13 or y < 1 or y > 14
			var brace := absi(x - y) <= 1 or absi(x - (15 - y)) <= 1
			if frame or brace:
				var shade := 1.0 if frame else 0.82
				if x == 0 or y == 0:
					shade = 1.15
				img.set_pixel(x, y, Color(shade * 0.85, shade * 0.85, shade * 0.85))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Hay bales, tyre stacks, oil drums or torches at the towers' feet.
func _gantry_feet(g: Node3D, tx: float) -> void:
	for s in [-1.0, 1.0]:
		for z in [1.6, -1.6]:
			var at := Vector3(s * (tx - 0.4), -0.5, z)
			match theme:
				"":
					var hay := _tiled(TexGen.hay(), 1.0, Vector3(3, 2, 1))
					_mesh(_box_mesh(Vector3(1.2, 1.2, 1.6)), hay, Transform3D(Basis.IDENTITY, at + Vector3(0, 0.6, 0)), g)
					_solid(g.transform * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.6, 0)), Vector3(1.2, 1.2, 1.6))
				"circuit":
					var tyre := CylinderMesh.new()
					tyre.top_radius = 0.42
					tyre.bottom_radius = 0.42
					tyre.height = 0.3
					tyre.radial_segments = 8
					tyre.rings = 1
					var rubber := TexGen.flat_material(Color(0.07, 0.07, 0.08), 0.9)
					var white := TexGen.flat_material(Color(0.9, 0.9, 0.9), 0.9)
					for k in 4:
						_mesh(tyre, white if k == 3 else rubber, Transform3D(Basis.IDENTITY, at + Vector3(0, 0.15 + k * 0.3, 0)), g)
					_solid(g.transform * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.6, 0)), Vector3(0.84, 1.2, 0.84))
				"wasteland":
					var drum := CylinderMesh.new()
					drum.top_radius = 0.3
					drum.bottom_radius = 0.3
					drum.height = 0.9
					drum.radial_segments = 8
					var mi := _mesh(drum, TexGen.material(TexGen.barrel(), 0.8), Transform3D(Basis.IDENTITY, at + Vector3(0, 0.45, 0)), g)
					track.glow_lid(mi)
					_solid(g.transform * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.45, 0)), Vector3(0.6, 0.9, 0.6))
				"jungle":
					if z < 0.0:
						continue
					_torch(g.transform * (at + Vector3(0, 0.5, 0)))


func _torch(at: Vector3) -> void:
	_mesh(_box_mesh(Vector3(0.12, 2.0, 0.12)), TexGen.material(TexGen.bark(), 1.0), Transform3D(Basis.IDENTITY, at + Vector3(0, 0.5, 0)))
	var flame := StandardMaterial3D.new()
	flame.albedo_color = Color(1.0, 0.6, 0.1)
	flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_mesh(_quad_mesh(Vector2(0.35, 0.6)), flame, Transform3D(Basis.IDENTITY, at + Vector3(0, 1.75, 0)))
	var core := flame.duplicate() as StandardMaterial3D
	core.albedo_color = Color(1.0, 0.92, 0.4)
	_mesh(_quad_mesh(Vector2(0.18, 0.32)), core, Transform3D(Basis.IDENTITY, at + Vector3(0, 1.68, 0.02)))


## Flag on a short pole standing at `base`; `s` picks which way it flies so
## it never hangs over the road.
func _flag(base: Vector3, s: float, tex: Texture2D, pole_h: float) -> void:
	_mesh(_box_mesh(Vector3(0.08, pole_h, 0.08)), TexGen.flat_material(Color(0.85, 0.85, 0.85), 0.5),
		Transform3D(Basis.IDENTITY, base + Vector3(0, pole_h * 0.5, 0)))
	if _flag_shader == null:
		_flag_shader = Shader.new()
		_flag_shader.code = FLAG_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _flag_shader
	mat.set_shader_parameter("tex", tex)
	var pm := PlaneMesh.new()
	pm.orientation = PlaneMesh.FACE_Z
	pm.size = Vector2(1.5, 0.9)
	pm.subdivide_width = 5
	var bas := _frame(0).basis
	if s < 0.0:
		bas = bas.rotated(Vector3.UP, PI)
	_mesh(pm, mat, Transform3D(bas, base + Vector3(0, pole_h - 0.5, 0) + bas.x * 0.75))


# --------------------------------------------------------------------------- stands and tents

## Stepped stand beside the approach, rows of people on it; the circuit one
## has a roof with the stage name on its fascia.
func _grandstand(s: float, k0: int, k1: int, rows: int, roof: bool) -> void:
	var mid := (k0 + k1) / 2
	var xf := _frame(mid)
	var length := float(k1 - k0) * TrackBuilder.SPACING + 3.0
	var off0 := _hw(mid) + 3.2
	var depth := 0.9
	if not _clear(xf * Vector3(s * (off0 + rows * depth), 0, 0), off0 + rows * depth):
		return
	_stand_side = s
	_stand_from = k0
	_stand_to = k1
	var seat := _tiled(TexGen.concrete(), 1.0, Vector3(3, 2, 1), Color(0.85, 0.85, 0.82))
	var paint := [TexGen.flat_material(Color(0.1, 0.3, 0.75), 0.8), TexGen.flat_material(Color(0.85, 0.85, 0.85), 0.8)]
	var base := -0.6
	for r in rows:
		var top := base + 0.6 + r * 0.55
		var c := Vector3(s * (off0 + depth * (r + 0.5)), (base + top) * 0.5, 0)
		var size := Vector3(depth, top - base, length)
		_mesh(_box_mesh(size), seat, xf * Transform3D(Basis.IDENTITY, c))
		# painted riser
		_mesh(_box_mesh(Vector3(0.04, 0.5, length)), paint[r % 2],
			xf * Transform3D(Basis.IDENTITY, Vector3(s * (off0 + depth * r) - s * 0.02, top - 0.25, 0)))
		# its row of fans
		var z := -length * 0.5 + 0.4
		while z < length * 0.5 - 0.3:
			if _rng.randf() < 0.85:
				_crowd.person(xf * Transform3D(Basis(Vector3.UP, (PI * 0.5) * s + _rng.randf_range(-0.3, 0.3)),
					Vector3(s * (off0 + depth * (r + 0.5)), top, z)), _rng.randf() < 0.6)
			z += _rng.randf_range(0.6, 0.9)
	var back := off0 + depth * rows
	var top_y := base + 0.6 + (rows - 1) * 0.55
	_solid(xf * Transform3D(Basis.IDENTITY, Vector3(s * (off0 + back) * 0.5, (base + top_y) * 0.5, 0)),
		Vector3(back - off0, top_y - base, length))
	if roof:
		var steel := TexGen.flat_material(Color(0.75, 0.77, 0.8), 0.5)
		var roof_y := top_y + 3.2
		for z in [-length * 0.5 + 0.5, 0.0, length * 0.5 - 0.5]:
			_mesh(_box_mesh(Vector3(0.25, roof_y - top_y + 1.8, 0.25)), steel,
				xf * Transform3D(Basis.IDENTITY, Vector3(s * (back + 0.1), (roof_y + top_y - 1.8) * 0.5, z)))
		var slab_w := back - off0 + 1.2
		_mesh(_box_mesh(Vector3(slab_w, 0.25, length + 1.0)), TexGen.flat_material(Color(0.85, 0.12, 0.1), 0.6),
			xf * Transform3D(Basis(Vector3.FORWARD, s * 0.08), Vector3(s * (back - slab_w * 0.5 + 0.1), roof_y, 0)))
		# fascia with the stage name, facing the road
		var name_tex := _panel(String(track.map.get("name", "")), length / 1.1, Color(1, 1, 1), Color(0.85, 0.12, 0.1),
			Color(1.0, 0.85, 0.1), 9)
		_mesh(_quad_mesh(Vector2(length, 1.1)), TexGen.material(name_tex, 0.8),
			xf * Transform3D(Basis(Vector3.UP, -s * PI * 0.5), Vector3(s * (off0 - 1.15), roof_y - 0.35, 0)))
		# back wall
		_mesh(_box_mesh(Vector3(0.2, roof_y - base, length)), seat,
			xf * Transform3D(Basis.IDENTITY, Vector3(s * (back + 0.25), (roof_y + base) * 0.5, 0)))


## Marquee with a striped pyramid roof (thatch in the jungle) and a sign.
func _tent(s: float, k: int, sign_text: String) -> void:
	var xf := _frame(k)
	var off := _hw(k) + 9.0
	var at := xf * Vector3(s * off, -0.5, 0)
	if not _clear(at, off):
		return
	var bas := xf.basis
	var walls := TexGen.flat_material(Color(0.95, 0.94, 0.88), 0.9)
	_mesh(_box_mesh(Vector3(4.0, 2.2, 4.0)), walls, Transform3D(bas, at + Vector3(0, 1.1, 0)))
	var roof := CylinderMesh.new()
	roof.top_radius = 0.0
	roof.bottom_radius = 3.1
	roof.height = 1.7
	roof.radial_segments = 4
	roof.rings = 1
	var roof_mat := TexGen.material(TexGen.hay(), 1.0) if theme == "jungle" else \
		TexGen.material(TexGen.stripes(Color(0.85, 0.1, 0.1), Color(0.97, 0.97, 0.95), 4), 0.9)
	_mesh(roof, roof_mat, Transform3D(bas.rotated(Vector3.UP, PI * 0.25), at + Vector3(0, 2.2 + 0.85, 0)))
	var sign_tex := _panel(sign_text, 3.4 / 0.7, Color(1, 1, 1), Color(0.08, 0.22, 0.72), Color(1.0, 0.85, 0.1), 9)
	_mesh(_quad_mesh(Vector2(3.4, 0.7)), TexGen.material(sign_tex, 0.8),
		Transform3D(bas.rotated(Vector3.UP, -s * PI * 0.5), at + Vector3(0, 1.75, 0) - bas.x * s * 2.03))
	_solid(Transform3D(bas, at + Vector3(0, 1.1, 0)), Vector3(4.0, 2.2, 4.0))


# --------------------------------------------------------------------------- hoardings, flags, crowd

## Sponsor boards lining both sides of the start straight (concrete blocks
## with faded sponsors in the wasteland).
func _hoardings() -> void:
	var wasted := theme == "wasteland"
	var frame := TexGen.material(TexGen.planks(), 1.0) if theme == "jungle" else TexGen.flat_material(Color(0.9, 0.9, 0.9), 0.7)
	var block := _tiled(TexGen.concrete(), 1.0, Vector3(3, 2, 1), Color(0.8, 0.78, 0.74))
	var next := _rng.randi() % SPONSORS.size()
	for s in [-1.0, 1.0]:
		for k in range(-REACH, REACH + 1):
			if absi(k) <= 1:
				continue
			var xf := _frame(k)
			var off := _hw(k) + 1.6
			var size := Vector3(0.6, 0.9, 2.95) if wasted else Vector3(0.12, 1.05, 2.95)
			var tilt := Basis.IDENTITY
			if wasted:
				if _rng.randf() < 0.2:
					continue  # gaps where blocks were dragged away
				tilt = Basis(Vector3.UP, _rng.randf_range(-0.12, 0.12))
			var c := Vector3(s * (off + size.x * 0.5), size.y * 0.5 - 0.15, 0)
			var bxf := xf * Transform3D(tilt, c)
			_mesh(_box_mesh(size), block if wasted else frame, bxf)
			_solid(bxf, size)
			var sp: Array = SPONSORS[next % SPONSORS.size()]
			next += 1
			if wasted and _rng.randf() < 0.5:
				continue  # bare concrete
			var tex := _panel(sp[0], 2.9 / 0.9, sp[1], sp[2], sp[1], 9, false, _rng.randi_range(1, 999) if wasted else 0)
			var mat := TexGen.material(tex, 0.8, Color(0.7, 0.62, 0.55) if wasted else Color.WHITE)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			_mesh(_quad_mesh(Vector2(2.9, 0.9)), mat,
				bxf * Transform3D(Basis(Vector3.UP, -s * PI * 0.5), Vector3(-s * (size.x * 0.5 + 0.01), 0.02, 0)))


func _flags_and_crowd() -> void:
	var wasted := theme == "wasteland"
	var density: float = {"": 0.85, "circuit": 0.7, "jungle": 0.5, "wasteland": 0.0}.get(theme, 0.6)
	var designs: Array[ImageTexture] = []
	if wasted:
		for k in 3:
			designs.append(_flag_tex(2, Color(0.08, 0.08, 0.08), Color(0.5, 0.08, 0.05), Color(0.08, 0.08, 0.08), true))
		designs.append(_flag_tex(3, Color(0.35, 0.3, 0.25), Color(0.08, 0.08, 0.08), Color.BLACK, true))
	elif theme == "jungle":
		designs.append(_flag_tex(2, Color(0.1, 0.55, 0.2), Color(1.0, 0.85, 0.1), Color(0.8, 0.1, 0.1)))
		designs.append(_flag_tex(1, Color(1.0, 0.85, 0.1), Color(0.1, 0.55, 0.2), Color(1.0, 0.85, 0.1)))
		designs.append(_flag_tex(0, Color.WHITE, Color.WHITE, Color.WHITE))
	else:
		designs.append(_flag_tex(0, Color.WHITE, Color.WHITE, Color.WHITE))
		for sp in SPONSORS:
			designs.append(_flag_tex(3, sp[2], sp[1], sp[1]))
		designs.append(_flag_tex(1, Color(0.1, 0.3, 0.85), Color(0.95, 0.95, 0.95), Color(0.85, 0.1, 0.1)))
		designs.append(_flag_tex(2, Color(0.1, 0.1, 0.1), Color(0.85, 0.1, 0.1), Color(1.0, 0.85, 0.1)))
	for s in [-1.0, 1.0]:
		var last_top := Vector3.INF
		for k in range(-REACH, REACH + 1):
			if absi(k) <= 1:
				last_top = Vector3.INF
				continue
			var on_stand: bool = s == _stand_side and k >= _stand_from - 1 and k <= _stand_to + 1
			var xf := _frame(k)
			var hw := _hw(k)
			# flagpoles behind the boards, bunting strung between them
			if posmod(k, 3) == 0 and not on_stand:
				var base := xf * Vector3(s * (hw + 2.4), _drop(k, hw + 2.4), 0)
				var tex: ImageTexture = designs[_rng.randi() % designs.size()]
				_flag(base, s, tex, 5.0)
				var top := base + Vector3(0, 4.6, 0)
				if last_top != Vector3.INF and not wasted:
					_string_bunting(last_top, top)
				last_top = top
			if on_stand:
				last_top = Vector3.INF
				continue
			# fans, two or three deep
			for row in 3:
				var off := hw + 2.9 + row * 0.75
				var z := -1.5 + _rng.randf_range(0.0, 0.4)
				while z < 1.5:
					if _rng.randf() < density * (1.0 - row * 0.2):
						var p := Vector3(s * (off + _rng.randf_range(-0.15, 0.15)), _drop(k, off) + row * 0.25, z)
						_crowd.person(xf * Transform3D(Basis(Vector3.UP, s * PI * 0.5 + _rng.randf_range(-0.4, 0.4)), p),
							_rng.randf() < 0.55)
					z += _rng.randf_range(0.55, 0.85)


## A line of little pennants sagging between two pole tops.
func _string_bunting(a: Vector3, b: Vector3) -> void:
	var count := int(a.distance_to(b) / 0.55)
	var cols := [Color(0.9, 0.12, 0.1), Color(1.0, 0.85, 0.1), Color(0.1, 0.35, 0.85), Color(0.95, 0.95, 0.95),
		Color(0.15, 0.6, 0.2)]
	var along := (b - a).normalized()
	for i in count:
		var t0 := float(i) / count
		var t1 := float(i + 0.8) / count
		var p0 := a.lerp(b, t0) + Vector3(0, -sin(t0 * PI) * 0.7, 0)
		var p1 := a.lerp(b, t1) + Vector3(0, -sin(t1 * PI) * 0.7, 0)
		var tip := (p0 + p1) * 0.5 + Vector3(0, -0.35, 0)
		var col: Color = cols[i % cols.size()]
		var n := along.cross(Vector3.UP).normalized()
		_pennants += 1
		for v in [p0, p1, tip]:
			_bunting.set_normal(n)
			_bunting.set_color(col)
			_bunting.add_vertex(v)


func _flush() -> void:
	var crowd := _crowd.make()
	if crowd:
		_root.add_child(crowd)
	if _pennants > 0:
		var bunting := _bunting.commit()
		var bm := StandardMaterial3D.new()
		bm.vertex_color_use_as_albedo = true
		bm.cull_mode = BaseMaterial3D.CULL_DISABLED
		bm.roughness = 0.9
		_mesh(bunting, bm, Transform3D.IDENTITY)


# --------------------------------------------------------------------------- live parts

## Race clock on the gantry, both faces, reading the race scene's time.
class TimingBoard extends Node3D:
	var _img: Image
	var _tex: ImageTexture
	var _shown := ""

	func setup(size: Vector2) -> void:
		_img = Image.create(31, 7, false, Image.FORMAT_RGBA8)
		StartArea.paint_led(_img, "0'00\"00")
		_tex = ImageTexture.create_from_image(_img)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _tex
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		for side in [1.0, -1.0]:
			var mi := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = size
			mi.mesh = qm
			mi.material_override = mat
			mi.position = Vector3(0, 0, 0.26 * side)
			if side < 0.0:
				mi.rotation.y = PI
			add_child(mi)

	func _process(_delta: float) -> void:
		var race := get_tree().current_scene
		var t := 0.0
		if race and "race_time" in race:
			t = race.get("race_time")
		var text := "%d'%02d\"%02d" % [int(t / 60.0) % 10, int(t) % 60, int(fmod(t, 1.0) * 100.0)]
		if text != _shown:
			_shown = text
			StartArea.paint_led(_img, text)
			_tex.update(_img)


## Three lamps that light red one by one with the countdown, then all go green.
class StartLights extends Node3D:
	var _lamps: Array[StandardMaterial3D] = []

	func setup(housing: Material) -> void:
		var pod := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.7, 0.8, 0.4)
		pod.mesh = bm
		pod.material_override = housing
		add_child(pod)
		for k in 3:
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(0.25, 0.04, 0.03)
			_lamps.append(mat)
			var lamp := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(0.55, 0.55)
			lamp.mesh = qm
			lamp.material_override = mat
			lamp.position = Vector3((k - 1) * 0.85, 0, 0.21)
			add_child(lamp)

	func _process(_delta: float) -> void:
		var race := get_tree().current_scene
		if race == null or not ("_countdown" in race):
			return
		var c: float = race.get("_countdown")
		var go: bool = race.get("_racing")
		for k in _lamps.size():
			if go:
				_lamps[k].albedo_color = Color(0.25, 1.0, 0.3)
			elif c <= 3.6 - k:
				_lamps[k].albedo_color = Color(1.0, 0.12, 0.06)
			else:
				_lamps[k].albedo_color = Color(0.25, 0.04, 0.03)
