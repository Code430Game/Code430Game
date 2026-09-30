## 1. Rules
- [x] 1.1 `marking_rules.json`: widths, dash on/off lengths, colours, centre style per class, lift above road

## 2. Builder
- [x] 2.1 `marking_builder.gd`: offsets from lane counts, centre/divider/edge lines as thin quads along trimmed, chunk-split polylines with miter normals
- [x] 2.2 Dashes by walking the polyline in metres
- [x] 2.3 Per-chunk `markings_lod0`; GLB export and import; material

## 3. Tests and verification
- [x] 3.1 gdUnit4: line counts per lane configuration, dash count for a known length, upward winding, trimmed ends, GLB round trip
- [x] 3.2 Screenshot on the 417 and on a residential street; Deck frame time (Steam Deck, deck preset, 30 s autodrive: avg 5.55 ms, p99 6.06 ms, unchanged from before markings)
