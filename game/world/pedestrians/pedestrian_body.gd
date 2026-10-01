class_name PedestrianBody
extends RigidBody3D
## Pooled physics body for a pedestrian near the player: frozen kinematic while walking
## (the manager sets its transform), physics for a few seconds after a vehicle hits it.
## Invisible: the MultiMesh draws the person.

signal hit(body: PedestrianBody)

var agent: Pedestrian = null


func _ready() -> void:
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_body_entered)


func _on_body_entered(other: Node) -> void:
	if agent == null or agent.state != Pedestrian.State.WALKING:
		return
	if other is VehicleBody3D or (other is RigidBody3D and other.is_in_group("traffic")):
		var v: Vector3 = other.linear_velocity
		if v.length() > 1.5:
			hit.emit(self)
