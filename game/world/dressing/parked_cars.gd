class_name ParkedCars
extends Node3D
## Cars parked in the lots' stalls: deterministic, drawn like traffic, takeable.
##
## Which stalls hold a car, and which car, comes from a seed made of the lot id and the
## current block of hours (`hour_bucket`), so every peer sees the same cars and a lot fills
## and empties through the day without flicker. Commercial lots (fee or operator) are fuller
## by day, residential ones at night. Cars are drawn from one MultiMesh per catalogue vehicle
## and LOD, refreshed a few times a second, within `draw_radius_m` of a player and no more than
## the preset's `parked_cars_per_chunk` per chunk (the stalls farthest from every player stay
## empty). The nearest few get a pooled TrafficCar body so they can be hit and taken: frozen
## while nothing is near, dynamic with their real mass while a vehicle is within a metre, and
## refrozen where they came to rest, never snapped back (a frozen snap launches what it
## touches). A taken car's stall stays empty for the session.

## Emitted when a car is taken from a stall here (the host tells the other peers).
signal stall_taken(key: String)

const CONFIG_PATH := "res://world/dressing/parking_config.json"
const BODY_SCENE := preload("res://world/traffic/traffic_car.tscn")
const TAIL_SHADER := preload("res://actors/vehicles/car_tail.gdshader")
## Cell size of the lookup grid: the per-tick body check and the draw pass only visit the cells
## near a player instead of every parked car in the city (thousands in a big pack).
const CELL_M := 32.0

class Parked:
	extends RefCounted
	var lot: ParkingLotBuilder.Lot
	var stall: ParkingLotBuilder.Stall
	var key: String  # lot id + stall index: stable across sessions and peers
	var vehicle_id: String
	var color: Color
	var chunk: Vector2i
	var moved: Transform3D  # where its body left it after a knock (IDENTITY when untouched)
	var moved_set: bool = false
	var body: TrafficCar = null
	var agent: TrafficAgent = null  # for the body (take and hit handling read it)

	func transform() -> Transform3D:
		if moved_set:
			return moved
		var y := stall.y if not is_nan(stall.y) else lot.ground_y
		var f := Vector3(stall.facing.x, 0.0, stall.facing.y)
		return Transform3D(Basis.looking_at(f, Vector3.UP), Vector3(stall.centre.x, y, stall.centre.y))


var config: Dictionary = {}
var lots: Array = []  # ParkingLotBuilder.Lot
## Positions cars are drawn around (the players). Set each frame by the scene.
var anchors: PackedVector3Array = PackedVector3Array()
## Clock hour (0..24), set by the scene; occupancy follows it in blocks of `hour_bucket`.
var hour: float = 12.0
## Pins the share of occupied stalls (screenshots, `--parking-occupancy=`); negative: use the table.
var occupancy_override: float = -1.0
var per_chunk_cap: int = 120
var bodies_max: int = 8
var lod0_m: float = 80.0
var cars: Array[Parked] = []  # occupied stalls for the current hour block
var _grid: Dictionary = {}  # Vector2i cell -> Array[Parked]
var _by_key: Dictionary = {}  # Parked.key -> Parked
var taken: Dictionary = {}  # Parked.key -> true for the session
var _bucket: int = -1
var _meshes: Dictionary = {}  # "vehicle_id:lod" -> MultiMeshInstance3D
var _bodies: Array[TrafficCar] = []
var _refresh_left: float = 0.0
var _tail_material: ShaderMaterial
var _body_material: StandardMaterial3D


func _ready() -> void:
	if config.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		config = parsed if parsed is Dictionary else {}


## Takes the pack's lots and builds the meshes and body pool.
func setup(pack_lots: Array) -> void:
	lots = pack_lots
	var preset: Dictionary = Settings.presets.get(Settings.current_preset_name, {})
	per_chunk_cap = int(preset.get("parked_cars_per_chunk", per_chunk_cap))
	bodies_max = int(preset.get("parked_car_bodies", bodies_max))
	lod0_m = float(preset.get("vehicle_lod0_m", lod0_m))
	_tail_material = ShaderMaterial.new()
	_tail_material.shader = TAIL_SHADER
	_body_material = VehicleMesh.body_material(Color.WHITE)
	for id: String in (config.get("vehicle_weights", {}) as Dictionary):
		if not VehicleCatalogue.has(id):
			continue
		for lod in [VehicleMesh.Lod.LOD0, VehicleMesh.Lod.LOD1]:
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "parked_%s_lod%d" % [id, lod]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			var mesh := VehicleMesh.build(VehicleCatalogue.entry(id), lod, true, VehicleCatalogue.livery(id))
			mesh.surface_set_material(0, _body_material)
			mesh.surface_set_material(3, _tail_material)
			mm.mesh = mesh
			mm.instance_count = 16
			mm.visible_instance_count = 0
			mmi.multimesh = mm
			add_child(mmi)
			_meshes["%s:%d" % [id, lod]] = mmi
	for i in range(bodies_max):
		var body: TrafficCar = BODY_SCENE.instantiate()
		body.set_meta("parked", true)
		add_child(body)
		body.process_mode = Node.PROCESS_MODE_DISABLED
		body.global_position = Vector3(0, -1000, 0)
		_bodies.append(body)
	fill()


## The hour block an hour falls in.
func bucket_of(h: float) -> int:
	return int(floor(fposmod(h, 24.0) / float(config.get("hour_bucket", 3))))


## Share of a lot's stalls occupied at `h`.
func occupancy(lot: ParkingLotBuilder.Lot, h: float) -> float:
	if occupancy_override >= 0.0:
		return occupancy_override
	var table: Dictionary = config.get("occupancy", {})
	var kind: Dictionary = table.get("commercial" if lot.is_commercial() else "residential", {"day": 0.5, "night": 0.5})
	var day: Array = config.get("day_hours", [7, 19])
	var is_day := h >= float(day[0]) and h < float(day[1])
	return float(kind["day"] if is_day else kind["night"])


## Recomputes which stalls hold which cars for the current hour block (deterministic).
func fill() -> void:
	for c in cars:
		_release(c)
	cars.clear()
	_grid.clear()
	_by_key.clear()
	_bucket = bucket_of(hour)
	var weights: Dictionary = config.get("vehicle_weights", {"sedan": 1.0})
	var ids: Array = []
	var total := 0.0
	for id: String in weights:
		if VehicleCatalogue.has(id):
			ids.append(id)
			total += float(weights[id])
	var mid_hour := (_bucket + 0.5) * float(config.get("hour_bucket", 3))
	for lot: ParkingLotBuilder.Lot in lots:
		var share := occupancy(lot, mid_hour)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(lot.id) ^ (_bucket * 7919)
		for s in lot.stalls:
			var roll := rng.randf()
			var pick := rng.randf() * total
			var colour_roll := rng.randi()
			var key := "%s#%d" % [lot.id, s.index]
			if roll >= share or taken.has(key):
				continue
			var id: String = ids[ids.size() - 1]
			for candidate: String in ids:
				pick -= float(weights[candidate])
				if pick <= 0.0:
					id = candidate
					break
			var palette: Array = VehicleCatalogue.livery(id).get("colors", VehicleCatalogue.entry(id).get("colors", [[1, 1, 1]]))
			var col: Array = palette[colour_roll % palette.size()]
			var p := Parked.new()
			p.lot = lot
			p.stall = s
			p.key = key
			p.vehicle_id = id
			p.color = Color(float(col[0]), float(col[1]), float(col[2]))
			p.chunk = RoadGeometry.chunk_of(Vector3(s.centre.x, 0.0, s.centre.y))
			cars.append(p)
			_by_key[key] = p
			var cell := _cell_of(s.centre)
			if not _grid.has(cell):
				_grid[cell] = []
			(_grid[cell] as Array).append(p)


static func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL_M)), int(floor(p.y / CELL_M)))


## [distance, car] for every car within `radius` of a player, nearest first; visits only the
## grid cells around the players.
func _near(radius: float) -> Array:
	var seen := {}
	var out: Array = []
	for a in anchors:
		var lo := _cell_of(Vector2(a.x - radius, a.z - radius))
		var hi := _cell_of(Vector2(a.x + radius, a.z + radius))
		for cx in range(lo.x, hi.x + 1):
			for cy in range(lo.y, hi.y + 1):
				for c: Parked in _grid.get(Vector2i(cx, cy), []):
					if seen.has(c):
						continue
					seen[c] = true
					var d := _distance(c.stall.centre)
					if d <= radius:
						out.append([d, c])
	out.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	return out


func _physics_process(delta: float) -> void:
	if anchors.is_empty() or _meshes.is_empty():
		return
	if bucket_of(hour) != _bucket:
		fill()
	_update_bodies()
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = float(config.get("refresh_s", 0.5))
		render()


func _distance(p: Vector2) -> float:
	var best := INF
	for a in anchors:
		best = minf(best, Vector2(a.x - p.x, a.z - p.y).length())
	return best


## The cars to draw: within the draw radius, nearest first, at most the cap per chunk.
func visible_cars() -> Array[Parked]:
	var near := _near(float(config.get("draw_radius_m", 350.0)))
	var per_chunk := {}
	var out: Array[Parked] = []
	for pair: Array in near:
		var c: Parked = pair[1]
		var n := int(per_chunk.get(c.chunk, 0))
		if n >= per_chunk_cap:
			continue
		per_chunk[c.chunk] = n + 1
		out.append(c)
	return out


func render() -> void:
	var groups := {}
	for c in visible_cars():
		var t := c.transform() if c.body == null else c.body.global_transform
		var lod := VehicleMesh.Lod.LOD0 if _distance(c.stall.centre) <= lod0_m else VehicleMesh.Lod.LOD1
		var key := "%s:%d" % [c.vehicle_id, lod]
		if not _meshes.has(key):
			continue
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append([t, c.color])
	for key: String in _meshes:
		var mm: MultiMesh = (_meshes[key] as MultiMeshInstance3D).multimesh
		var list: Array = groups.get(key, [])
		if list.size() > mm.instance_count:
			mm.instance_count = int(list.size() * 1.5)
		for i in range(list.size()):
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
			mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
		mm.visible_instance_count = list.size()


## Gives the nearest cars bodies; frozen unless a vehicle is close, refrozen where they rest.
func _update_bodies() -> void:
	var near := _near(float(config.get("body_radius_m", 45.0)))
	var wanted := {}
	for i in range(mini(near.size(), _bodies.size())):
		wanted[near[i][1]] = true
	for b in _bodies:
		var held := car_for(b) if b.agent != null else null
		if held != null and not wanted.has(held) and b.freeze:
			_release(held)
	for c: Parked in wanted:
		if c.body == null:
			_attach(c)
		if c.body == null:
			continue
		if c.body.vehicle_near():
			if c.body.freeze:
				c.body.freeze = false  # dynamic before any contact: a car you hit moves with its mass
				c.body.speed_cap = float(config.get("separation_cap_mps", 25.0))
		elif not c.body.freeze and c.body.linear_velocity.length() < 0.2 and c.body.angular_velocity.length() < 0.2:
			c.moved = c.body.global_transform  # where it came to rest: it stays there
			c.moved_set = true
			c.body.refreeze()


func _attach(c: Parked) -> void:
	for b in _bodies:
		if b.agent == null:
			var a := TrafficAgent.new()
			a.vehicle_id = c.vehicle_id
			a.color = c.color
			a.transform = c.transform()
			a.retired = true  # not driving anywhere
			a.resting = true
			a.length_m = float(VehicleCatalogue.entry(c.vehicle_id)["dims"]["length_m"])
			c.agent = a
			c.body = b
			b.agent = a
			b.set_meta("parked_key", c.key)
			var entry := VehicleCatalogue.entry(c.vehicle_id)
			b.set_box(VehicleMesh.box_size(entry), float(entry.get("mass_kg", 1400.0)))
			b.process_mode = Node.PROCESS_MODE_INHERIT
			b.global_transform = c.transform()
			b.refreeze()
			return


func _release(c: Parked) -> void:
	if c.body == null:
		return
	c.body.agent = null
	c.body.refreeze()
	c.body.remove_meta("parked_key")
	c.body.process_mode = Node.PROCESS_MODE_DISABLED
	c.body.global_position = Vector3(0, -1000, 0)
	c.body = null
	c.agent = null


## The parked car behind a body, or null.
func car_for(body: Node) -> Parked:
	if body == null or not body.has_meta("parked_key"):
		return null
	return _by_key.get(body.get_meta("parked_key"))


## Turns the parked car behind `body` into a drivable car of its class and colour at its
## spot; its stall stays empty for the session. Returns null when `body` is not a parked car.
func take(body: Node) -> VehicleBody3D:
	var c := car_for(body)
	if c == null:
		return null
	var t := c.body.global_transform if c.body != null else c.transform()
	var car: VehicleBody3D = TrafficManager.DRIVABLE_CAR_SCENE.instantiate()
	car.set("body_color", c.color)
	car.set("vehicle_id", c.vehicle_id)
	var holder: Node = get_parent() if get_parent() != null else self
	holder.add_child(car)
	car.global_transform = t.translated_local(Vector3(0.0, 0.1, 0.0))
	if car.has_method("set_spawn"):
		car.set_spawn(car.global_transform)
	taken[c.key] = true
	_release(c)
	_forget(c)
	render()
	stall_taken.emit(c.key)
	return car


## Host: empties the stall `key` for a guest who takes its car. Returns {"transform", "color",
## "vehicle"}, or {} when the stall holds no car (already taken, or not occupied this hour).
func release_key(key: String) -> Dictionary:
	var c: Parked = _by_key.get(key)
	if c == null:
		return {}
	var out := {"transform": c.body.global_transform if c.body != null else c.transform(), "color": c.color, "vehicle": c.vehicle_id}
	mark_taken(key)
	stall_taken.emit(key)
	return out


## Any peer: the car in stall `key` has been taken; it stays empty for the session.
func mark_taken(key: String) -> void:
	taken[key] = true
	var c: Parked = _by_key.get(key)
	if c != null:
		_release(c)
		_forget(c)
	render()


func _forget(c: Parked) -> void:
	cars.erase(c)
	_by_key.erase(c.key)
	var cell: Array = _grid.get(_cell_of(c.stall.centre), [])
	cell.erase(c)
