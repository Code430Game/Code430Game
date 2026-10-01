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
var transform: Transform3D = Transform3D.IDENTITY
var body: TrafficCar = null  # pooled physics body while near a player, else null
var anchor_dist: float = INF  # distance to the nearest player, refreshed once per tick
var stopped_at_sign: bool = false  # came to a full stop at the stop sign ahead


func position() -> Vector3:
	return transform.origin
