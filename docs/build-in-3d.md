# Build in a fresh LuanTTD world

A fresh ordinary world starts with a LuanTTD port of **OpenTTD 14.1’s
TerraGenesis**. Seed 1751 starts near **Great Chinfingley Market**.
Try the generated town street at `(14,14)`: open **Roadworks → Bus
Stops** and place a roadside stop. The world has real 3D corner slopes
and source-based coastal flooding, not water at every tile of equal
height. A fresh singleplayer world opens the generator setup first.
Choose the seed, size, landscape and population options. For a
mainland-style map, open **Landscape options** and choose **No forced
coast** or pick which edges to make coastal. Then click **Save and return**. This ends the local setup session:
press **Play** again on the same world to load the new terrain. Wait
for the placement screen to finish. Dedicated servers generate automatically
from their OpenTTD world-generation options.

This is not the full OpenTTD industry, vehicle, or terrain
ruleset; see [the generated world guide](generated-campaign.md).

Type **/world_origin** to report your map generator, seed, and size.
Choose a named scenario in the setup screen instead of **Generate a world** to use a fixed industry or coast layout.

## Moving around

- Fly with **WASD**, rise with **Space**, and descend with **Shift**.
  Hold **E** (Aux1) to fly faster. E is still the diagonal modifier
  when releasing the Bulldozer.
- **Navigation → Jump Map** shows the whole region. Click a
  destination to return there in 3D. A 64×64 map shows every tile; a
  128×128 map also offers a local view with individual tiles.

## Water and coastal light

Sea ripples and river animation are visible without custom shaders.
River surface marks run toward outlets or downhill into inland basins;
they do not change flood rules, bridges, or ship routes. Coastal haze
and the sky gradient are part of the scene.

For Luanti's real sky and sun glints, turn on **Shaders**, **Dynamic
shadows**, **Waving liquids**, and **Liquid reflections** in client
Settings. Its stock shader reflects sky and sunlight, not silhouettes
of nearby houses. Set **Waving liquids wave height** to about **0.16**
for small waves. Game updates do not change your client settings.

## Construction at a glance

- **Roadworks** and **Railworks** are the primary construction menus.
  Select the mode first, then lay the way, place the station or depot,
  build a bridge, or choose a tunnel. You can get to the controls with
  the number assigned to the visible hotbar slot.
- **AutoRoad:** click on a half-tile, or hold left-click and aim
  along a straight axis, then release. Preview highlights the buildable
  part. Use another drag for a turn. Right-click while holding to cancel.
  In **Road Tools → One-way**, drag in the direction traffic
  should travel. Repeat the same drag to remove the signs.
- **Bridge:** pick the two endpoints in the world, then choose an
  available type from the list. The list gives price and speed. A type
  isn't offered if its stock length or date restrictions rule it out,
  or the preview lacks that bridge family. A rail bridge currently
  offers timber only.
- **Level crossing:** use normal Road across a compatible railway or
  normal Rail across a compatible road. The tracks must be perpendicular
  on supported terrain. If an existing crossing is separated by a
  half-road, drag up to the adjoining road tile. A compatible crossing
  one tile beyond it still connects; only the missing approach is billed. Angled approaches and rail junctions on the
  crossing itself cannot be created in this preview.
- **Bulldoze** works from the construction menus. Click for one
  tile, or hold left-click and release at the other corner for an
  area. Hold **E** (Aux1) on release for a diagonal area. Right-click
  while holding to cancel. Protected tiles are skipped and clearing
  stops when the company can't afford the next tile. It is separate
  from the mode-specific tools for taking out track or fittings.
- **Owned trains** can choose between branches at a junction. Inspect
  the depot, buy a locomotive, and pick its platforms, then choose **Dispatch**.
  A supported single two-body shuttle can reserve ahead to a safe
  point on the next forward leg and still stop at the through platform.
  If the route must reverse or has no safe point ahead, put a regular
  Path Signal directly beyond the platform in the arrival direction
  or use a dead end. See [the through-platform limits](autorail.md).


## Fly the Bakewell Cotswald LB-3

Open **Sea & Air → Airfields** and build two country airfields
near towns. Inspect your first hangar and purchase the **Bakewell
Cotswald LB-3**. Choose **Choose destination airfield** in the
hangar panel, pick the destination, then select and click **Dispatch**. It has the stock 30-passenger cabin and its own
gear-down and gear-up models. It currently operates solo: only the
Sampson pair supports shared-airfield operation. The stock six-bag mail
hold is not yet carried by the preview's passenger service.
