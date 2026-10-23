class_name SurfaceDetail
extends RefCounted
## Generated detail textures for ground surfaces (asphalt grain, concrete speckle, paint wear),
## sampled in world space by ground_detail.gdshader so chunks need no UVs.
##
## Each texture is seamless greyscale noise centred on mid-grey (0.5 = no change): the shader
## turns it into a small brightness and roughness variation over the vertex colour. Built once
## per size from fixed seeds, so every run and every machine gets the same pixels. The preset
## picks the size (`surface_detail_px`) and whether a second, larger-scale sample breaks up the
## tiling (`surface_detail_macro`). No normal maps: the ground meshes carry no tangents.

const SHADER := preload("res://world/roads/ground_detail.gdshader")
## kind -> [seed, frequency, grain amplitude, speckle chance, speckle amplitude, tile metres]
const KINDS := {
	"asphalt": [431, 0.16, 0.14, 0.02, 0.2, 2.5],
	"concrete": [432, 0.1, 0.13, 0.01, 0.12, 1.5],
	"paint": [433, 0.06, 0.08, 0.0, 0.0, 2.0],
}

static var _cache: Dictionary = {}  # "kind:size" -> ImageTexture
const RECIPE_VERSION := 3  # bump when build_image changes, so cached PNGs are rebuilt


static var _last_preset: Dictionary = {}  # the last preset() read on the main thread, for loads on others


## The preset's detail texture size and macro switch (defaults when there is no preset). Off the
## main thread (a map loading under the loading screen) it is the last one read on it.
static func preset() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return _last_preset if not _last_preset.is_empty() else {"px": 512, "macro": false}
	var tree := Engine.get_main_loop() as SceneTree
	var settings: Node = tree.root.get_node_or_null("Settings") if tree != null else null
	var p: Dictionary = {}
	if settings != null:
		p = (settings.get("presets") as Dictionary).get(str(settings.get("current_preset_name")), {})
	_last_preset = {"px": int(p.get("surface_detail_px", 512)), "macro": bool(p.get("surface_detail_macro", false))}
	return _last_preset


## Greyscale detail image for `kind` at `size` px (fresh; see texture() for the cached one).
static func build_image(kind: String, size: int) -> Image:
	var spec: Array = KINDS[kind]
	var noise := FastNoiseLite.new()
	noise.seed = int(spec[0])
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	# Frequency is per pixel at 512 px; scale it so every size shows the same pattern per metre.
	noise.frequency = float(spec[1]) * 512.0 / size
	var grain := noise.get_seamless_image(size, size, false, false, 0.1, true)
	grain.convert(Image.FORMAT_L8)
	var src := grain.get_data()
	var out := PackedByteArray()
	out.resize(src.size())
	var amp := float(spec[2]) * 2.0
	for i in range(src.size()):
		out[i] = clampi(int(128.0 + (src[i] - 128.0) * amp), 0, 255)
	# Aggregate: a few lone pixels, mostly lighter stones, at fixed random spots.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec[0]) * 7
	var stones := int(size * size * float(spec[3]))
	var lift := int(float(spec[4]) * 255.0)
	for k in range(stones):
		var i := rng.randi_range(0, out.size() - 1)
		out[i] = clampi(out[i] + (lift if rng.randf() < 0.6 else -lift), 0, 255)
	return Image.create_from_data(size, size, false, Image.FORMAT_L8, out)


## The cached detail texture for `kind` at the preset's size.
## Built on the first run and kept as a PNG in user:// (the output is deterministic), so later
## boots skip the noise generation (about 0.2 s at 512 px on a Mac, more on the Deck).
static func texture(kind: String) -> ImageTexture:
	var size: int = preset()["px"]
	var key := "%s:%d" % [kind, size]
	if not _cache.has(key):
		var path := "user://cache/surface_detail_v%d_%s_%d.png" % [RECIPE_VERSION, kind, size]
		var img: Image = null
		if FileAccess.file_exists(path):
			img = Image.load_from_file(path)
		if img == null or img.get_width() != size:
			img = build_image(kind, size)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://cache"))
			img.save_png(path)
		img.convert(Image.FORMAT_L8)
		img.generate_mipmaps()
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


## A ground material: vertex colours (sRGB) with `kind` detail in world space.
static func material(kind: String, roughness: float, emission: Color = Color.BLACK, emission_energy: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("detail", texture(kind))
	m.set_shader_parameter("tile_m", float(KINDS[kind][5]))
	m.set_shader_parameter("roughness", roughness)
	m.set_shader_parameter("macro", bool(preset()["macro"]))
	m.set_shader_parameter("emission_color", emission)
	m.set_shader_parameter("emission_energy", emission_energy)
	return m
