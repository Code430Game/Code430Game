class_name Turf
extends RefCounted
## Ground a faction holds (add-hostile-gang): a polygon from the pack's `turf.v0.json` (or a
## ring made in code for `--gang=N`), the faction that holds it and where its crew regroups.

const FILE_NAME := "turf.v0.json"

var id: String = ""
var name: String = ""
var faction: String = ""  # "" means the game's first faction
var ring: PackedVector2Array = PackedVector2Array()  # x, z in local metres
var centre: Vector2 = Vector2.ZERO
var ground_y: float = 0.0  # set by the manager once it has sampled the ground


## The pack's turfs; an empty array when it has none.
static func load_all(pack_dir: String) -> Array[Turf]:
	var out: Array[Turf] = []
	var path := pack_dir.path_join(FILE_NAME)
	if not FileAccess.file_exists(path):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not (parsed.get("turfs") is Array):
		push_warning("Turf: %s is not a turf file" % path)
		return out
	for d in parsed["turfs"]:
		if d is Dictionary and d.get("ring") is Array:
			out.append(from_dict(d))
	return out


static func from_dict(d: Dictionary) -> Turf:
	var t := Turf.new()
	t.id = str(d.get("id", ""))
	t.name = str(d.get("name", ""))
	t.faction = str(d.get("faction", ""))
	for p in d["ring"]:
		t.ring.append(Vector2(float(p[0]), float(p[1])))
	if d.get("centre") is Array and (d["centre"] as Array).size() == 2:
		t.centre = Vector2(float(d["centre"][0]), float(d["centre"][1]))
	else:
		t.centre = centroid(t.ring)
	return t


## A square turf of `half` metres around `at` (the testbed's --gang, tests).
static func square(at: Vector3, half: float, faction_id: String = "", turf_id: String = "here") -> Turf:
	var t := Turf.new()
	t.id = turf_id
	t.name = turf_id
	t.faction = faction_id
	t.ring = PackedVector2Array([Vector2(at.x - half, at.z - half), Vector2(at.x + half, at.z - half), Vector2(at.x + half, at.z + half), Vector2(at.x - half, at.z + half)])
	t.centre = Vector2(at.x, at.z)
	t.ground_y = at.y
	return t


static func centroid(points: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in points:
		c += p
	return c / maxf(points.size(), 1)


## True when `p` (x, z) lies inside the ring, grown by `margin` metres.
func contains(p: Vector3, margin: float = 0.0) -> bool:
	var q := Vector2(p.x, p.z)
	if Geometry2D.is_point_in_polygon(q, ring):
		return true
	return margin > 0.0 and distance_to_edge(q) <= margin


## Distance from `q` to the nearest edge of the ring.
func distance_to_edge(q: Vector2) -> float:
	var best := INF
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		best = minf(best, q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)))
	return best


## A point inside the ring (rejection sampling in its bounds).
func random_point(rng: RandomNumberGenerator) -> Vector2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in ring:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	for _i in range(40):
		var q := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
		if Geometry2D.is_point_in_polygon(q, ring):
			return q
	return centre


## The ring's extent as a rect (for the maps).
func bounds() -> Rect2:
	var r := Rect2(ring[0], Vector2.ZERO) if ring.size() > 0 else Rect2()
	for p in ring:
		r = r.expand(p)
	return r
