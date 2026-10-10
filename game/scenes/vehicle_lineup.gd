extends Node3D
## Every catalogue vehicle side by side: LOD0 in front, LOD1 behind, each in a palette colour,
## for screenshots. `--night` darkens the sky and lights the lamps; `--screenshot=path` saves
## a frame and quits; `--angle=front|side|rear` picks the camera; `--at=<id>` centres it on
## that vehicle.
##
## Run: Godot --path game res://scenes/vehicle_lineup.tscn -- --screenshot=/tmp/lineup.png

const SPACING_M := 3.4

var _screenshot := ""
var _night := false
var _angle := "front"
var _frames := 0
var _at := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			_screenshot = arg.get_slice("=", 1)
		elif arg == "--night":
			_night = true
		elif arg.begins_with("--angle="):
			_angle = arg.get_slice("=", 1)
		elif arg.begins_with("--at="):
			_at = arg.get_slice("=", 1)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.04, 0.05, 0.08) if _night else Color(0.62, 0.74, 0.86)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.12, 0.13, 0.18) if _night else Color(0.55, 0.58, 0.62)
	env.environment.glow_enabled = _night
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 0.08 if _night else 1.0
	sun.shadow_enabled = true
	add_child(sun)
	VehicleMesh.light_material().emission_energy_multiplier = VehicleMesh.LIGHT_NIGHT_ENERGY if _night else 0.0
	VehicleMesh.tail_material().emission_energy_multiplier = VehicleMesh.LIGHT_NIGHT_ENERGY * 0.6 if _night else 0.0
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 60)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.22, 0.24)
	plane.material = mat
	ground.mesh = plane
	add_child(ground)
	var ids: PackedStringArray = VehicleCatalogue.ids()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var x0 := -SPACING_M * (ids.size() - 1) * 0.5
	var focus_x := 0.0
	for i in range(ids.size()):
		var id := ids[i]
		var e: Dictionary = VehicleCatalogue.entry(id)
		var spacing := SPACING_M * (1.6 if e["body_class"] == "bus" else 1.0)
		var colour := VehicleCatalogue.pick_color(id, rng)
		for lod in [VehicleMesh.Lod.LOD0, VehicleMesh.Lod.LOD1]:
			var mi := MeshInstance3D.new()
			mi.mesh = VehicleMesh.build(e, lod, true, VehicleCatalogue.livery(id))
			mi.set_surface_override_material(0, VehicleMesh.body_material(colour))
			mi.position = Vector3(x0 + i * SPACING_M + (spacing - SPACING_M) * 0.5, 0, 0.0 if lod == VehicleMesh.Lod.LOD0 else 14.0)
			add_child(mi)
		if id == _at:
			focus_x = x0 + i * SPACING_M
	var cam := Camera3D.new()
	add_child(cam)
	match _angle:
		"side":
			cam.position = Vector3(-22, 4.0, -9)
			cam.look_at(Vector3(-2, 1.0, 3))
		"rear":
			cam.position = Vector3(4, 4.5, 32)
			cam.look_at(Vector3(0, 1.0, 7))
		_:
			cam.position = Vector3(4, 5.0, -17)
			cam.look_at(Vector3(0, 1.0, 4))
	cam.position.x += focus_x  # after look_at: slides the view sideways, same angle
	cam.fov = 55.0
	cam.current = true


func _process(_delta: float) -> void:
	_frames += 1
	if _screenshot != "" and _frames == 8:
		await RenderingServer.frame_post_draw
		var err := get_viewport().get_texture().get_image().save_png(_screenshot)
		print("screenshot: %s (%s)" % [_screenshot, error_string(err)])
		get_tree().quit()
