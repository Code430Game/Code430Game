extends SceneTree
## Headless smoke run: load a pack, build all chunks, print stats and timing.
## godot --headless --path game -s res://world/build/smoke_build.gd -- code430.ottawa-centretown


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var pack_id := args[0] if args.size() > 0 else "code430.ottawa-centretown"
	var dir := PackLocator.find_pack(pack_id)
	if dir == "":
		push_error("pack not found: %s (searched %s)" % [pack_id, PackLocator.search_dirs()])
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	var pack := MapPack.new()
	if not pack.load(dir):
		quit(1)
		return
	var t1 := Time.get_ticks_msec()
	var root := Node3D.new()
	var stats := pack.build_all_chunks(root, true)
	var t2 := Time.get_ticks_msec()
	print("pack %s at %s" % [pack.manifest["id"], dir])
	print("graph: %d nodes, %d edges, %d junctions; load %d ms" % [pack.graph.nodes.size(), pack.graph.edges.size(), pack.junctions.size(), t1 - t0])
	print("build: %s; %d ms" % [stats, t2 - t1])
	var spawn := pack.spawn_transform()
	print("spawn: %s" % spawn.origin)
	root.free()
	quit(0)
