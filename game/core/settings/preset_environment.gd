class_name PresetEnvironment
extends WorldEnvironment
## WorldEnvironment that follows the active graphics preset.
## Attach to any scene's WorldEnvironment; it re-applies on preset changes.


func _ready() -> void:
	Settings.preset_applied.connect(_on_preset_applied)
	Settings.apply_to_environment(environment)


func _on_preset_applied(_name: String, _preset: Dictionary) -> void:
	Settings.apply_to_environment(environment)
