extends Node
## Autoload "Game": menu selections plus everything saved to disk, namely
## highscores (top 5 race times per map, lap count and car class, best lap per
## map and class) and the ghost of the best race for each of those.

const RECORDS_PATH := "user://records.json"
const GHOST_DIR := "user://ghosts"
const MAX_SCORES := 5
const LAP_OPTIONS := [1, 3, 5]
## 2: records and ghosts split by car class (Cars.CLASSES)
const RECORDS_VERSION := 2

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
var manual_gears := false  # shift with Up / Down (or the bumpers) instead of the automatic box

var _records := {}


func _ready() -> void:
	_load_records()
	_setup_input()


func _setup_input() -> void:
	_bind("accelerate", [KEY_W, KEY_UP], [JOY_BUTTON_A], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_bind("brake", [KEY_S, KEY_DOWN], [JOY_BUTTON_X], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_bind("steer_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("steer_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("handbrake", [KEY_SPACE], [JOY_BUTTON_B], [])
	_bind("camera", [KEY_C], [JOY_BUTTON_Y], [])
	_bind("reset", [KEY_R], [JOY_BUTTON_BACK], [])
	_bind("restart", [KEY_T], [], [])
	_bind("shift_up", [KEY_UP], [JOY_BUTTON_RIGHT_SHOULDER], [])
	_bind("shift_down", [KEY_DOWN], [JOY_BUTTON_LEFT_SHOULDER], [])
	_bind("look", [KEY_F2], [], [])
	_bind("quit", [KEY_ESCAPE], [JOY_BUTTON_START], [])
	_apply_gearbox_keys()


## With the manual box the Up / Down arrows shift gears, so they come off
## throttle and brake (W / S and the triggers still work).
func set_manual_gears(on: bool) -> void:
	manual_gears = on
	_apply_gearbox_keys()
	_records["manual_gears"] = on
	_save_records()


func _apply_gearbox_keys() -> void:
	for pair in [["accelerate", KEY_UP], ["brake", KEY_DOWN]]:
		var action: String = pair[0]
		var e := InputEventKey.new()
		e.physical_keycode = pair[1]
		if manual_gears:
			InputMap.action_erase_event(action, e)
		elif not InputMap.action_has_event(action, e):
			InputMap.action_add_event(action, e)


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
	if Maps.get_map(map_id).get("no_rain", false):
		race_rain = false  # no weather on the Moon


## Class of the chosen car; records and ghosts are only compared within one.
func car_class() -> String:
	return Cars.class_of(car_id)


func race_key(id: String = map_id, lap_count: int = laps, cls: String = car_class()) -> String:
	return "%s_%dlap_%s" % [id, lap_count, cls]


func lap_key(id: String = map_id, cls: String = car_class()) -> String:
	return "%s_%s" % [id, cls]


# --------------------------------------------------------------------------- highscores

func scores(key: String = race_key()) -> Array:
	var r: Dictionary = _records.get("races", {})
	return r.get(key, [])


func best_lap(key: String = lap_key()) -> float:
	var b: Dictionary = _records.get("best_laps", {})
	return b.get(key, INF)


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


## Returns true if this was a new best lap for the map and class.
func submit_lap(time: float, key: String = lap_key()) -> bool:
	if time >= best_lap(key):
		return false
	var b: Dictionary = _records.get("best_laps", {})
	b[key] = time
	_records["best_laps"] = b
	_save_records()
	return true


func _load_records() -> void:
	var f := FileAccess.open(RECORDS_PATH, FileAccess.READ) if FileAccess.file_exists(RECORDS_PATH) else null
	if f:
		var data: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if data is Dictionary:
			_records = data
			last_initials = _records.get("last_initials", "AAA")
			manual_gears = _records.get("manual_gears", false)
	# also run on every start, as a build from before the classes may have
	# saved under the old keys since
	if _migrate_to_classes() or int(_records.get("version", 1)) < RECORDS_VERSION:
		_records["version"] = RECORDS_VERSION
		_save_records()


## Saves from before car classes: sort each highscore, best lap and ghost into
## the class of the car that set it, merging with what that class already has.
## Returns true if anything moved.
func _migrate_to_classes() -> bool:
	var changed := false
	var races: Dictionary = _records.get("races", {})
	var old_race := RegEx.create_from_string("^.+_\\d+lap$")
	for key: String in races.keys():
		if old_race.search(key) == null:
			continue
		for e: Dictionary in races[key]:
			var k := "%s_%s" % [key, Cars.class_of(e.get("car", ""))]
			var list: Array = races.get(k, [])
			list.append(e)
			list.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return (x["time"] as float) < (y["time"] as float))
			races[k] = list.slice(0, MAX_SCORES)
		races.erase(key)
		changed = true
	_records["races"] = races

	# ghosts: <map>_<n>lap.ghost -> <map>_<n>lap_<class>.ghost, keeping the faster
	# one if the class already has a ghost; their splits also give each class's
	# laps, which help place the old best laps
	var ghost_laps := {}  # lap_key -> fastest lap in that class's ghosts
	var rx := RegEx.create_from_string("^(.+)_(\\d+)lap\\.ghost$")
	var files := DirAccess.get_files_at(GHOST_DIR) if DirAccess.dir_exists_absolute(GHOST_DIR) else PackedStringArray()
	for file in files:
		var m := rx.search(file)
		if m == null:
			continue
		var base := file.get_basename()
		var g := _read_ghost(_ghost_path(base))
		var cls := Cars.class_of(g.get("car", ""))
		var key := "%s_%s" % [base, cls]
		if (g.get("time", INF) as float) < ghost_time(key):
			DirAccess.remove_absolute(_ghost_path(key))
			DirAccess.rename_absolute(_ghost_path(base), _ghost_path(key))
		else:
			DirAccess.remove_absolute(_ghost_path(base))
		changed = true
		var splits: PackedFloat32Array = g.get("splits", PackedFloat32Array())
		var lk := lap_key(m.get_string(1), cls)
		for i in splits.size():
			var t := splits[i] - (splits[i - 1] if i > 0 else 0.0)
			ghost_laps[lk] = minf(ghost_laps.get(lk, INF), t)

	# best laps: old keys are the bare map id, new ones end in a class letter
	var laps: Dictionary = _records.get("best_laps", {})
	for id: String in laps.keys():
		if Cars.CLASSES.has(id.get_slice("_", id.get_slice_count("_") - 1)):
			continue
		var t: float = laps[id]
		var lk := lap_key(id, _class_of_best_lap(id, t, ghost_laps, races))
		laps[lk] = minf(laps.get(lk, INF), t)
		laps.erase(id)
		changed = true
	for lk: String in ghost_laps:
		laps[lk] = minf(laps.get(lk, INF), ghost_laps[lk])
	_records["best_laps"] = laps
	return changed


## Which class an old per-map best lap was most likely set in: a ghost lap that
## matches it, else the car of the stage's fastest race per lap, else rally.
func _class_of_best_lap(id: String, t: float, ghost_laps: Dictionary, races: Dictionary) -> String:
	for cls: String in Cars.CLASSES:
		if absf(ghost_laps.get(lap_key(id, cls), INF) - t) < 0.05:
			return cls
	var best := INF
	var out := Cars.DEFAULT_CLASS
	for lap_count in LAP_OPTIONS:
		for cls: String in Cars.CLASSES:
			for e: Dictionary in races.get(race_key(id, lap_count, cls), []):
				if (e["time"] as float) / lap_count < best:
					best = (e["time"] as float) / lap_count
					out = cls
	return out


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
## A ghost set in another class is never handed out, so you only race your own.
func load_ghost(key: String = race_key()) -> Dictionary:
	var g := _read_ghost(_ghost_path(key))
	var cls := key.get_slice("_", key.get_slice_count("_") - 1)
	if Cars.CLASSES.has(cls) and Cars.class_of(g.get("car", "")) != cls:
		return {}
	return g


func _read_ghost(path: String) -> Dictionary:
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
