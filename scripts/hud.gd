class_name Hud
extends Control
## Arcade HUD drawn with _draw in a 640x360 virtual screen: Sega-style time
## readouts, analogue tach with gear box and big italic speed, a minimap,
## surface readout and a damage diagram.

var car: RallyCar
var track: TrackBuilder
var cam: CameraRig
var race: Node  # main.gd, for timers

var _font: Font
var _map_points := PackedVector2Array()
var _map_colors := PackedColorArray()
var _map_center := Vector2.ZERO
var _map_scale := 1.0

const YELLOW := Color(1.0, 0.84, 0.1)
const RED := Color(0.95, 0.15, 0.1)
const GREEN := Color(0.3, 0.95, 0.2)
const INK := Color(0.02, 0.02, 0.08)


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


func _process(_delta: float) -> void:
	queue_redraw()


func _text(pos: Vector2, s: String, size: int, col: Color, outline := 4, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(_font, pos, s, align, width, size, outline, INK)
	draw_string(_font, pos, s, align, width, size, col)


func _italic(pos: Vector2, s: String, size: int, col: Color, outline := 5) -> void:
	# fake italic via a skewed transform, like the chunky arcade digits
	draw_set_transform_matrix(Transform2D(Vector2(1, 0), Vector2(-0.22, 1), pos))
	_text(Vector2.ZERO, s, size, col, outline)
	draw_set_transform_matrix(Transform2D.IDENTITY)


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
	draw_rect(Rect2(14, 92, 14, 20), Color.WHITE)
	_text(Vector2(17, 108), str(race.lap), 16, RED, 0)
	_italic(Vector2(34, 110), fmt_time(race.lap_time), 22, Color.WHITE)
	_text(Vector2(484, 44), "BEST LAP", 13, GREEN, 3)
	_italic(Vector2(486, 68), fmt_time(race.best_lap), 20, Color.WHITE)
	_text(Vector2(484, 86), "LAST", 11, YELLOW, 3)
	_text(Vector2(520, 86), fmt_time(race.last_lap), 11, Color.WHITE, 3)
	_text(Vector2(90, 88), "%d / %d" % [mini(race.lap, race.total_laps), race.total_laps], 13, Color.WHITE, 3)
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

	# gear box
	var g := Rect2(c + Vector2(r + 6, -6), Vector2(30, 34))
	draw_rect(g.grow(2), INK)
	draw_rect(g, Color(0.12, 0.02, 0.02))
	var gear_s := "R" if car.gear == -1 else str(car.gear)
	_text(g.position + Vector2(7, 28), gear_s, 28, Color(1.0, 0.18, 0.12), 0)
	_text(g.position + Vector2(0, 46), "SHIFT", 9, Color.WHITE, 2)

	# speed
	var kmh := int(round(car.speed * 3.6))
	_italic(c + Vector2(r + 44, 24), "%3d" % kmh, 40, Color.WHITE, 6)
	_text(c + Vector2(r + 124, 24), "km/h", 14, Color.WHITE, 3)


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
