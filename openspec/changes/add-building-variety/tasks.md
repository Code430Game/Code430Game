## 1. Importer
- [x] 1.1 Export material, colour, roof shape and levels, levels, shopfront; schema; golden; Ottawa rebuilt

## 2. Game
- [x] 2.1 Six facade treatments in the shader, chosen from material, kind and height; colour from data; tests
- [x] 2.2 Pitched roofs (gable, hip) from the footprint's oriented box; parapets and roof boxes on flat roofs; tests
- [x] 2.3 Shopfront ground floors and balconies; tests

## 3. Verification
- [x] 3.1 Deck downtown (2026-10-01, idle, 150 cars, 120 people): GPU 8.38 ms against 8.02 ms before, render CPU 1.62 ms, physics 9.38 ms, frame avg 13.9 ms, one 99 ms spike at a chunk add (the heavier building meshes; collision spread over frames is the planned fix); screenshots of the terraces at x 1340 z 440, shopfronts at x 120 z 183 and downtown towers checked
- [ ] 3.2 **Stop: human walks a few blocks on the Deck**
