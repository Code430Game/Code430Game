extends Node3D
## People side by side for screenshots (add-character-features): each outfit twice, body A then
## body B beside it, so the bodies compare like for like. `--tone=` sets
## the content mode, `--angle=front|side` the camera, `--screenshot=path` saves a frame and quits.
##
## Run: Godot --path game res://scenes/character_lineup.tscn -- --screenshot=/tmp/people.png

const SPACING_M := 0.85
const COLUMNS := 5

var _screenshot := ""
var _angle := "front"
var _frames := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			_screenshot = arg.get_slice("=", 1)
		elif arg.begins_with("--angle="):
			_angle = arg.get_slice("=", 1)
		elif arg.begins_with("--tone="):
			ContentMode.set_mode(arg.get_slice("=", 1), false)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.74, 0.86)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.62)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 20)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.33, 0.34)
	plane.material = mat
	ground.mesh = plane
	add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var x0 := -SPACING_M * (COLUMNS * 2 - 1) * 0.5
	for i in range(COLUMNS):
		var outfit := CharacterProfile.random(rng)
		for body in [0, 1]:
			var p := outfit.duplicate()
			p["body"] = body
			var rig := CharacterRig.new()
			rig.profile = CharacterProfile.normalise(p)
			rig.position = Vector3(x0 + (i * 2 + body) * SPACING_M + i * 0.35, 0.0, 0.0)
			rig.rotation.y = PI  # face the camera (bodies face -Z)
			add_child(rig)
	var cam := Camera3D.new()
	add_child(cam)
	if _angle == "side":
		cam.position = Vector3(-6.5, 1.6, 0.8)
		cam.look_at(Vector3(0, 1.0, 0.8))
	else:
		cam.position = Vector3(0.0, 1.3, 7.6)
		cam.look_at(Vector3(0, 0.9, 0.0))
	cam.fov = 50.0
	cam.current = true


func _process(_delta: float) -> void:
	_frames += 1
	if _screenshot != "" and _frames == 8:
		await RenderingServer.frame_post_draw
		var err := get_viewport().get_texture().get_image().save_png(_screenshot)
		print("screenshot: %s (%s)" % [_screenshot, error_string(err)])
		get_tree().quit()
