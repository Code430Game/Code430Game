## 1. Helicopter
- [x] 1.1 `helicopter.gd`: body and rotors, take-off from a helipad, circling, return; rotor voice; tests
- [x] 1.2 Sight: the helicopter counts as police sight except when the player is under cover (deck, garage, tunnel, dense trees); night searchlight; tests (trees have no collision yet, so canopy does not hide the player)

- [x] 1.3 From the human's first chase ("I do not think you can escape from the helicopter"): it sees only within 150 m and with nothing solid in the way. After 2 s without sight it circles where it last saw the player and sweeps its light there, and picks them up again only by seeing them (or a tip from a car or officer that has them). So hide under cover, then slip away while it searches. Tests

## 2. Verification
- [x] 2.1 Deck benchmark: a 3-star chase at night (2026-10-05, `--benchmark=40 --autodrive --preset=deck --wanted=3 --time=22`: avg 12.58 / 13.00 ms, p99 25.0 / 21.0 ms over two runs; the helicopter was up for 42 of 43 logged seconds. The day chase without it was 13.81 ms.)
- [ ] 2.2 Human tries to lose the helicopter on the Deck
