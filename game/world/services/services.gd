class_name Services
extends RefCounted
## Emergency service places from services.v0.json (add-emergency-services): police stations,
## security desks, hospitals, fire stations, ambulance posts and helipads, each with a street
## address where the data has one (add-map-legend). Their map icons are PlaceIcons.

class Place:
	extends RefCounted
	var id: String
	var kind: String
	var name: String
	var at: Vector3
	var road_node: String
	var address: String  # "474 Elgin Street", "on Bronson Avenue", or "" when unknown


static func load_places(pack_dir: String) -> Array[Place]:
	var out: Array[Place] = []
	var path := pack_dir.path_join("services.v0.json")
	if not FileAccess.file_exists(path):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return out
	for d: Dictionary in data.get("places", []):
		var p := Place.new()
		p.id = str(d["id"])
		p.kind = str(d["kind"])
		p.name = str(d["name"]) if d["name"] != null else ""
		var a: Array = d["at"]
		p.at = Vector3(float(a[0]), float(a[1]), float(a[2]))
		p.road_node = str(d["road_node"]) if d["road_node"] != null else ""
		p.address = str(d.get("address", "")) if d.get("address") != null else ""
		out.append(p)
	return out


## Underground garages as places of kind "garage" for the map's legend and markers: the lot's
## name (or "Parking garage"), the middle of its outline, and "on <street>" for the nearest
## named road within `street_m`.
static func garage_places(lots: Array, graph: RoadGraph, street_m: float = 120.0) -> Array[Place]:
	var out: Array[Place] = []
	for lot: ParkingLotBuilder.Lot in lots:
		if lot.kind != "underground":
			continue
		var c := lot.bounds.get_center()
		var p := Place.new()
		p.id = lot.id
		p.kind = "garage"
		p.name = lot.name
		p.at = Vector3(c.x, lot.ground_y, c.y)
		p.road_node = ""
		p.address = street_near(graph, p.at, street_m)
		out.append(p)
	return out


## "on <name>" for the nearest named road within `within_m` of `at`, or "".
static func street_near(graph: RoadGraph, at: Vector3, within_m: float) -> String:
	if graph == null:
		return ""
	var best := ""
	var best_d := within_m
	for eid in graph.sorted_edge_ids():
		var e: RoadGraph.RoadEdge = graph.edges[eid]
		if e.name == "":
			continue
		for i in range(e.polyline.size() - 1):
			var a := Vector2(e.polyline[i].x, e.polyline[i].z)
			var b := Vector2(e.polyline[i + 1].x, e.polyline[i + 1].z)
			var q := Geometry2D.get_closest_point_to_segment(Vector2(at.x, at.z), a, b)
			var d := q.distance_to(Vector2(at.x, at.z))
			if d < best_d:
				best_d = d
				best = e.name
	return "on " + best if best != "" else ""


## The place of `kind` nearest `from`, or null.
static func nearest(places: Array[Place], kind: String, from: Vector3) -> Place:
	var best: Place = null
	for p in places:
		if p.kind == kind and (best == null or p.at.distance_to(from) < best.at.distance_to(from)):
			best = p
	return best


## Where to put a player arriving at `place`: its road node (on the street outside), else the
## place itself.
static func arrival(place: Place, graph: RoadGraph) -> Vector3:
	if place.road_node != "" and graph != null and graph.nodes.has(place.road_node):
		return (graph.nodes[place.road_node] as RoadGraph.RoadNode).position
	return place.at
