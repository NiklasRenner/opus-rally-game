extends Node3D
## The race scene. Builds the chosen map, car, camera and HUD in code and runs
## the race: countdown, laps (or one run from start to finish on a
## point-to-point stage, with split times on the way), ghost recording and
## playback, finish, pause.

# Hidden checkpoints are off until they have something to show them on the
# road; meanwhile a lap only needs the car to have been half way round.
const CHECKPOINTS := false
const CHECKPOINT_SPACING := 200.0  # metres of road between hidden checkpoints
const CHECKPOINT_MARGIN := TrackBuilder.VERGE + 4.0  # beyond the road edge, room to cut an apex
const FINISH_MARGIN := 1.0  # beyond the road edge: the car has to go under the gantry
const SPLITS := 3  # split times on the way along a point-to-point stage
const FALL_DEPTH := 7.0  # this far below the road it last drove on, a car has gone over the edge
const FALL_TIME := 1.3  # seconds of falling to watch before it's put back on the road

var track: TrackBuilder
var car: RallyCar
var cam: CameraRig
var hud: Hud
var audio: EngineAudio
var overlay: RaceMenu
var look: RetroLook

# race state read by the HUD
var race_time := 0.0
var lap_time := 0.0
var lap := 1
var total_laps := 3
var best_lap := INF
var last_lap := INF
var ghost_time := INF
var progress_fraction := 0.0
var message := ""
var split_text := ""
var finished := false
var point_to_point := false  # one run from start to finish, no laps
var splits_passed := 0  # point-to-point: split points passed so far, of SPLITS
var distance_to_go := 0.0  # metres to the finish on a point-to-point stage

var _countdown := 3.6
var _racing := false
var _progress_index := 0
var _gates := PackedInt32Array()  # road sample of each checkpoint in order, the finish line last
var _next_gate := 0
var _halfway := false  # been half way round this lap, the rule while checkpoints are off
var _last_pos := Vector3.ZERO
var _cliffs := false  # the stage has drops a car can go over (see _check_fall)
var _on_road := -1  # road sample the car was last on, where a fall puts it back
var _fall_timer := -1.0
var _message_timer := 0.0
var _split_timer := 0.0
var _splits := PackedFloat32Array()  # race time at each lap line, or each split point and the finish
var _split_points := PackedInt32Array()  # road samples of a point-to-point stage's split points

# ghosts
var _recording := PackedFloat32Array()
var _record_clock := 0.0
var ghost: Ghost  # read by the HUD minimap
var _ghost_splits := PackedFloat32Array()

# weather
var _headlights := false
var _rain: CPUParticles3D
var _env: Environment
var _sun: DirectionalLight3D
var _palette: Dictionary


func _ready() -> void:
	point_to_point = Maps.get_map(Game.map_id).get("point_to_point", false)
	total_laps = 1 if point_to_point else Game.laps
	best_lap = Game.best_lap()
	_setup_environment()
	# the world keeps its gravity between races, so every stage sets its own
	var gravity: float = Maps.get_map(Game.map_id).get("gravity", ProjectSettings.get_setting("physics/3d/default_gravity"))
	PhysicsServer3D.area_set_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, gravity)

	track = TrackBuilder.new()
	track.name = "Track"
	track.map = Maps.get_map(Game.map_id)
	track.rain = Game.race_rain
	add_child(track)
	track.build()

	car = RallyCar.new()
	car.name = "Car"
	car.spec = Cars.get_car(Game.car_id)
	add_child(car)
	car.place(track.get_spawn_transform(track.wrap_index(track.start_index - 4)))
	car.impact.connect(_on_impact)
	car.rain = Game.race_rain
	car.gravity = gravity
	car.manual_gears = Game.manual_gears
	var marks := SkidMarks.new()
	marks.name = "SkidMarks"
	add_child(marks)
	car.marks = marks
	if _headlights:
		car.set_headlights(true)
	if Game.race_rain:
		_build_rain()

	if Game.ghost_enabled:
		var data := Game.load_ghost()
		if not data.is_empty():
			ghost = Ghost.new()
			add_child(ghost)
			ghost.setup(data)
			ghost_time = data.get("time", INF)
			_ghost_splits = data.get("splits", PackedFloat32Array())

	cam = CameraRig.new()
	cam.target = car
	cam.track = track
	add_child(cam)
	cam.current = true
	cam.snap()

	audio = EngineAudio.new()
	audio.car = car
	add_child(audio)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.car = car
	hud.track = track
	hud.cam = cam
	hud.race = self
	layer.add_child(hud)
	hud.setup_map()
	overlay = RaceMenu.new()
	overlay.race = self
	layer.add_child(overlay)
	_progress_index = track.wrap_index(track.start_index - 4)
	_last_pos = track.get_spawn_transform(_progress_index).origin
	var span := track.count() if track.loop else track.finish_index - track.start_index
	if CHECKPOINTS:
		var gate_count := maxi(4, roundi(track.stage_length / CHECKPOINT_SPACING))
		for k in range(1, gate_count):
			_gates.append(track.start_index + k * span / gate_count)
	_gates.append(track.finish_index)
	if point_to_point:
		# split times along the way, against the ghost's at the same points
		for k in range(1, SPLITS + 1):
			_split_points.append(track.start_index + k * span / (SPLITS + 1))
	_cliffs = track.map.has("cliffs") or track.map.has("geo")
	distance_to_go = track.stage_length

	look = RetroLook.new()
	look.env = _env
	look.sun = _sun
	look.car = car
	look.sky_colors = [_palette["sky_top"], _palette["sky_horizon"], _palette["sky_ground"]]
	add_child(look)
	look.setup(self, Game.retro_look)


func _setup_environment() -> void:
	var theme: String = Maps.get_map(Game.map_id).get("theme", "")
	var p := Conditions.palette(theme, Game.race_rain)
	_palette = p
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = Conditions.sky(p)
	sky.sky_material = pano
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = p["ambient"]
	env.ambient_light_energy = p["ambient_energy"]
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = p["fog"]
	env.fog_density = p["fog_density"]
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = p["sun_dir"]
	sun.light_color = p["sun_color"]
	sun.light_energy = p["sun_energy"]
	sun.shadow_enabled = p["shadows"]
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	_sun = sun
	_headlights = p["headlights"]


## Rain: streaks falling around the camera wherever it goes.
func _build_rain() -> void:
	_rain = CPUParticles3D.new()
	_rain.amount = 900
	_rain.lifetime = 0.7
	_rain.preprocess = 0.7
	_rain.local_coords = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(22, 1, 22)
	_rain.direction = Vector3(0.15, -1, 0.05)
	_rain.spread = 3.0
	_rain.initial_velocity_min = 26.0
	_rain.initial_velocity_max = 32.0
	_rain.gravity = Vector3(0, -9.8, 0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.9)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.82, 0.95, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	quad.material = mat
	_rain.mesh = quad
	add_child(_rain)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"):
		if not finished:
			overlay.open_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("look"):
		Game.retro_look = not Game.retro_look
		look.set_enabled(Game.retro_look)
		_flash("ARCADE LOOK" if Game.retro_look else "MODERN LOOK", 1.0)
	elif finished:
		return
	elif event.is_action_pressed("camera"):
		cam.cycle()
	elif event.is_action_pressed("reset"):
		reset_car()
	elif event.is_action_pressed("restart"):
		restart()


## Put the car back on the road: where it is, or at road sample `at`.
func reset_car(at := -1) -> void:
	var idx := at if at >= 0 else track.nearest_index(car.global_position, _progress_index)
	# never past a checkpoint the car hasn't been through, so a reset can't skip one
	if _gate_missed(idx) >= 0:
		idx = track.wrap_index(_gates[_next_gate] - 3)
	# nor out on a point-to-point stage's lead-in or run-out
	if not track.loop:
		idx = clampi(idx, track.start_index, track.finish_index - 3)
	var xf := track.get_spawn_transform(idx)
	car.place(xf)
	_last_pos = xf.origin
	cam.snap()


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://menu.tscn")


func _on_impact(strength: float, _zone: String) -> void:
	cam.shake(strength)
	audio.crash(strength)
	if strength > 0.6:
		_flash("CRASH!", 0.8)


func _flash(text: String, t: float) -> void:
	message = text
	_message_timer = t


func _physics_process(delta: float) -> void:
	# countdown 3, 2, 1, GO
	if not _racing:
		_countdown -= delta
		if _countdown > 0.6:
			message = str(int(ceil(_countdown - 0.6)))
		else:
			_racing = true
			car.control_enabled = true
			_flash("GO!", 1.0)
		return
	if finished:
		_update_ghost()
		return

	race_time += delta
	lap_time += delta
	_record(delta)
	_update_ghost()

	var pos := car.global_position
	var idx := track.nearest_index(pos, _progress_index)
	if track.frac_of(idx) > 0.45 and track.frac_of(idx) < 0.55:
		_halfway = true
	# laps count only through every checkpoint in order and then the finish gate
	var gate := _gates[_next_gate]
	if (CHECKPOINTS or _halfway) and _through_gate(gate, _last_pos, pos):
		_next_gate += 1
		if _next_gate == _gates.size():
			_next_gate = 0
			_halfway = false
			_complete_lap()
	if splits_passed < _split_points.size() and idx >= _split_points[splits_passed] and idx - _split_points[splits_passed] < 20:
		splits_passed += 1
		_split()
	_last_pos = pos
	_progress_index = idx
	progress_fraction = clampf(track.frac_of(idx), 0.0, 1.0)
	if point_to_point:
		distance_to_go = maxf(track.finish_index - idx, 0) * track.stage_length / (track.finish_index - track.start_index)
	if _cliffs:
		_check_fall(delta, idx)

	# wrong way and missed checkpoint warnings
	if _message_timer <= 0.0 and not finished:
		if _gate_missed(idx) >= 3:
			message = "MISSED CHECKPOINT"
		elif car.linear_velocity.dot(track.tangents[idx]) < -4.0:
			message = "WRONG WAY"
		else:
			message = ""


## Did the car go forwards through the gate across road sample `i` between
## positions `a` and `b`? The gate spans the road plus a margin either side,
## a narrow one at the finish line.
func _through_gate(i: int, a: Vector3, b: Vector3) -> bool:
	var c := track.points[i]
	var t := Vector3(track.tangents[i].x, 0.0, track.tangents[i].z).normalized()
	var da := (a - c).dot(t)
	var db := (b - c).dot(t)
	if da >= 0.0 or db < 0.0:
		return false
	var x := a.lerp(b, da / (da - db))
	var lateral := absf((x - c).dot(Vector3(-t.z, 0.0, t.x)))
	var margin := FINISH_MARGIN if i == track.finish_index else CHECKPOINT_MARGIN
	return lateral <= track.widths[i] * 0.5 + margin and absf(x.y - c.y) < 10.0


## How many road samples road sample `idx` lies beyond the next checkpoint, or -1
## while it is still between the last checkpoint passed and the next one (or
## behind them).
func _gate_missed(idx: int) -> int:
	if _gates.size() < 2:
		return -1
	var n := track.count()
	var nxt := _gates[_next_gate]
	if not track.loop:
		return idx - nxt if idx >= nxt else -1
	var prev := _gates[_next_gate - 1] if _next_gate > 0 else _gates[_gates.size() - 1]
	if wrapi(idx - prev, 0, n) < wrapi(nxt - prev, 0, n):
		return -1
	var ahead := wrapi(idx - nxt, 0, n)
	return ahead if ahead < wrapi(prev - idx, 0, n) else -1


func _complete_lap() -> void:
	last_lap = lap_time
	_split()
	var new_best := Game.submit_lap(lap_time)
	if new_best:
		best_lap = lap_time
	if lap >= total_laps:
		_finish()
		return
	lap += 1
	lap_time = 0.0
	if new_best:
		_flash("BEST LAP!", 2.0)
	elif lap == total_laps:
		_flash("FINAL LAP", 2.0)
	else:
		_flash("LAP %d" % lap, 1.5)


## Note the race time at a lap line (or a point-to-point split point) and show
## the split against the ghost's time at the same one.
func _split() -> void:
	_splits.append(race_time)
	var k := _splits.size() - 1
	if k < _ghost_splits.size():
		var d := race_time - _ghost_splits[k]
		split_text = "%s%.2f" % ["+" if d >= 0.0 else "-", absf(d)]
		_split_timer = 3.0


## Over the edge of a cliff: once the car has dropped well below the road it
## was last on, give it a moment to fall, then put it back on that road
## (behind the next checkpoint, as any reset).
func _check_fall(delta: float, idx: int) -> void:
	var pos := car.global_position
	if _fall_timer < 0.0:
		if track.distance_to_road(pos, idx) < track.widths[idx] * 0.5 + TrackBuilder.VERGE + 1.0 \
				and absf(pos.y - track.points[idx].y) < 3.0:
			_on_road = idx
		if _on_road >= 0 and pos.y < track.points[_on_road].y - FALL_DEPTH:
			_fall_timer = FALL_TIME
			_flash("OFF THE CLIFF!", FALL_TIME + 0.4)
	else:
		_fall_timer -= delta
		if _fall_timer <= 0.0:
			_fall_timer = -1.0
			reset_car(_on_road)


func _finish() -> void:
	finished = true
	car.control_enabled = false
	car.stopping = point_to_point  # there's a wall at the end of the run-out
	message = ""
	var faster_ghost := race_time < Game.ghost_time()
	if faster_ghost:
		Game.save_ghost({"time": race_time, "name": Game.last_initials, "rate": Ghost.RATE,
			"frames": _recording, "splits": _splits, "car": Game.car_id})
	overlay.open_results(race_time, faster_ghost)


## When the player enters initials, stamp them on the ghost they just set.
func name_ghost(initials: String) -> void:
	var g := Game.load_ghost()
	if not g.is_empty() and is_equal_approx(g.get("time", -1.0), race_time):
		g["name"] = initials
		Game.save_ghost(g)


func _record(delta: float) -> void:
	_record_clock += delta
	while _record_clock >= 0.0:
		Ghost.record(_recording, car.global_transform)
		_record_clock -= 1.0 / Ghost.RATE


func _update_ghost() -> void:
	if ghost:
		ghost.show_at(race_time)


func _process(delta: float) -> void:
	if _rain:
		_rain.global_position = cam.global_position + car.linear_velocity * 0.4 + Vector3(0, 14, 0)
	if _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			message = ""
	if _split_timer > 0.0:
		_split_timer -= delta
		if _split_timer <= 0.0:
			split_text = ""
