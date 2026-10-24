extends Node
## Autoload "Game": menu selections plus everything saved to disk, namely
## highscores (top 5 race times per map and lap count, best lap per map) and
## the ghost of the best race for each map and lap count.

const RECORDS_PATH := "user://records.json"
const GHOST_DIR := "user://ghosts"
const MAX_SCORES := 5
const LAP_OPTIONS := [1, 3, 5]

var map_id: String = Maps.LIST[0]["id"]
var car_id: String = Cars.LIST[0]["id"]
var laps := 3
var ghost_enabled := true
var last_initials := "AAA"
var weather := "RANDOM"  # menu choice, see Conditions.WEATHERS
# what the current race actually got (rolled when a race starts from the menu,
# kept for restarts)
var race_rain := false
var retro_look := true  # banded light, hard shadows, depth fog (F2, RetroLook)

var _records := {}


func _ready() -> void:
	_setup_input()
	_load_records()


func _setup_input() -> void:
	_bind("accelerate", [KEY_W, KEY_UP], [JOY_BUTTON_A], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_bind("brake", [KEY_S, KEY_DOWN], [JOY_BUTTON_X], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_bind("steer_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("steer_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("handbrake", [KEY_SPACE], [JOY_BUTTON_B], [])
	_bind("camera", [KEY_C], [JOY_BUTTON_Y], [])
	_bind("reset", [KEY_R], [JOY_BUTTON_BACK], [])
	_bind("repair", [KEY_T], [], [])
	_bind("look", [KEY_F2], [], [])
	_bind("quit", [KEY_ESCAPE], [JOY_BUTTON_START], [])


## Input actions are registered in code so the project needs no input map
## setup; move them to Project Settings > Input Map if you want to rebind.
func _bind(action: String, keys: Array, buttons: Array, axes: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.15)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(action, e)
	for a in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = a[0]
		e.axis_value = a[1]
		InputMap.action_add_event(action, e)


## Resolve RANDOM weather for the next race.
func roll_conditions() -> void:
	race_rain = weather == "RAIN" or (weather == "RANDOM" and randf() < 0.35)


func race_key(id: String = map_id, lap_count: int = laps) -> String:
	return "%s_%dlap" % [id, lap_count]


# --------------------------------------------------------------------------- highscores

func scores(key: String = race_key()) -> Array:
	var r: Dictionary = _records.get("races", {})
	return r.get(key, [])


func best_lap(id: String = map_id) -> float:
	var b: Dictionary = _records.get("best_laps", {})
	return b.get(id, INF)


## Where `time` would land in the table (0-based), or -1 if it doesn't make it.
func score_rank(time: float, key: String = race_key()) -> int:
	var list := scores(key)
	for i in list.size():
		if time < (list[i]["time"] as float):
			return i
	return list.size() if list.size() < MAX_SCORES else -1


func add_score(name: String, time: float, key: String = race_key()) -> int:
	var list := scores(key).duplicate()
	var rank := score_rank(time, key)
	if rank < 0:
		return -1
	list.insert(rank, {"name": name, "time": time, "car": car_id, "date": Time.get_date_string_from_system()})
	while list.size() > MAX_SCORES:
		list.pop_back()
	var races: Dictionary = _records.get("races", {})
	races[key] = list
	_records["races"] = races
	last_initials = name
	_records["last_initials"] = name
	_save_records()
	return rank


## Returns true if this was a new best lap for the map.
func submit_lap(time: float, id: String = map_id) -> bool:
	if time >= best_lap(id):
		return false
	var b: Dictionary = _records.get("best_laps", {})
	b[id] = time
	_records["best_laps"] = b
	_save_records()
	return true


func _load_records() -> void:
	if not FileAccess.file_exists(RECORDS_PATH):
		return
	var f := FileAccess.open(RECORDS_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		_records = data
		last_initials = _records.get("last_initials", "AAA")


func _save_records() -> void:
	var f := FileAccess.open(RECORDS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_records, "  "))


# --------------------------------------------------------------------------- ghosts

func _ghost_path(key: String) -> String:
	return "%s/%s.ghost" % [GHOST_DIR, key]


## Ghost = {"time": float, "name": String, "rate": float,
##          "frames": PackedFloat32Array (x, y, z, qx, qy, qz, qw per sample),
##          "splits": PackedFloat32Array (race time at the end of each lap),
##          "car": String (Cars id)}
func load_ghost(key: String = race_key()) -> Dictionary:
	var path := _ghost_path(key)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = f.get_var()
	return data if data is Dictionary else {}


func save_ghost(ghost: Dictionary, key: String = race_key()) -> void:
	DirAccess.make_dir_recursive_absolute(GHOST_DIR)
	var f := FileAccess.open(_ghost_path(key), FileAccess.WRITE)
	if f:
		f.store_var(ghost)


func ghost_time(key: String = race_key()) -> float:
	var g := load_ghost(key)
	return g.get("time", INF)
