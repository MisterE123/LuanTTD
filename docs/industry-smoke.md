# Industrial smoke

Generated campaigns have local smoke over the modeled brick chimneys at stock
power stations, factories, and steel mills. The smallest plumes are vapor from
the oil refinery's service nozzles. Farms, wells, mines, and town buildings do
not get decorative smoke. This is a visual effect: it does not indicate cargo
delivery, change production, or use the simulation's randomness.

The power-station attachment follows
[OpenTTD 16.0-RC1's chimney effect](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/industry_cmd.cpp).
The 3D implementation anchors it to the exhaust opening in each actual mesh
and uses original translucent smoke art. It emits only for nearby players
after a chimney has been painted. The player-specific spawners stop as the
player leaves and the existing puffs fade out.

Rebuild the billboard with `python3 tools/build_industry_smoke.py`.
`lua tests/industry_smoke_view.lua` checks outlet selection and emitter lifecycle.
`tests/campaign_worker_industry_smoke_native.sh` verifies the two stock power
station rims and both rendered plumes in an ordinary native Luanti client.
