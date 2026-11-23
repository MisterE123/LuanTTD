# Day and night

One sun-and-moon circuit lasts **one in-game calendar year**. January 1
starts at noon. A leap year gets its full 366 days, while a regular
year gets 365. Faster simulation moves the sun and moon faster;
the simulation pause freezes them in place. Reopening a world
resumes the saved calendar phase.

The sun and the square, cratered moon follow a shared orbit tilted by
20°, so the sun can cast diagonal shadows. Warm twilight separates day
from night, and moonlight keeps open terrain readable. Rebuild the
original moon texture with `python3 tools/terrain_moon_raster.py`.

In an ordinary campaign, Luanti displays the simulation worker's native
solar phase. Luanti's independent `time_speed` no longer sets an
unrelated campaign clock. This does not affect the separate Original
terrain survey.

`lua tests/atmosphere.lua` covers the calendar, speed changes, pause,
save/reopen, and native clock synchronization. `tests/atmosphere_native.sh`
checks the visuals in a real Luanti client. `tests/daylight_native.sh`
exercises the actual worker's calendar and the native engine clock.
