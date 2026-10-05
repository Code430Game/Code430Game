# Design: surface detail

- **World-space UVs.** Every ground material already gets a world position in the shader;
  detail UV is `world.xz / tile_m` with `tile_m` 4 for asphalt and 2 for concrete. No chunk
  rebuild and no new vertex attributes for the textures.
- **Joints need a distance along the ribbon.** Sidewalk vertices gain `UV2.x` = metres along
  the way (the builder has the cumulative length already) and `UV2.y` = across in metres.
  The joint line is `fract(UV2.x / slab_m)` under a width threshold. This changes the
  sidewalk vertex format, so the GLB chunks are re-exported with the attribute; the runtime
  builder writes it directly.
- **Zebra stripes as marking quads**, not texture: a crossing is short, so quads are cheap
  (eight to twelve per crossing, about 1,300 crossings in Ottawa) and they get the same
  emissive-at-dusk material as the lane lines. The stripe direction is the crossing way's
  direction; the extent is the road width at that point from the nearest edge, clipped to
  the curb lines.
- **Signalised stop lines** reuse the stop line the signals round draws where present; the
  crossing adds one only where none exists.
- **Generated textures** use the same deterministic noise helper as the water and sky work;
  a test asserts byte-identical output across runs.

## Decisions for the human
- Zebra on every crossing (asked), or zebra at signals and two-line elsewhere (Ottawa practice)?
- Slab length 1.5 m downtown, 2 m on paths: fine, or one value?
