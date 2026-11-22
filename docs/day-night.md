# Day and night

Ordinary LuanTTD campaigns follow Luanti's world clock. The sun and moon
move along a shared orbit tilted by 20°, so the sun can cast diagonal
shadows. The sky passes through warm twilight, and moonlight keeps open
terrain readable for building. The moon is original procedural art:
`python3 tools/terrain_moon_raster.py` rebuilds the small texture.

- `time_speed` still sets clock speed (Luanti default 72, a 20-minute
  full day). An explicit `time_speed = 0` stays frozen at its selected
  world time.
- `bayline_moonlight_ratio` controls nighttime terrain lighting. Its
  default is 0.53; lower is darker, higher is brighter. Daylight still
  rises toward full brightness, with a smooth twilight transition.
- Turning off `bayline_coastal_haze` disables optional fog and clouds,
  not the day/night cycle, moon or stars.

This is presentation only: it does not change production, service
schedules, map saves, or the separate Original terrain survey mode. An
administrator can use Luanti's existing `/time` command to inspect a
particular time of day.

`lua tests/atmosphere.lua` exercises profile continuity and player
lifecycle. `tests/atmosphere_native.sh` draws the production profile
on a small real Luanti world. Set `BAYLINE_ATMOSPHERE_TEST_SPEED=7200`
to test an accelerated—but still engine-driven—clock.
