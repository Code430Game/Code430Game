class_name OfficerBody
extends AnimatableBody3D
## The capsule that lets the player's weapons reach a police officer (add-police-combat). It
## rides on the officer node, sits on its own `police` physics layer with an empty mask (so
## nothing is pushed by it and the player and cars pass through as before), and points back
## at the officer so `Shooter.hit()` can hand the hit to the PoliceManager. Rays, the melee
## sweep and paintballs find it; nothing else collides with it.

const LAYER := 8  # physics layer 4, "police"

var officer: Node3D


func _init(radius: float = 0.32, height: float = 1.8) -> void:
	name = "OfficerBody"
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


## Takes the body out of the way (a downed or tagged-out officer can't be hit again).
func disable() -> void:
	collision_layer = 0
