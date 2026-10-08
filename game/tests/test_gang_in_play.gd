extends GdUnitTestSuite
## The Double Cross crew in single-player on the proving ground (fix/gang-spawns-in-play):
## with no session the crew stands on its turf, on the ground, and notices a player there.
## On the Deck the crew stood 60 m underground: the turf's ground height came from a physics
## ray at load, before the turf's chunk (a kilometre from the spawn) had any collision.

const TESTBED := preload("res://scenes/play_testbed.tscn")

var _bed: Node


func before_test() -> void:
	_bed = TESTBED.instantiate()
	_bed.set("_pack_id", "code430.proving-ground")
	_bed.set("_start_in_car", false)
	_bed.set("_mute", true)
	_bed.set("_traffic_cap", 0)
	_bed.set("_peds_cap", 0)
	_bed.set("_spawn_override", Vector3(650.0, 0.0, 475.0))
	add_child(_bed)
	for i in range(600):
		await get_tree().process_frame
		if _bed.get("_player") != null and _bed.get("_factions") != null and _bed.get("_streamer") != null:
			break
	# Let the boot finish: the spawn ring built and the first streaming pass landed.
	var streamer: Node = _bed.get("_streamer")
	for i in range(600):
		await get_tree().process_frame
		if streamer != null and not streamer.call("is_busy"):
			break
	for i in range(30):
		await get_tree().process_frame


func after_test() -> void:
	var streamer: Node = _bed.get("_streamer")
	for i in range(600):
		if not streamer.call("is_busy"):
			break
		await get_tree().process_frame
	streamer.flush()
	streamer.process_mode = Node.PROCESS_MODE_DISABLED
	_bed.queue_free()
	for i in range(60):
		await get_tree().process_frame


func test_the_crew_stands_on_the_ground_and_notices_a_player_on_the_turf() -> void:
	for i in range(30):
		await get_tree().physics_frame
	var player: Node3D = _bed.get("_player")
	var factions: FactionManager = _bed.get("_factions")
	var pack: MapPack = _bed.get("_pack")
	assert_int(factions.members.size()).is_equal(6)
	# Every member stands on the terrain, not at y 0 and not on the viaduct deck above the block.
	for m in factions.members:
		var h := pack.ground_height(m.global_position.x, m.global_position.z)
		assert_float(m.global_position.y).override_failure_message("%s at y %.1f, ground %.1f" % [m.name, m.global_position.y, h]).is_equal_approx(h, 1.5)
	# Walk the player onto the turf centre: within a few seconds the crew is no longer on patrol.
	var centre := factions.turfs[0].centre
	player.global_position = Vector3(centre.x, pack.ground_height(centre.x, centre.y) + 0.2, centre.y)
	assert_bool(factions.in_turf(player.global_position)).is_true()
	var reacted := false
	for i in range(60 * 8):
		await get_tree().physics_frame
		if factions.crew_state(0) != FactionManager.Crew.PATROL:
			reacted = true
			break
	assert_bool(reacted).override_failure_message("the crew stayed on patrol with the player on the turf centre").is_true()
