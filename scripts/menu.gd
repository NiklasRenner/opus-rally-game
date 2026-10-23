extends Control
## Main menu: pick a stage, car, lap count, ghost and weather, and see the
## stage's records.
## The car row swaps the stage preview for a turntable of the chosen car.
## Arrow keys / d-pad to move and change, Enter / A to confirm.

const ROWS := ["STAGE", "CAR", "LAPS", "GHOST", "WEATHER", "START RACE", "QUIT"]
const OPTION_ROWS := 5
const ROW_H := 23

var _sel := 0
var _map_i := 0
var _car_i := 0
var _previews: Array = []  # per map: {"pts": PackedVector2Array, "cols": PackedColorArray, "length": float}
var _sky: Texture2D
var _ghost_info := {}
var _t := 0.0
var _showroom: SubViewport
var _turntable: Node3D


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_sky = TexGen.sky_panorama()
	_map_i = Maps.index_of(Game.map_id)
	_car_i = Cars.index_of(Game.car_id)
	_build_showroom()
	for m in Maps.LIST:
		var tb := TrackBuilder.new()
		tb.map = m
		tb.prepare()
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for i in range(0, tb.count(), 2):
			pts.append(Vector2(tb.points[i].x, tb.points[i].z))
			cols.append(Surfaces.get_surface(tb.surfaces[i])["hud"])
		_previews.append({"pts": pts, "cols": cols, "length": tb.total_length})
		tb.free()
	_refresh()


## A little 3D scene rendered off screen and drawn into the right panel.
func _build_showroom() -> void:
	_showroom = SubViewport.new()
	_showroom.size = Vector2i(300, 104)
	_showroom.own_world_3d = true
	_showroom.transparent_bg = true
	_showroom.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_showroom)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.70, 0.85)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	_showroom.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.1
	_showroom.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 1.7, 6.6)
	_showroom.add_child(cam)
	cam.look_at(Vector3(0, 0.0, 0), Vector3.UP)
	var floor_mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 2.5
	disc.bottom_radius = 2.5
	disc.height = 0.08
	disc.radial_segments = 16
	floor_mi.mesh = disc
	floor_mi.material_override = TexGen.material(TexGen.checker(), 0.9, Color(0.75, 0.75, 0.8))
	floor_mi.position.y = -0.76
	_showroom.add_child(floor_mi)
	_turntable = Node3D.new()
	_showroom.add_child(_turntable)


func _show_car() -> void:
	for c in _turntable.get_children():
		c.queue_free()
	var model := CarModel.new()
	model.spec = Cars.LIST[_car_i]
	_turntable.add_child(model)
	model.build()
	model.add_display_wheels()


func _refresh() -> void:
	Game.map_id = Maps.LIST[_map_i]["id"]
	if Game.car_id != Cars.LIST[_car_i]["id"] or _turntable.get_child_count() == 0:
		Game.car_id = Cars.LIST[_car_i]["id"]
		_show_car()
	_ghost_info = Game.load_ghost()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("ui_up"):
		_sel = wrapi(_sel - 1, 0, ROWS.size())
	elif event.is_action_pressed("ui_down"):
		_sel = wrapi(_sel + 1, 0, ROWS.size())
	elif event.is_action_pressed("ui_left"):
		_change(-1)
	elif event.is_action_pressed("ui_right"):
		_change(1)
	elif event.is_action_pressed("ui_accept"):
		match ROWS[_sel]:
			"START RACE":
				Game.roll_conditions()
				get_tree().change_scene_to_file("res://main.tscn")
			"QUIT":
				get_tree().quit()
			_:
				_change(1)
	elif event.is_action_pressed("quit"):
		get_tree().quit()
	else:
		return
	if is_inside_tree():  # starting a race swaps the scene out from under us
		get_viewport().set_input_as_handled()
		queue_redraw()


func _change(dir: int) -> void:
	match ROWS[_sel]:
		"STAGE":
			_map_i = wrapi(_map_i + dir, 0, Maps.LIST.size())
		"CAR":
			_car_i = wrapi(_car_i + dir, 0, Cars.LIST.size())
		"LAPS":
			var opts: Array = Game.LAP_OPTIONS
			Game.laps = opts[wrapi(opts.find(Game.laps) + dir, 0, opts.size())]
		"GHOST":
			Game.ghost_enabled = not Game.ghost_enabled
		"WEATHER":
			var w: Array = Conditions.WEATHERS
			Game.weather = w[wrapi(w.find(Game.weather) + dir, 0, w.size())]
	_refresh()


func _process(delta: float) -> void:
	_t += delta
	_turntable.rotation.y += delta * 0.8
	queue_redraw()


func _draw() -> void:
	var vs := get_viewport_rect().size
	# sky backdrop + a scrolling checker strip
	draw_texture_rect_region(_sky, Rect2(Vector2.ZERO, vs), Rect2(fmod(_t * 6.0, 256.0), 20, 256, 110))
	for x in range(-32, int(vs.x) + 32, 16):
		var ox := x + int(fmod(_t * 40.0, 32.0))
		for row in 2:
			var c := Color.WHITE if ((ox / 16 + row) % 2 == 0) else RetroUI.INK
			draw_rect(Rect2(ox, vs.y - 24 + row * 12, 16, 12), c)
	RetroUI.italic(self, Vector2(22, 54), "RETRO RALLY", 46, RetroUI.YELLOW, 8)
	RetroUI.text(self, Vector2(26, 74), "late-90s arcade rally", 12, Color.WHITE, 3)

	var map: Dictionary = Maps.LIST[_map_i]
	var prev: Dictionary = _previews[_map_i]

	# --- options
	var left := Rect2(20, 88, 270, 212)
	RetroUI.panel(self, left)
	var car: Dictionary = Cars.LIST[_car_i]
	var values := ["< %s >" % map["name"], "< %s >" % car["name"], "< %d >" % Game.laps,
		"< %s >" % ("ON" if Game.ghost_enabled else "OFF"), "< %s >" % Game.weather, "", ""]
	for i in ROWS.size():
		var y := left.position.y + 26 + i * ROW_H + (8 if i >= OPTION_ROWS else 0)
		if i == _sel:
			RetroUI.cursor(self, Rect2(left.position.x + 8, y - 16, left.size.x - 16, ROW_H))
		var col := RetroUI.YELLOW if i == _sel else Color.WHITE
		if i < OPTION_ROWS:
			RetroUI.text(self, Vector2(left.position.x + 16, y), ROWS[i], 14, RetroUI.CYAN, 3)
			RetroUI.text(self, Vector2(left.position.x + 90, y), values[i], 14, col, 3)
		else:
			RetroUI.italic(self, Vector2(left.position.x + 18, y), ROWS[i], 18, col, 5)
	RetroUI.text(self, Vector2(left.position.x + 16, left.end.y - 12), "%s  %.1f km" % [map["blurb"], prev["length"] / 1000.0], 10, Color(0.85, 0.9, 1.0), 2)

	var right := Rect2(306, 88, 314, 212)
	RetroUI.panel(self, right)
	if ROWS[_sel] == "CAR":
		_draw_car(right, car)
	else:
		_draw_stage(right, map, prev)
	RetroUI.text(self, Vector2(22, vs.y - 32), "ARROWS / D-PAD  select     ENTER / A  confirm     ESC  quit", 10, Color.WHITE, 3)


func _draw_car(right: Rect2, car: Dictionary) -> void:
	draw_texture(_showroom.get_texture(), right.position + Vector2(7, 46))
	RetroUI.italic(self, right.position + Vector2(14, 28), car["name"], 20, RetroUI.YELLOW, 5)
	RetroUI.text(self, right.position + Vector2(16, 44), car["blurb"], 11, Color.WHITE, 3)
	var stats: Dictionary = car["stats"]
	# bars relative to the spread across the garage
	var bars := [["ACCEL", RallyCar.accel(car), _range(RallyCar.accel)], ["TOP SPD", RallyCar.top_speed(car), _range(RallyCar.top_speed)],
		["GRIP", stats["grip"], Vector2(0.9, 1.16)], ["TURN-IN", stats["steer"], Vector2(0.85, 1.3)]]
	for i in bars.size():
		var b: Array = bars[i]
		var x := right.position.x + 16 + (i % 2) * 150
		var y := right.position.y + 156 + (i / 2) * 22
		RetroUI.text(self, Vector2(x, y), b[0], 10, RetroUI.CYAN, 2)
		var frac := clampf(inverse_lerp(b[2].x * 0.85, b[2].y, b[1]), 0.08, 1.0)
		var bar := Rect2(x + 54, y - 8, 80, 8)
		draw_rect(bar.grow(1), RetroUI.INK)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), RetroUI.YELLOW)
	RetroUI.text(self, Vector2(right.position.x + 16, right.end.y - 8), "%d kg   top %d km/h      %d/%d  LEFT / RIGHT" % [stats["mass"], RallyCar.top_speed(car),
		_car_i + 1, Cars.LIST.size()],
		10, Color(0.85, 0.9, 1.0), 2)


## Smallest and largest value of a per-car figure across the garage.
func _range(f: Callable) -> Vector2:
	var r := Vector2(INF, -INF)
	for c in Cars.LIST:
		var v: float = f.call(c)
		r = Vector2(minf(r.x, v), maxf(r.y, v))
	return r


func _draw_stage(right: Rect2, map: Dictionary, prev: Dictionary) -> void:
	# --- stage preview
	var pts: PackedVector2Array = prev["pts"]
	var cols: PackedColorArray = prev["cols"]
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	var box := Rect2(right.position + Vector2(12, 14), Vector2(130, 130))
	var sc := minf(box.size.x / (mx.x - mn.x), box.size.y / (mx.y - mn.y))
	var off := box.get_center() - (mn + mx) * 0.5 * sc
	for i in pts.size():
		var j := (i + 1) % pts.size()
		draw_line(off + pts[i] * sc, off + pts[j] * sc, RetroUI.INK, 5.0)
	for i in pts.size():
		var j := (i + 1) % pts.size()
		draw_line(off + pts[i] * sc, off + pts[j] * sc, cols[i], 3.0)
	var dot := int(fmod(_t * 18.0, pts.size()))
	draw_circle(off + pts[dot] * sc, 4.0, RetroUI.RED)
	draw_circle(off + pts[0] * sc, 3.0, Color.WHITE)

	# --- records for this stage + lap count
	var rx := right.position.x + 156
	var ry := right.position.y + 24
	RetroUI.text(self, Vector2(rx, ry), "TOP 5  %d LAP%s" % [Game.laps, "S" if Game.laps > 1 else ""], 12, RetroUI.YELLOW, 3)
	var list := Game.scores()
	for i in Game.MAX_SCORES:
		var y := ry + 18 + i * 16
		if i < list.size():
			var e: Dictionary = list[i]
			RetroUI.text(self, Vector2(rx, y), "%d %s" % [i + 1, e["name"]], 12, Color.WHITE, 3)
			RetroUI.text(self, Vector2(rx + 64, y), Hud.fmt_time(e["time"]), 12, Color.WHITE, 3)
		else:
			RetroUI.text(self, Vector2(rx, y), "%d ---" % (i + 1), 12, Color(0.6, 0.6, 0.7), 3)
	RetroUI.text(self, Vector2(rx, ry + 112), "BEST LAP", 11, RetroUI.GREEN, 3)
	RetroUI.text(self, Vector2(rx + 64, ry + 112), Hud.fmt_time(Game.best_lap()), 11, Color.WHITE, 3)
	RetroUI.text(self, Vector2(rx, ry + 130), "GHOST", 11, RetroUI.CYAN, 3)
	if _ghost_info.is_empty():
		RetroUI.text(self, Vector2(rx + 64, ry + 130), "none yet", 11, Color(0.7, 0.7, 0.8), 3)
	else:
		RetroUI.text(self, Vector2(rx + 64, ry + 130), "%s %s" % [_ghost_info.get("name", "???"), Hud.fmt_time(_ghost_info.get("time", INF))], 11, Color.WHITE, 3)
	RetroUI.text(self, Vector2(right.position.x + 12, right.end.y - 12), "surfaces:  tarmac", 10, Surfaces.get_surface("asphalt")["hud"], 2)
	RetroUI.text(self, Vector2(right.position.x + 110, right.end.y - 12), "gravel", 10, Surfaces.get_surface("gravel")["hud"], 2)
