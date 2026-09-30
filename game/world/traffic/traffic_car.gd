class_name TrafficCar
extends RigidBody3D
## A traffic agent's body: frozen kinematic while following its lane (the
## manager moves it), physics for a few seconds after the player hits it.

var path_id: int = -1
var distance: float = 0.0  # along the current path
var speed: float = 0.0  # m/s
var wait_time: float = 0.0
var occupies_junction: String = ""
var hit_timer: float = 0.0
var retired: bool = false  # after a hit: sits where it stopped until despawned
var tint: Color = Color.WHITE

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.5
	mat.metallic = 0.3
	_mesh.material_override = mat


## Places the body on its lane, facing along `direction` (forward is -Z).
func place(position: Vector3, direction: Vector3) -> void:
	var basis := Basis.looking_at(direction, Vector3.UP)
	global_transform = Transform3D(basis, position)


func _on_body_entered(body: Node) -> void:
	if retired or body is TrafficCar:
		return
	if body is VehicleBody3D or body is CharacterBody3D:
		hit_timer = 1.0  # set properly by the manager, which knows the config
		retired = true
		freeze = false
