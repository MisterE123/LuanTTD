# Street-level sightseeing

Open **Survey** in the construction hotbar and select a sightseeing tool.
Aim and left-click to use it.

- **Walk:** click open, dry ground.
- **Drive Car:** click a connected street.
- **Fly Plane:** click an airport.
- **Train Cab:** click the train you want to see from the cab.
- **Ride Vehicle:** click a passenger train or bus to ride along.

Each button shows the required target above the hotbar. If there is no
compatible target, sightseeing does not start somewhere else. Use
**Inspect**, **Jump Map**, or **Teleport above tile** without leaving Survey.

Use **WASD** to walk, the mouse to look, Space for a short hop and
Shift to crouch. Press Luanti's camera key (**C** by default) to see
the animated street avatar from behind or in front. It is scaled to
the game's house doors. The camera follows the terrain and ordinary graded
roads. Houses and shops have solid walls; the sightseeing mode does
not reserve a traffic lane, interact with vehicles, or change the map.

Use **W** to accelerate, **A/D** to choose a turn, and **S** to brake or reverse when driving.
The car cruises at about the pace of regular road traffic and backs up
more slowly. Its speed does not change with the simulation clock.
Look through the car’s real window openings from behind the wheel. The
car’s body is visible outside to other players. A drive is for sightseeing,
not a company vehicle purchase.

**Right-click** to leave sightseeing and restore the builder camera.
The previous hotbar and construction controls are restored. The
`/walk`, `/car`, `/plane`, `/train`, and `/ride` commands are optional
shortcuts. See [flight controls](sightseeing-flight.md) and
[the train cab and passenger rides](seated-sightseeing.md). The builder has no
visible body in any camera mode.

`lua tests/pedestrian.lua` checks candidate landing and grade collision
profiles. `tests/pedestrian_native.sh` exercises the real Luanti
client on an ordinary road grade, a house wall, and the builder return.

`lua tests/avatar_car.lua` checks cruise, reverse and live road restrictions.
`tests/avatar_car_native.sh` measures both speeds with real keyboard input.
For comparison, run `tests/stock_road_fleet_native.sh` with
`LUANTTD_QA_FLEET_WAVE=sightseeing_speed LUANTTD_QA_FLEET_YEAR=1955 LUANTTD_QA_FLEET_TREE_PLACER=0`
to measure normal-speed MPS bus and mail truck traffic in an ordinary worker campaign.


`lua5.1 tests/survey_sightseeing.lua` checks dispatch and exact targets
for all five Survey items. The graphical Linux fixture
`tests/survey_sightseeing_native.sh` opens the real hotbar and enters
and exits Walk with actual keyboard and mouse controls.
`tests/survey_sightseeing_backends_native.sh` clicks a real connected road
and a built Country Airport; it drives, takes off and restores the exact
builder pose without entering a chat command.
