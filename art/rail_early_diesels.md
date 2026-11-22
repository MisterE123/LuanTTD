# SH/Hendry '25' and UU '37'

Original 3D rolling stock for the temperate standard-rail SH/Hendry '25'
and UU '37'. Design numbers 13 and 14, introduction dates, speeds,
horsepower, cost factors, reliability data, and weights are from the
[pinned OpenTTD 16.0-RC1 stock roster](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h).
The Hendry is a compact 128 km/h Bo–Bo with comparatively flat cab
ends; the 144 km/h UU has six axles, split headcode pods, and raised
rounded bonnets.

- **Class 25 reference:** David Martin, [Preserved diesel locomotive D7628 beside the Esk](https://www.geograph.org.uk/photo/5356545), [CC BY-SA 2.0](https://creativecommons.org/licenses/by-sa/2.0/).
- **Class 37 reference:** Steve Knight, [37403 and 37025 at Bo'ness station](https://commons.wikimedia.org/wiki/File:37403_and_37025_at_Bo%27ness_station.jpg), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

The photographs were consulted for silhouette and engineering construction.
No photo pixels, decals, textures, or original OpenTTD sprites are included
or projected onto the models. Both models use original liveries, beveled
steel panels, separately mounted windscreens and wipers, fan guards, vents,
wheels, bearings and drawgear. The editable Blender files each have two
independent bogie pivots and independently rolling axles. Their runtime
meshes are exported with neutral pose and baked palette UVs.

Rebuild both with
`blender -b -t 3 --python-exit-code 1 --python tools/build_early_diesel_art.py`.
Set `LUANTTD_DIESEL_REVIEW` to an existing output directory for side-by-side
studio renders. The vehicle bodies, textures, and generator are original
LuanTTD work.
