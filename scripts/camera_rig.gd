class_name CameraRig
extends Camera3D
## Switchable driving views. Press C (or pad Y) to cycle. Hold F (or click the
## right stick) to look back: the camera sits ahead of the car facing it, with
## the road behind in view, until the key is let go.

const MODES := ["CHASE", "FAR CHASE", "HOOD", "BUMPER", "TV"]

var target: RallyCar
var track: TrackBuilder
var mode := 0
var _dir := Vector3.FORWARD
var _height := 2.0
var _shake := 0.0
var _tv_spot := Vector3.ZERO
var _tv_index := -1000


func _ready() -> void:
	process_physics_priority = 100  # after the car has moved
	far = 4000.0
	near = 0.05


func cycle() -> void:
	mode = (mode + 1) % MODES.size()
	_tv_index = -1000


func mode_name() -> String:
	if Input.is_action_pressed("look_back"):
		return "LOOK BACK"
	return MODES[mode]


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func snap() -> void:
	if target:
		_dir = _flat_forward()
		_physics_process(1.0 / 60.0)


func _flat_forward() -> Vector3:
	var f := -target.global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.01:
		return _dir
	return f.normalized()


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var car_xf := target.global_transform
	var car_pos := car_xf.origin
	var speed_fov := clampf(target.speed * 0.25, 0.0, 12.0)
	if Input.is_action_pressed("look_back"):
		_look_back(car_pos, delta)
		_apply_shake(delta)
		return
	match MODES[mode]:
		"CHASE", "FAR CHASE":
			var far_cam: bool = MODES[mode] == "FAR CHASE"
			var dist := 9.5 if far_cam else 6.6
			var h := 3.6 if far_cam else 2.5
			_dir = _dir.slerp(_flat_forward(), clampf(delta * 5.0, 0.0, 1.0)).normalized()
			_height = lerpf(_height, car_pos.y + h, clampf(delta * 6.0, 0.0, 1.0))
			var want := car_pos - _dir * dist
			want.y = _height
			global_position = _clear_of_walls(car_pos, want)
			look_at(car_pos + _dir * 5.0 + Vector3.UP * 1.0, Vector3.UP)
			fov = (62.0 if far_cam else 68.0) + speed_fov
		"HOOD":
			global_transform = car_xf * Transform3D(Basis(Vector3.RIGHT, -0.06), Vector3(0, 0.78, -0.55))
			fov = 74.0 + speed_fov
		"BUMPER":
			global_transform = car_xf * Transform3D(Basis(), Vector3(0, 0.02, -2.3))
			fov = 80.0 + speed_fov
		"TV":
			_update_tv(car_pos)
			look_at(car_pos + Vector3.UP * 0.5, Vector3.UP)
			fov = clampf(2400.0 / maxf(global_position.distance_to(car_pos), 1.0), 18.0, 70.0)
	_apply_shake(delta)


func _apply_shake(delta: float) -> void:
	if _shake > 0.0:
		h_offset = randf_range(-1.0, 1.0) * _shake * 0.25
		v_offset = randf_range(-1.0, 1.0) * _shake * 0.25
		_shake = move_toward(_shake, 0.0, delta * 2.5)
	else:
		h_offset = 0.0
		v_offset = 0.0


## Arcade look-back: in front of the car and a little above, facing back over
## it at the road behind. Keeps the chase direction up to date so letting go
## of the key drops straight back into the chosen view.
func _look_back(car_pos: Vector3, delta: float) -> void:
	_dir = _dir.slerp(_flat_forward(), clampf(delta * 5.0, 0.0, 1.0)).normalized()
	_height = lerpf(_height, car_pos.y + 2.5, clampf(delta * 6.0, 0.0, 1.0))
	var want := car_pos + _dir * 6.6
	want.y = car_pos.y + 2.2
	global_position = _clear_of_walls(car_pos, want)
	look_at(car_pos - _dir * 5.0 + Vector3.UP * 1.0, Vector3.UP)
	fov = 68.0


## Pull a camera spot in towards the car if a wall or hill is in between.
func _clear_of_walls(car_pos: Vector3, want: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(car_pos + Vector3.UP, want, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		return (hit["position"] as Vector3) + (car_pos - want).normalized() * 0.4
	return want


## Trackside camera: pick a spot ahead of the car, hold it until the car passes.
func _update_tv(car_pos: Vector3) -> void:
	if track == null:
		return
	var n := track.count()
	var idx := track.nearest_index(car_pos, maxi(_tv_index, 0))
	var behind := track.ahead(_tv_index, idx)
	if _tv_index < 0 or (behind > 12 and behind < n / 2):
		_tv_index = track.wrap_index(idx + 22)
		var side := track.tangents[_tv_index].cross(Vector3.UP).normalized()
		var s := 1.0 if (_tv_index / 22) % 2 == 0 else -1.0
		_tv_spot = track.points[_tv_index] + side * s * 13.0 + Vector3.UP * 3.5
	global_position = _tv_spot
