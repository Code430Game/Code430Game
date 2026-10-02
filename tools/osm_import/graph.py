"""Build the road graph: nodes at junctions and way ends, edges with polylines.

Approach: count how many drivable ways use each OSM node. A node becomes a
graph node if it is used by two or more ways, appears twice in one way (loop),
or is a way endpoint. Each way is split at those nodes into edges. Attributes
are read from tags, missing ones are filled from the class defaults table and
recorded in `defaulted_fields`.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from osm_import import tags as T
from osm_import.config import ImportConfig
from osm_import.osm_data import OsmData, OsmWay
from osm_import.projection import Projector

Point = tuple[float, float, float]


@dataclass
class RoadNode:
    id: str
    position: Point
    osm_node_ids: list[int]
    tags: dict[str, str] = field(default_factory=dict)
    junction_type: str = "junction"
    ground_y: float = 0.0

    @property
    def control(self) -> str:
        """Traffic control at this node from its OSM tags: signals, stop, give_way or none."""
        hw = self.tags.get("highway", "")
        if hw == "traffic_signals":
            return "signals"
        if hw == "stop":
            return "stop"
        if hw == "give_way":
            return "give_way"
        return "none"


@dataclass
class RoadEdge:
    id: str
    from_node: str
    to_node: str
    polyline: list[Point]
    road_class: str
    lanes_forward: int
    lanes_backward: int
    oneway: bool
    speed_kph: int
    width_m: float
    layer: int
    bridge: bool
    tunnel: bool
    name: str | None
    osm_way_id: int
    defaulted_fields: list[str]
    access: str | None = None
    length_m: float = 0.0
    control_to: str = "none"  # stop | signals | none for traffic arriving at to_node
    control_from: str = "none"  # the same for traffic arriving at from_node
    bus: str = ""  # "only": the whole edge is for buses; "lane": one forward lane is (bus_lane)
    bus_lane: int = -1  # forward lane index reserved for buses (0 = nearest the centre line)

    @property
    def is_link(self) -> bool:
        return self.road_class.endswith("_link")


@dataclass
class PedestrianWay:
    id: str
    polyline: list[Point]
    road_class: str
    osm_way_id: int
    name: str | None
    kind: str = (
        "footway"  # sidewalk | crossing | footway | path | steps | cycleway | pedestrian | track
    )
    width_m: float = 1.5
    covered: bool = False  # tunnel=* or covered=yes: passes under something, not drawn
    profile: str = ""  # "tunnel" (dug passage) | "trench" (ramps down to one) | ""
    top: list[float] = field(default_factory=list)  # tunnel ceiling height per point
    shoulder_m: float | None = None  # terrain blends back over this beyond the margin
    margin_m: float | None = (
        None  # terrain follows the way within half width + this (None: road margin)
    )


@dataclass
class RoadGraph:
    nodes: dict[str, RoadNode]
    edges: dict[str, RoadEdge]
    pedestrian: list[PedestrianWay]
    notes: dict = field(default_factory=dict)
    bus_stops: list[dict] = field(default_factory=list)  # {"id", "position", "edge"}

    def incident(self) -> dict[str, list[str]]:
        """Node id -> ids of edges touching it."""
        out: dict[str, list[str]] = {nid: [] for nid in self.nodes}
        for eid, e in self.edges.items():
            out[e.from_node].append(eid)
            if e.to_node != e.from_node:
                out[e.to_node].append(eid)
        return out


def polyline_length(points: list[Point]) -> float:
    return sum(math.dist(points[i][::2], points[i + 1][::2]) for i in range(len(points) - 1))


def _lanes(
    way: OsmWay, road_class: str, oneway: bool, cfg: ImportConfig, defaulted: list[str]
) -> tuple[int, int]:
    tags = way.tags
    total = T.parse_int(tags.get("lanes"))
    fwd = T.parse_int(tags.get("lanes:forward"))
    bwd = T.parse_int(tags.get("lanes:backward"))
    d = cfg.for_class(road_class)
    if oneway:
        if total is None:
            total = d.lanes_oneway
            defaulted.append("lanes")
        return max(total, 1), 0
    if fwd is not None and bwd is not None:
        return max(fwd, 1), max(bwd, 1)
    if total is None:
        total = d.lanes
        defaulted.append("lanes")
    total = max(total, 2) if total >= 2 else 1
    if fwd is not None:
        return max(fwd, 1), max(total - fwd, 1)
    if bwd is not None:
        return max(total - bwd, 1), max(bwd, 1)
    half = total // 2
    return max(total - half, 1), max(half, 1)


def _edge_from_segment(
    way: OsmWay,
    seg_index: int,
    node_ids: list[int],
    data: OsmData,
    proj: Projector,
    cfg: ImportConfig,
) -> RoadEdge:
    tags = way.tags
    road_class = tags["highway"]
    defaulted: list[str] = []
    ow = T.parse_oneway(tags.get("oneway"))
    if ow == "unset":
        if tags.get("junction") in ("roundabout", "circular"):
            oneway = True
        elif road_class in cfg.implied_oneway_classes:
            oneway = True
            defaulted.append("oneway")
        else:
            oneway = False
    else:
        oneway = ow != "no"
    points_ids = list(node_ids)
    if ow == "reverse":
        points_ids.reverse()
    polyline: list[Point] = []
    for nid in points_ids:
        n = data.nodes[nid]
        x, z = proj.to_local(n.lat, n.lon)
        polyline.append((x, 0.0, z))
    # Stop signs and signals tagged on the approach (interior vertices) apply to one end:
    # direction=forward follows the way, backward opposes it; otherwise the nearer end.
    control_to, control_from = "none", "none"
    for i, nid in enumerate(points_ids[1:-1], start=1):
        ntags = data.nodes[nid].tags
        kind = {"stop": "stop", "traffic_signals": "signals"}.get(ntags.get("highway", ""))
        if kind is None:
            continue
        direction = ntags.get("direction", "")
        if ow == "reverse" and direction in ("forward", "backward"):
            direction = "backward" if direction == "forward" else "forward"
        if direction == "forward":
            ends = ["to"]
        elif direction == "backward":
            ends = ["from"]
        elif direction == "both":
            ends = ["to", "from"]
        else:
            ends = ["to" if i >= len(points_ids) / 2 else "from"]
        for end in ends:
            current = control_to if end == "to" else control_from
            if current == "signals":
                continue  # signals outrank a stop
            if end == "to":
                control_to = kind
            else:
                control_from = kind
    lanes_f, lanes_b = _lanes(way, road_class, oneway, cfg, defaulted)
    bus, bus_lane = _bus_lanes(tags, lanes_f, ow == "reverse")
    width = T.parse_width_m(tags.get("width"))
    if width is None:
        width = (lanes_f + lanes_b) * cfg.lane_width_m
        defaulted.append("width")
    speed = T.parse_maxspeed_kph(tags.get("maxspeed"))
    if speed is None:
        speed = cfg.for_class(road_class).speed_kph
        defaulted.append("speed_kph")
    return RoadEdge(
        id=f"w{way.id}.{seg_index}",
        from_node=f"n{points_ids[0]}",
        to_node=f"n{points_ids[-1]}",
        polyline=polyline,
        road_class=road_class,
        lanes_forward=lanes_f,
        lanes_backward=lanes_b,
        oneway=oneway,
        speed_kph=speed,
        width_m=width,
        layer=T.parse_layer(tags.get("layer")),
        bridge=T.is_truthy(tags.get("bridge")),
        tunnel=T.is_truthy(tags.get("tunnel")) and tags.get("tunnel") != "building_passage",
        name=tags.get("name"),
        osm_way_id=way.id,
        defaulted_fields=defaulted,
        access=tags.get("motor_vehicle", tags.get("access")),
        length_m=polyline_length(polyline),
        control_to=control_to,
        control_from=control_from,
        bus=bus,
        bus_lane=bus_lane,
    )


def _bus_lanes(tags: dict, lanes_f: int, reversed_way: bool) -> tuple[str, int]:
    """("only", -1) for a bus-only way, ("lane", index) when one forward lane is reserved."""
    access = tags.get("motor_vehicle", tags.get("access"))
    bus_values = ("yes", "designated")
    if tags.get("highway") == "busway" or (
        access in ("no", "private")
        and (tags.get("bus") in bus_values or tags.get("psv") in bus_values)
    ):
        return "only", -1
    direction = "backward" if reversed_way else "forward"
    for key in (f"bus:lanes:{direction}", f"psv:lanes:{direction}", "bus:lanes", "psv:lanes"):
        if key in tags and (
            key.count(":") == 1
            and tags.get("oneway") not in ("yes", "-1")
            and direction == "backward"
        ):
            continue
        if key in tags:
            lanes = tags[key].split("|")
            for i, value in enumerate(lanes):
                if value == "designated":
                    return "lane", min(i, max(lanes_f - 1, 0))
            return "", -1
    busway = tags.get("busway:right", tags.get("busway"))
    if busway == "lane" or tags.get("lanes:bus") or tags.get("lanes:psv"):
        return "lane", max(lanes_f - 1, 0)
    return "", -1


def build_graph(
    data: OsmData,
    drivable: list[OsmWay],
    pedestrian: list[OsmWay],
    proj: Projector,
    cfg: ImportConfig,
) -> RoadGraph:
    """Build nodes and edges from filtered ways."""
    usage: dict[int, int] = {}
    for way in drivable:
        for nid in way.nodes:
            if nid in data.nodes:
                usage[nid] = usage.get(nid, 0) + 1
    graph_node_ids: set[int] = set()
    for way in drivable:
        known = [n for n in way.nodes if n in data.nodes]
        graph_node_ids.add(known[0])
        graph_node_ids.add(known[-1])
        for nid in known:
            if usage[nid] >= 2:
                graph_node_ids.add(nid)

    nodes: dict[str, RoadNode] = {}
    for nid in sorted(graph_node_ids):
        n = data.nodes[nid]
        x, z = proj.to_local(n.lat, n.lon)
        nodes[f"n{nid}"] = RoadNode(f"n{nid}", (x, 0.0, z), [nid], dict(n.tags))

    edges: dict[str, RoadEdge] = {}
    edge_of_node: dict[int, str] = {}  # OSM node -> an edge passing through it (bus stops)
    for way in sorted(drivable, key=lambda w: w.id):
        known = [n for n in way.nodes if n in data.nodes]
        seg: list[int] = [known[0]]
        seg_index = 0
        for nid in known[1:]:
            seg.append(nid)
            if nid in graph_node_ids:
                if len(seg) >= 2 and (seg[0] != seg[-1] or len(seg) > 2):
                    edge = _edge_from_segment(way, seg_index, seg, data, proj, cfg)
                    edges[edge.id] = edge
                    for sn in seg:
                        edge_of_node.setdefault(sn, edge.id)
                    seg_index += 1
                seg = [nid]
    bus_stops: list[dict] = []
    for nid, eid in sorted(edge_of_node.items()):
        t = data.nodes[nid].tags
        if t.get("highway") == "bus_stop" or (
            t.get("public_transport") == "stop_position" and t.get("bus") == "yes"
        ):
            x, z = proj.to_local(data.nodes[nid].lat, data.nodes[nid].lon)
            bus_stops.append({"id": f"s{nid}", "position": (x, 0.0, z), "edge": eid})

    peds: list[PedestrianWay] = []
    for way in sorted(pedestrian, key=lambda w: w.id):
        known = [n for n in way.nodes if n in data.nodes]
        pl: list[Point] = []
        for nid in known:
            n = data.nodes[nid]
            x, z = proj.to_local(n.lat, n.lon)
            pl.append((x, 0.0, z))
        kind = way.tags["highway"]
        if kind == "footway" and way.tags.get("footway") in ("sidewalk", "crossing"):
            kind = way.tags["footway"]
        width = T.parse_width_m(way.tags.get("width"))
        if width is None:
            width = float(cfg.pedestrian.get("default_width_m", {}).get(kind, 1.5))
        covered = (
            T.is_truthy(way.tags.get("tunnel")) and way.tags.get("tunnel") != "building_passage"
        ) or T.is_truthy(way.tags.get("covered"))
        peds.append(
            PedestrianWay(
                f"p{way.id}",
                pl,
                way.tags["highway"],
                way.id,
                way.tags.get("name"),
                kind,
                width,
                covered,
            )
        )

    graph = RoadGraph(nodes, edges, peds, bus_stops=bus_stops)
    _classify_nodes(graph)
    return graph


def _classify_nodes(graph: RoadGraph) -> None:
    inc = graph.incident()
    for nid, node in graph.nodes.items():
        degree = len(inc[nid])
        if degree == 1:
            node.junction_type = "dead_end"
        elif degree == 2:
            node.junction_type = "pass_through"
        else:
            node.junction_type = "junction"
