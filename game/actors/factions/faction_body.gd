class_name FactionBody
extends AnimatableBody3D
## The capsule that lets weapons reach a gang member (add-hostile-gang), the officer body's
## twin: it rides on the member, sits on its own `factions` physics layer with an empty mask
## (nothing is pushed by it; players and cars pass through), and points back at the member so
## `Shooter.hit()` and an officer's shot can hand the hit to the FactionManager.

const LAYER := 16  # physics layer 5, "factions"

var member: GangMember


func _init(radius: float = 0.32, height: float = 1.8) -> void:
	name = "FactionBody"
	sync_to_physics = false
	collision_layer = LAYER
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0)
	shape.shape = capsule
	shape.position = Vector3.UP * capsule.height * 0.5
	add_child(shape)


## Takes the body out of the way (a downed or tagged-out member can't be hit again).
func disable() -> void:
	collision_layer = 0


func enable() -> void:
	collision_layer = LAYER
