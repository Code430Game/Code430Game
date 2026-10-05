## 1. Importer
- [x] 1.1 `services.py`: query, kinds (security kept apart from police), centres, nearest road node; `services.v0.json`, schema, pack validation; tests; Ottawa re-export with the counts here
  - 2026-10-05 Ottawa: 2 police (Ottawa Police Headquarters and an unnamed station), 2 security (uOttawa Campus Protection, Rideau Centre Security), 2 hospitals, 2 fire stations, 3 ambulance posts, 1 helipad

## 2. Game
- [x] 2.1 Load services; map and minimap icons with hover names; tests
- [x] 2.2 Busted respawns at the nearest police station, wasted at the nearest hospital (spawn point fallback); the first patrol car leaves from a station in the spawn ring; tests
- [x] 2.3 Mac screenshots: the map icons, a respawn outside the police headquarters
  - 2026-10-05: map screenshot shared (icons: P police, S security, + hospital, F fire, A ambulance, H helipad; drawn over everything). The busted and wasted banner names the station or hospital

## 3. Verification
- [ ] 3.1 Human gets busted and wasted on the Deck (feedback to the backlog)
