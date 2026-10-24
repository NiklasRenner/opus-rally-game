class_name Geo
extends RefCounted
## Geometry helpers shared by the code that builds meshes (cars, trees,
## stages, the start area).

static var _wind := 0.0


## +1 if Godot's front faces have cross(b - a, c - a) pointing outward, else -1.
static func winding() -> float:
	if _wind == 0.0:
		var arr := BoxMesh.new().get_mesh_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var cr := (v[idx[1]] - v[idx[0]]).cross(v[idx[2]] - v[idx[0]])
		_wind = 1.0 if cr.dot(n[idx[0]]) > 0.0 else -1.0
	return _wind


## True if triangle a, b, c has to be emitted as a, c, b for its front face
## to point along `n`.
static func flipped(a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> bool:
	return (b - a).cross(c - a).dot(n) * winding() < 0.0
