class_name TrafficCar
extends RigidBody3D
## Pooled physics body for a traffic agent near the player: frozen kinematic
## while following (the manager sets its transform), physics for a few seconds
## after the player hits it. Invisible: the MultiMesh draws the car.

signal hit(car: TrafficCar)

var agent: TrafficAgent = null


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
		hit.emit(self)
