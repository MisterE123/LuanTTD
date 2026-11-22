# Animated coastal water

The five `bl_water_*_anim.png` textures are original generated art.
Ocean ripples are wind waves with subtle, uneven sky-colored glints.
The quieter green-blue river has small directional surface streaks
advected downstream. These materials have no baked shore geometry,
scene/object silhouettes, or borrowed graphics. Real reflection effects,
where supported, belong to renderer and lighting code rather than the art.

Each indexed sheet contains ten 64-by-64 frames, arranged vertically for
Luanti's `vertical_frames` animation (set `aspect_w=64`, `aspect_h=64`).
Suggested cycle lengths: ocean approximately 4 seconds, rivers 2 seconds.
Both dimensions and the animation phase wrap. The water can be tinted
further by the renderer; no transparency is required.

Direction suffixes describe **image axes**, not world axes:

| River sheet suffix | Flow in the image |
| --- | --- |
| `river_anim` | down (+V) |
| `river_north_anim` | up (-V) |
| `river_east_anim` | right (+U) |
| `river_west_anim` | left (-U) |

The cardinal sheets rotate each frame individually, so the animation
strip stays vertical. Convert image axes to the relevant model or
world-aligned UV axes where assigning the texture. Native Luanti 5.10
verification on world-aligned +Y cube faces finds +U corresponds to
world +X, +V corresponds to world +Z. Mesh UVs may differ.

Edit or regenerate with `python3 tools/terrain_water_raster.py`
(Pillow). Check with `python3 tests/terrain_water_art.py`.
