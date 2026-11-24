# Metropolitan Airport

**Airfields → Metro & Commuter Airports → Build Metropolitan Airport** is available from 1980. The
footprint, terminal order, runway reservations, and hangar use the
OpenTTD 16.0-RC1 source tables. The 6×6 terminal has a radius-six catchment
and separate arrival and departure runways. An arriving aircraft must
still wait for departure traffic when it crosses the departure runway.

The original City Airport models are reused only for shared stock graphics.
The new arrival-side radar, departure runway stripe and runway thresholds
have [editable Blender source](../art/metropolitan_airport_parts.blend).
The display is not intended as a copy of the original game's sprites.

The native QA fixture builds two airports in a regular 1985 worker session,
checks all 36 painted cells, buys a Bakewell Luckett LB-80, watches taxi and
takeoff at one field and landing at the other, and proves the same plane
continues serving its route after restarting the world. A separate
Metro–City gameplay test checks fares and the catchment footprint.
Airport noise integration and radar animation are not yet exposed in game.

Source pin: OpenTTD 16.0-RC1, revision 07b339c0aaeb0a87be9490b2f1c3f17c6b00b837.
The extraction script retains the source tile IDs, ordered transitions,
hangars, entries, flags, and terminal groups. The other imported fixed-wing
tables are not yet mounted as playable airports.
