class_name PlayerConfig
extends Resource
## Tunables for the on-foot player. Edit player_config.tres, not code.

@export_group("Movement")
@export var walk_speed_mps: float = 2.5
@export var run_speed_mps: float = 6.0
@export var acceleration_mps2: float = 24.0
@export var deceleration_mps2: float = 30.0
@export var jump_height_m: float = 1.2
@export var turn_speed_rad_s: float = 10.0
@export var floor_max_angle_deg: float = 50.0
@export var wade_speed_factor: float = 0.45
## Tallest curb or stair the player walks straight up without jumping.
@export var step_height_m: float = 0.35

@export_group("Camera")
@export var camera_distance_m: float = 3.5
@export var camera_height_m: float = 1.5
@export var camera_orbit_speed_rad_s: float = 2.8
@export var camera_pitch_min_deg: float = -35.0
@export var camera_pitch_max_deg: float = 60.0
@export var camera_default_pitch_deg: float = 12.0
@export var mouse_look_rad_per_px: float = 0.0025

@export_group("Vehicles")
@export var enter_range_m: float = 2.5
@export var exit_max_speed_mps: float = 5.0
@export var exit_side_offset_m: float = 1.6
@export var exit_probe_up_m: float = 1.0
@export var exit_probe_down_m: float = 4.0


## Upward velocity that reaches jump_height_m under the given gravity.
func jump_velocity(gravity: float) -> float:
	return sqrt(2.0 * gravity * jump_height_m)
