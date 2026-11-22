# Native 3D terrain survey fixture

The optional survey turns a **private, real 256×256 OpenTTD 14.1 save** into
visible 3D terrain in a separate Luanti game. It does not start or replace
the LuanTTD campaign. It is not a playable importer, cannot resume service,
and does not write a new OpenTTD save.

```sh
tests/terrain_survey_native.sh /private/stock-fixture.sav /private/new-output
```

Requirements: Luanti client/server, Xvfb, xdpyinfo, xauth, xdotool,
ImageMagick and Python/Pillow. FFmpeg is optional for a short flight clip.
The hermetic Linux test can also use the native harness environment
variables `BAYLINE_NATIVE_TOOLS`, `BAYLINE_NATIVE_TCP`,
`BAYLINE_NATIVE_PORT` and `BAYLINE_NATIVE_DISPLAY`. Generate a suitable
private save using the existing unmodified-stock oracle in
`tests/openttd_save_map.py` with `--retain-fixture`. The source must
contain a graded coast and some built ordinary roads.

## What it shows and verifies

- A high view on a source-selected graded inlet, then a second view of
  the existing road network on sloped ground. Native windows consume
  live terrain-stream chunks, not a prebuilt 3D scene or screenshots.
- Original LuanTTD shared-corner OBJ terrain assets are mounted at their
  exact tile positions. The renderer uses stock slope profiles and real
  water/coast flags. For a graded shoreline, the fixture derives its
  original wet/shingle material directly from the exact asset's two
  triangles, not from imported OpenTTD artwork.
- Source ordinary stock road bits drive the existing road atlas. On
  grades it uses the ported stock foundation choice and shaped road
  surface; crossings, custom roadtypes, depots and stops do not get
  invented graphics. A few source wood tiles receive existing scenery
  trees only when their model datum fits the slope. Buildings, towns
  and vehicles are intentionally not part of this survey.
- The client flies across two chunk boundaries while the terrain
  updater mounts new chunks and removes distant ones. Per update,
  the profile builder prepares at most 2 chunks, native node work
  installs at most 2 and clears at most 4, and at most 36 are
  resident. Each chunk is at most 8×8 logical tiles. Luanti's separate
  disposable-air mapblock emerge preloads only the corridor envelope;
  it is not stock terrain generation or whole-map rendering.
- The runner checks actual mounted node IDs, both boundary crossings,
  the work and residency limits, textured terrain/coast/road pixels,
  and that the source SHA-256 is unchanged.

The output directory contains the private staged data, its own disposable
world and profile, `coast.png`, `roads.png`, `seam.png`, `arrival.png`,
`proof.json` and (when available) `flythrough.mp4`. Do not distribute
the staged game or source data. No OpenTTD save, engine or graphics are
committed here.
