extends SceneTree
## Exports every chunk of a map pack as GLB into <pack>/chunks/ (task 6.6).
## godot --headless --path game -s res://world/build/pack_builder.gd -- <pack-id>
## MapPack.build_all_chunks imports these (GlbChunks.import_chunk) while
## GlbChunks.chunks_are_current says they match the pack's inputs.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var pack_id := args[0] if args.size() > 0 else "code430.ottawa-centretown"
	var dir := PackLocator.find_pack(pack_id)
	if dir == "":
		push_error("pack not found: %s" % pack_id)
		quit(1)
		return
	var pack := MapPack.new()
	if not pack.load(dir):
		quit(1)
		return
	var written := GlbChunks.export_all(pack)
	print("wrote %d GLB chunks to %s" % [written, dir.path_join("chunks")])
	quit(0)
