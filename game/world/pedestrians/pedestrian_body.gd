class_name PedestrianBody
extends RigidBody3D
## Pooled physics body for a pedestrian near the player: frozen kinematic while walking (the
## manager sets its transform) so people on foot bump into it. It sits on the pedestrian layer
## with an empty mask, so vehicles never touch it: a frozen body is an immovable wall to the
## solver and stopped cars dead. A slightly larger sensor reports vehicles closing on it, and
## the manager knocks the person down before any contact. Invisible: the MultiMesh draws them.

signal hit(body: PedestrianBody, vehicle: Node3D, velocity: Vector3)

const LAYER := 4  # physics layer 3, "pedestrians": players carry it in their mask, vehicles don't
const SENSOR_MARGIN_M := 0.15

var agent: Pedestrian = null
var min_hit_speed: float = 1.5  # m/s closing speed that counts as a hit (from the config)
var sensor: Area3D


func _ready() -> void:
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = LAYER
	collision_mask = 0
	sensor = Area3D.new()
	sensor.name = "Sensor"
	sensor.collision_layer = 0
	sensor.collision_mask = 1
	sensor.monitorable = false
	var body_shape := $Shape as CollisionShape3D
	var capsule := body_shape.shape as CapsuleShape3D
	var grown := CapsuleShape3D.new()
	grown.radius = capsule.radius + SENSOR_MARGIN_M
	grown.height = capsule.height + SENSOR_MARGIN_M * 2.0
	var shape := CollisionShape3D.new()
	shape.shape = grown
	shape.transform = body_shape.transform
	sensor.add_child(shape)
	add_child(sensor)
	sensor.body_entered.connect(_on_sensor_body_entered)


func _on_sensor_body_entered(other: Node3D) -> void:
	if agent == null or agent.state != Pedestrian.State.WALKING:
		return
	var v := vehicle_velocity(other)
	if v == Vector3.INF:
		return
	var to_me := global_position - other.global_position
	to_me.y = 0.0
	var closing := v.dot(to_me.normalized()) if to_me.length() > 0.01 else v.length()
	if closing > min_hit_speed:
		hit.emit(self, other, v)


## The velocity of a vehicle body, or Vector3.INF when `other` is not a vehicle. Traffic cars
## are frozen and moved by transform, so theirs comes from the agent driving them.
static func vehicle_velocity(other: Node) -> Vector3:
	if other is VehicleBody3D:
		return (other as VehicleBody3D).linear_velocity
	if other is TrafficCar:
		var car := other as TrafficCar
		if car.agent == null:
			return Vector3.INF
		if not car.freeze:
			return car.linear_velocity
		return -car.agent.transform.basis.z * car.agent.speed
	return Vector3.INF


## Physics after a knock-down: collides with the world and vehicles like any body.
func make_dynamic(velocity: Vector3) -> void:
	collision_mask = 1
	freeze = false
	linear_velocity = velocity


## Back to a walking body: frozen, no mask.
func make_walker() -> void:
	freeze = true
	collision_mask = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## Takes an unused body out of the physics world. Skips it when it was handed to someone
## again before this deferred call ran.
func park() -> void:
	if agent == null:
		process_mode = Node.PROCESS_MODE_DISABLED
