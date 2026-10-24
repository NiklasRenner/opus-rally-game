class_name RallyCar
extends RigidBody3D
## Arcade raycast car. Each wheel casts a ray for suspension, then applies
## lateral grip and drive/brake forces limited by a friction circle whose
## size comes from the surface under that wheel. Once a tyre breaks loose it
## only gets `slide` x grip back until it has nearly stopped slipping, which is
## what makes ice and wet feel slippery and gravel feel drifty.

signal impact(strength: float, zone: String)

const WHEEL_RADIUS := Cars.WHEEL_RADIUS
const SUSP_REST := 0.42
const SPRING := 32000.0
const DAMPER := 2600.0
const BRAKE_FORCE := 15000.0
const HANDBRAKE_FORCE := 5000.0
const FINAL_DRIVE := 4.4
const GEAR_RATIOS := [3.3, 2.2, 1.65, 1.3, 1.06]  # gears 1..5
const REVERSE_RATIO := 3.4
const IDLE_RPM := 1000.0
const REDLINE := 8000.0
const PEAK_TORQUE := 470.0
const AERO_DRAG := 0.9
const DOWNFORCE := 1.4
const STEER_LOW := 0.62
const STEER_HIGH := 0.2
const WEIGHT_TRANSFER := 0.035  # grip shift per m/s^2 of longitudinal accel
const ENGINE_BRAKE := 1600.0
const YAW_INERTIA := 2000.0
const YAW_ASSIST := 5.0
const DRIFT_CAP := 0.8  # body slip angle (rad) where spin protection kicks in


class Wheel:
	var pos: Vector3
	var radius := WHEEL_RADIUS  # visual tyre radius (physics always uses WHEEL_RADIUS)
	var front: bool
	var pivot: Node3D
	var spinner: Node3D
	var fx: TyreFx
	var grounded := false
	var dist := 0.0
	var weight := 0.0
	var sliding := false
	var spinning := false
	var slip := 0.0
	var spin := 0.0
	var surface := "grass"
	var contact := Vector3.ZERO
	var normal := Vector3.UP


var spec: Dictionary = Cars.LIST[0]  # set before adding to the tree
var control_enabled := false
var manual_gears := false  # Up / Down shift; the automatic box takes over once control ends
var rain := false  # wet weather: less grip, spray off every tyre
var gravity := 9.81  # the stage's gravity (the Moon's is low); the assists scale with it
var marks: SkidMarks  # set by the race scene; tyre marks are left here
var model: CarModel
var wheels: Array[Wheel] = []

var throttle := 0.0
var brake := 0.0
var steer := 0.0
var handbrake := false
var steer_angle := 0.0

var gear := 1  # -1 reverse, 1..5
var rpm := IDLE_RPM
var shift_timer := 0.0
var _reverse_timer := 0.0

var speed := 0.0
var forward_speed := 0.0
var surface := "asphalt"
var skid := 0.0  # 0..1 how much tyres are sliding (audio / hud)

var damage := {"front": 0.0, "rear": 0.0, "left": 0.0, "right": 0.0}
var _impact_cooldown := 0.0
## Velocities over the last few physics steps. A hard hit is often resolved
## over several steps (pushed out of the wall rather than by one big contact
## impulse), so impacts are measured as the change across this window too.
var _vel_history: Array[Vector3] = []
const IMPACT_WINDOW := 6  # steps, 0.05 s at 120 Hz
var _prev_forward_speed := 0.0
var _accel_long := 0.0
var _load_shift := 0.0  # + = weight on the front (braking / lifting)
var body_slip := 0.0  # angle between heading and travel, for HUD / tests
var _upside_down_time := 0.0
var track_skid := 0.0  # tank: how much the tracks are skidding sideways to pivot
var _m := 1.0  # mass / reference mass: scales chassis forces so every vehicle rides alike

var _pending_place: Variant = null  # Transform3D applied inside _integrate_forces
var _smoke: CPUParticles3D
var _sparks: CPUParticles3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mass = spec["stats"]["mass"]
	_m = mass / Cars.REF_MASS
	collision_layer = 2
	collision_mask = 1 | 8
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.32, 0.05)
	angular_damp = 1.2
	linear_damp = 0.0
	contact_monitor = true
	max_contacts_reported = 8
	can_sleep = false
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.1
	physics_material_override = pm

	# body + cabin boxes, unless the spec brings its own
	var shapes: Array = spec.get("shapes", [[Vector3(1.74, 0.62, 4.1), Vector3(0, 0.12, 0)],
		[Vector3(1.3, 0.45, 1.8), Vector3(0, 0.62, 0.25)]])
	for sh in shapes:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = sh[0]
		cs.shape = box
		cs.position = sh[1]
		add_child(cs)

	if spec["stats"].has("inertia"):
		# small vehicles: a scaled saloon's yaw/roll inertia so the assists stay stable
		inertia = Vector3(1750.0, 2000.0, 360.0) * _m * stat("inertia")

	model = CarModel.new()
	model.spec = spec
	add_child(model)
	model.build()
	_build_wheels()
	_build_fx()


## Optional handling stat from the spec (drag, pivot, armour, pitch, gearing...).
func stat(key: String, default := 1.0) -> float:
	return spec["stats"].get(key, default)


## Rough performance figures for the menu bars: low-gear pull per kg
## (relative to the reference saloon) and top speed in km/h.
static func accel(spec: Dictionary) -> float:
	var st: Dictionary = spec["stats"]
	return st["power"] * st.get("gearing", 1.0) * Cars.REF_MASS / st["mass"]


static func top_speed(spec: Dictionary) -> float:
	# where the best gear's pull meets air drag, rolling resistance and the
	# physics engine's default linear damping (0.1 x mass x speed)
	var st: Dictionary = spec["stats"]
	var gearing: float = st.get("gearing", 1.0)
	var mass: float = st["mass"]
	var down: float = DOWNFORCE * mass / Cars.REF_MASS * st.get("downforce", 1.0)
	var v := 1.0
	while v < 120.0:
		var pull := 0.0
		for ratio in GEAR_RATIOS:
			var rpm: float = v / WHEEL_RADIUS * ratio * FINAL_DRIVE * gearing * 60.0 / TAU
			if rpm < REDLINE:
				pull = maxf(pull, torque_at(rpm) * ratio * FINAL_DRIVE * gearing / WHEEL_RADIUS * st["power"])
		var resist: float = AERO_DRAG * st.get("drag", 1.0) * v * v + 0.1 * mass * v \
			+ 0.012 * (mass * 9.81 + down * v * v) * (1.0 + v / 20.0)
		if pull < resist:
			break
		v += 0.5
	return v * 3.6


func _build_wheels() -> void:
	var wl := Cars.wheels(spec)
	var pos := Cars.wheel_positions(spec)
	var modelled := model.take_wheels()
	for i in 4:
		var w := Wheel.new()
		w.pos = pos[i]
		w.front = i < 2
		w.radius = wl["rf"] if w.front else wl["rr"]
		w.pivot = Node3D.new()
		w.pivot.position = w.pos
		add_child(w.pivot)
		w.spinner = Node3D.new()
		# small tyres sit lower than the physics wheel so they still touch the road
		w.spinner.position.y = w.radius - WHEEL_RADIUS
		w.pivot.add_child(w.spinner)
		if not modelled.is_empty():
			w.spinner.add_child(modelled[i])
		w.fx = TyreFx.new()
		add_child(w.fx)
		wheels.append(w)


func _make_particles(tex: Texture2D, amount: int, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = false
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true  # else idle particles show as black sprites
	quad.material = mat
	p.mesh = quad
	p.direction = Vector3(0, 1, 0)
	p.spread = 35.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	var curve := Curve.new()
	curve.max_value = 3.0
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.3))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = grad
	return p


func _build_fx() -> void:
	_smoke = _make_particles(TexGen.puff(), 30, 1.6)
	_smoke.color = Color(0.2, 0.2, 0.22, 0.8)
	_smoke.position = Vector3(0, 0.45, -1.4)
	add_child(_smoke)
	_sparks = CPUParticles3D.new()
	_sparks.amount = 24
	_sparks.lifetime = 0.5
	_sparks.one_shot = true
	_sparks.explosiveness = 0.95
	_sparks.emitting = false
	_sparks.local_coords = false
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.06, 0.06)
	bm.material = TexGen.flat_material(Color(1.0, 0.75, 0.2), 0.5, true)
	_sparks.mesh = bm
	_sparks.direction = Vector3(0, 1, 0)
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 3.0
	_sparks.initial_velocity_max = 8.0
	_sparks.gravity = Vector3(0, -12, 0)
	add_child(_sparks)


# --------------------------------------------------------------------------- input

func _read_input(delta: float) -> void:
	var t := 0.0
	var b := 0.0
	var s := 0.0
	var hb := false
	if control_enabled:
		t = Input.get_action_strength("accelerate")
		b = Input.get_action_strength("brake")
		s = Input.get_axis("steer_left", "steer_right")
		hb = Input.is_action_pressed("handbrake")
		if manual_gears:
			if Input.is_action_just_pressed("shift_up"):
				_shift(1)
			elif Input.is_action_just_pressed("shift_down"):
				_shift(-1)
	throttle = move_toward(throttle, t, delta * 6.0)
	brake = move_toward(brake, b, delta * 8.0)
	# keyboard steering ramps in, centres faster
	var rate := 8.0 if absf(s) > absf(steer) else 9.0
	steer = move_toward(steer, s, delta * rate)
	handbrake = hb


# --------------------------------------------------------------------------- physics

func _physics_process(delta: float) -> void:
	_read_input(delta)
	var b3 := global_transform.basis
	forward_speed = -b3.z.dot(linear_velocity)
	speed = linear_velocity.length()
	# weight transfer: braking/lifting loads the front tyres and unloads the
	# rears (the Scandinavian-flick / lift-off-oversteer trick), accelerating
	# does the opposite
	_accel_long = lerpf(_accel_long, (forward_speed - _prev_forward_speed) / delta, clampf(delta * 10.0, 0.0, 1.0))
	_prev_forward_speed = forward_speed
	_load_shift = clampf(-_accel_long * WEIGHT_TRANSFER, -0.3, 0.35)

	# reverse logic: hold brake while (nearly) stopped to back up
	var drive_input := throttle
	var brake_input := brake
	if gear == -1:
		drive_input = brake
		brake_input = throttle
		if throttle > 0.1 and forward_speed > -1.0:
			gear = 1
	elif brake > 0.5 and throttle < 0.1 and absf(forward_speed) < 1.0:
		_reverse_timer += delta
		if _reverse_timer > 0.25:
			gear = -1
	else:
		_reverse_timer = 0.0

	_update_gearbox(delta, drive_input)

	var power_mult: float = 1.0 - damage["front"] * 0.45 - (damage["left"] + damage["right"] + damage["rear"]) * 0.08
	power_mult = maxf(power_mult, 0.25) * (spec["stats"]["power"] as float)
	var ratio: float = -REVERSE_RATIO if gear == -1 else GEAR_RATIOS[gear - 1]
	var engine_force := torque_at(rpm) * ratio * FINAL_DRIVE * stat("gearing") / WHEEL_RADIUS * drive_input * power_mult
	if shift_timer > 0.0 or rpm >= REDLINE:
		engine_force *= 0.15
	if gear == -1:
		engine_force = maxf(engine_force, -6000.0)
	elif drive_input < 0.05 and forward_speed > 3.0:
		engine_force = -ENGINE_BRAKE * _m  # lifting off shifts weight forward

	# speed-sensitive steering + damage pulls the car to the bent side
	var max_steer := lerpf(STEER_LOW, STEER_HIGH, sqrt(clampf(speed / 40.0, 0.0, 1.0))) * (spec["stats"]["steer"] as float)
	var pull: float = (damage["left"] - damage["right"]) * 0.06
	steer_angle = -steer * max_steer + pull

	var pivot_fade := 1.0 - clampf(absf(forward_speed) / 9.0, 0.0, 1.0)
	track_skid = absf(steer) * pivot_fade if stat("pivot", 0.0) > 0.0 else 0.0
	var sliding := 0
	var grounded := 0
	var surf_votes := {}
	for w in wheels:
		_update_wheel(w, delta, engine_force * 0.25, brake_input)
		if w.grounded:
			grounded += 1
			surf_votes[w.surface] = surf_votes.get(w.surface, 0) + 1
		if w.sliding:
			sliding += 1
	if not surf_votes.is_empty():
		var best := 0
		for k in surf_votes:
			if surf_votes[k] > best:
				best = surf_votes[k]
				surface = k
	skid = move_toward(skid, float(sliding) / 4.0 * clampf(speed / 8.0, 0.0, 1.0), delta * 4.0)

	# aero
	apply_central_force(-linear_velocity * speed * AERO_DRAG * stat("drag"))
	if grounded > 0:
		apply_central_force(-b3.y * speed * speed * DOWNFORCE * _m * stat("downforce"))
		if grounded >= 2:
			_arcade_assists(b3, max_steer)
			if stat("pivot", 0.0) > 0.0:
				_skid_steer(b3)
	else:
		# airborne: slowly level out so landings are survivable
		var level := b3.y.cross(Vector3.UP)
		apply_torque((level * 2500.0 - angular_velocity * 400.0) * _m)

	_update_rpm(delta, drive_input)
	_leave_marks()
	model.animate(delta, forward_speed, steer)
	_update_fx(delta)
	_check_flipped(delta)
	_impact_cooldown = maxf(_impact_cooldown - delta, 0.0)


## The arcade layer on top of the tyre model, after Sega Rally style handling:
## the car rotates as much as the stick asks (within what the surface can
## plausibly give), counter-steer catches slides, and a drift angle cap stops
## a held slide turning into an instant spin.
func _arcade_assists(b3: Basis, max_steer: float) -> void:
	var up := b3.y
	var yaw := angular_velocity.dot(up)
	# downforce beyond a saloon's lets winged cars corner harder at speed
	var aero := 1.0 + DOWNFORCE * maxf(stat("downforce") - 1.0, 0.0) * speed * speed / (Cars.REF_MASS * gravity)
	var grip: float = Surfaces.get_surface(surface)["grip"] * stat("grip") * aero
	var fwd := -b3.z
	var vel := linear_velocity - up * linear_velocity.dot(up)
	body_slip = 0.0
	if vel.length() > 3.0:
		body_slip = fwd.signed_angle_to(vel.normalized(), up)
	if forward_speed < 2.0:
		return  # reversing / stopped: no assists
	if not handbrake:
		# yaw rate the driver is asking for: kinematic at low speed, capped by
		# a bit more than the surface's grip at high speed
		var kinematic := speed * tan(max_steer) / 2.6
		var grip_yaw := grip * gravity * 1.4 / maxf(speed, 3.0)
		var target := -steer * minf(kinematic, grip_yaw)
		var gain := YAW_ASSIST * clampf(grip / 1.3, 0.2, 1.0)
		if absf(steer) < 0.05:
			gain *= 0.4  # hands off: just settle the car
		var assist := (target - yaw) * YAW_INERTIA * _m * gain * clampf(speed / 8.0, 0.0, 1.0)
		apply_torque(up * assist)
	elif absf(steer) > 0.1:
		# handbrake pivot: kick the tail out toward the steer for hairpins
		apply_torque(up * -steer * 9000.0 * _m * clampf(speed / 10.0, 0.0, 1.0))
	# spin protection: past the cap, turn the nose back toward the travel direction
	var cap := DRIFT_CAP + (0.5 if handbrake else 0.0)
	if absf(body_slip) > cap and speed > 5.0:
		apply_torque(up * signf(body_slip) * (absf(body_slip) - cap) * 26000.0 * _m)


## Tank steering: tracks turn the hull on the spot, fading out with speed
## where the normal steering takes over.
func _skid_steer(b3: Basis) -> void:
	var up := b3.y
	var yaw := angular_velocity.dot(up)
	var target := -steer * 1.3
	var blend := 1.0 - clampf(absf(forward_speed) / 9.0, 0.0, 1.0)
	if forward_speed < -0.5:
		target = -target  # reversing turns the other way, like a car
	apply_torque(up * (target - yaw) * YAW_INERTIA * _m * 10.0 * stat("pivot", 0.0) * blend)


## Engine torque curve (Nm) at an rpm.
static func torque_at(r: float) -> float:
	var x := clampf((r - IDLE_RPM) / (REDLINE - IDLE_RPM), 0.0, 1.0)
	return PEAK_TORQUE * (0.62 + 0.38 * sin(x * PI * 0.9 + 0.25))


func _update_gearbox(delta: float, drive_input: float) -> void:
	shift_timer = maxf(shift_timer - delta, 0.0)
	if gear < 1 or shift_timer > 0.0 or (manual_gears and control_enabled):
		return
	# shift on road speed, not on wheelspin, so the box doesn't hunt
	var road_rpm := _road_rpm(gear)
	if road_rpm > 7200.0 and gear < GEAR_RATIOS.size() and drive_input > 0.1:
		gear += 1
		shift_timer = 0.2
	elif gear > 1:
		if (road_rpm < 3300.0 and _road_rpm(gear - 1) < 6600.0) or road_rpm < 1800.0:
			gear -= 1
			shift_timer = 0.15


## Manual shift. Down from first while (nearly) stopped selects reverse; a
## downshift that would over-rev the engine is refused.
func _shift(dir: int) -> void:
	if gear == -1:
		if dir > 0:
			gear = 1
			shift_timer = 0.15
		return
	var g := gear + dir
	if g > GEAR_RATIOS.size():
		return
	if g < 1:
		if absf(forward_speed) < 1.5:
			gear = -1
		return
	if dir < 0 and _road_rpm(g) > REDLINE + 300.0:
		return
	gear = g
	shift_timer = 0.2 if dir > 0 else 0.15


func _road_rpm(g: int) -> float:
	var ratio: float = REVERSE_RATIO if g == -1 else GEAR_RATIOS[g - 1]
	return absf(forward_speed) / WHEEL_RADIUS * ratio * FINAL_DRIVE * stat("gearing") * 60.0 / TAU


func _update_rpm(delta: float, drive_input: float) -> void:
	var spinning := false
	var grounded := false
	for w in wheels:
		grounded = grounded or w.grounded
		if w.spinning and drive_input > 0.3:
			spinning = true
	var target := _road_rpm(gear)
	if spinning or not grounded:
		target = maxf(target, lerpf(IDLE_RPM, REDLINE * 0.95, drive_input))
	target = clampf(maxf(target, IDLE_RPM + drive_input * 1500.0), IDLE_RPM, REDLINE + 150.0)
	rpm = lerpf(rpm, target, clampf(delta * 12.0, 0.0, 1.0))


func _update_wheel(w: Wheel, delta: float, drive_force: float, brake_input: float) -> void:
	var xf := global_transform
	var up := xf.basis.y
	var origin := xf * w.pos
	var ray_len := SUSP_REST + WHEEL_RADIUS
	var query := PhysicsRayQueryParameters3D.create(origin, origin - up * ray_len, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	# steering on the visual pivot
	if w.front:
		w.pivot.rotation.y = steer_angle

	if hit.is_empty():
		w.grounded = false
		w.sliding = false
		w.weight = 0.0
		w.dist = ray_len
		w.spinning = false
		w.spin = move_toward(w.spin, 0.0, delta * 5.0)
		_place_wheel(w, delta)
		return

	w.grounded = true
	var contact: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	w.contact = contact
	w.normal = n
	var collider: Object = hit["collider"]
	w.surface = "grass"
	if collider and collider.has_meta("surface"):
		w.surface = collider.get_meta("surface")
	var sd := Surfaces.get_surface(w.surface)
	var grip: float = sd["grip"] * spec["stats"]["grip"]
	if rain:
		grip *= sd["rain"]
	var slide_k: float = sd["slide"]
	var peak: float = sd["peak"]
	if not w.front:
		peak *= 0.9  # rears peak a touch earlier: the car wants to rotate
	var drag_k: float = sd["drag"]
	var bump: float = sd["bump"]

	w.dist = origin.distance_to(contact)
	var compression := ray_len - w.dist
	var rel := contact - global_position
	var pv := linear_velocity + angular_velocity.cross(rel)
	var susp_vel := pv.dot(up)
	var f_susp := (SPRING * compression - DAMPER * susp_vel) * _m
	if compression > SUSP_REST * 0.85:
		f_susp += (compression - SUSP_REST * 0.85) * SPRING * 6.0 * _m  # bump stop
	if bump > 0.0 and speed > 2.0:
		f_susp += _rng.randf_range(-1.0, 1.0) * bump * 2943.0 * _m * clampf(speed / 15.0, 0.0, 1.5)
	f_susp = maxf(f_susp, 0.0)
	w.weight = f_susp
	apply_force(up * f_susp, origin - global_position)

	# contact frame
	var fwd := -xf.basis.z
	if w.front:
		fwd = fwd.rotated(up, steer_angle)
	fwd = (fwd - n * fwd.dot(n)).normalized()
	var side := fwd.cross(n).normalized()
	var v_long := pv.dot(fwd)
	var v_lat := pv.dot(side)
	var m_share := mass * 0.25

	# weight transfer changes how much grip each axle has
	var axle_grip := 1.0 + (_load_shift if w.front else -_load_shift)
	var lat_grip := axle_grip * (1.0 - 0.8 * track_skid)
	if handbrake and not w.front:
		lat_grip *= 0.2

	# longitudinal: drive + brakes + rolling resistance
	var f_long := drive_force
	var stop_limit := absf(v_long) * m_share / delta
	var brake_f := brake_input * BRAKE_FORCE * _m * (0.6 if w.front else 0.4) * 0.5
	if handbrake and not w.front:
		brake_f += HANDBRAKE_FORCE * _m
	if brake_f > 0.0:
		f_long -= signf(v_long) * minf(brake_f, stop_limit)
	var roll := drag_k * w.weight * clampf(absf(v_long) / 3.0, 0.0, 1.0) * (1.0 + absf(v_long) / 20.0)
	f_long -= signf(v_long) * minf(roll, stop_limit)

	# traction limit for drive/brake; lateral grip shrinks as the tyre spends
	# grip on drive or braking (friction circle)
	var limit := grip * w.weight * axle_grip
	w.spinning = absf(f_long) > limit
	if w.spinning:
		f_long = signf(f_long) * limit * (0.5 + 0.5 * slide_k)
	var long_use := f_long / maxf(limit, 1.0)
	var lat_avail := grip * w.weight * lat_grip * sqrt(maxf(0.15, 1.0 - long_use * long_use * 0.6))

	# lateral: slip-angle curve (Marco Monster / simplified Pacejka): force
	# climbs steeply to a peak at a few degrees, then falls off to `slide`
	# of the peak deep into a slide, so slides are progressive and holdable
	var alpha := atan2(v_lat, maxf(absf(v_long), 4.0))
	var x := absf(alpha) / peak
	var curve := x * (2.0 - x) if x < 1.0 else lerpf(1.0, slide_k, smoothstep(1.0, 4.0, x))
	var f_lat := -signf(alpha) * curve * lat_avail
	# at crawling speeds don't overshoot: never push harder than it takes to stop the slip
	var f_stop := -v_lat * m_share / delta * 0.5
	if absf(f_stop) < absf(f_lat):
		f_lat = f_stop
	w.sliding = x > 1.6
	w.slip = absf(v_lat) * clampf(x - 1.0, 0.0, 1.0) + (6.0 if w.spinning else 0.0)
	var f := Vector2(f_long, f_lat)

	# apply grip forces slightly above the contact to tame body roll (arcade)
	var apply_at := contact + up * 0.35 - global_position
	apply_force(fwd * f.x + side * f.y, apply_at)

	# wheel spin for visuals / rpm
	var target_spin := v_long / WHEEL_RADIUS
	if w.spinning and absf(drive_force) > 10.0:
		target_spin += signf(drive_force) * 25.0
	if handbrake and not w.front:
		target_spin = 0.0
	w.spin = lerpf(w.spin, target_spin, clampf(delta * 20.0, 0.0, 1.0))
	_place_wheel(w, delta)


func _place_wheel(w: Wheel, delta: float) -> void:
	w.pivot.position = w.pos - Vector3(0, w.dist - WHEEL_RADIUS, 0)
	w.spinner.rotate_x(-w.spin * delta)


## Tyre marks: rubber where tyres slide or spin on tarmac (a damp line when
## it rains), ruts on gravel, mud and turf on soft ground (a faint track even
## when just driving through) and short dark marks off the line.
func _leave_marks() -> void:
	if marks == null:
		return
	for i in wheels.size():
		var w := wheels[i]
		var strength := 0.0
		var sd := Surfaces.get_surface(w.surface)
		var kind: String = sd["mark"]
		if w.grounded and speed > 2.0:
			if w.sliding:
				strength = clampf(w.slip / 5.0, 0.35, 1.0)
			if w.spinning or (handbrake and not w.front):
				strength = 1.0
			if kind in ["rut", "mud", "turf"]:
				strength = maxf(strength, 0.3)
			strength = maxf(strength, _launch() * 0.7)
		if rain and kind == "rubber":
			kind = "wet"
		if model.is_tank() and w.grounded and speed > 1.0:
			strength = maxf(strength, 0.6)  # tracks chew everything up
		marks.track(i, kind if strength > 0.0 else "", w.contact, w.normal, strength)


## How hard the tyres are scrabbling to pull away: full throttle at low speed
## (a cosmetic burnout for smoke and marks off the line). 0..1.
func _launch() -> float:
	if model.is_tank() or throttle < 0.7 or forward_speed < 0.2 or forward_speed > 9.0:
		return 0.0
	return (1.0 - forward_speed / 9.0) * throttle


func _update_fx(delta: float) -> void:
	var launch := _launch()
	for w in wheels:
		var sd := Surfaces.get_surface(w.surface)
		var amount := 0.0
		var spray := false
		if w.grounded:
			if sd["fx_always"] and speed > 6.0:
				amount = clampf(speed / 40.0, 0.15, 0.5)
			if w.sliding and speed > 3.0:
				amount = maxf(amount, clampf(w.slip / 6.0, 0.35, 1.0))
			if w.spinning:
				amount = 1.0
			amount = maxf(amount, launch * (0.6 if w.front else 1.0))
			spray = rain and speed > 8.0 and not sd["fx_always"]
			if spray:
				amount = maxf(amount, clampf(speed / 30.0, 0.3, 0.8))
		w.fx.global_position = w.spinner.global_position - Vector3(0, w.radius * 0.7, 0)
		w.fx.show_surface(w.surface, amount, spray)
	_smoke.emitting = damage["front"] > 0.5
	_smoke.color = Color(0.15, 0.15, 0.17, 0.4 + damage["front"] * 0.5)


func _check_flipped(delta: float) -> void:
	if global_transform.basis.y.dot(Vector3.UP) < 0.2 and speed < 3.0:
		_upside_down_time += delta
		if _upside_down_time > 2.5:
			_upside_down_time = 0.0
			get_parent().call("reset_car")
	else:
		_upside_down_time = 0.0


# --------------------------------------------------------------------------- damage

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _pending_place != null:
		# teleports must go through the body state or the physics server overwrites them
		state.transform = _pending_place
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_pending_place = null
		_vel_history.clear()
		return
	var total := Vector3.ZERO
	var point := Vector3.ZERO
	var normal := Vector3.ZERO
	var best := 0.0
	for i in state.get_contact_count():
		var imp := state.get_contact_impulse(i)
		var mag := imp.length()
		total += imp
		if mag > best:
			best = mag
			point = state.get_contact_local_position(i)
			normal = state.get_contact_local_normal(i)
	var dv := total.length() / mass
	# speed lost over the window while touching something; up/down is left out
	# so landings from jumps don't count, and the car's own grip and brakes
	# can't change its speed this much this quickly
	_vel_history.append(state.linear_velocity)
	if _vel_history.size() > IMPACT_WINDOW:
		_vel_history.pop_front()
	if state.get_contact_count() > 0:
		var change := state.linear_velocity - _vel_history[0]
		change.y = 0.0
		if change.length() > dv:
			dv = change.length()
			if best <= 0.0:
				# no telling impulse: take the contact whose normal pushed us the way we went
				var along := -INF
				for i in state.get_contact_count():
					var n := state.get_contact_local_normal(i)
					if n.dot(change) > along:
						along = n.dot(change)
						point = state.get_contact_local_position(i)
						normal = n
	if dv > 2.2 and _impact_cooldown <= 0.0:
		_impact_cooldown = 0.12
		_vel_history.clear()
		call_deferred("_apply_impact", dv, point, normal)


func _apply_impact(dv: float, point: Vector3, normal: Vector3) -> void:
	var local := to_local(point)
	var zone := ""
	if absf(local.z) / 2.0 > absf(local.x) / 0.9:
		zone = "front" if local.z < 0.0 else "rear"
	else:
		zone = "left" if local.x < 0.0 else "right"
	var amount := (dv - 2.2) * 0.035 * stat("armour")
	damage[zone] = minf(damage[zone] + amount, 1.0)
	# dent inward: away from the contact, towards the middle of the car
	var inward := (global_position - point)
	inward.y *= 0.3
	inward = inward.normalized()
	if normal.dot(inward) > 0.0:
		inward = (inward + normal).normalized()
	model.dent(point, inward, minf(0.06 + dv * 0.025, 0.4) * stat("armour"), 0.7 + dv * 0.04)
	model.update_parts(damage, linear_velocity)
	_sparks.global_position = point
	_sparks.restart()
	impact.emit(clampf(dv / 15.0, 0.0, 1.0), zone)


## Rain: a pair of spot lamps lighting the road ahead.
func set_headlights(on: bool) -> void:
	for l in get_tree().get_nodes_in_group("headlight_%d" % get_instance_id()):
		l.queue_free()
	if not on:
		return
	var front := minf(model.front_z(), Cars.wheels(spec)["zf"] - 0.3)
	for s in [-1.0, 1.0]:
		var l := SpotLight3D.new()
		l.add_to_group("headlight_%d" % get_instance_id())
		l.position = Vector3(s * 0.5, 0.05, front)
		l.rotation.x = -0.12
		l.light_color = Color(1.0, 0.94, 0.78)
		l.light_energy = 5.0
		l.spot_range = 60.0
		l.spot_angle = 26.0
		l.spot_attenuation = 0.8
		l.shadow_enabled = false
		add_child(l)


func total_damage() -> float:
	return (damage["front"] + damage["rear"] + damage["left"] + damage["right"]) / 4.0


func place(xf: Transform3D) -> void:
	global_transform = xf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_pending_place = xf
	gear = 1
	rpm = IDLE_RPM
	for w in wheels:
		w.sliding = false
		w.spin = 0.0
