## 1. Radio
- [x] 1.1 `radio_station` on drivable cars; the radio follows the driven car's station; changing station writes it back; tests
  - `placeholder_car.gd` carries `radio_station` (empty until first driven). `Radio.car_entered(car)` tunes to it; a car with none, or a station no longer loaded, takes the player's last choice (`chosen_id`, the one saved in settings.cfg). Getting into a taken car is not a choice: settings keep the player's own station. `select` and `cycle` write back to the car being driven, and nothing writes while on foot.
  - Tests in `test_radio.gd`: first car takes the choice and the dial writes back; the swap scenario from the spec (Redline FM kept, the taken car's own station played, settings untouched); a car left off stays off; a stale station falls back.
- [x] 1.2 Taken and parked cars get a seeded station or off; emergency vehicles start on Chatter AM or off; co-op carries the field; tests
  - `Radio.pick_for_car(seed, emergency)`: one in five taken cars is off, the rest pick from `radio.v0.json`; emergency vehicles are Chatter AM or off, half and half. Seeds: a traffic car's model and where it was taken (`TrafficManager.station_seed`), a parked car's stall key, an ambulance or patrol car's spawn point (set when it spawns, so taking one keeps it).
  - Co-op: "the car's existing snapshot" for a taken car is the host's take grant, so `release_near` and `release_key` return a `station` and `_grant_take` carries it (defaulted, so an older peer's three-argument call still lands). Remote players' radios are not heard, so `PlayerSync` state is unchanged.
  - Tests: station on `take_car` (`test_traffic`), `ParkedCars.take` and `release_key` (`test_parked_cars`), `release_near` (`test_coop`), spawned patrol cars and ambulances (`test_police`, `test_ambulance`), and the pick's spread and determinism (`test_radio`).

## 2. Verification
- [ ] 2.1 Human swaps between two cars on the Deck and hears each keep its station
