extends SceneTree
## Headless edge drop report (EdgeDropReport): where the ground past a road's edge drops more
## than a wheel can take, with x, z for each.
## godot --headless --path game -s res://world/build/edge_drop_report.gd -- [pack id] [rows]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var pack_id := args[0] if args.size() > 0 else "code430.ottawa-centretown"
	var limit := int(args[1]) if args.size() > 1 else 40
	var dir := PackLocator.find_pack(pack_id)
	if dir == "":
		push_error("pack not found: %s (searched %s)" % [pack_id, PackLocator.search_dirs()])
		quit(1)
		return
	var pack := MapPack.new()
	if not pack.load(dir):
		quit(1)
		return
	print(EdgeDropReport.format(EdgeDropReport.analyse(pack), limit))
	quit(0)
