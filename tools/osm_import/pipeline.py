"""Run the import stages end to end."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path

from osm_import.cluster import ClusterStats, cluster_junctions
from osm_import.config import DEFAULT_CONFIG_PATH, ImportConfig, load_config
from osm_import.crossings import infer_bridges
from osm_import.elevation import (
    ElevationSource,
    ElevationStats,
    apply_elevation,
    apply_pedestrian_elevation,
)
from osm_import.export import dump_json, graph_to_dict
from osm_import.filter import FilterResult, filter_ways
from osm_import.forks import shape_forks
from osm_import.graph import RoadGraph, build_graph
from osm_import.osm_data import BBox, OsmData
from osm_import.projection import Projector
from osm_import.validation import ValidationReport, render_markdown, validate

log = logging.getLogger(__name__)


@dataclass
class PipelineResult:
    graph: RoadGraph
    report: ValidationReport
    filter_result: FilterResult
    cluster_stats: ClusterStats
    graph_dict: dict
    elevation_stats: ElevationStats | None = None


def run_pipeline(
    data: OsmData,
    bbox: BBox,
    cfg: ImportConfig,
    config_name: str = "road_classes.json",
    elevation: ElevationSource | None = None,
) -> PipelineResult:
    """Filter, project, build, cluster, elevate, validate. Does not touch disk."""
    fr = filter_ways(data, cfg)
    log.info(
        "filter: %d drivable, %d pedestrian, dropped %s",
        len(fr.drivable),
        len(fr.pedestrian),
        fr.dropped,
    )
    proj = Projector.for_bbox(bbox)
    graph = build_graph(data, fr.drivable, fr.pedestrian, proj, cfg)
    log.info("graph: %d nodes, %d edges before clustering", len(graph.nodes), len(graph.edges))
    stats = cluster_junctions(graph, cfg)
    log.info(
        "cluster: %d clusters, %d nodes merged, %d edges removed",
        stats.clusters,
        stats.nodes_merged,
        stats.edges_removed,
    )
    fork_stats = shape_forks(graph, cfg)
    graph.notes = {
        "filter_dropped": dict(sorted(fr.dropped.items())),
        "junction_clusters": stats.clusters,
        "nodes_merged": stats.nodes_merged,
        "edges_removed_in_clusters": stats.edges_removed,
        "forks": fork_stats.forks,
        "merges": fork_stats.merges,
    }
    elev_stats: ElevationStats | None = None
    elev_meta: dict | None = None
    crossings = None
    if elevation is not None:
        crossings = infer_bridges(graph, elevation.sample)
        elev_stats = apply_elevation(graph, elevation, cfg)
        apply_pedestrian_elevation(graph, elevation, cfg)
        elev_meta = dict(sorted(elevation.describe().items()))
        elev_meta["bridge_clearance_m"] = cfg.bridge_clearance_m
        log.info(
            "elevation: y %.1f..%.1f, %d fixed, %d clamped, %d conflicts, %d edges over grade",
            elev_stats.min_y,
            elev_stats.max_y,
            elev_stats.fixed_vertices,
            elev_stats.vertices_clamped,
            elev_stats.bound_conflicts,
            len(elev_stats.edges_over_grade),
        )
    bounds = proj.bbox_local(bbox)
    report = validate(graph, cfg, bounds, fr.dropped_by_node())
    if elev_stats is not None:
        report.elevation = elev_stats.to_dict()
        report.elevation["inferred_bridges"] = crossings.to_list() if crossings else []
    sources = [dict(sorted(data.source.items()))]
    gd = graph_to_dict(graph, bbox, proj.frame, sources, config_name, elev_meta)
    return PipelineResult(graph, report, fr, stats, gd, elev_stats)


def write_outputs(result: PipelineResult, out_dir: Path, title: str) -> dict[str, Path]:
    """Write road_graph.v0.json and the validation report (JSON and Markdown)."""
    out_dir.mkdir(parents=True, exist_ok=True)
    paths = {
        "graph": out_dir / "road_graph.v0.json",
        "report_json": out_dir / "validation_report.json",
        "report_md": out_dir / "validation_report.md",
    }
    dump_json(result.graph_dict, paths["graph"])
    dump_json(result.report.to_dict(), paths["report_json"])
    paths["report_md"].write_text(render_markdown(result.report, title), encoding="utf-8")
    return paths


def load_cfg(path: Path | None) -> tuple[ImportConfig, str]:
    p = path or DEFAULT_CONFIG_PATH
    return load_config(p), p.name
