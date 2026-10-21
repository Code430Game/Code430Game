## 1. World tab
- [ ] 1.1 Weather hold and release (`Weather.hold(id)`, `Weather.release()`), snow allowed when held; clock fixed hour and stop (`DayNight.fix_hour(h)`, `DayNight.run()`), day length; tests (a held state stays past its duration, release walks again, a fixed hour stays put)
- [ ] 1.2 World tab rows (Weather, Time, Day length) with left/right values, in the shared theme; guests see the host's values greyed; the host's picks replicate through the existing weather and clock snapshots; tests on the rows and a two-peer round trip
## 2. Go to
- [ ] 2.1 "Gang turf" legend kind from the pack's turfs (centre as the place); Y "Go to" on a place: the player on foot beside it facing the nearest street, out of any car; refused while wanted with a line; tests (the spot is on the walk graph or ground, the wanted refusal)
- [ ] 2.2 `docs/controls.md`; Mac screenshots: the World tab, a rain pick, the legend with "Go to"
## 3. Check
- [ ] 3.1 Deck: package, deploy, benchmark against main (unchanged)
- [ ] 3.2 **Stop: the human picks rain then snow, sets 22:00, and goes to the helipad and the turf on the Deck**
