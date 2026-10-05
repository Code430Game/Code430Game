"""Underground garages from parking entrances (add-underground-parking 1.1, 1.2)."""

import math

from shapely.geometry import Point, Polygon

from osm_import.buildings import Building, BuildingsResult
from osm_import.cluster import cluster_junctions
from osm_import.config import load_config
from osm_import.elevation import FlatSource, apply_elevation
from osm_import.filter import filter_ways
from osm_import.garages import build_garages
from osm_import.graph import build_graph
from osm_import.projection import Projector
from tests.osm_helpers import BBOX, make_data

CFG = load_config()
GROUND = 10.0


class Flat:
    def sample(self, _x, _z):
        return GROUND


def _setup(ways, node_tags):
    data = make_data(ways, node_tags)
    fr = filter_ways(data, CFG)
    proj = Projector.for_bbox(BBOX)
    g = build_graph(data, fr.drivable, fr.pedestrian, proj, CFG)
    cluster_junctions(g, CFG)
    apply_elevation(g, FlatSource(GROUND), CFG)
    return data, g, proj


def _building(bid, name, x0, z0, x1, z1):
    ring = [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
    return Building(
        bid, "commercial", name, 20.0, GROUND, [ring], ring, [0, 1, 2, 0, 2, 3], 1, "levels"
    )


STREET = (1, [(-100, 0), (100, 0)], {"highway": "secondary"})
# Driveways north off the street: node 1002 ends the first, 1004 the second, 1006 the third.
DRIVE_A = (2, [(0, 0), (0, -20)], {"highway": "service", "service": "driveway"})
DRIVE_B = (3, [(30, 0), (30, -20)], {"highway": "service", "service": "driveway"})
DRIVE_C = (4, [(-60, 0), (-60, -15)], {"highway": "service", "service": "driveway"})


def _ids(data):
    """OSM node ids at the driveway ends, by their (x, z)."""
    out = {}
    for w in data.ways.values():
        if w.tags.get("service") == "driveway":
            out[w.id] = w.nodes[-1]
    return out


def test_named_entrances_make_one_garage_tier_garage_under_their_building():
    data0 = make_data([STREET, DRIVE_A, DRIVE_B, DRIVE_C])
    ends = _ids(data0)
    tags = {
        ends[2]: {
            "amenity": "parking_entrance",
            "parking": "underground",
            "name": "Arts Garage",
            "capacity": "200",
        },
        ends[3]: {"amenity": "parking_entrance", "parking": "underground", "name": "Arts Garage"},
    }
    data, g, proj = _setup([STREET, DRIVE_A, DRIVE_B, DRIVE_C], tags)
    hall = _building("w9.0", "Arts Hall", -20, -90, 60, -30)
    garages = build_garages(
        data, g, proj, BuildingsResult([hall]), [], Flat(), CFG.parking.get("garages")
    )
    garage = [x for x in garages if x.tier == "garage"]
    assert len(garage) == 1
    gar = garage[0]
    assert gar.name == "Arts Garage" and gar.capacity == 200
    assert len(gar.entrances) == 2
    assert gar.footprint_source == "building"
    assert abs(gar.floor_y - (GROUND - 3.2)) < 0.01
    poly = Polygon(gar.rings[0])
    for e in gar.entrances:
        start, end = e.ramp
        assert start[1] == e.y and abs(end[1] - gar.floor_y) < 1e-6
        assert poly.buffer(0.6).contains(
            Point(end[0], end[2])
        )  # the ramp arrives inside the garage
        assert e.dir[1] < -0.9  # heading north, into the block


def test_a_private_unnamed_entrance_is_a_door():
    data0 = make_data([STREET, DRIVE_C])
    ends = _ids(data0)
    tags = {ends[4]: {"amenity": "parking_entrance", "parking": "underground", "access": "private"}}
    data, g, proj = _setup([STREET, DRIVE_C], tags)
    garages = build_garages(data, g, proj, None, [], Flat(), CFG.parking.get("garages"))
    assert [x.tier for x in garages] == ["door"]
    e = garages[0].entrances[0]
    start, end = e.ramp
    assert math.dist((start[0], start[2]), (end[0], end[2])) > 6.0
    assert end[1] < start[1] - 1.0  # the door sits below the street
    assert garages[0].rings == []


def test_an_override_opens_the_museum_garage_without_tags():
    data0 = make_data([STREET, DRIVE_A])
    ends = _ids(data0)
    tags = {ends[2]: {"amenity": "parking_entrance"}}
    data, g, proj = _setup([STREET, DRIVE_A], tags)
    museum = _building("w8.0", "Victoria Memorial Museum Building", -40, -100, 40, -30)
    garages = build_garages(
        data, g, proj, BuildingsResult([museum]), [], Flat(), CFG.parking.get("garages")
    )
    assert [x.tier for x in garages] == ["garage"]
    assert garages[0].name == "Victoria Memorial Museum Building"


def test_a_public_entrance_without_a_building_gets_a_capacity_sized_garage():
    data0 = make_data([STREET, DRIVE_C])
    ends = _ids(data0)
    tags = {
        ends[4]: {
            "amenity": "parking_entrance",
            "parking": "underground",
            "capacity": "100",
            "fee": "yes",
        }
    }
    data, g, proj = _setup([STREET, DRIVE_C], tags)
    gar = build_garages(data, g, proj, None, [], Flat(), CFG.parking.get("garages"))[0]
    assert gar.tier == "garage" and gar.footprint_source == "capacity"
    area = Polygon(gar.rings[0]).area
    assert 100 * 28 * 0.8 < area < 100 * 28 * 1.6


def test_surface_and_multi_storey_entrances_are_not_garages():
    data0 = make_data([STREET, DRIVE_A, DRIVE_B])
    ends = _ids(data0)
    tags = {
        ends[2]: {"amenity": "parking_entrance", "parking": "multi-storey"},
        ends[3]: {"amenity": "parking_entrance", "parking": "surface"},
    }
    data, g, proj = _setup([STREET, DRIVE_A, DRIVE_B], tags)
    assert build_garages(data, g, proj, None, [], Flat(), CFG.parking.get("garages")) == []
