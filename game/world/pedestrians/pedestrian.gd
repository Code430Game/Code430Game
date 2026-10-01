class_name Pedestrian
extends RefCounted
## Simulation state of one pedestrian. Rendering is a MultiMesh instance; a physics body is
## attached only while near a player.

enum State { WALKING, HIT, DOWN }

var path_id: int = -1
var distance: float = 0.0
var forward: bool = true  # walking toward the path's end
var speed: float = 1.3
var lateral: float = 0.0  # offset from the ribbon centre, metres, left-positive
var wait_time: float = 0.0
var state: int = State.WALKING
var timer: float = 0.0  # HIT: physics window left; DOWN: time until removal
var color: Color = Color.WHITE
var transform: Transform3D = Transform3D.IDENTITY
var body: PedestrianBody = null


func position() -> Vector3:
	return transform.origin
