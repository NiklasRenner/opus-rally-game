extends SceneTree
## Builds a real-road stage's ground (the banks along the road and the
## terrain grid fitted to them) and bakes it to data/stages/<geo>.built, which
## the game then loads instead of building it every time. Run it again after
## changing anything the ground is built from; the game warns when the bake
## is out of date.
##
##   godot --headless -s tools/bake_terrain.gd -- turini [more map ids]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failed := 0
	for id in OS.get_cmdline_user_args():
		var map := Maps.get_map(id)
		if map["id"] != id or not map.has("geo"):
			printerr("%s isn't a geo stage" % id)
			failed += 1
			continue
		var t0 := Time.get_ticks_msec()
		var tb := TrackBuilder.new()
		tb.map = map
		tb.bake = true
		get_root().add_child(tb)
		tb.build()
		var path := "res://data/stages/%s.built" % map["geo"]
		if not FileAccess.file_exists(path):
			printerr("%s: no bake written" % id)
			failed += 1
		else:
			print("%s: baked %s (%.1f MB) in %.1f s" % [id, path, FileAccess.get_file_as_bytes(path).size() / 1e6,
				(Time.get_ticks_msec() - t0) / 1000.0])
		tb.queue_free()
	quit(1 if failed else 0)
