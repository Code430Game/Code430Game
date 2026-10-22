class_name DistrictSet
extends RefCounted
## Neighbouring districts played as one map (add-district-stitching 2.1-2.3).
##
## A city's districts share its pinned origin and have borders on its 256 m chunk grid, so
## their coordinates line up and each chunk belongs to exactly one of them. Each district's
## files run a little past its border (the importer reads the lat/lon box around it), so a
## chunk is always built from the district that owns it. The importer cut every road at the
## border and listed where it leaves (border.v0.json); here two districts' crossings that meet
## (within JOIN_M, headings opposite within JOIN_DEG) are joined: the two pieces of one OSM
## segment become one edge again, other roads meet at one node, and the roadblocks there go.
## A crossing with no partner keeps its roadblock.

const JOIN_M := 1.0
const JOIN_DEG := 15.0
const CHUNK_M := 256.0


## Why `manifests` (pack.json dictionaries) can't be played together, or "" when they can:
## every one a map with a border, one origin and projection, no two borders overlapping.
static func refusal(manifests: Array) -> String:
	if manifests.size() < 2:
		return ""
	var first: Dictionary = manifests[0].get("map", {})
	var rects: Array[Rect2i] = []
	for m: Dictionary in manifests:
		var map: Dictionary = m.get("map", {})
		var id := str(m.get("id", "?"))
		if str(m.get("type", "")) != "map":
			return "%s is not a map pack" % id
		if not map.has("border"):
			return "%s has no border on its city's chunk grid" % id
		if str(map.get("crs", "")) != str(first.get("crs", "")):
			return "%s uses another projection (%s)" % [id, map.get("crs", "")]
		var o: Dictionary = map.get("origin", {})
		var o0: Dictionary = first.get("origin", {})
		if not is_equal_approx(float(o.get("easting", 0.0)), float(o0.get("easting", 0.0))) or not is_equal_approx(float(o.get("northing", 0.0)), float(o0.get("northing", 0.0))):
			return "%s has another origin than %s" % [id, manifests[0].get("id", "?")]
		var r := border_rect(map["border"])
		for k in range(rects.size()):
			if rects[k].intersects(r):
				return "%s overlaps %s" % [id, manifests[k].get("id", "?")]
		rects.append(r)
	return ""


## A border ({"chunks": [x0, z0, x1, z1]}) as a rectangle of chunk coordinates.
static func border_rect(border: Dictionary) -> Rect2i:
	var c: Array = border.get("chunks", [0, 0, 0, 0])
	return Rect2i(int(c[0]), int(c[1]), int(c[2]) - int(c[0]), int(c[3]) - int(c[1]))


## The index into `rects` of the district owning chunk `coord`, or -1.
static func owner_of(coord: Vector2i, rects: Array[Rect2i]) -> int:
	for k in range(rects.size()):
		if rects[k].has_point(coord):
			return k
	return -1


static func chunk_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CHUNK_M), floori(z / CHUNK_M))


## Pairs of crossings that meet: [[part a, crossing a, part b, crossing b]], each crossing in
## at most one pair, nearest first.
static func pair_crossings(borders: Array) -> Array:
	var candidates: Array = []
	var cos_limit := cos(deg_to_rad(JOIN_DEG))
	for i in range(borders.size()):
		for j in range(i + 1, borders.size()):
			for a: Dictionary in borders[i].get("crossings", []):
				for b: Dictionary in borders[j].get("crossings", []):
					var pa := Vector2(float(a["position"][0]), float(a["position"][2]))
					var pb := Vector2(float(b["position"][0]), float(b["position"][2]))
					var d := pa.distance_to(pb)
					if d > JOIN_M:
						continue
					var ha := Vector2(float(a["heading"][0]), float(a["heading"][1]))
					var hb := Vector2(float(b["heading"][0]), float(b["heading"][1]))
					if ha.dot(hb) > -cos_limit:
						continue
					candidates.append([d, i, a, j, b])
	candidates.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var used := {}
	var out: Array = []
	for c: Array in candidates:
		var ka := "%d:%s" % [c[1], c[2]["node"]]
		var kb := "%d:%s" % [c[3], c[4]["node"]]
		if used.has(ka) or used.has(kb):
			continue
		used[ka] = true
		used[kb] = true
		out.append([c[1], c[2], c[3], c[4]])
	return out


## The road graphs of the districts (road_graph.v0.json dictionaries) as one, joined at their
## paired crossings. `rects` are the districts' borders (chunk coordinates). Returns {"graph":
## the merged dictionary, "joined": [{"at": Vector3, "edges": [edge ids]}] (for the roadblocks
## to drop), "pairs": how many crossings joined}.
static func merge_graphs(graphs: Array, borders: Array, rects: Array[Rect2i]) -> Dictionary:
	var nodes := {}  # id -> node dict
	var edges := {}  # id -> edge dict
	var rename: Array = []  # per part: old node id -> new id
	var peds: Array = []
	var bus_stops: Array = []
	var gores: Array = []
	for k in range(graphs.size()):
		var g: Dictionary = graphs[k]
		var map := {}
		for n: Dictionary in g.get("nodes", []):
			var nid := str(n["id"])
			var new_id := nid
			if nodes.has(nid):
				new_id = "%s.d%d" % [nid, k]
			map[nid] = new_id
			var copy := n.duplicate(true)
			copy["id"] = new_id
			nodes[new_id] = copy
		rename.append(map)
		for e: Dictionary in g.get("edges", []):
			var copy := e.duplicate(true)
			copy["from"] = map.get(str(e["from"]), e["from"])
			copy["to"] = map.get(str(e["to"]), e["to"])
			var eid := str(e["id"])
			copy["_part"] = k
			if edges.has(eid):
				eid = "%s.d%d" % [eid, k]
			copy["id"] = eid
			edges[eid] = copy
		for p: Dictionary in g.get("pedestrian_ways", []):
			var c := p.duplicate(true)
			c["_part"] = k
			peds.append(c)
		bus_stops.append_array(g.get("bus_stops", []))
		for s: Variant in g.get("gores", []):
			if s is Dictionary and _owned_point(s, k, rects):
				gores.append(s)
	var joined: Array = []
	var pairs := pair_crossings(borders)
	for pr: Array in pairs:
		var ia: int = pr[0]
		var ib: int = pr[2]
		var na: String = rename[ia].get(str(pr[1]["node"]), str(pr[1]["node"]))
		var nb: String = rename[ib].get(str(pr[3]["node"]), str(pr[3]["node"]))
		var ea := _edge_at(edges, na, ia)
		var eb := _edge_at(edges, nb, ib)
		if ea.is_empty() or eb.is_empty():
			continue
		var at := Vector3(float(pr[1]["position"][0]), float(pr[1]["position"][1]), float(pr[1]["position"][2]))
		joined.append({"at": at, "edges": [str(pr[1]["edge"]), str(pr[3]["edge"])]})
		var same_segment := str(pr[1]["edge"]).get_slice("b", 0) == str(pr[3]["edge"]).get_slice("b", 0) and str(pr[1]["edge"]).begins_with("w")
		if same_segment and _concat(edges, ea, eb, na, nb):
			nodes.erase(na)
			nodes.erase(nb)
			continue
		# Different segments meet here: one node, the two roads through it.
		for e: Dictionary in edges.values():
			if e["from"] == nb:
				e["from"] = na
			if e["to"] == nb:
				e["to"] = na
		nodes.erase(nb)
		(nodes[na] as Dictionary)["junction_type"] = "pass_through"
	var merged_peds := _join_pedestrian(peds)
	var out_edges: Array = []
	for eid in edges:
		var e: Dictionary = edges[eid]
		e.erase("_part")
		out_edges.append(e)
	out_edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	var out_nodes: Array = nodes.values()
	out_nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	var meta: Dictionary = (graphs[0].get("meta", {}) as Dictionary).duplicate(true)
	return {
		"graph": {"meta": meta, "nodes": out_nodes, "edges": out_edges, "pedestrian_ways": merged_peds, "bus_stops": bus_stops, "gores": gores},
		"joined": joined,
		"pairs": joined.size(),
	}


## The edge ending at node `nid` (node ids are unique once merged; a border node has one).
static func _edge_at(edges: Dictionary, nid: String, _part: int) -> Dictionary:
	for e: Dictionary in edges.values():
		if e["from"] == nid or e["to"] == nid:
			return e
	return {}


## Joins two pieces of one segment, `ea` ending at border node `na` and `eb` starting at `nb`
## (or the other way round), into one edge under the segment's id. False when they don't run
## the same way.
static func _concat(edges: Dictionary, ea: Dictionary, eb: Dictionary, na: String, nb: String) -> bool:
	var first: Dictionary
	var second: Dictionary
	if ea["to"] == na and eb["from"] == nb:
		first = ea
		second = eb
	elif eb["to"] == nb and ea["from"] == na:
		first = eb
		second = ea
	else:
		return false
	var pl: Array = (first["polyline"] as Array).duplicate()
	var rest: Array = second["polyline"]
	for i in range(1, rest.size()):
		pl.append(rest[i])
	var joined: Dictionary = first.duplicate(true)
	joined["polyline"] = pl
	joined["to"] = second["to"]
	joined["control_to"] = second.get("control_to", "none")
	joined["length_m"] = float(first.get("length_m", 0.0)) + float(second.get("length_m", 0.0))
	joined["id"] = str(ea["id"]).get_slice(".d", 0).get_slice("b", 0)
	edges.erase(str(ea["id"]))
	edges.erase(str(eb["id"]))
	edges[str(joined["id"])] = joined
	return true


## Pedestrian ways from every district: two pieces of one way that meet at the border (same id
## up to the piece suffix, an end within 5 cm of the other's start) become one again.
static func _join_pedestrian(peds: Array) -> Array:
	var out: Array = []
	var by_base := {}
	for p: Dictionary in peds:
		var base := str(p["id"]).get_slice("b", 0)
		if not by_base.has(base):
			by_base[base] = []
		(by_base[base] as Array).append(p)
	var bases: Array = by_base.keys()
	bases.sort()
	for base: String in bases:
		var group: Array = by_base[base]
		var merged := true
		while merged and group.size() > 1:
			merged = false
			for i in range(group.size()):
				for j in range(group.size()):
					if i == j or int(group[i]["_part"]) == int(group[j]["_part"]):
						continue
					var a: Array = group[i]["polyline"]
					var b: Array = group[j]["polyline"]
					if _close(a[a.size() - 1], b[0]):
						var joined: Dictionary = (group[i] as Dictionary).duplicate(true)
						var pl: Array = a.duplicate()
						for q in range(1, b.size()):
							pl.append(b[q])
						joined["polyline"] = pl
						joined["top"] = []
						joined["_part"] = -1  # joins no further pieces of its own district
						group.remove_at(maxi(i, j))
						group.remove_at(mini(i, j))
						group.append(joined)
						merged = true
						break
				if merged:
					break
		var n := 0
		for p: Dictionary in group:
			p.erase("_part")
			if group.size() > 1:
				n += 1
				p["id"] = "%sb%d" % [base, n]
			else:
				p["id"] = base if str(p["id"]).get_slice("b", 0) == base else p["id"]
			out.append(p)
	return out


static func _close(a: Array, b: Array) -> bool:
	return Vector2(float(a[0]), float(a[2])).distance_to(Vector2(float(b[0]), float(b[2]))) < 0.05


static func _owned_point(strip: Dictionary, part: int, rects: Array[Rect2i]) -> bool:
	var pts: Array = strip.get("points", strip.get("polyline", []))
	if pts.is_empty():
		return part == 0
	var p: Array = pts[0]
	return owner_of(chunk_of(float(p[0]), float(p[p.size() - 1])), rects) == part
