# Day and night

The sun and moon move along a shared orbit tilted by 20°, so the sun
can cast diagonal shadows. The sky passes through warm twilight, and
moonlight keeps open terrain readable for building. The moon is
original procedural art: `python3 tools/terrain_moon_raster.py`
rebuilds the texture.

The sky follows **simulation speed**. A full day takes **2 minutes at
1×**, **1 minute at 2×**, or **30 seconds at 4×**. Pausing holds the
current sky; resuming continues from that point. The date and economy
progress at their existing pace. This does not change a service
schedule or turn the sky one revolution per economy day.

Luanti still owns the world clock and its saved phase. A server
administrator can use Luanti's `/time` command to set that phase.
A non-default positive Luanti `time_speed` overrides the 1×
baseline, and explicit `time_speed = 0` still freezes the sky
regardless of the playback controls. None of this applies to the
separate Original terrain survey.

`lua tests/atmosphere.lua` covers visual continuity and default,
paused, accelerated and resumed speeds. `tests/atmosphere_native.sh`
draws the same profile in a real Luanti client. `tests/daylight_native.sh`
checks the actual server's native time advances at the appropriate speed.
