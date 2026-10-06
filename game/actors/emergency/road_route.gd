class_name RoadRoute
extends RefCounted
## Road-graph routing shared by the police and emergency vehicles: A* over the road graph
## (one-way rules ignored, as for any vehicle with lights on).

const SAME_LEVEL_M := 5.0


## Node positions along the cheapest path from `from` to `to`, ending at `to`. Empty when
## either end is off the network or they are not connected.
static func find(graph: RoadGraph, from: Vector3, to: Vector3) -> PackedVector3Array:
	var start := nearest_node(graph, from)
	var goal := nearest_node(graph, to)
	var out := PackedVector3Array()
	if start == "" or goal == "":
		return out
	var dist := {start: 0.0}
	var prev := {}
	var open: Array = [[0.0, start]]
	var goal_pos: Vector3 = graph.nodes[goal].position
	var steps := 0
	while not open.is_empty() and steps < 4000:
		steps += 1
		var best := 0
		for k in range(open.size()):
			if float(open[k][0]) < float(open[best][0]):
				best = k
		var cur: String = open[best][1]
		open.remove_at(best)
		if cur == goal:
			break
		for eid: String in graph.incident(cur):
			var e: RoadGraph.RoadEdge = graph.edges[eid]
			var nxt := e.to_node if e.from_node == cur else e.from_node
			var nd := float(dist[cur]) + e.length_m
			if nd < float(dist.get(nxt, INF)):
				dist[nxt] = nd
				prev[nxt] = cur
				open.append([nd + (graph.nodes[nxt] as RoadGraph.RoadNode).position.distance_to(goal_pos), nxt])
	if not prev.has(goal) and start != goal:
		return out
	var chain: Array[String] = [goal]
	while chain[0] != start:
		chain.push_front(prev[chain[0]])
	for nid in chain:
		out.append((graph.nodes[nid] as RoadGraph.RoadNode).position)
	out.append(to)
	return out


## The end of the road edge nearest `p` (within 80 m) that is closer to it, or "". Roads at
## about the same height come first, so someone under a deck is reached from the road below.
static func nearest_node(graph: RoadGraph, p: Vector3) -> String:
	var hit := graph.nearest_edge(p, 80.0, SAME_LEVEL_M)
	if hit.is_empty():
		hit = graph.nearest_edge(p, 80.0)
	if hit.is_empty():
		return ""
	var e: RoadGraph.RoadEdge = hit["edge"]
	var a: Vector3 = graph.nodes[e.from_node].position
	var b: Vector3 = graph.nodes[e.to_node].position
	return e.from_node if a.distance_to(p) < b.distance_to(p) else e.to_node
