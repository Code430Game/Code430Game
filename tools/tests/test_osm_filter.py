from osm_import.config import load_config
from osm_import.filter import filter_ways
from tests.osm_helpers import make_data

CFG = load_config()


def test_filter_classes():
    data = make_data(
        [
            (1, [(0, 0), (100, 0)], {"highway": "residential"}),
            (2, [(0, 10), (100, 10)], {"highway": "footway"}),
            (3, [(0, 20), (100, 20)], {"highway": "construction"}),
            (4, [(0, 30), (100, 30)], {"highway": "service", "service": "parking_aisle"}),
            (5, [(0, 40), (100, 40)], {"highway": "service", "access": "private"}),
            (6, [(0, 50), (100, 50)], {"highway": "pedestrian", "area": "yes"}),
            (
                7,
                [(0, 60), (100, 60)],
                {"highway": "service", "access": "private", "motor_vehicle": "yes"},
            ),
            (8, [(0, 70), (100, 70)], {"highway": "bus_stop"}),
        ]
    )
    result = filter_ways(data, CFG)
    assert [w.id for w in result.drivable] == [1, 4, 7]  # parking aisles are kept (class parking)
    assert [w.id for w in result.pedestrian] == [2]
    assert result.dropped == {
        "highway=construction": 1,
        "access=private": 1,
        "area=yes": 1,
        "highway=bus_stop": 1,
    }
    assert {w.id for w, _ in result.dropped_ways} == {5}


def test_way_with_one_known_node_is_dropped():
    data = make_data([(1, [(0, 0), (100, 0)], {"highway": "residential"})])
    del data.nodes[1001]
    result = filter_ways(data, CFG)
    assert result.drivable == []
    assert result.dropped == {"too_few_nodes": 1}
