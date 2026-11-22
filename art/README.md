# Editable fleet prototypes

Ten original Blender files and matching OBJ files. These are style sketches
made from newly constructed geometry and an original palette, not recreations
of particular upstream game sprites. No upstream sprites or assets are included.

The baseline official OpenGFX and OpenGFX2 graphics sets and zBase use GPL,
not Creative Commons. We used OpenTTD + OpenGFX privately for gameplay
comparison. It is not the Creative Commons art input for this fleet.

Creative Commons candidate leads for future per-vehicle verification:
- Timberwolf's UK Road Vehicles 3 v3.4.3: the official OpenTTD content registry
  lists [CC BY-SA 3.0](https://bananas.openttd.org/package/newgrf/5457460a).
  Check the exact source/version and individual credits before adapting.
- [Rail Island Factory's OpenTTD catalog](https://factory.railisland.com/openttd/)
  lists certain vehicle entries as CC0; verify each downloadable item.
  Catalog-wide licensing must not be inferred from a single entry.

For a model deliberately adapted from released game art, record exactly which
sprite/version and author were used, link the applicable license, identify
the changes, and preserve any attribution and share-alike requirements.

## Road architecture

`bus_shelter.blend` and `road_depot.blend` are original models with named,
editable component geometry. The stop uses an open shelter with a roof,
supports, bench, flag, timetable and raised pavement rather than a texture
printed across the road. The repair shop has a modeled vehicle bay, apron,
roof seams, masonry trim, window surrounds and chimney. Both use original
color swatches rather than imported OpenTTD art. Run
`blender -b -t 2 --python tools/build_road_art.py` to regenerate the native
Luanti meshes (three shelter layouts and four depot orientations).

## Towns and industries

`tools/build_scenery_art.py` regenerates 13 original editable models:
four house styles, a civic clock hall, four kinds of trees, a mine
headframe, farm, steel mill and factory. Their matching OBJ files use the
included original palette, without any OpenTTD graphics.

### Starter town parcels

The original market, corner grocer, and civic green each have editable
Blender source in `art/town_*.blend` and a Luanti OBJ export. These are
purpose-modeled mesh parcels, not map icons. Run
`blender -b -t 2 --python tools/build_town_props.py` to rebuild them.
Sidewalk surfaces use the same joined asphalt mask as ordinary roads;
run `python3 tools/build_town_streets.py` after regenerating road textures.

### Service cues

The two short arrival and fare sounds are original synthesizer scores
in `tools/build_service_sounds.py`, rendered to mono Ogg Vorbis for Luanti.
No OpenTTD sound assets are included. Set `bayline_service_sounds = false`
to mute the milestone cues independently of the client master volume.
