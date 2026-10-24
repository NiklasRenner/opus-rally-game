class_name Ghost
extends Node3D
## Records the car's pose at a fixed rate during a race, and plays a recorded
## race back as a see-through car you can race against.

const RATE := 20.0  # samples per second
const STRIDE := 7  # x, y, z, qx, qy, qz, qw

var frames := PackedFloat32Array()


# --------------------------------------------------------------------------- recording

static func record(into: PackedFloat32Array, xf: Transform3D) -> void:
	var q := xf.basis.get_rotation_quaternion()
	into.append_array([xf.origin.x, xf.origin.y, xf.origin.z, q.x, q.y, q.z, q.w])


# --------------------------------------------------------------------------- playback

func setup(data: Dictionary) -> void:
	frames = data.get("frames", PackedFloat32Array())
	var model := CarModel.new()
	model.spec = Cars.get_car(data.get("car", ""))
	add_child(model)
	model.build()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.85, 1.0, 0.38)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	_apply_ghost_material(model, mat)
	var tag := Label3D.new()
	tag.text = "GHOST"
	tag.font_size = 48
	tag.outline_size = 10
	tag.modulate = Color(0.6, 0.9, 1.0, 0.85)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	tag.position = Vector3(0, 1.8, 0)
	add_child(tag)
	visible = false


func _apply_ghost_material(node: Node, mat: Material) -> void:
	for c in node.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_override = mat
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif c is Label3D:
			c.queue_free()  # door numbers would show through
		_apply_ghost_material(c, mat)


func sample_count() -> int:
	return frames.size() / STRIDE


## Show the ghost where it was `t` seconds after the start.
func show_at(t: float) -> void:
	var n := sample_count()
	if n < 2:
		visible = false
		return
	var f := t * RATE
	var i := int(floor(f))
	if i >= n - 1:
		visible = false  # ghost has finished
		return
	visible = t >= 0.0
	var a := _pose(i)
	var b := _pose(i + 1)
	global_transform = a.interpolate_with(b, f - i)


func _pose(i: int) -> Transform3D:
	var k := i * STRIDE
	var q := Quaternion(frames[k + 3], frames[k + 4], frames[k + 5], frames[k + 6]).normalized()
	return Transform3D(Basis(q), Vector3(frames[k], frames[k + 1], frames[k + 2]))
