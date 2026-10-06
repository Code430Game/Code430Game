"""Road network validation: components, dead ends, ramps, one-way traps.

Approach: build an undirected multigraph for connectivity and a directed graph
(two-way edges in both directions) for strongly connected components. Nodes
within the bbox edge margin are treated as "touches the bbox edge" so artifacts
of cutting the extract are reported separately from real problems.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field

import networkx as nx

from osm_import.config import ImportConfig
from osm_import.graph import RoadEdge, RoadGraph

SAMPLE_LIMIT = 8


@dataclass
class ComponentEntry:
    nodes: int
    edges: int
    touches_bbox_edge: bool
    classes: dict[str, int]
    sample_way_ids: list[int]
    sample_names: list[str]
    likely_cause: str


@dataclass
class DeadEndEntry:
    node_id: str
    osm_node_id: int
    edge_id: str
    osm_way_id: int
    road_class: str
    name: str | None
    category: str


@dataclass
class RampEntry:
    edge_ids: list[str]
    osm_way_ids: list[int]
    road_class: str
    connected_classes: list[str]
    problem: str


@dataclass
class TrapEntry:
    kind: str
    nodes: int
    sample_way_ids: list[int]
    sample_names: list[str]
    classes: dict[str, int]


@dataclass
class ValidationReport:
    summary: dict = field(default_factory=dict)
    components: list[ComponentEntry] = field(default_factory=list)
    dead_ends: dict[str, list[DeadEndEntry]] = field(default_factory=dict)
    ramps: list[RampEntry] = field(default_factory=list)
    traps: list[TrapEntry] = field(default_factory=list)
    elevation: dict | None = None
    junction_clusters: list[dict] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "summary": self.summary,
            "elevation": self.elevation,
            "components": [asdict(c) for c in self.components],
            "dead_ends": {k: [asdict(d) for d in v] for k, v in self.dead_ends.items()},
            "ramps": [asdict(r) for r in self.ramps],
            "one_way_traps": [asdict(t) for t in self.traps],
            "junction_clusters": self.junction_clusters,
        }


def _touches_edge(
    graph: RoadGraph, bounds: tuple[float, float, float, float], margin: float
) -> set[str]:
    min_x, min_z, max_x, max_z = bounds
    out: set[str] = set()
    for nid, n in graph.nodes.items():
        x, _, z = n.position
        if x - min_x < margin or max_x - x < margin or z - min_z < margin or max_z - z < margin:
            out.add(nid)
    return out


def _undirected(graph: RoadGraph) -> nx.MultiGraph:
    g = nx.MultiGraph()
    g.add_nodes_from(graph.nodes)
    for eid, e in graph.edges.items():
        g.add_edge(e.from_node, e.to_node, key=eid)
    return g


def _directed(graph: RoadGraph) -> nx.DiGraph:
    g = nx.DiGraph()
    g.add_nodes_from(graph.nodes)
    for e in graph.edges.values():
        g.add_edge(e.from_node, e.to_node)
        if not e.oneway:
            g.add_edge(e.to_node, e.from_node)
    return g


def _class_counts(edges: list[RoadEdge]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for e in edges:
        counts[e.road_class] = counts.get(e.road_class, 0) + 1
    return dict(sorted(counts.items()))


def _samples(edges: list[RoadEdge]) -> tuple[list[int], list[str]]:
    ways = sorted({e.osm_way_id for e in edges})[:SAMPLE_LIMIT]
    names = sorted({e.name for e in edges if e.name})[:SAMPLE_LIMIT]
    return ways, names


def validate(
    graph: RoadGraph,
    cfg: ImportConfig,
    bounds: tuple[float, float, float, float],
    dropped_by_node: dict[int, list[tuple[int, str]]] | None = None,
) -> ValidationReport:
    """Run all checks and return the report."""
    report = ValidationReport()
    edge_nodes = _touches_edge(graph, bounds, cfg.bbox_edge_margin_m)
    inc = graph.incident()
    ug = _undirected(graph)
    dropped_by_node = dropped_by_node or {}

    # Components
    comps = sorted(nx.connected_components(ug), key=lambda c: (-len(c), min(c)))
    for i, comp in enumerate(comps):
        eids = {k for a, b, k in ug.edges(comp, keys=True)}
        edges = [graph.edges[k] for k in sorted(eids)]
        ways, names = _samples(edges)
        touches = any(n in edge_nodes for n in comp)
        cause = "main network" if i == 0 else ("cut by bbox edge" if touches else "isolated island")
        if i > 0 and not touches:
            reasons = sorted(
                {
                    reason
                    for n in comp
                    for osm_id in graph.nodes[n].osm_node_ids
                    for _, reason in dropped_by_node.get(osm_id, [])
                }
            )
            if reasons:
                cause = "connector filtered out (" + ", ".join(reasons) + ")"
        report.components.append(
            ComponentEntry(len(comp), len(edges), touches, _class_counts(edges), ways, names, cause)
        )

    # Dead ends
    categories = {
        "bbox_edge": [],
        "declared_noexit": [],
        "likely_real": [],
        "suspicious": [],
        "parking": [],
    }
    for nid in sorted(graph.nodes):
        if len(inc[nid]) != 1:
            continue
        e = graph.edges[inc[nid][0]]
        node = graph.nodes[nid]
        if e.road_class == "parking":
            cat = "parking"  # aisles and driveways end in lots: counted apart from real streets
        elif nid in edge_nodes:
            cat = "bbox_edge"
        elif node.tags.get("noexit") == "yes":
            cat = "declared_noexit"
        elif e.road_class in cfg.likely_real_dead_end_classes and not e.is_link:
            cat = "likely_real"
        else:
            cat = "suspicious"
        categories[cat].append(
            DeadEndEntry(nid, node.osm_node_ids[0], e.id, e.osm_way_id, e.road_class, e.name, cat)
        )
    report.dead_ends = categories

    # Ramps: chains of *_link edges
    link_graph = nx.MultiGraph()
    for eid, e in graph.edges.items():
        if e.is_link:
            link_graph.add_edge(e.from_node, e.to_node, key=eid)
    for chain in sorted(nx.connected_components(link_graph), key=lambda c: min(c)):
        chain_eids = sorted({k for a, b, k in link_graph.edges(chain, keys=True)})
        chain_edges = [graph.edges[k] for k in chain_eids]
        touched: dict[str, int] = {}
        attach_nodes: set[str] = set()
        for nid in chain:
            for eid in inc[nid]:
                e = graph.edges[eid]
                if not e.is_link:
                    touched[e.road_class] = touched.get(e.road_class, 0) + 1
                    attach_nodes.add(nid)
        if any(n in edge_nodes for n in chain):
            continue
        classes = sorted(touched)
        link_class = chain_edges[0].road_class
        parent = link_class.removesuffix("_link")
        problem = ""
        if len(attach_nodes) < 2:
            problem = "connects at fewer than two points (leads nowhere)"
        elif link_class in ("motorway_link", "trunk_link") and not (
            {"motorway", "trunk"} & set(classes)
        ):
            problem = f"{link_class} does not touch a motorway or trunk"
        elif parent not in classes and not ({c for c in classes} & cfg.major_classes):
            problem = f"{link_class} touches no major road ({', '.join(classes) or 'nothing'})"
        if problem:
            report.ramps.append(
                RampEntry(
                    chain_eids,
                    sorted({e.osm_way_id for e in chain_edges}),
                    link_class,
                    classes,
                    problem,
                )
            )

    # One-way traps via SCCs
    dg = _directed(graph)
    sccs = sorted(nx.strongly_connected_components(dg), key=lambda c: (-len(c), min(c)))
    main_size = len(sccs[0]) if sccs else 0
    oneway_dead_ends = 0
    for scc in sccs[1:]:
        if any(n in edge_nodes for n in scc):
            continue
        if len(scc) == 1 and len(inc[next(iter(scc))]) == 1:
            oneway_dead_ends += 1  # the dead end of a one-way stub; already listed under dead ends
            continue
        has_in = any(dg.has_edge(u, v) for v in scc for u in dg.predecessors(v) if u not in scc)
        has_out = any(dg.has_edge(u, v) for u in scc for v in dg.successors(u) if v not in scc)
        if has_in and not has_out:
            kind = "trap_can_enter_not_leave"
        elif has_out and not has_in:
            kind = "unreachable_can_leave_not_enter"
        elif not has_in and not has_out:
            continue  # isolated component, already listed under components
        else:
            continue  # both in and out exist: not a trap
        edges = [e for e in graph.edges.values() if e.from_node in scc or e.to_node in scc]
        ways, names = _samples(edges)
        report.traps.append(TrapEntry(kind, len(scc), ways, names, _class_counts(edges)))

    report.summary = {
        "nodes": len(graph.nodes),
        "edges": len(graph.edges),
        "total_length_km": round(sum(e.length_m for e in graph.edges.values()) / 1000.0, 3),
        "classes": _class_counts(list(graph.edges.values())),
        "components": len(report.components),
        "largest_component_nodes": report.components[0].nodes if report.components else 0,
        "largest_scc_nodes": main_size,
        "dead_ends": {k: len(v) for k, v in report.dead_ends.items()},
        "ramp_problems": len(report.ramps),
        "one_way_traps": len(report.traps),
        "oneway_dead_ends": oneway_dead_ends,
        "defaulted_fields": _defaulted_counts(graph),
    }
    return report


def _defaulted_counts(graph: RoadGraph) -> dict[str, int]:
    counts: dict[str, int] = {}
    for e in graph.edges.values():
        for f in e.defaulted_fields:
            counts[f] = counts.get(f, 0) + 1
    return dict(sorted(counts.items()))


def render_markdown(report: ValidationReport, title: str) -> str:
    """Human-readable version of the report."""
    s = report.summary
    lines = [f"# Road network validation: {title}", ""]
    lines += [
        f"- Nodes: {s['nodes']}, edges: {s['edges']}, total length: {s['total_length_km']} km",
        f"- Connected components: {s['components']} (largest has {s['largest_component_nodes']} nodes)",
        f"- Largest strongly connected component: {s['largest_scc_nodes']} nodes",
        "- Dead ends: " + ", ".join(f"{k} {v}" for k, v in s["dead_ends"].items()),
        (
            f"- Ramp problems: {s['ramp_problems']}; one-way traps: {s['one_way_traps']} "
            f"(plus {s['oneway_dead_ends']} one-way stubs that simply dead-end, counted under dead ends)"
        ),
        "- Defaulted fields: "
        + (", ".join(f"{k} {v}" for k, v in s["defaulted_fields"].items()) or "none"),
        "",
        "## Edge classes",
        "",
        "| Class | Edges |",
        "|---|---|",
    ]
    lines += [f"| {k} | {v} |" for k, v in s["classes"].items()]

    lines += ["", "## Connected components", ""]
    if len(report.components) <= 1:
        lines.append("The network is one connected component.")
    else:
        lines += [
            "| Nodes | Edges | Likely cause | Classes | Sample names | Sample way ids |",
            "|---|---|---|---|---|---|",
        ]
        for c in report.components:
            classes = ", ".join(f"{k} {v}" for k, v in c.classes.items())
            lines.append(
                f"| {c.nodes} | {c.edges} | {c.likely_cause} | {classes} | "
                f"{', '.join(c.sample_names) or '-'} | {', '.join(str(w) for w in c.sample_way_ids)} |"
            )

    lines += ["", "## Dead ends", ""]
    for cat, entries in report.dead_ends.items():
        lines.append(f"### {cat} ({len(entries)})")
        lines.append("")
        if cat in ("bbox_edge", "likely_real"):
            lines.append(f"{len(entries)} entries; listed in the JSON report only.")
        elif not entries:
            lines.append("none")
        else:
            lines += ["| Node | Way | Class | Name |", "|---|---|---|---|"]
            lines += [
                f"| {d.osm_node_id} | {d.osm_way_id} | {d.road_class} | {d.name or '-'} |"
                for d in entries
            ]
        lines.append("")

    lines += ["## Ramp connectivity", ""]
    if not report.ramps:
        lines.append("Every *_link chain connects a major road at two or more points.")
    else:
        lines += ["| Class | Problem | Touches | Way ids |", "|---|---|---|---|"]
        lines += [
            f"| {r.road_class} | {r.problem} | {', '.join(r.connected_classes) or '-'} | {', '.join(str(w) for w in r.osm_way_ids)} |"
            for r in report.ramps
        ]

    lines += ["", "## One-way traps", ""]
    if not report.traps:
        lines.append(
            "No traps: every node inside the bbox can reach and be reached from the main network."
        )
    else:
        lines += [
            "| Kind | Nodes | Classes | Sample names | Sample way ids |",
            "|---|---|---|---|---|",
        ]
        for t in report.traps:
            classes = ", ".join(f"{k} {v}" for k, v in t.classes.items())
            lines.append(
                f"| {t.kind} | {t.nodes} | {classes} | {', '.join(t.sample_names) or '-'} | {', '.join(str(w) for w in t.sample_way_ids)} |"
            )
    lines += ["", "## Junction clusters", ""]
    if not report.junction_clusters:
        lines.append("No junction nodes were merged.")
    else:
        lines.append(
            f"- {len(report.junction_clusters)} merged junctions; each road keeps its own line "
            "through them. Largest arm offsets from the centroid:"
        )
        lines += [
            f"  - {c['node_id']} (OSM {', '.join(str(i) for i in c['osm_node_ids'])}): "
            f"{c['max_arm_offset_m']} m"
            for c in report.junction_clusters[:10]
        ]
    if "water" in s:
        w = s["water"]
        lines += [
            "",
            "## Water",
            "",
            f"- Polygons written: {w['polygons']}; relations or ways skipped: {len(w['skipped'])}",
        ]
        for sk in w["skipped"]:
            lines.append(f"  - {sk['id']}: {sk['reason']}")
    if "barriers" in s:
        lines += [
            "",
            "## Barriers",
            "",
            "- " + (", ".join(f"{k} {v}" for k, v in s["barriers"].items()) or "none"),
        ]
    if "buildings" in s:
        b = s["buildings"]
        lines += [
            "",
            "## Buildings",
            "",
            f"- Footprints written: {b['footprints']}; height from tag/levels/default: {b['height_sources']}",
        ]
        for sk in b["skipped"]:
            lines.append(f"  - {sk['id']}: {sk['reason']}")
    lines += ["", "## Elevation", ""]
    if report.elevation is None:
        lines.append("No elevation applied: every y is 0.")
    else:
        el = report.elevation
        lines += [
            f"- Road height range: {el['min_y']} m to {el['max_y']} m",
            f"- Bridge/tunnel (fixed) vertices: {el['fixed_vertices']}; approach vertices raised or lowered to meet them: {el['vertices_clamped']}",
            f"- Conflicting bridge constraints: {el['bound_conflicts']}; bridge chains without a ground anchor: {el['anchorless_spans']}",
            f"- Vertices under a bridge footprint refilled from neighbours (DTM keeps decks): {el['contaminated_vertices']}",
            f"- Worst residual grade: {el['max_residual_grade']}; edges still over their class limit: {len(el['edges_over_grade'])}",
        ]
        if el["edges_over_grade"]:
            lines.append("  " + ", ".join(el["edges_over_grade"][:20]))
        lines.append(
            f"- Shared heights: {el.get('shared_deck_vertices', 0)} deck and"
            f" {el.get('shared_ground_vertices', 0)} ground vertices; largest step before"
            f" {el.get('max_shared_step', 0)} m, left after {el.get('shared_step_left', 0)} m"
            + ("; ran out of rounds" if el.get("share_rounds_exhausted") else "")
        )
        raised = el.get("clearance_raised", [])
        lines.append(f"- Span chains raised again for clearance after sharing: {len(raised)}")
        if raised:
            lines.append("  " + ", ".join(raised[:20]))
        shortfalls = el.get("clearance_shortfalls", [])
        lines.append(f"- Decks short of their clearance over a road: {len(shortfalls)}")
        for sf in shortfalls[:30]:
            lines.append(
                f"  - {sf['deck']} over {sf['road']} at ({sf['x']}, {sf['z']}):"
                f" {sf['clearance_m']} m, {sf['missing_m']} m short"
            )
        inferred = el.get("inferred_bridges", [])
        lines.append(f"- Bridges inferred from untagged crossings: {len(inferred)}")
        for ib in inferred[:30]:
            lines.append(
                f"  - {ib['edge_id']} ({ib['over_class']}) over {ib['under_edge_id']} ({ib['under_class']}), by {ib['reason']}"
            )
    lines.append("")
    return "\n".join(lines)
