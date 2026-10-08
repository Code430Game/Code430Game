"""The synthetic elevation source's hill can be moved by a region file (add-proving-ground)."""

from osm_import.elevation import SyntheticSource


def test_synthetic_hill_can_move_and_says_so():
    centred = SyntheticSource()
    moved = SyntheticSource(hill_x=-380.0, hill_z=-330.0)
    assert moved.sample(-380.0, -330.0) > moved.sample(0.0, 0.0)
    assert centred.sample(0.0, 0.0) > centred.sample(-380.0, -330.0)
    assert "hill_centre" not in centred.describe(), "the default keeps the golden fixture's meta"
    assert moved.describe()["hill_centre"] == [-380.0, -330.0]
    assert moved.describe()["hill_radius"] == 250.0
