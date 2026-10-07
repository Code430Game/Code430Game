extends Node
## Settings autoload: graphics preset selection, the player's control bindings, persistence.
##
## Preset data lives in presets.json. The active preset is `deck` on Steam Deck
## hardware unless the player saved an override; otherwise `high`. Rendering
## features that live on the viewport are applied here; features that live on an
## Environment resource are applied by `apply_to_environment`, which scenes call
## from their WorldEnvironment (see PresetEnvironment).

signal preset_applied(preset_name: String, preset: Dictionary)

const PRESETS_PATH := "res://core/settings/presets.json"
const DEFAULT_SETTINGS_PATH := "user://settings.cfg"
const SECTION_GRAPHICS := "graphics"
const KEY_PRESET := "preset"
## Rebound controls: key "<action>/pad" or "<action>/key", value Controls.event_to_dict().
## Defaults stay in project.godot, so resetting is deleting this section.
const SECTION_CONTROLS := "controls"
const PRESET_AUTO := "auto"
const PRESET_DECK := "deck"
const PRESET_HIGH := "high"

const SCALING_MODES := {
	"bilinear": Viewport.SCALING_3D_MODE_BILINEAR,
	"fsr": Viewport.SCALING_3D_MODE_FSR,
	"fsr2": Viewport.SCALING_3D_MODE_FSR2,
}
const MSAA_MODES := {
	"disabled": Viewport.MSAA_DISABLED,
	"2x": Viewport.MSAA_2X,
	"4x": Viewport.MSAA_4X,
	"8x": Viewport.MSAA_8X,
}
const SCREEN_SPACE_AA_MODES := {
	"disabled": Viewport.SCREEN_SPACE_AA_DISABLED,
	"fxaa": Viewport.SCREEN_SPACE_AA_FXAA,
}
const SHADOW_QUALITIES := {
	"hard": RenderingServer.SHADOW_QUALITY_HARD,
	"soft_very_low": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
	"soft_low": RenderingServer.SHADOW_QUALITY_SOFT_LOW,
	"soft_medium": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
	"soft_high": RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
	"soft_ultra": RenderingServer.SHADOW_QUALITY_SOFT_ULTRA,
}

## Where the settings file is read and written. Tests point this at a temp file.
var settings_path: String = DEFAULT_SETTINGS_PATH
## All presets by name, loaded from PRESETS_PATH.
var presets: Dictionary = {}
## The player's saved choice: "auto", "deck", or "high".
var preset_override: String = PRESET_AUTO
## Name of the preset currently applied.
var current_preset_name: String = ""
## True when the machine was detected as a Steam Deck.
var is_steam_deck: bool = false
## The player's rebinds, "<action>/pad" or "<action>/key" -> Controls.event_to_dict().
var binding_overrides: Dictionary = {}


func _ready() -> void:
	presets = load_presets(PRESETS_PATH)
	is_steam_deck = DeckDetector.is_steam_deck(DeckDetector.collect_facts())
	load_settings()
	apply_bindings()  # autoloads are ready before the first scene reads the input map
	apply_preset(resolve_preset_name())


## Loads the preset table from a JSON file. Returns an empty dictionary on error.
static func load_presets(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Settings: presets file missing: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Settings: presets file is not a JSON object: %s" % path)
		return {}
	var result: Dictionary = {}
	for key: String in parsed.keys():
		if not key.begins_with("_"):
			result[key] = parsed[key]
	return result


## Returns the preset name that should be active given the override and hardware.
func resolve_preset_name() -> String:
	if preset_override != PRESET_AUTO and presets.has(preset_override):
		return preset_override
	return PRESET_DECK if is_steam_deck else PRESET_HIGH


## Reads the saved override from disk. Missing file means "auto".
func load_settings() -> void:
	var cfg := ConfigFile.new()
	preset_override = PRESET_AUTO
	if cfg.load(settings_path) == OK:
		var value: Variant = cfg.get_value(SECTION_GRAPHICS, KEY_PRESET, PRESET_AUTO)
		if typeof(value) == TYPE_STRING:
			preset_override = value
	binding_overrides = {}
	if cfg.has_section(SECTION_CONTROLS):
		for key in cfg.get_section_keys(SECTION_CONTROLS):
			var d: Variant = cfg.get_value(SECTION_CONTROLS, key)
			if d is Dictionary:
				binding_overrides[key] = d


## Writes the current override to disk.
func save_settings() -> Error:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)
	cfg.set_value(SECTION_GRAPHICS, KEY_PRESET, preset_override)
	if cfg.has_section(SECTION_CONTROLS):
		cfg.erase_section(SECTION_CONTROLS)
	for key: String in binding_overrides:
		cfg.set_value(SECTION_CONTROLS, key, binding_overrides[key])
	return cfg.save(settings_path)


## Puts the saved rebinds over the project defaults. Unknown actions and bad entries are skipped.
func apply_bindings() -> void:
	for key: String in binding_overrides:
		var action := key.get_slice("/", 0)
		var event := Controls.event_from_dict(binding_overrides[key])
		if event != null and InputMap.has_action(action) and Controls.rebindable(action):
			Controls.replace_binding(action, event)


## Binds `event` to `action` (replacing its controller or keyboard binding) and saves. Refused,
## returning the conflicting action's label, when another action live at the same time already
## uses that press; returns "" when bound.
func rebind(action: String, event: InputEvent) -> String:
	if not Controls.rebindable(action):
		return action
	var other := Controls.conflict(action, event)
	if other != "":
		return Controls.label(other)
	Controls.replace_binding(action, event)
	binding_overrides["%s/%s" % [action, "pad" if Controls.is_pad_event(event) else "key"]] = Controls.event_to_dict(event)
	save_settings()
	return ""


## Back to the bindings in project.godot, and forgets the saved rebinds.
func reset_bindings() -> void:
	binding_overrides = {}
	InputMap.load_from_project_settings()
	save_settings()


## Sets the player's preset choice ("auto", "deck", "high"), saves it, and applies it.
func set_preset_override(name: String) -> void:
	if name != PRESET_AUTO and not presets.has(name):
		push_warning("Settings: unknown preset '%s', keeping '%s'" % [name, preset_override])
		return
	preset_override = name
	save_settings()
	apply_preset(resolve_preset_name())


## Applies viewport-level settings for the named preset and emits preset_applied.
func apply_preset(name: String) -> void:
	if not presets.has(name):
		push_error("Settings: cannot apply unknown preset '%s'" % name)
		return
	var preset: Dictionary = presets[name]
	current_preset_name = name
	var viewport := get_viewport()
	if viewport != null:
		viewport.scaling_3d_mode = SCALING_MODES.get(preset["scaling_mode"], Viewport.SCALING_3D_MODE_BILINEAR)
		viewport.scaling_3d_scale = float(preset["scaling_scale"])
		viewport.msaa_3d = MSAA_MODES.get(preset["msaa_3d"], Viewport.MSAA_DISABLED)
		viewport.screen_space_aa = SCREEN_SPACE_AA_MODES.get(preset["screen_space_aa"], Viewport.SCREEN_SPACE_AA_DISABLED)
		viewport.positional_shadow_atlas_size = int(preset["positional_shadow_size"])
	RenderingServer.directional_shadow_atlas_set_size(int(preset["directional_shadow_size"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(SHADOW_QUALITIES.get(preset["shadow_quality"], RenderingServer.SHADOW_QUALITY_SOFT_LOW))
	RenderingServer.positional_soft_shadow_filter_set_quality(SHADOW_QUALITIES.get(preset["shadow_quality"], RenderingServer.SHADOW_QUALITY_SOFT_LOW))
	Engine.max_fps = int(preset["max_fps"])
	preset_applied.emit(name, preset)


## Applies the Environment-level features of the current preset to `env`.
func apply_to_environment(env: Environment) -> void:
	if env == null or not presets.has(current_preset_name):
		return
	var preset: Dictionary = presets[current_preset_name]
	env.sdfgi_enabled = bool(preset["sdfgi"])
	env.ssr_enabled = bool(preset["ssr"])
	env.ssao_enabled = bool(preset["ssao"])
	env.ssil_enabled = bool(preset["ssil"])
	env.volumetric_fog_enabled = bool(preset["volumetric_fog"])
	# Godot's default density (0.05 per metre) whites the city out past about 50 m; the preset
	# sets a light haze instead.
	env.volumetric_fog_density = float(preset["volumetric_fog_density"])
	env.glow_enabled = bool(preset["glow"])


## Returns the active preset's data.
func get_current_preset() -> Dictionary:
	return presets.get(current_preset_name, {})
