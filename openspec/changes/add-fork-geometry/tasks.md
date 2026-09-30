## 1. Importer
- [x] 1.1 `forks.py`: detect forks and merges, shift the link end to the through road's edge with a 40 m blend, tag the node; tests
- [x] 1.2 Schema: `junction_type` gains `fork` and `merge`; golden files regenerated
- [x] 1.3 Barriers: samples end on edge ends; overlap rule ignores roads at a different level; tests

## 2. Game
- [x] 2.1 No junction polygon at fork or merge nodes; through edges taper across them; ramp connectors carry no junction claim; test

## 3. Verification
- [x] 3.1 Ottawa rebuilt (2026-09-30): 24 forks, 16 merges shaped; barriers now curb 2434, parapet 114, guardrail 37, median 24, soundwall 18; Bronson interchange ramp parapets continuous on both sides, no walls across the 417
- [ ] 3.2 **Stop: human drives the 417 exits and the Bronson interchange on the Deck**
