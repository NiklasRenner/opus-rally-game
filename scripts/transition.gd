extends CanvasLayer
## Autoload "Transition": scene changes behind a chequered flag. Two flag
## panels sweep in from the sides, row by row like cloth catching the wind,
## and meet in the middle; only once the closed flag has been drawn on screen
## is the scene swapped (building a stage holds the game up for a moment),
## then the panels sweep back out the way they came.

const CELL := 20  # chequer square, in pixels of the 640x360 viewport
const CLOSE_TIME := 0.45
const OPEN_TIME := 0.5
const STAGGER := 0.35  # how far behind the leading row the last row runs, as a share of the sweep
const SETTLE_FRAMES := 4  # frames to stay closed after the swap (first-frame shader compiles)
const WHITE := Color(0.93, 0.93, 0.88)
const FOLD := Color(0.8, 0.8, 0.78)  # white squares in a fold of the cloth
const BLACK := Color(0.05, 0.05, 0.08)

var busy := false  # a transition is running; menus and the race ignore input meanwhile

var _cover := 0.0  # 0 open .. 1 closed
var _from := 0.0
var _to := 0.0
var _time := 0.0
var _length := 1.0
var _clock := 0.0  # drives the cloth shading
var _canvas: Control

signal _swept


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_flags)
	add_child(_canvas)
	set_process(false)


## Change to the scene at `path` behind the flag.
func change_scene(path: String, delay := 0.0) -> void:
	_run(func() -> void: get_tree().change_scene_to_file(path), delay)


## Reload the current scene behind the flag; `delay` seconds pass before the
## flag starts to close (time to watch the car blow up).
func reload(delay := 0.0) -> void:
	_run(func() -> void: get_tree().reload_current_scene(), delay)


func _run(swap: Callable, delay: float) -> void:
	if busy:
		return
	busy = true
	if delay > 0.0:
		await get_tree().create_timer(delay, true, false, true).timeout
	await _sweep(1.0, CLOSE_TIME)
	# the closed flag has to reach the screen before the load holds the game up
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = false
	swap.call()
	await get_tree().scene_changed
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	await _sweep(0.0, OPEN_TIME)
	busy = false


func _sweep(to: float, length: float) -> void:
	_from = _cover
	_to = to
	_time = 0.0
	_length = length
	set_process(true)
	await _swept


func _process(delta: float) -> void:
	# a long frame (the load itself) must not skip the sweep
	delta = minf(delta, 1.0 / 30.0)
	_clock += delta
	_time += delta
	_cover = lerpf(_from, _to, clampf(_time / _length, 0.0, 1.0))
	_canvas.queue_redraw()
	if _time >= _length:
		set_process(false)
		_swept.emit()


## How far row `r`'s panels have come in, 0..1. Rows lag along a wave so the
## leading edge ripples like a flag.
func _row_cover(r: int) -> float:
	var lag := (0.5 + 0.5 * sin(r * 0.55 + 1.2)) * STAGGER
	var t := clampf((_cover * (1.0 + STAGGER) - lag), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _draw_flags() -> void:
	if _cover <= 0.0:
		return
	var vs := _canvas.get_viewport_rect().size
	var half := floorf(vs.x / 2.0)
	var rows := ceili(vs.y / CELL)
	for r in rows:
		var reach := floorf(_row_cover(r) * half)
		if reach <= 0.0:
			continue
		var y := float(r * CELL)
		# left panel: squares counted back from its leading edge, so the
		# chequer slides in with it and meets the right panel's in step
		_draw_row(r, y, half, reach, -1)
		_draw_row(r, y, half, reach, 1)
	if _cover >= 1.0:
		var plate := Rect2(half - 70, floorf(vs.y / 2.0) - 13, 140, 26)
		RetroUI.panel(_canvas, plate, 0.95)
		RetroUI.italic(_canvas, plate.position + Vector2(0, 19), "LOADING", 16, RetroUI.YELLOW, 4,
			HORIZONTAL_ALIGNMENT_CENTER, plate.size.x)


## One row of one panel. `side` -1 is the left panel, 1 the right; `reach` is
## how far its leading edge has come in from the screen edge.
func _draw_row(r: int, y: float, half: float, reach: float, side: int) -> void:
	var edge := reach if side < 0 else half * 2.0 - reach
	var k := 0
	var x := edge
	while (side < 0 and x > 0.0) or (side > 0 and x < half * 2.0):
		var x0 := x - CELL if side < 0 else x
		var col := BLACK
		if (k + r + (0 if side < 0 else 1)) % 2 == 0:
			# a slow ripple of shade across the cloth, in two hard steps
			col = WHITE if sin(x0 * 0.012 + r * 0.45 - _clock * 5.0) > -0.4 else FOLD
		_canvas.draw_rect(Rect2(x0, y, CELL, CELL), col)
		x += CELL * side
		k += 1
	# yellow-on-ink hem along the leading edge, like the menu panels
	var hem := edge - 3.0 if side < 0 else edge
	_canvas.draw_rect(Rect2(hem, y, 3, CELL), RetroUI.INK)
	_canvas.draw_rect(Rect2(hem + 1.0, y, 1, CELL), RetroUI.YELLOW)
