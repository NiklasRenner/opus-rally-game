class_name Crowd
extends RefCounted
## Spectators, built as one mesh of boxes for the whole crowd. Each box takes
## its colour (shirt, skin, trousers) from the vertex colour and its detail
## from a tiny pixel atlas: faces, hair, collars, a chest print, belts, shoes.
## The atlas is a mask, not a picture: red shades the box's own colour, green
## swaps in the person's hair colour, blue darkens to near black.
## Spectators can jump on the spot: UV2.x is each one's phase, UV2.y is
## 1 if they jump plus 2 x their hair colour.

const SHIRTS := [Color(0.9, 0.15, 0.1), Color(0.1, 0.3, 0.85), Color(1.0, 0.85, 0.1), Color(0.95, 0.95, 0.95),
	Color(0.2, 0.6, 0.2), Color(0.95, 0.5, 0.1), Color(0.55, 0.15, 0.6), Color(0.1, 0.65, 0.75)]
const SKINS := [Color(0.95, 0.78, 0.62), Color(0.82, 0.62, 0.45), Color(0.55, 0.38, 0.25), Color(0.98, 0.84, 0.72)]
const PANTS := [Color(0.2, 0.22, 0.3), Color(0.15, 0.15, 0.15), Color(0.35, 0.3, 0.22), Color(0.3, 0.38, 0.6)]
const HAIRS := 4  # black, brown, blond, grey; picked in the shader

# atlas tiles, 16 px each in a row
enum Tile { PLAIN, FACE, HEAD_BACK, HEAD_SIDE, HAIR, SHIRT_FRONT, SHIRT_BACK, PANTS }
const TILES := 8

const SHADER := "shader_type spatial;
uniform sampler2D tex : filter_nearest;
void vertex() {
	VERTEX.y += max(0.0, sin(TIME * 8.0 + UV2.x)) * 0.16 * mod(UV2.y, 2.0);
}
void fragment() {
	vec3 m = texture(tex, UV).rgb;
	float h = floor(UV2.y * 0.5);
	vec3 hair = h < 0.5 ? vec3(0.02, 0.015, 0.01) : h < 1.5 ? vec3(0.12, 0.05, 0.02)
		: h < 2.5 ? vec3(0.55, 0.38, 0.12) : vec3(0.3, 0.3, 0.3);
	vec3 c = mix(COLOR.rgb * m.r, hair, m.g);
	ALBEDO = c * (1.0 - m.b * 0.9);
	ROUGHNESS = 0.9;
}
"

static var _material: ShaderMaterial

var count := 0
var _st := SurfaceTool.new()
var _rng: RandomNumberGenerator


func _init(rng: RandomNumberGenerator) -> void:
	_rng = rng
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


## One spectator standing at `xf` (feet), facing along its -z.
func person(xf: Transform3D, hop: bool) -> void:
	count += 1
	var uv2 := Vector2(_rng.randf() * TAU, (1.0 if hop else 0.0) + 2.0 * (_rng.randi() % HAIRS))
	var shirt: Color = SHIRTS[_rng.randi() % SHIRTS.size()]
	var skin: Color = SKINS[_rng.randi() % SKINS.size()]
	_box(xf, Vector3(0, 0.4, 0), Vector3(0.42, 0.8, 0.26), PANTS[_rng.randi() % PANTS.size()], uv2,
		[Tile.PANTS, Tile.PANTS, Tile.PANTS, Tile.PLAIN])
	_box(xf, Vector3(0, 1.15, 0), Vector3(0.5, 0.7, 0.3), shirt, uv2,
		[Tile.SHIRT_FRONT, Tile.SHIRT_BACK, Tile.SHIRT_BACK, Tile.SHIRT_BACK])
	_box(xf, Vector3(0, 1.68, 0), Vector3(0.3, 0.3, 0.3), skin, uv2,
		[Tile.FACE, Tile.HEAD_BACK, Tile.HEAD_SIDE, Tile.HAIR])
	var arms := _rng.randf()
	for sx in [-1.0, 1.0]:
		var up: bool = arms < 0.35 or (arms < 0.65 and sx > 0.0)
		if up:
			_box(xf, Vector3(sx * 0.31, 1.78, 0), Vector3(0.12, 0.62, 0.12), skin, uv2)
		else:
			_box(xf, Vector3(sx * 0.31, 1.12, 0), Vector3(0.12, 0.62, 0.14), shirt, uv2)
	if _rng.randf() < 0.3:
		_box(xf, Vector3(0, 1.88, -0.04), Vector3(0.34, 0.1, 0.38), SHIRTS[_rng.randi() % SHIRTS.size()], uv2)


## The finished crowd, or null if nobody turned up.
func make() -> MeshInstance3D:
	if count == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "Crowd"
	mi.mesh = _st.commit()
	mi.material_override = material()
	return mi


static func material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = sh
		_material.set_shader_parameter("tex", ImageTexture.create_from_image(_atlas()))
	return _material


## A box with its faces mapped to atlas tiles: [front (-z), back, sides, top].
func _box(xf: Transform3D, at: Vector3, size: Vector3, col: Color, uv2: Vector2,
		tiles: Array = [Tile.PLAIN, Tile.PLAIN, Tile.PLAIN, Tile.PLAIN]) -> void:
	var h := size * 0.5
	var lc := col.srgb_to_linear()
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sgn
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = h[(axis + 1) % 3]
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = h[(axis + 2) % 3]
			var c := n * h[axis]
			var tile: int = tiles[3] if axis == 1 else (tiles[2] if axis == 0 else (tiles[0] if sgn < 0.0 else tiles[1]))
			if axis == 1 and sgn < 0.0:
				tile = Tile.PLAIN
			var q := [c - u - v, c + u - v, c + u + v, c - u + v]
			var uv := []
			for p in q:
				uv.append(_uv(p, h, axis, tile))
			var wn := (xf.basis * n).normalized()
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var pts := [xf * (at + q[tri[0]]), xf * (at + q[tri[1]]), xf * (at + q[tri[2]])]
				var order := [0, 2, 1] if Geo.flipped(pts[0], pts[1], pts[2], wn) else [0, 1, 2]
				for k in order:
					_st.set_normal(wn)
					_st.set_color(lc)
					_st.set_uv(uv[tri[k]])
					_st.set_uv2(uv2)
					_st.add_vertex(pts[k])


## Atlas UV of a box corner `p` (relative to the box centre): across and up
## the face as you look at it, inset half a pixel so tiles don't bleed.
static func _uv(p: Vector3, h: Vector3, axis: int, tile: int) -> Vector2:
	var across: float
	var up: float
	match axis:
		0:
			across = p.z / h.z
			up = p.y / h.y
		1:
			across = p.x / h.x
			up = -p.z / h.z
		_:
			across = p.x / h.x
			up = p.y / h.y
	var s := Vector2(0.5 + across * 0.47, 0.5 - up * 0.47)
	return Vector2((tile + s.x) / TILES, s.y)


## The mask atlas: TILES tiles of 16 x 16. Red = shade of the box colour,
## green = hair, blue = near-black detail.
static func _atlas() -> Image:
	var img := Image.create(16 * TILES, 16, false, Image.FORMAT_RGB8)
	for t in TILES:
		for y in 16:
			for x in 16:
				img.set_pixel(t * 16 + x, y, _mask(t, x, y))
	return img


static func _mask(t: int, x: int, y: int) -> Color:
	var shade := 0.92 + 0.08 * float((x * 7 + y * 13) % 5) / 4.0  # a little cloth grain
	var edge := x == 0 or x == 15
	match t:
		Tile.FACE:
			if y < 4 or (y == 4 and x % 3 != 1) or ((x < 2 or x > 13) and y < 9):
				return Color(0, 1, 0)  # fringe and sideburns
			if y >= 7 and y <= 8 and (x in [4, 5, 10, 11]):
				return Color(1, 0, 1)  # eyes
			if y == 6 and (x in [3, 4, 5, 10, 11, 12]):
				return Color(0, 1, 0)  # eyebrows
			if y == 12 and x >= 6 and x <= 9:
				return Color(0.7, 0, 0.6)  # mouth
			if y == 10 and (x == 7 or x == 8):
				return Color(0.8, 0, 0)  # nose shadow
			return Color(1, 0, 0)
		Tile.HEAD_BACK:
			return Color(0, 1, 0) if y < 13 or (y == 13 and x % 2 == 0) else Color(0.85, 0, 0)
		Tile.HEAD_SIDE:
			if y < 5 or (x > 9 and y < 13):
				return Color(0, 1, 0)
			if y >= 8 and y <= 10 and (x == 6 or x == 7):
				return Color(0.8, 0, 0)  # ear
			return Color(1, 0, 0)
		Tile.HAIR:
			return Color(0, 1, 0)
		Tile.SHIRT_FRONT:
			if y <= 3 and absi(x * 2 - 15) <= 7 - y * 2:
				return Color(0.75, 0, 0.5)  # V neck
			if y >= 6 and y <= 9 and x >= 4 and x <= 11:
				return Color(1, 0, 0) if (x + y) % 3 else Color(1, 0, 0.5)  # chest print
			if y == 15:
				return Color(0.7, 0, 0)  # hem
			return Color(shade * 0.85 if edge else shade * 0.85, 0, 0)
		Tile.SHIRT_BACK:
			if y == 15:
				return Color(0.7, 0, 0)
			return Color(shade * (0.75 if edge else 0.85), 0, 0)
		Tile.PANTS:
			if y <= 1:
				return Color(0.5, 0, 0.7)  # belt
			if y >= 13:
				return Color(0.4, 0, 0.8)  # shoes
			if y >= 5 and (x == 7 or x == 8):
				return Color(0.55, 0, 0)  # between the legs
			return Color(shade * 0.9, 0, 0)
	return Color(shade * (0.85 if edge else 1.0), 0, 0)
