## 1. Mesh
- [x] 1.1 `car_mesh.gd`: parametric body, cabin, arches, lights; white body vertices, coloured glass and lights; test on triangle count, bounds and colour split

## 2. Use
- [x] 2.1 Player car scene uses the mesh and cylinder wheels; traffic MultiMesh uses the shared mesh with instance colour; taken cars keep their colour; tests

## 3. Verification
- [x] 3.1 Deck (2026-09-30, deck preset, 150 traffic cars, idle Deck): GPU 6.50 ms with the car body against 6.31 ms with boxes; render CPU 1.04 ms; draw calls 276; physics 7.35 ms
- [ ] 3.2 **Stop: human looks at the cars on the Deck**
