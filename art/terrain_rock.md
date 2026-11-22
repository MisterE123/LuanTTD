# Natural rock and rough ground

The original artwork separates grass, stony turf, exposed rock, and built
structures. All natural stone is generated procedurally; it has no borders,
photographs, baked light or OpenTTD graphics.

- `bl_hill_side.png`: 128px neutral gray weathered slate, with subtle
  bedding and worn fissures for exposed terrain walls and the bedrock floor.
- `bl_hill0.png` through `bl_hill3.png`: 32px weathered mineral tops for
  elevated ground and landmark blocks. Variants share their edge pattern;
  their inner mineral variation is independent. The old mountain symbols
  were removed from all four tops, not only the walls.
- `bl_clear_rough.png`: dull olive stony turf for stock terrain class 1.
- `bl_clear_rocks.png`: pale gray slate with sparse vegetation for stock
  terrain class 2. Both 64px clear textures work on flat and sloped tiles.
- Legacy road/rail tunnel quadrants are composed from the new hill top.
  They use lossless 4-bit indexed PNGs that preserve the original asphalt,
  ballast, and portal colors. Engineered road retaining masonry is unchanged.

Regenerate from the repository root using Pillow:

```sh
python3 tools/terrain_rock_raster.py
python3 tests/terrain_rock_art.py
```

The primary art generator uses the same material and tunnel sources. Tests
audit exported pixels, natural color and contrast, repeat seams, and the
size of all 128 affected tunnel textures.
