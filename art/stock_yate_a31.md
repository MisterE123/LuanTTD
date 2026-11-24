# Yate Aerospace YAe46 and Airtaxi A31

This follows the missing Temperate introductions in game-date order:
the YAe46 (#237) precedes the A31 (#234) despite their stock IDs.

| Source engine | Base introduction | Passenger seats | Mail | Airport class |
| --- | --- | ---: | ---: | --- |
| Yate Aerospace YAe46 #237 | 31 March 1980 | 80 | 10 bags | Country or City |
| Airtaxi A31 #234 | 1 May 1981 | 210 | 25 bags | City |

The exact source is OpenTTD 16.0-RC1 `table/engines.h` MA and AVI
rows. The YAe46 has jet sound but is a conventional CTOL aircraft
(`P`), not a fast CTOL jet (`J`). It may dispatch from a small airport.
The stock calendar supplies the actual introduction under its seed;
these are the base dates, not dates hardcoded into the depot.

The YAe46 has four modeled open engines, shoulder wings, a connected
T-tail, main landing-gear fairings and original navy livery. The A31
has a shorter wide-body pressure shell, separate open underwing engines,
fitted split wingtip fences and burgundy livery. Both have interactive
gear-down and gear-up native exports derived from the same exterior.
No proprietary or original-game art is embedded.

Editable sources: `stock_yate_yae46.blend`, `stock_airtaxi_a31.blend`; build
with `tools/build_stock_yate_a31_art.py`. The stock source test confirms
the class and every data field. The cash test dispatches paid services
and checks restores; the YAe46 serves a mixed Country/City route. The
original meshes are also tested on the native client's actual airport
movement and geometry.
