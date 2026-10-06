"""Paved gores between a ramp and its road (add-road-shoulders 1.4)."""

import math

import pytest

from osm_import.cluster import cluster_junctions
from osm_import.config import load_config
from osm_import.elevation import FlatSource, apply_elevation
from osm_import.filter import filter_ways
from osm_import.gores import build_gores
from osm_import.graph import build_graph
from osm_import.pack import _road_footprints
from osm_import.projection import Projector
from tests.osm_helpers import BBOX, make_data

CFG = load_config()
MOTORWAY = {"highway": "motorway", "oneway": "yes", "lanes": "2"}
RAMP = {"highway": "motorway_link", "oneway": "yes", "lanes": "1"}


def graph_for(ways):
    data = make_data(ways)
    fr = filter_ways(data, CFG)
    g = build_graph(data, fr.drivable, fr.pedestrian, Projector.for_bbox(BBOX), CFG)
    cluster_junctions(g, CFG)
    apply_elevation(g, FlatSource(10.0), CFG)
    return g


def off_ramp():
    """A motorway running east with an off-ramp leaving it at x 0 and drifting south."""
    return [
        (1, [(-200, 0), (0, 0), (200, 0)], MOTORWAY),
        (2, [(0, 0), (60, 6), (120, 20), (200, 40)], RAMP),
    ]


def test_an_off_ramp_gets_a_paved_gore_up_to_the_limit():
    g = graph_for(off_ramp())
    gores = build_gores(g, CFG)
    assert gores and g.gores is gores
    limit = CFG.bridges["infill_max_m"]
    overlap = CFG.bridges["infill_overlap_m"]
    for s in gores:
        assert s.source.startswith("gore:")
        for (x, y, _z), half in zip(s.points, s.left_m, strict=True):
            assert y == pytest.approx(10.0, abs=0.01)
            assert 0.0 < x < 200.0  # after the fork, not before it
            assert half <= limit / 2.0 + overlap + 1e-6
    length = sum(
        math.dist(a[::2], b[::2])
        for s in gores
        for a, b in zip(s.points, s.points[1:], strict=False)
    )
    assert length > 20.0


def test_opposing_carriageways_across_a_median_get_no_gore():
    ways = [
        (1, [(-200, 0), (200, 0)], MOTORWAY),
        (2, [(200, 14), (-200, 14)], MOTORWAY),  # 3.5 m between the paved edges
    ]
    g = graph_for(ways)
    assert build_gores(g, CFG) == []


def test_other_classes_get_no_gore():
    ways = [
        (w, pts, {**tags, "highway": "primary" if w == 1 else "primary_link"})
        for w, pts, tags in off_ramp()
    ]
    assert build_gores(graph_for(ways), CFG) == []


def test_the_terrain_is_flattened_under_a_gore():
    g = graph_for(off_ramp())
    build_gores(g, CFG)
    plain, _ = _road_footprints(graph_for(off_ramp()), include_pedestrian=False)
    with_gores, _ = _road_footprints(g, include_pedestrian=False)
    assert len(with_gores) > len(plain)
