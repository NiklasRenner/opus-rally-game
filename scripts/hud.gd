class_name Hud
extends Control
## Arcade HUD drawn with _draw in a 640x360 virtual screen: Sega-style time
## readouts with a lap plate, analogue tach with a gear plate and big italic
## speed, a minimap, surface readout and a damage diagram.

var car: RallyCar
var track: TrackBuilder
var cam: CameraRig
var race: Node  # main.gd, for timers

var _font: Font
var _map_points := PackedVector2Array()
var _map_colors := PackedColorArray()
var _map_center := Vector2.ZERO
var _map_scale := 1.0
# plates punch out briefly when the gear or lap changes
var _shown_gear := 1
var _gear_pop := 0.0
var _shown_lap := 1
var _lap_pop := 0.0

const YELLOW := RetroUI.YELLOW
const RED := RetroUI.RED
const GREEN := RetroUI.GREEN
const INK := RetroUI.INK


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func setup_map() -> void:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in track.points:
		mn = mn.min(Vector2(p.x, p.z))
		mx = mx.max(Vector2(p.x, p.z))
	_map_center = (mn + mx) * 0.5
	_map_scale = 78.0 / maxf(mx.x - mn.x, mx.y - mn.y)
	for i in range(0, track.count(), 2):
		var p := track.points[i]
		_map_points.append(Vector2(p.x, p.z))
		_map_colors.append(Surfaces.get_surface(track.surfaces[i])["hud"])


func _process(delta: float) -> void:
	if car and car.gear != _shown_gear:
		_shown_gear = car.gear
		_gear_pop = 1.0
	if race and race.lap != _shown_lap:
		_shown_lap = race.lap
		_lap_pop = 1.0
	_gear_pop = maxf(_gear_pop - delta * 5.0, 0.0)
	_lap_pop = maxf(_lap_pop - delta * 3.0, 0.0)
	queue_redraw()


func _blink(period_ms: float) -> bool:
	return Time.get_ticks_msec() % int(period_ms * 2.0) < int(period_ms)


## Chamfered arcade plate: ink edge, coloured rim, a face shaded from `top`
## to `bottom` and a gloss line.
func _plate(r: Rect2, rim: Color, top: Color, bottom: Color, cut := 5.0) -> void:
	draw_colored_polygon(_octagon(r.grow(3.0), cut + 2.0), INK)
	draw_colored_polygon(_octagon(r.grow(1.0), cut + 1.0), rim)
	var face := _octagon(r, cut)
	var cols := PackedColorArray()
	for p in face:
		cols.append(top.lerp(bottom, (p.y - r.position.y) / r.size.y))
	draw_polygon(face, cols)
	draw_rect(Rect2(r.position.x + cut, r.position.y + 2.0, r.size.x - cut * 2.0, 2.0), Color(1, 1, 1, 0.3))


static func _octagon(r: Rect2, c: float) -> PackedVector2Array:
	var a := r.position
	var b := r.end
	return PackedVector2Array([Vector2(a.x + c, a.y), Vector2(b.x - c, a.y), Vector2(b.x, a.y + c), Vector2(b.x, b.y - c),
		Vector2(b.x - c, b.y), Vector2(a.x + c, b.y), Vector2(a.x, b.y - c), Vector2(a.x, a.y + c)])


## Big italic glyphs centred on `mid` with a drop shadow, scaled about the
## centre for the change pop.
func _plate_digit(mid: Vector2, s: String, size: int, col: Color, scale := 1.0, outline := 5) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := Vector2(-w * 0.5, size * 0.36)
	draw_set_transform_matrix(Transform2D(Vector2(scale, 0), Vector2(-0.22 * scale, scale), mid))
	draw_string_outline(_font, p + Vector2(2, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, INK)
	draw_string_outline(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, INK)
	draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Outlined text. Unlike RetroUI.text, outline 0 still draws a hairline edge.
func _text(pos: Vector2, s: String, size: int, col: Color, outline := 4) -> void:
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, INK)
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## Fake italic via a skewed transform, like the chunky arcade digits.
func _italic(pos: Vector2, s: String, size: int, col: Color, outline := 5) -> void:
	RetroUI.italic(self, pos, s, size, col, outline)


static func fmt_time(t: float) -> String:
	if t == INF or t < 0.0:
		return "-'--\"--"
	var m := int(t / 60.0)
	var s := int(t) % 60
	var cs := int((t - floorf(t)) * 100.0)
	return "%d'%02d\"%02d" % [m, s, cs]


func _draw() -> void:
	if car == null or race == null:
		return
	var vs := get_viewport_rect().size

	# --- progress bar
	var prog: float = race.progress_fraction
	_text(Vector2(178, 16), "START", 12, Color.WHITE, 3)
	_text(Vector2(426, 16), "GOAL", 12, Color.WHITE, 3)
	draw_rect(Rect2(178, 20, 284, 7), INK)
	draw_rect(Rect2(179, 21, 282 * prog, 5), Color(0.55, 0.95, 0.15))

	# --- times
	_text(Vector2(14, 44), "TOTAL TIME", 13, YELLOW, 3)
	_italic(Vector2(16, 70), fmt_time(race.race_time), 26, Color.WHITE)
	_text(Vector2(14, 88), "LAP TIME", 13, RED, 3)
	_draw_lap_plate(Rect2(17, 93, 24, 22))
	_italic(Vector2(52, 112), fmt_time(race.lap_time), 22, Color.WHITE)
	_text(Vector2(484, 44), "BEST LAP", 13, GREEN, 3)
	_italic(Vector2(486, 68), fmt_time(race.best_lap), 20, Color.WHITE)
	_text(Vector2(484, 86), "LAST", 11, YELLOW, 3)
	_text(Vector2(520, 86), fmt_time(race.last_lap), 11, Color.WHITE, 3)
	if race.ghost_time < INF:
		_text(Vector2(484, 102), "GHOST", 11, Color(0.6, 0.9, 1.0), 3)
		_text(Vector2(520, 102), fmt_time(race.ghost_time), 11, Color.WHITE, 3)
	# split vs ghost at each lap line: green when ahead, red when behind
	var split: String = race.split_text
	if split != "":
		var ahead := split.begins_with("-")
		_italic(Vector2(vs.x * 0.5 - 40, 206), split, 26, GREEN if ahead else RED, 5)

	# --- countdown / messages
	var msg: String = race.message
	if msg != "":
		_italic(Vector2(vs.x * 0.5 - msg.length() * 13.0, 160), msg, 48, YELLOW, 8)

	_draw_tach(Vector2(70, 300))
	_draw_map(Vector2(574, 290))
	_draw_damage(Vector2(436, 254))

	# surface + camera
	var sd := Surfaces.get_surface(car.surface)
	_text(Vector2(436, 345), sd["label"], 14, sd["hud"], 3)
	_text(Vector2(436, 240), "CAM  " + cam.mode_name(), 10, Color(0.8, 0.85, 1.0), 3)


func _draw_tach(c: Vector2) -> void:
	var r := 46.0
	draw_circle(c, r + 3.0, INK)
	draw_circle(c, r, Color(0.96, 0.96, 0.94))
	draw_circle(c, r - 3.0, Color(0.1, 0.1, 0.14))
	# 0..9 x1000 rpm across 270 degrees
	var a0 := deg_to_rad(135.0)
	var span := deg_to_rad(270.0)
	var red_from := 7.0 / 9.0
	draw_arc(c, r - 7.0, a0 + span * red_from, a0 + span, 12, RED, 6.0)
	for k in 10:
		var a := a0 + span * k / 9.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(c + dir * (r - 4.0), c + dir * (r - 11.0), Color.WHITE, 2.0)
		var lp := c + dir * (r - 19.0) + Vector2(-4, 5)
		draw_string(_font, lp, str(k), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE if k < 7 else RED)
	var x := clampf(car.rpm / 9000.0, 0.0, 1.0)
	var na := a0 + span * x
	draw_line(c, c + Vector2(cos(na), sin(na)) * (r - 6.0), RED, 3.0)
	draw_circle(c, 4.0, Color(0.7, 0.7, 0.72))
	draw_string(_font, c + Vector2(-14, 24), "x1000", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.8, 0.8, 0.8))

	_draw_gear_plate(Rect2(c + Vector2(r + 9, -20), Vector2(32, 40)))

	# speed
	var kmh := int(round(car.speed * 3.6))
	_italic(c + Vector2(r + 52, 24), "%3d" % kmh, 40, Color.WHITE, 6)
	_text(c + Vector2(r + 132, 24), "km/h", 14, Color.WHITE, 3)


## Lap number on a yellow plate with the lap count tabbed on its corner; the
## plate flashes red on the final lap.
func _draw_lap_plate(p: Rect2) -> void:
	var lap: int = mini(race.lap, race.total_laps)
	var final: bool = lap == race.total_laps and race.total_laps > 1 and not race.finished
	var hot := final and _blink(250.0)
	var rim := Color.WHITE.lerp(YELLOW, _lap_pop)
	if hot:
		_plate(p, rim, Color(1.0, 0.45, 0.3), Color(0.75, 0.05, 0.02), 4.0)
	else:
		_plate(p, rim, Color(1.0, 0.95, 0.45), Color(0.98, 0.5, 0.05), 4.0)
	_plate_digit(p.get_center() + Vector2(-1, -1), str(lap), 20, Color.WHITE if hot else RED, 1.0 + 0.5 * _lap_pop, 4)
	var tab := Rect2(p.end + Vector2(-3, -9), Vector2(16, 11))
	draw_rect(tab, INK)
	_text(tab.position + Vector2(2, 9), "/%d" % race.total_laps, 10, YELLOW, 0)
	if final:
		_italic(Vector2(92, 88), "FINAL LAP", 13, YELLOW if _blink(250.0) else Color.WHITE, 3)


## Gear on a dark red plate under a GEAR tab. The manual box adds a row of
## shift lights that run up the rev range and flash at the limiter.
func _draw_gear_plate(g: Rect2) -> void:
	var limiter := car.rpm > 7400.0 and car.gear >= 1 and car.gear < car.ratios.size()
	var rim := YELLOW.lerp(Color.WHITE, _gear_pop)
	if car.manual_gears and limiter and _blink(70.0):
		rim = RED
	_plate(g, rim, Color(0.55, 0.06, 0.03), Color(0.07, 0.0, 0.02), 6.0)
	var tab := Rect2(g.position + Vector2(2, -13), Vector2(g.size.x - 4, 10))
	draw_rect(tab.grow(1), INK)
	_text(tab.position + Vector2(3, 9), "GEAR", 9, YELLOW, 0)
	var gear_s := "R" if car.gear == -1 else str(car.gear)
	var col := YELLOW if car.gear == -1 else Color(1.0, 0.32, 0.14)
	_plate_digit(g.get_center() + Vector2(1, -1), gear_s, 30, col.lerp(Color.WHITE, _gear_pop * 0.8), 1.0 + 0.45 * _gear_pop, 5)
	if car.manual_gears:
		var lights := [[5600.0, GREEN], [6400.0, GREEN], [7000.0, YELLOW], [7400.0, RED]]
		for i in lights.size():
			var on: bool = car.rpm >= (lights[i][0] as float) and not (limiter and not _blink(70.0))
			var led := Rect2(g.position.x + i * 8.5, g.end.y + 5, 6, 5)
			draw_rect(led.grow(1), INK)
			var lc: Color = lights[i][1]
			draw_rect(led, lc if on else lc.darkened(0.75))
	_text(Vector2(g.position.x + (2.0 if car.manual_gears else 4.0), g.end.y + 22), "MANUAL" if car.manual_gears else "AUTO", 9, Color(0.8, 0.85, 1.0), 2)


func _draw_map(c: Vector2) -> void:
	var r := 44.0
	draw_circle(c, r + 3.0, INK)
	draw_circle(c, r, Color(0.78, 0.86, 0.55, 0.85))
	var pts := PackedVector2Array()
	for p in _map_points:
		pts.append(c + (p - _map_center) * _map_scale)
	for i in pts.size():
		var j := (i + 1) % pts.size()
		draw_line(pts[i], pts[j], _map_colors[i], 3.0)
	# ghost car: a cyan blip, so you can see how far ahead or behind it is
	var g: Ghost = race.ghost
	if g and g.visible:
		var gp := c + (Vector2(g.global_position.x, g.global_position.z) - _map_center) * _map_scale
		var blink := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 90.0)
		draw_circle(gp, 5.0, INK)
		draw_circle(gp, 4.0, Color(0.55, 0.9, 1.0, blink))
	var cp := Vector2(car.global_position.x, car.global_position.z)
	var mp := c + (cp - _map_center) * _map_scale
	var f := -car.global_transform.basis.z
	var fd := Vector2(f.x, f.z).normalized()
	var tri := PackedVector2Array([mp + fd * 6.0, mp + fd.orthogonal() * 4.0 - fd * 3.0, mp - fd.orthogonal() * 4.0 - fd * 3.0])
	draw_colored_polygon(tri, Color.WHITE)
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), INK, 1.0)


func _draw_damage(o: Vector2) -> void:
	# little top-down car: body + four zone panels coloured green -> red
	var d: Dictionary = car.damage
	var w := 18.0
	var h := 34.0
	var col := func(v: float) -> Color: return GREEN.lerp(Color(1.0, 0.85, 0.1), clampf(v * 2.0, 0.0, 1.0)).lerp(RED, clampf(v * 2.0 - 1.0, 0.0, 1.0))
	draw_rect(Rect2(o, Vector2(w, h)).grow(2), INK)
	draw_rect(Rect2(o + Vector2(3, 7), Vector2(w - 6, h - 14)), Color(0.3, 0.3, 0.35))
	draw_rect(Rect2(o, Vector2(w, 6)), col.call(d["front"]))
	draw_rect(Rect2(o + Vector2(0, h - 6), Vector2(w, 6)), col.call(d["rear"]))
	draw_rect(Rect2(o + Vector2(0, 7), Vector2(3, h - 14)), col.call(d["left"]))
	draw_rect(Rect2(o + Vector2(w - 3, 7), Vector2(3, h - 14)), col.call(d["right"]))
	_text(o + Vector2(24, 12), "DAMAGE", 9, Color.WHITE, 2)
	_text(o + Vector2(24, 28), "%d%%" % int(car.total_damage() * 100.0), 14, col.call(car.total_damage()), 3)
