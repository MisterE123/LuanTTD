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
Look through the car’s real window openings from behind the wheel, or
switch to either third-person view to see the full exterior. Front and
rear wheels follow the road grade, so the car and cockpit pitch together
on hills. Other players see the same exterior. A drive is for sightseeing,
not a company vehicle purchase.

**Right-click** to leave sightseeing and restore the builder camera.
The previous hotbar and construction controls are restored. The
`/walk`, `/car`, `/plane`, `/train`, and `/ride` commands are optional
shortcuts. See [flight controls](sightseeing-flight.md) and
[the train cab and passenger rides](seated-sightseeing.md). The builder has no
visible body in any camera mode. Rejoining a world restores your last
position and look direction. If you logged out inside a vehicle, you
return to the builder view at that location, clear of the road or terrain
where necessary, rather than reattaching to a vehicle that may have moved.

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


## A clean sightseeing view

**Inventory → Controls → Cinematic view**, or `/cine`, hides the hotbar,
hover and selection outlines, labels, and game overlays for your screen
only. Movement and sightseeing controls still work. Type `/cine` again
or open Inventory and choose **Restore interface**. Construction clicks
are ignored until the interface is restored. Luanti's own chat overlay
can be hidden separately with its chat key (**F2** by default).

**Hide decorative scenery** in the same panel, or `/candy`, toggles the
non-simulation animals and occasional shop cars just for you. Whales and
porpoises swim in open sea; gulls wheel over the coast, eagles circle hills
and woods, and foxes roam working fields. Decorative cars use connected town
streets between shops and disappear before they can crowd a working road
vehicle. None of these actors has orders, moves cargo, or is saved.
