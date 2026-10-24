extends Node3D
## The race scene. Builds the chosen map, car, camera and HUD in code and runs
## the race: countdown, laps, ghost recording and playback, finish, pause.

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

var _countdown := 3.6
var _racing := false
var _progress_index := 0
var _checkpoint := false
var _message_timer := 0.0
var _split_timer := 0.0
var _splits := PackedFloat32Array()

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
	total_laps = Game.laps
	best_lap = Game.best_lap()
	_setup_environment()

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
	car.place(track.get_spawn_transform(track.count() - 4))
	car.impact.connect(_on_impact)
	car.rain = Game.race_rain
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
	_progress_index = track.count() - 4

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


func reset_car() -> void:
	var idx := track.nearest_index(car.global_position, _progress_index)
	car.place(track.get_spawn_transform(idx))
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

	var n := track.count()
	var idx := track.nearest_index(car.global_position, _progress_index)
	if idx > n * 0.45 and idx < n * 0.55:
		_checkpoint = true
	if _checkpoint and _progress_index > n * 0.85 and idx < n * 0.15:
		_checkpoint = false
		_complete_lap()
	_progress_index = idx
	progress_fraction = float(idx) / n

	# wrong way warning
	if _message_timer <= 0.0 and not finished:
		message = "WRONG WAY" if car.linear_velocity.dot(track.tangents[idx]) < -4.0 else ""


func _complete_lap() -> void:
	last_lap = lap_time
	_splits.append(race_time)
	var new_best := Game.submit_lap(lap_time)
	if new_best:
		best_lap = lap_time
	# split against the ghost at the same lap line
	var k := _splits.size() - 1
	if k < _ghost_splits.size():
		var d := race_time - _ghost_splits[k]
		split_text = "%s%.2f" % ["+" if d >= 0.0 else "-", absf(d)]
		_split_timer = 3.0
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


func _finish() -> void:
	finished = true
	car.control_enabled = false
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
