class_name RaceMenu
extends Control
## In-race overlay: pause menu (with a controls page), arcade initials entry
## for a highscore, and the results screen with the map's top 5.

enum Mode { NONE, PAUSE, CONTROLS, INITIALS, RESULTS }

const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
const CONTROLS := [
	["THROTTLE", "W / UP", "RT / A"],
	["BRAKE, REVERSE", "S / DOWN", "LT / X"],
	["STEER", "A D / ARROWS", "LEFT STICK"],
	["HANDBRAKE", "SPACE", "B"],
	["CAMERA", "C", "Y"],
	["RESET TO ROAD", "R", "BACK"],
	["REPAIR", "T", ""],
	["PAUSE", "ESC", "START"],
]

var race: Node  # main.gd
var mode := Mode.NONE
var _sel := 0
var _options: Array[String] = []
var _time := 0.0
var _rank := -1
var _new_ghost := false
var _initials := [0, 0, 0]
var _slot := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func open_pause() -> void:
	if mode == Mode.PAUSE:
		_resume()
		return
	if mode == Mode.CONTROLS:
		_back_to_pause()
		return
	mode = Mode.PAUSE
	_options = ["RESUME", "RESTART", "CONTROLS", "MAIN MENU"]
	_sel = 0
	get_tree().paused = true


func _resume() -> void:
	mode = Mode.NONE
	get_tree().paused = false


func open_results(time: float, new_ghost: bool) -> void:
	_time = time
	_new_ghost = new_ghost
	_rank = Game.score_rank(time)
	if _rank >= 0:
		mode = Mode.INITIALS
		var last: String = Game.last_initials
		for i in 3:
			var c := last.substr(i, 1) if i < last.length() else "A"
			_initials[i] = maxi(LETTERS.find(c), 0)
		_slot = 0
	else:
		_show_results()


func _show_results() -> void:
	mode = Mode.RESULTS
	_options = ["RACE AGAIN", "MAIN MENU"]
	_sel = 0


func _initials_string() -> String:
	var s := ""
	for i in _initials:
		s += LETTERS[i]
	return s


func _input(event: InputEvent) -> void:
	if mode == Mode.NONE or not event.is_pressed() or event.is_echo():
		return
	match mode:
		Mode.PAUSE, Mode.RESULTS:
			if event.is_action_pressed("ui_up"):
				_sel = wrapi(_sel - 1, 0, _options.size())
			elif event.is_action_pressed("ui_down"):
				_sel = wrapi(_sel + 1, 0, _options.size())
			elif event.is_action_pressed("ui_accept"):
				_choose(_options[_sel])
			elif event.is_action_pressed("ui_cancel") and mode == Mode.PAUSE:
				_resume()
			else:
				return
		Mode.CONTROLS:
			if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
				_back_to_pause()
			else:
				return
		Mode.INITIALS:
			if event.is_action_pressed("ui_up"):
				_initials[_slot] = wrapi(_initials[_slot] + 1, 0, LETTERS.length())
			elif event.is_action_pressed("ui_down"):
				_initials[_slot] = wrapi(_initials[_slot] - 1, 0, LETTERS.length())
			elif event.is_action_pressed("ui_left"):
				_slot = maxi(_slot - 1, 0)
			elif event.is_action_pressed("ui_right"):
				_slot = mini(_slot + 1, 2)
			elif event.is_action_pressed("ui_accept"):
				if _slot < 2:
					_slot += 1
				else:
					_commit_initials()
			elif event is InputEventKey and (event as InputEventKey).unicode > 0:
				# typing letters directly also works
				var ch := String.chr((event as InputEventKey).unicode).to_upper()
				var k := LETTERS.find(ch)
				if k >= 0 and ch != " ":
					_initials[_slot] = k
					if _slot < 2:
						_slot += 1
				else:
					return
			else:
				return
	if is_inside_tree():  # restart / menu swap the scene out from under us
		get_viewport().set_input_as_handled()
		queue_redraw()


func _commit_initials() -> void:
	var name := _initials_string()
	_rank = Game.add_score(name, _time)
	if _new_ghost:
		race.name_ghost(name)
	_show_results()


func _choose(option: String) -> void:
	match option:
		"RESUME":
			_resume()
		"RESTART", "RACE AGAIN":
			race.restart()
		"CONTROLS":
			mode = Mode.CONTROLS
		"MAIN MENU":
			race.to_menu()


func _back_to_pause() -> void:
	mode = Mode.PAUSE
	_sel = _options.find("CONTROLS")


func _process(_delta: float) -> void:
	if mode != Mode.NONE:
		queue_redraw()


func _draw() -> void:
	if mode == Mode.NONE:
		return
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0.05, 0.35))
	match mode:
		Mode.PAUSE:
			var r := Rect2(vs.x * 0.5 - 110, 100, 220, 160)
			RetroUI.panel(self, r)
			RetroUI.italic(self, Vector2(r.position.x + 20, r.position.y + 36), "PAUSE", 30, RetroUI.YELLOW)
			_draw_options(Vector2(r.position.x + 20, r.position.y + 62))
		Mode.CONTROLS:
			_draw_controls(vs)
		Mode.INITIALS:
			var r := Rect2(vs.x * 0.5 - 160, 70, 320, 200)
			RetroUI.panel(self, r)
			RetroUI.italic(self, Vector2(r.position.x + 18, r.position.y + 34), "NEW RECORD!", 28, RetroUI.YELLOW)
			RetroUI.text(self, Vector2(r.position.x + 20, r.position.y + 62), "RANK %d   %s" % [_rank + 1, Hud.fmt_time(_time)], 16, Color.WHITE)
			RetroUI.text(self, Vector2(r.position.x + 20, r.position.y + 88), "ENTER YOUR INITIALS", 13, RetroUI.CYAN, 3)
			for i in 3:
				var x := r.position.x + 90 + i * 48
				var box := Rect2(x, r.position.y + 100, 40, 50)
				draw_rect(box, RetroUI.INK)
				if i == _slot:
					RetroUI.cursor(self, box)
				RetroUI.italic(self, Vector2(x + 9, r.position.y + 140), LETTERS[_initials[i]], 40, Color.WHITE, 6)
			RetroUI.text(self, Vector2(r.position.x + 20, r.position.y + 184), "UP/DOWN letter  LEFT/RIGHT move  ENTER ok", 10, Color(0.8, 0.85, 1.0), 2)
		Mode.RESULTS:
			_draw_results(vs)


func _draw_controls(vs: Vector2) -> void:
	var r := Rect2(vs.x * 0.5 - 200, 50, 400, 250)
	RetroUI.panel(self, r)
	RetroUI.italic(self, r.position + Vector2(18, 34), "CONTROLS", 26, RetroUI.YELLOW)
	RetroUI.text(self, r.position + Vector2(200, 58), "KEYBOARD", 11, RetroUI.CYAN, 3)
	RetroUI.text(self, r.position + Vector2(300, 58), "PAD", 11, RetroUI.CYAN, 3)
	for i in CONTROLS.size():
		var row: Array = CONTROLS[i]
		var y := r.position.y + 80 + i * 20
		RetroUI.text(self, Vector2(r.position.x + 20, y), row[0], 13, Color.WHITE, 3)
		RetroUI.text(self, Vector2(r.position.x + 200, y), row[1], 13, RetroUI.YELLOW, 3)
		RetroUI.text(self, Vector2(r.position.x + 300, y), row[2], 13, RetroUI.YELLOW, 3)
	RetroUI.text(self, r.position + Vector2(20, 240), "ENTER / ESC  back", 10, Color(0.8, 0.85, 1.0), 2)


func _draw_options(at: Vector2) -> void:
	for i in _options.size():
		var y := at.y + i * 24
		if i == _sel:
			RetroUI.cursor(self, Rect2(at.x - 6, y - 16, 192, 22))
		RetroUI.text(self, Vector2(at.x, y), _options[i], 16, Color.WHITE if i != _sel else RetroUI.YELLOW)


func _draw_results(vs: Vector2) -> void:
	var r := Rect2(vs.x * 0.5 - 190, 40, 380, 280)
	RetroUI.panel(self, r)
	var map: Dictionary = Maps.get_map(Game.map_id)
	RetroUI.italic(self, r.position + Vector2(18, 34), "FINISH!", 30, RetroUI.YELLOW)
	RetroUI.text(self, r.position + Vector2(170, 22), map["name"], 13, Color.WHITE, 3)
	RetroUI.text(self, r.position + Vector2(170, 38), "%d LAP%s" % [Game.laps, "S" if Game.laps > 1 else ""], 11, RetroUI.CYAN, 3)
	RetroUI.text(self, r.position + Vector2(18, 62), "TIME", 13, RetroUI.YELLOW, 3)
	RetroUI.italic(self, r.position + Vector2(64, 64), Hud.fmt_time(_time), 22, Color.WHITE)
	RetroUI.text(self, r.position + Vector2(200, 62), "BEST LAP", 13, RetroUI.GREEN, 3)
	RetroUI.text(self, r.position + Vector2(280, 62), Hud.fmt_time(Game.best_lap()), 13, Color.WHITE, 3)
	if _new_ghost:
		RetroUI.text(self, r.position + Vector2(18, 84), "NEW GHOST SAVED - RACE IT NEXT TIME", 11, RetroUI.CYAN, 3)
	RetroUI.text(self, r.position + Vector2(18, 108), "TOP %d" % Game.MAX_SCORES, 13, RetroUI.YELLOW, 3)
	var list := Game.scores()
	for i in Game.MAX_SCORES:
		var y := r.position.y + 128 + i * 18
		var col := Color.WHITE
		if i == _rank:
			RetroUI.cursor(self, Rect2(r.position.x + 12, y - 14, 356, 18))
			col = RetroUI.YELLOW
		RetroUI.text(self, Vector2(r.position.x + 18, y), "%d." % (i + 1), 13, col, 3)
		if i < list.size():
			var e: Dictionary = list[i]
			RetroUI.text(self, Vector2(r.position.x + 44, y), e["name"], 13, col, 3)
			RetroUI.text(self, Vector2(r.position.x + 100, y), Hud.fmt_time(e["time"]), 13, col, 3)
			if e.has("car"):
				var car_name: String = Cars.get_car(e["car"])["name"]
				RetroUI.text(self, Vector2(r.position.x + 186, y), car_name.get_slice(" ", 0), 10, col, 2)
			RetroUI.text(self, Vector2(r.position.x + 286, y), e.get("date", ""), 10, Color(0.75, 0.8, 0.95), 2)
		else:
			RetroUI.text(self, Vector2(r.position.x + 44, y), "---   -'--\"--", 13, Color(0.6, 0.6, 0.7), 3)
	_draw_options(r.position + Vector2(24, 238))
