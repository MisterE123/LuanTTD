# Street-level sightseeing

Aim at dry ground or a street and type `/walk` to leave the builder
camera. If you're looking at water, a building, or the sky, the game
looks around the target or below the camera for nearby dry land.

Use **WASD** to walk, the mouse to look, Space for a short hop and
Shift to crouch. Press Luanti's camera key (**C** by default) to see
the animated street avatar from behind or in front. It is scaled to
the game's house doors. The camera follows the terrain and ordinary graded
roads. Houses and shops have solid walls; the sightseeing mode does
not reserve a traffic lane, interact with vehicles, or change the map.

Aim at a connected street and type `/car` to go for a drive. Use **W**
to accelerate, **A/D** to choose a turn, and **S** to brake or reverse.
The car cruises at about the pace of regular road traffic and backs up
more slowly. Its speed does not change with the simulation clock.
A drive is for sightseeing, not a company vehicle purchase.

For either mode, **right-click** or repeat its command to restore the
builder camera at the same aerial position and angle. The previous
hotbar and construction controls are restored. The builder has no
visible body in any camera mode.

`lua tests/pedestrian.lua` checks candidate landing and grade collision
profiles. `tests/pedestrian_native.sh` exercises the real Luanti
client on an ordinary road grade, a house wall, and the builder return.

`lua tests/avatar_car.lua` checks cruise, reverse and live road restrictions.
`tests/avatar_car_native.sh` measures both speeds with real keyboard input.
For comparison, run `tests/stock_road_fleet_native.sh` with
`LUANTTD_QA_FLEET_WAVE=sightseeing_speed LUANTTD_QA_FLEET_YEAR=1955 LUANTTD_QA_FLEET_TREE_PLACER=0`
to measure normal-speed MPS bus and mail truck traffic in an ordinary worker campaign.
