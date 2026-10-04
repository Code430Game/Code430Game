class_name TrafficCar
extends RigidBody3D
## Pooled physics body for a traffic agent near the player: frozen kinematic while following
## (the manager sets its transform), physics for a few seconds after the player hits it.
## Invisible: the MultiMesh draws the car.
##
## A frozen body is infinite mass to the solver, so a car touching it stops dead (or, if the
## frozen body moves into it, gets shoved as if weightless). So while a player's vehicle is
## within a metre, the body is "guarded": dynamic, with its class's mass, and steered
## along its lane by velocity instead of teleported. A real contact then trades momentum
## between two real bodies; a near miss just refreezes it. While dynamic its speed is capped
## (`speed_cap`) so a wedged body can never be launched.

signal hit(car: TrafficCar)

var agent: TrafficAgent = null
var last_hitter_velocity: Vector3 = Vector3.ZERO
var last_hitter: Node3D = null
var guarded: bool = false  # dynamic and following its agent: a player's vehicle is close
var speed_cap: float = INF  # m/s while dynamic; INF when frozen
var sensor: Area3D


## Resizes the box to a vehicle (width, height, length) and sets its mass; without a mass,
## one is guessed from the length (cars, or buses when `size` is bigger).
func set_box(size: Vector3, kg: float = -1.0) -> void:
	var shape := $Shape as CollisionShape3D
	var box := shape.shape as BoxShape3D
	if box.size != size:
		box = BoxShape3D.new()
		box.size = size
		shape.shape = box
	shape.position.y = size.y * 0.5 + 0.1
	_fit_sensor()
	mass = kg if kg > 0.0 else (1100.0 if size.z < 6.0 else 12000.0)


func _ready() -> void:
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_body_entered)
	sensor = Area3D.new()
	sensor.name = "Sensor"
	sensor.collision_layer = 0
	sensor.collision_mask = 1
	sensor.monitorable = false
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = BoxShape3D.new()
	sensor.add_child(shape)
	add_child(sensor)
	_fit_sensor()


## The sensor box: the body's box grown by `margin` on every side.
func _fit_sensor(margin: float = 1.0) -> void:
	if sensor == null:
		return
	var body_shape := $Shape as CollisionShape3D
	var s := sensor.get_node("Shape") as CollisionShape3D
	(s.shape as BoxShape3D).size = (body_shape.shape as BoxShape3D).size + Vector3.ONE * margin * 2.0
	s.position = body_shape.position


## True while a player's vehicle is inside the sensor (asked of the area each time: counting
## enter and exit events lost track when the body switched between frozen and dynamic).
func vehicle_near() -> bool:
	if sensor == null or not sensor.monitoring or not is_inside_tree():
		return false
	for b in sensor.get_overlapping_bodies():
		if b is VehicleBody3D:
			return true
	return false


## Guarded following: dynamic, steered toward `target`. The velocity is blended a quarter of
## the way toward the one that reaches the target this step, aimed no faster than
## `steer_speed`: setting it outright every step would overrule every contact and make the body
## an unstoppable pusher again. `cap` bounds its speed whatever happens.
func follow(target: Transform3D, delta: float, steer_speed: float, cap: float) -> void:
	if freeze:
		freeze = false
		guarded = true
	speed_cap = cap
	var to := target.origin - global_position
	var want := (to / maxf(delta, 0.001)).limit_length(steer_speed)
	linear_velocity = linear_velocity.lerp(want, 0.25)
	var q := (target.basis.get_rotation_quaternion() * global_basis.get_rotation_quaternion().inverse()).normalized()
	var angle := q.get_angle()
	if angle > PI:
		angle -= TAU
	var want_spin := q.get_axis().normalized() * angle / maxf(delta, 0.001) if absf(angle) > 0.0001 else Vector3.ZERO
	angular_velocity = angular_velocity.lerp(want_spin.limit_length(2.0), 0.25)


## Back to frozen kinematic following (the manager snaps it to the agent next).
func refreeze() -> void:
	guarded = false
	speed_cap = INF
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if speed_cap < INF and state.linear_velocity.length() > speed_cap:
		state.linear_velocity = state.linear_velocity.limit_length(speed_cap)


func _on_body_entered(body: Node) -> void:
	if agent == null or agent.retired or body is TrafficCar:
		return
	if body is VehicleBody3D or body is CharacterBody3D:
		last_hitter_velocity = body.get("linear_velocity") if body is VehicleBody3D else (body as CharacterBody3D).velocity
		last_hitter = body
		hit.emit(self)
