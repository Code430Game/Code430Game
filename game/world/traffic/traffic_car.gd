class_name TrafficCar
extends RigidBody3D
## Pooled physics body for a traffic agent near the player: frozen kinematic
## while following (the manager sets its transform), physics for a few seconds
## after the player hits it. Invisible: the MultiMesh draws the car.

signal hit(car: TrafficCar)

var agent: TrafficAgent = null
var last_hitter_velocity: Vector3 = Vector3.ZERO


## Resizes the box to a vehicle kind (cars by default, buses when `size` is bigger).
func set_box(size: Vector3) -> void:
	var shape := $Shape as CollisionShape3D
	var box := shape.shape as BoxShape3D
	if box.size != size:
		box = BoxShape3D.new()
		box.size = size
		shape.shape = box
	shape.position.y = size.y * 0.5 + 0.1
	mass = 1100.0 if size.z < 6.0 else 12000.0


func _ready() -> void:
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if agent == null or agent.retired or body is TrafficCar:
		return
	if body is VehicleBody3D or body is CharacterBody3D:
		last_hitter_velocity = body.get("linear_velocity") if body is VehicleBody3D else (body as CharacterBody3D).velocity
		hit.emit(self)
