"""Emergency service places (add-emergency-services 1.1)."""

from osm_import.services import kind_of


def test_kinds():
    assert kind_of({"amenity": "police", "name": "Ottawa Police Headquarters"}) == "police"
    assert kind_of({"amenity": "police", "name": "Rideau Centre Security"}) == "security"
    assert kind_of({"amenity": "police", "name": "UOttawa Campus Protection"}) == "security"
    assert kind_of({"amenity": "police", "police": "private"}) == "security"
    assert kind_of({"amenity": "hospital"}) == "hospital"
    assert kind_of({"amenity": "fire_station"}) == "fire_station"
    assert kind_of({"emergency": "ambulance_station"}) == "ambulance"
    assert kind_of({"aeroway": "helipad"}) == "helipad"
    assert kind_of({"amenity": "clinic"}) is None
