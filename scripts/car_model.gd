class_name CarModel
extends Node3D
## A vehicle modelled in Blender (art/), imported from models/ and painted
## with its skin (rally cars, F1) or procedural camouflage (the tank).
## Panels dent at runtime: vertices near an impact are pushed inward and
## scuffed darker; bolt-on parts (bumpers, wings, light pod, mirrors, skirts)
## fall off once their damage zone passes a threshold.

const MAX_DENT := 0.42
const MESH_Y := -0.72  # ground level in car space; the Blender models sit on their origin
const LINK := 0.22  # tank track link length in metres (one texture repeat)
const ROLL_MAX := 5.0  # m/s: fastest the tracks and road wheels are drawn turning
## Rolling radius of a tank's running gear, by node name prefix.
const SPIN_R := {"RoadWheel_": 0.24, "Sprocket_": 0.25, "Idler_": 0.21, "ReturnRoller_": 0.065}
## Rally cars: what dents and what falls off unless the spec says otherwise.
const CAR_DENTS := ["Body", "Bumper_F", "Bumper_R"]
const CAR_PARTS := [["Bumper_F", "front", 0.3], ["Bumper_R", "rear", 0.35], ["Spoiler", "rear", 0.55],
	["LightPod", "front", 0.2], ["Mirror_L", "left", 0.2], ["Mirror_R", "right", 0.2]]
const BEACON_COLS := [Color(0.15, 0.35, 1.0), Color(1.0, 0.1, 0.06)]  # blue, red
const FLASH := 0.9  # seconds for one blue-blue, red-red cycle of the light bar
const WHEEL_NODES := ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]  # same order as Cars.wheel_positions

const FACE_BACK := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
const FACE_RIGHT := Basis(Vector3(0, 0, -1), Vector3.UP, Vector3.RIGHT)
const FACE_LEFT := Basis(Vector3(0, 0, 1), Vector3.UP, Vector3.LEFT)

var spec: Dictionary = Cars.LIST[0]

var _deformables: Array[Dictionary] = []
var _parts := {}
var _body_mat: StandardMaterial3D
## Solid axles (monster truck): they follow their two wheels up and down.
var _axles: Array = [null, null]
var _axle_y: Array = [0.0, 0.0]


## Tilt and drop each solid axle to match its wheels: tilt is the left wheel's
## drop minus the right's, sink how far the pair has dropped from rest.
func place_axles(tilt_f: float, tilt_r: float, sink_f: float, sink_r: float) -> void:
	var half: float = Cars.wheels(spec)["x"]
	for i in 2:
		var axle: Node3D = _axles[i]
		if axle == null or not is_instance_valid(axle):
			continue
		axle.position.y = _axle_y[i] - (sink_f if i == 0 else sink_r)
		axle.rotation.z = atan2(tilt_f if i == 0 else tilt_r, 2.0 * half)


## Set once the car has taken the model's wheels onto its suspension, so a
## rebuilt (repaired) model drops its own copies.
var _wheels_taken := false
# F1: the driver's head follows the steering
var _head: Node3D
# tank only: animated bits
var _turret: Node3D
var _gun: Node3D  # mantlet, kept level by the stabiliser
# police car: the light bar's blue and red lenses and the glow they throw
var _beacons: Array[StandardMaterial3D] = [TexGen.flat_material(BEACON_COLS[0], 0.2, true),
	TexGen.flat_material(BEACON_COLS[1], 0.2, true)]
var _beacon_glow: OmniLight3D
var _flash_t := 0.0
var _track_mat: StandardMaterial3D
var _road_wheels: Array[Node3D] = []
var _wheel_r: Array[float] = []


func build() -> void:
	_body_mat = StandardMaterial3D.new()
	_body_mat.vertex_color_use_as_albedo = true
	_body_mat.roughness = 0.32
	_body_mat.metallic_specular = 0.75
	_head = null
	_gun = null
	_beacon_glow = null
	_road_wheels.clear()
	_wheel_r.clear()
	_build_mesh()


func kind() -> String:
	return spec.get("type", "car")


func is_tank() -> bool:
	return kind() == "tank"


## z of the nose in car space (headlights in the rain).
func front_z() -> float:
	return spec["nose"]


# --------------------------------------------------------------------------- building

## Imports the model, paints it (by material name, the part before any "."),
## makes its panels dentable and registers its bolt-ons as parts that can be
## knocked off.
func _build_mesh() -> void:
	var root: Node3D = (load(spec["mesh"]) as PackedScene).instantiate()
	root.position.y = spec.get("ground_y", MESH_Y)
	_axles = [root.find_child("Axle_F", true, false), root.find_child("Axle_R", true, false)]
	_axle_y = [_axles[0].position.y if _axles[0] else 0.0, _axles[1].position.y if _axles[1] else 0.0]
	add_child(root)
	var mats := _tank_materials() if is_tank() else _car_materials()
	for m in mats.values():
		var bm := m as BaseMaterial3D
		if bm and bm.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
			bm.vertex_color_use_as_albedo = true  # light baked into the model (art/cars/build_cars.py)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			var key := m.resource_name.get_slice(".", 0) if m else ""
			if mats.has(key):
				(mi as MeshInstance3D).set_surface_override_material(s, mats[key])
	for n in spec.get("dents", CAR_DENTS):
		var node := root.find_child(n, true, false)
		if node:
			_make_dentable(node)
	for p in spec.get("parts", CAR_PARTS):
		var node := root.find_child(p[0], true, false)
		if node:
			_add_part(node, p[1], p[2])
	if _wheels_taken:
		for n in WHEEL_NODES:
			var w := root.find_child(n, true, false)
			if w:
				w.free()
	if kind() == "f1":
		_helmet(spec["helmet_pos"], spec["helmet"], 0.15)  # looks into the corners
	var bar := root.find_child("LightBar", true, false) as Node3D
	if spec.get("beacons", false) and bar:
		_beacon_glow = OmniLight3D.new()
		_beacon_glow.position = Vector3(0, 0.3, 0)
		_beacon_glow.omni_range = 7.0
		_beacon_glow.light_energy = 1.6
		_beacon_glow.shadow_enabled = false
		bar.add_child(_beacon_glow)  # goes with the bar if it is knocked off
	set_process(_beacon_glow != null)
	if not is_tank():
		return
	_turret = root.find_child("Turret", true, false)
	_gun = root.find_child("GunMantlet", true, false)
	for node in root.find_children("*", "Node3D", true, false):
		for prefix in SPIN_R:
			if String(node.name).begins_with(prefix):
				_road_wheels.append(node)
				_wheel_r.append(SPIN_R[prefix])
	_tank_decals(root)


func _car_materials() -> Dictionary:
	# the painted skin covers body and glass alike
	var skin: Texture2D = load(spec["skin"])
	var glass := _tex_mat(skin, 0.08, Color.WHITE)
	glass.metallic_specular = 0.9
	var chrome := TexGen.flat_material(Color(0.75, 0.75, 0.78), 0.2)
	chrome.metallic = 0.8
	return {
		"Livery": _tex_mat(skin, 0.3, Color.WHITE),
		"Glass": glass,
		"Trim": TexGen.flat_material(Color(0.07, 0.07, 0.08), 0.7),
		"Chrome": chrome,
		"Lamp": TexGen.flat_material(Color(1.0, 0.95, 0.75), 0.2, true),
		"Flap": TexGen.flat_material(spec["flaps"], 0.9),
		"Tyre": TexGen.material(TexGen.chevron_tread() if spec.get("tread") == "chevron" else TexGen.tread(), 0.95),
		"Rim": TexGen.material(TexGen.rim(spec["rims"], spec.get("spokes", 5), spec.get("rim_ring", Color(0, 0, 0, 0)),
			spec.get("hubcap", Color(0, 0, 0, 0))), 0.4),
		"Tail": TexGen.flat_material(Color(1.0, 0.12, 0.08), 0.3, true),
		"Frame": _frame_mat(),
		"Steel": _steel_mat(),
		"BeaconBlue": _beacons[0],
		"BeaconRed": _beacons[1],
	}


## Tube frame paint: the light baked into the model's vertex colours shades
## each tube round.
func _frame_mat() -> StandardMaterial3D:
	var m := TexGen.flat_material(spec.get("frame", Color(0.8, 0.08, 0.06)), 0.45)
	m.vertex_color_use_as_albedo = true
	return m


## Darker, duller than chrome: cast metal like the truck's diff housings.
func _steel_mat() -> StandardMaterial3D:
	var m := TexGen.flat_material(Color(0.24, 0.25, 0.27), 0.5)
	m.metallic = 0.4
	m.vertex_color_use_as_albedo = true  # light baked into the model, like the frame
	return m


func _tank_materials() -> Dictionary:
	_track_mat = _tex_mat(TexGen.track_links(), 0.95, Color.WHITE)
	_track_mat.set_meta("scrolls", true)  # animate() moves its uv1_offset
	return {
		"Paint_Green": _tex_mat(TexGen.camo(), 0.85, Color.WHITE),
		"Paint_DarkGreen": _tex_mat(TexGen.camo(), 0.9, Color(0.6, 0.6, 0.6)),
		"DarkMetal": TexGen.flat_material(Color(0.07, 0.07, 0.07), 0.6),
		"Rubber": TexGen.flat_material(Color(0.05, 0.05, 0.05), 0.95),
		"Track": _track_mat,
		# road wheel faces: lightening holes so the wheels are seen to turn
		"Wheel": TexGen.material(TexGen.rim(Color(0.55, 0.48, 0.34), 6), 0.9),  # dusty sand road wheels
		"Glass": TexGen.flat_material(Color(0.08, 0.16, 0.2), 0.1),
		"Lamp": TexGen.flat_material(Color(1.0, 0.95, 0.75), 0.2, true),
		"TailLight": TexGen.flat_material(Color(0.8, 0.08, 0.05), 0.3, true),
		"Canvas": TexGen.flat_material(Color(0.3, 0.27, 0.18), 1.0),
	}


## Nearest-filtered texture that takes the dent scuffs (vertex colour) as a tint.
func _tex_mat(tex: Texture2D, roughness: float, tint: Color) -> StandardMaterial3D:
	var m := TexGen.material(tex, roughness, tint)
	m.vertex_color_use_as_albedo = true
	return m


## The model's own wheels (FL, FR, RL, RR), taken out to ride on the car's
## suspension. Empty for models without wheels (the tank).
func take_wheels() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in WHEEL_NODES:
		var w: Node3D = find_child(n, true, false)
		if w == null:
			return []
		out.append(w)
	for w in out:
		w.get_parent().remove_child(w)
		w.position = Vector3.ZERO
	_wheels_taken = true
	return out


## Driver's helmet with a dark visor; turns with the steering in animate().
func _helmet(pos: Vector3, col: Color, r: float) -> void:
	_head = Node3D.new()
	_head.position = pos
	add_child(_head)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	mi.material_override = TexGen.flat_material(col, 0.3)
	_head.add_child(mi)
	var visor := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(r * 1.45, r * 0.42, r * 0.7)
	visor.mesh = bm
	visor.material_override = TexGen.flat_material(Color(0.05, 0.06, 0.1), 0.1)
	visor.position = Vector3(0, r * 0.08, -r * 0.68)
	_head.add_child(visor)


## Small Danish flags on the skirts and the back, tactical number on the
## turret bins, white tactical code on the glacis.
func _tank_decals(root: Node3D) -> void:
	var flag := TexGen.danish_flag()
	for s in [-1.0, 1.0]:
		var bas := FACE_RIGHT if s > 0.0 else FACE_LEFT
		var skirt: Node3D = root.find_child("SideSkirt_R" if s > 0.0 else "SideSkirt_L", true, false)
		_decal(flag, Vector2(0.26, -1), Vector3(s * 0.035, -0.19, 0.0), bas, skirt)
		_decal(TexGen.pixel_text(spec["number"], Color(0.92, 0.92, 0.86), Color(0.12, 0.15, 0.09)),
			Vector2(0.42, -1), Vector3(s * 0.817, 0.22, 0.78), bas, _turret)
	_decal(flag, Vector2(0.17, -1), Vector3(0, 0.16, 2.235), FACE_BACK, self)
	# glacis: lies back from the nose, read from in front
	var up := Vector3(0, 0.275, 0.961)
	var glacis := Basis(Vector3.LEFT, up, Vector3.LEFT.cross(up))
	var code := _decal(TexGen.pixel_text("DK 34-" + String(spec["number"]), Color(0.92, 0.92, 0.88), Color(0, 0, 0, 0)),
		Vector2(0.5, -1), Vector3(-0.5, 0.21, -1.99), glacis, self)
	(code.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR


## A textured sticker. A negative height keeps the texture's pixel aspect.
func _decal(tex: Texture2D, size: Vector2, pos: Vector3, bas: Basis, parent: Node3D) -> MeshInstance3D:
	if size.y < 0.0:
		size.y = size.x * tex.get_height() / tex.get_width()
	var qm := QuadMesh.new()
	qm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	mi.material_override = TexGen.material(tex, 0.45)
	mi.transform = Transform3D(bas, pos)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(mi)
	return mi


# --------------------------------------------------------------------------- damage

## Swap an imported mesh for one dentable triangle soup per surface, keeping
## its children.
func _make_dentable(mi: MeshInstance3D) -> void:
	var mesh := mi.mesh
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(v.size())
			for i in v.size():
				idx[i] = i
		# light baked into the model, if any, is where the dent scuffs start from
		var baked: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var colors := PackedColorArray()
		for i in idx:
			verts.append(v[i])
			uvs.append(uv[i])
			colors.append(baked[i] if not baked.is_empty() else Color.WHITE)
		var mat := mi.get_surface_override_material(s)
		var own := mesh.surface_get_material(s)
		var glass := own != null and own.resource_name.get_slice(".", 0) == "Glass"
		_add_deformable(mi, verts, uvs, mat if mat else own, colors, _pane_uvs(verts) if glass else PackedVector2Array())
	mi.mesh = null


## Where each corner of a triangle soup sits on its window pane, for the glass
## shader (RetroLook) to lay the same reflection out on every window whatever
## its size: y runs 0..1 up the pane; x is the pane's width in decimetres
## (whole part) plus 0..1 across it, left to right seen from outside. A pane
## is the triangles joined at their corners and facing within ~35 degrees of
## the first one found, so a faceted windscreen counts as one.
static func _pane_uvs(verts: PackedVector3Array) -> PackedVector2Array:
	var tris := verts.size() / 3
	var normals := PackedVector3Array()
	var at := {}  # corner position (to the mm) -> triangles that touch it
	for t in tris:
		var a := verts[t * 3]
		normals.append((verts[t * 3 + 1] - a).cross(verts[t * 3 + 2] - a) * Geo.winding())
		for k in 3:
			var key := Vector3i((verts[t * 3 + k] * 1000.0).round())
			if not at.has(key):
				at[key] = []
			at[key].append(t)
	var out := PackedVector2Array()
	out.resize(verts.size())
	var pane := PackedInt32Array()
	pane.resize(tris)
	pane.fill(-1)
	for first in tris:
		if pane[first] != -1:
			continue
		pane[first] = first
		var facing := normals[first].normalized()
		var group: Array[int] = [first]
		var i := 0
		var n_sum := Vector3.ZERO
		while i < group.size():
			var t := group[i]
			i += 1
			n_sum += normals[t]
			for k in 3:
				for o in at[Vector3i((verts[t * 3 + k] * 1000.0).round())]:
					if pane[o] == -1 and normals[o].normalized().dot(facing) > 0.82:
						pane[o] = first
						group.append(o)
		var n := n_sum.normalized()
		var up := Vector3.UP - n * n.y
		if up.length() < 0.3:  # a roof or bonnet pane: "up" runs towards the nose
			up = Vector3.FORWARD - n * n.z
		up = up.normalized()
		var across := up.cross(n).normalized()
		var lo := Vector2(INF, INF)
		var hi := -lo
		for t in group:
			for k in 3:
				var p := verts[t * 3 + k]
				var q := Vector2(p.dot(across), p.dot(up))
				lo = lo.min(q)
				hi = hi.max(q)
		var size := (hi - lo).max(Vector2(0.001, 0.001))
		var width := maxf(roundf(size.x * 10.0), 1.0)
		for t in group:
			for k in 3:
				var p := verts[t * 3 + k]
				var q := (Vector2(p.dot(across), p.dot(up)) - lo) / size
				out[t * 3 + k] = Vector2(width + q.x * 0.999, q.y)
	return out


## A dentable triangle soup. Its vertex colours (the model's baked light, or
## white, scuffed darker by dents) tint the material's texture.
func _add_deformable(parent: Node3D, verts: PackedVector3Array, uvs: PackedVector2Array, mat: Material,
		colors := PackedColorArray(), panes := PackedVector2Array()) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not panes.is_empty():
		arrays[Mesh.ARRAY_TEX_UV2] = panes  # glass: where on its window pane (_pane_uvs)
	if colors.is_empty():
		colors.resize(verts.size())
		colors.fill(Color.WHITE)
	var mi := MeshInstance3D.new()
	mi.mesh = ArrayMesh.new()
	parent.add_child(mi)
	var d := {"mi": mi, "arrays": arrays, "base": verts.duplicate(), "verts": verts, "colors": colors,
		"detached": false, "mat": mat if mat else _body_mat}
	_deformables.append(d)
	_rebuild(d)


## Flat normals for a triangle soup wound so that front faces point outward.
static func _flat_normals(verts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(verts.size())
	var s := Geo.winding()
	for i in range(0, verts.size(), 3):
		var n := ((verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i]) * s).normalized()
		out[i] = n
		out[i + 1] = n
		out[i + 2] = n
	return out


func _rebuild(d: Dictionary) -> void:
	var arrays: Array = d["arrays"]
	arrays[Mesh.ARRAY_VERTEX] = d["verts"]
	arrays[Mesh.ARRAY_NORMAL] = _flat_normals(d["verts"])
	arrays[Mesh.ARRAY_COLOR] = d["colors"]
	var mi: MeshInstance3D = d["mi"]
	var mesh: ArrayMesh = mi.mesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, d["mat"])


## Register an imported node as a bolt-on, with a collision box round its meshes.
func _add_part(node: Node3D, zone: String, threshold: float) -> void:
	var box := AABB()
	var first := true
	var list: Array = [node]
	list.append_array(node.find_children("*", "MeshInstance3D", true, false))
	for mi in list:
		if not mi is MeshInstance3D or (mi as MeshInstance3D).mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node3D = mi
		while n != node:
			xf = n.transform * xf
			n = n.get_parent()
		var b: AABB = xf * (mi as MeshInstance3D).mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	_parts[String(node.name)] = {"node": node, "zone": zone, "threshold": threshold,
		"size": box.size.max(Vector3(0.05, 0.05, 0.05)), "offset": box.get_center(), "detached": false}


## Push vertices near `point` (global) along `dir` (global, pointing into the car).
func dent(point: Vector3, dir: Vector3, amount: float, radius: float) -> void:
	for d in _deformables:
		if d["detached"]:
			continue
		var mi: MeshInstance3D = d["mi"]
		var inv := mi.global_transform.affine_inverse()
		var lp := inv * point
		var ldir := (inv.basis * dir).normalized()
		var verts: PackedVector3Array = d["verts"]
		var base: PackedVector3Array = d["base"]
		var colors: PackedColorArray = d["colors"]
		var changed := false
		for i in verts.size():
			var dist := verts[i].distance_to(lp)
			if dist >= radius:
				continue
			var f := 1.0 - dist / radius
			f *= f
			var nv := verts[i] + ldir * amount * f
			var off := nv - base[i]
			if off.length() > MAX_DENT:
				nv = base[i] + off.limit_length(MAX_DENT)
			verts[i] = nv
			colors[i] = colors[i].lerp(Color(0.28, 0.27, 0.26), clampf(f * amount * 2.5, 0.0, 0.5))
			changed = true
		if changed:
			d["verts"] = verts
			d["colors"] = colors
			_rebuild(d)


## Detach bolt-on parts whose zone damage passed their threshold.
func update_parts(zones: Dictionary, car_velocity: Vector3) -> Array[String]:
	var dropped: Array[String] = []
	for part_name in _parts:
		var p: Dictionary = _parts[part_name]
		if p["detached"]:
			continue
		if (zones[p["zone"]] as float) >= (p["threshold"] as float):
			_detach(part_name, car_velocity)
			dropped.append(part_name)
	return dropped


func _detach(part_name: String, car_velocity: Vector3) -> void:
	var p: Dictionary = _parts[part_name]
	p["detached"] = true
	var node: Node3D = p["node"]
	for d in _deformables:
		if node.is_ancestor_of(d["mi"]):
			d["detached"] = true
	var gt := node.global_transform
	var rb := RigidBody3D.new()
	rb.mass = 6.0
	rb.collision_layer = 4
	rb.collision_mask = 1 | 4
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = p["size"]
	cs.shape = bs
	cs.position = p.get("offset", Vector3.ZERO)
	rb.add_child(cs)
	# drop the part into the world (car's parent), not into the car
	get_parent().get_parent().add_child(rb)
	rb.global_transform = gt
	node.reparent(rb, true)
	var kick := (gt.origin - global_position).normalized()
	rb.linear_velocity = car_velocity * 0.85 + kick * 3.0 + Vector3.UP * 2.5
	rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	get_tree().create_timer(30.0).timeout.connect(rb.queue_free)


# --------------------------------------------------------------------------- animation

## The police light bar: a double flash of blue, then a double flash of red,
## the unlit lens dimmed, and the roof light glowing in the lit colour.
func _process(delta: float) -> void:
	_flash_t = fmod(_flash_t + delta, FLASH)
	var half := FLASH / 2.0
	var side := 0 if _flash_t < half else 1
	var t := fmod(_flash_t, half) / half
	var on := t < 0.22 or (t > 0.36 and t < 0.58)
	for i in 2:
		var lit := on and i == side
		_beacons[i].albedo_color = BEACON_COLS[i] if lit else BEACON_COLS[i].darkened(0.7)
	if is_instance_valid(_beacon_glow):
		_beacon_glow.visible = on
		_beacon_glow.light_color = BEACON_COLS[side]


## Per-frame animation: the F1 driver looks into the corner; the tank's tracks
## and road wheels roll with the ground speed and the turret leans into the
## steering.
func animate(delta: float, forward_speed: float, steer: float) -> void:
	if _head:
		_head.rotation.y = lerpf(_head.rotation.y, -steer * 0.45, clampf(delta * 6.0, 0.0, 1.0))
	if not is_tank() or _turret == null:
		return
	# links and wheel holes repeat every few centimetres, so above walking pace
	# the true speed strobes into a crawl or even runs backwards on screen;
	# like the arcade games, roll them at a capped speed that always reads
	var roll := clampf(forward_speed, -ROLL_MAX, ROLL_MAX)
	_track_mat.uv1_offset.x = fmod(_track_mat.uv1_offset.x + roll * delta / LINK, 1.0)
	for i in _road_wheels.size():
		_road_wheels[i].rotation.x -= roll * delta / _wheel_r[i]
	_turret.rotation.y = lerpf(_turret.rotation.y, -steer * 0.35, clampf(delta * 3.0, 0.0, 1.0))
	if _gun:
		# stabiliser: hold the barrel level while the hull pitches, within the
		# gun's elevation limits, with a little lag so bumps still show
		var hull_pitch := asin(clampf(-global_basis.z.normalized().y, -1.0, 1.0))
		var aim := clampf(-hull_pitch, -0.12, 0.3)
		_gun.rotation.x = lerpf(_gun.rotation.x, aim, clampf(delta * 5.0, 0.0, 1.0))
