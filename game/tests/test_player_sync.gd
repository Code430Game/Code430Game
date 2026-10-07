extends GdUnitTestSuite
## PlayerSync tells listeners about a leaving peer while its replica is still readable, so the
## host can leave a guest's helicopter where they were (WorldSync used to look the replica up
## after it had already been freed and never found it).


func test_remote_leaving_is_raised_before_the_replica_is_freed() -> void:
	var parent: Node3D = auto_free(Node3D.new())
	add_child(parent)
	var sync: PlayerSync = auto_free(PlayerSync.new())
	sync.remote_parent = parent
	add_child(sync)
	sync._on_peer_joined(7, {"color": Color.RED, "profile": {}})
	assert_bool(sync.remotes.has(7)).is_true()
	var seen: Array = []
	sync.remote_leaving.connect(func(id: int, r: RemotePlayer) -> void:
		seen.append([id, is_instance_valid(r) and r.is_inside_tree(), sync.remotes.has(id)]))
	sync._on_peer_left(7)
	assert_array(seen).has_size(1)
	assert_int(seen[0][0]).is_equal(7)
	assert_bool(seen[0][1]).is_true()  # still in the tree when raised
	assert_bool(seen[0][2]).is_true()  # still registered when raised
	assert_bool(sync.remotes.has(7)).is_false()
