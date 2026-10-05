class_name Services
extends RefCounted
## Emergency service places from services.v0.json (add-emergency-services): police stations,
## security desks, hospitals, fire stations, ambulance posts and helipads.

const ICON := {
	"police": {"letter": "P", "color": Color(0.2, 0.4, 0.95)},
	"security": {"letter": "S", "color": Color(0.4, 0.45, 0.6)},
	"hospital": {"letter": "+", "color": Color(0.9, 0.2, 0.25)},
	"fire_station": {"letter": "F", "color": Color(0.95, 0.5, 0.1)},
	"ambulance": {"letter": "A", "color": Color(0.95, 0.35, 0.4)},
	"helipad": {"letter": "H", "color": Color(0.85, 0.85, 0.9)},
}


class Place:
	extends RefCounted
	var id: String
	var kind: String
	var name: String
	var at: Vector3
	var road_node: String


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
		out.append(p)
	return out


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
