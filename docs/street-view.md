# Street-level sightseeing

Aim at dry ground or a street and type `/walk` to leave the builder
camera. If you're looking at water, a building, or the sky, the game
looks around the target or below the camera for nearby dry land.

Use **WASD** to walk, the mouse to look, Space for a short hop and
Shift to crouch. Press Luanti's camera key (**C** by default) to see
the animated street avatar from behind or in front. The camera follows the terrain and ordinary graded
roads. Houses and shops have solid walls; the sightseeing mode does
not reserve a traffic lane, interact with vehicles, or change the map.

Aim at a connected street and type `/car` to go for a drive. Use **W**
to accelerate, **A/D** to choose a turn, and **S** to brake or reverse.
A drive is for sightseeing, not a company vehicle purchase.

For either mode, **right-click** or repeat its command to restore the
builder camera at the same aerial position and angle. The previous
hotbar and construction controls are restored.

`lua tests/pedestrian.lua` checks candidate landing and grade collision
profiles. `tests/pedestrian_native.sh` exercises the real Luanti
client on an ordinary road grade, a house wall, and the builder return.
