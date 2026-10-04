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
var kerb_wait: float = 0.0  # seconds spent waiting to step onto a crossing
var waiting_to_cross: bool = false
var state: int = State.WALKING
var timer: float = 0.0  # HIT: physics window left; DOWN: time until removal
var color: Color = Color.WHITE
var pool: int = -1  # body pool (PedestrianManager.POOLS), chosen from the colour when unset
var transform: Transform3D = Transform3D.IDENTITY
var walk_phase: float = 0.0  # walk cycle, radians (see CharacterRig.step_walk)
var walk_amount: float = 0.0  # 0 standing .. 1 full stride
var body: PedestrianBody = null
var ragdoll: CharacterRagdoll = null  # while knocked down, when the pool has one


func position() -> Vector3:
	return transform.origin
