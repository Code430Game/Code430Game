import pytest

from osm_import import tags as T


@pytest.mark.parametrize(
    "value,expected", [("2", 2), ("2;3", 2), ("3.0", 3), (None, None), ("many", None)]
)
def test_parse_int(value, expected):
    assert T.parse_int(value) == expected


@pytest.mark.parametrize(
    "value,expected", [("12", 12.0), ("12.5 m", 12.5), ("10 ft", 3.048), ("0", None), (None, None)]
)
def test_parse_width(value, expected):
    result = T.parse_width_m(value)
    assert result == pytest.approx(expected) if expected is not None else result is None


@pytest.mark.parametrize(
    "value,expected", [("50", 50), ("30 mph", 48), ("walk", None), (None, None), ("100 km/h", 100)]
)
def test_parse_maxspeed(value, expected):
    assert T.parse_maxspeed_kph(value) == expected


@pytest.mark.parametrize(
    "value,expected", [("1", 1), ("-1", -1), ("-1;0", -1), (None, 0), ("x", 0)]
)
def test_parse_layer(value, expected):
    assert T.parse_layer(value) == expected


@pytest.mark.parametrize(
    "value,expected",
    [
        ("yes", "forward"),
        ("true", "forward"),
        ("-1", "reverse"),
        ("no", "no"),
        (None, "unset"),
        ("alternating", "unset"),
    ],
)
def test_parse_oneway(value, expected):
    assert T.parse_oneway(value) == expected


@pytest.mark.parametrize(
    "value,expected", [("yes", True), ("viaduct", True), ("no", False), (None, False)]
)
def test_is_truthy(value, expected):
    assert T.is_truthy(value) is expected
