class_name TrafficAgent
extends RefCounted
## Simulation state of one traffic car. Rendering is a MultiMesh instance; a
## physics body is attached only while the car is near a player.

var path_id: int = -1
var distance: float = 0.0
var speed: float = 0.0
var wait_time: float = 0.0
var occupies_junction: String = ""
var retired: bool = false  # hit: physics for hit_timer seconds, then resting or recovered
var resting: bool = false  # retired and at rest off its lane; blocks followers, never moves again
var hit_timer: float = 0.0
var color: Color = Color.WHITE
var kind: int = 0  # TrafficManager.Kind: 0 car, 1 bus (from the vehicle's body class)
var vehicle_id: String = "sedan"  # VehicleCatalogue entry: body, size, palette
var length_m: float = 4.3
var next_stop_d: float = INF  # buses: distance along the current path of the next stop
var dwell: float = 0.0  # buses: seconds left standing at a stop
var transform: Transform3D = Transform3D.IDENTITY
var body: TrafficCar = null  # pooled physics body while near a player, else null
var anchor_dist: float = INF  # distance to the nearest player, refreshed once per tick
var stopped_at_sign: bool = false  # came to a full stop at the stop sign ahead
var braking: bool = false  # slowing or held: tail lights flash
var blocked_time: float = 0.0  # seconds stuck behind something that is not moving
var lane_shift: Vector3 = Vector3.ZERO  # sidestep: world offset from the old lane, blended out over lane_shift_m
var lane_shift_left_m: float = 0.0  # metres of travel left in the blend
var lane_shift_m: float = 0.0  # metres of travel the blend covers


func position() -> Vector3:
	return transform.origin
