extends GdUnitTestSuite
## add-world-menu: a real controller Y press on an open full map reaches the legend's Go to.

const OVERVIEW := preload("res://ui/map/overview_map.tscn")


func after_test() -> void:
	get_tree().paused = false


func _joy(button: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame


func test_y_on_a_place_asks_to_go_there() -> void:
	var was := Settings.tester_options
	Settings.tester_options = true
	var map: OverviewMap = auto_free(OVERVIEW.instantiate())
	var player: Node3D = auto_free(Node3D.new())
	add_child(player)
	var r := MapRenderer.new()
	r.set_bounds(Vector4(-1000, -1000, 1000, 1000))
	map.renderer = r
	map.player = player
	add_child(map)
	var p := Services.Place.new()
	p.id = "pad"
	p.kind = "helipad"
	p.name = "Pad"
	p.at = Vector3(10, 0, 10)
	map.places = [p]
	map.open()
	await get_tree().process_frame
	var asked: Array = []
	map.legend.go_to_requested.connect(func(pl: Services.Place) -> void: asked.append(pl))
	await _joy(JOY_BUTTON_A)  # open the kind
	assert_int(map.legend.level).is_equal(MapLegend.Level.PLACES)
	await _joy(JOY_BUTTON_Y)
	assert_int(asked.size()).is_equal(1)
	map.close()
	Settings.tester_options = was
