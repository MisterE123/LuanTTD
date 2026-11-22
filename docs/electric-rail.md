# Electrify an owned railway

The electric roster includes the stock **SH '30'** and **SH '40'** and overhead
wire for flat, single-piece ordinary rail. Steam and diesel can still
run on the converted railway. Electric locomotives must buy, start and route on
powered track.

Build ordinary track, a depot and both platforms first. Open
**Railworks → Rail Tools and Operations → Rail Engineering → Rail Types**:

- **Electrify railway** takes two rectangle corners. Hover over the
  opposite corner to see the price, then click to commit. Back or
  right-click cancels the selection. Select complete platforms, not
  individual tiles of a longer platform.
- **Convert to ordinary rail** uses the same selection. An owned
  occupied or reserved route cannot be changed while its train is in
  service. Early years won't offer electrification until the stock
  company roster qualifies.

At the starting tariffs, electrification is **$68 per piece** and
conversion back is **$12 per piece**. Flat straights and curves are
supported, as are flat passenger platforms, enclosed depots, and
unoccupied wooden rail bridges. Selecting either bridge portal changes
the entire bridge once; the land below is not charged or converted.
Ordinary slopes, junctions, tunnels and level crossings cannot be
converted. Overhead wire inside the depot is hidden by the shed.
Electric locomotives support one owned shuttle, not the paired pilot.

## Legacy Harbor Valley reference

These coordinates are for existing Harbor Valley worlds only. New
ordinary worlds are generated; in those worlds start with
`bayline_stock_bus_start_year = 1970` for the SH ’30’, or set 1978
for the SH ’40’. Choose a flat connected approach and use the same
construction and signalling steps below with your own coordinates.

1. Use `/survey 33 14`. Place a depot at `(28,14)` facing east, then
   lay a straight from `(29,14)` to `(37,14)`.
2. Build platforms `(31,14)–(32,14)` and `(36,14)–(37,14)`.
   In Rail Signals, click Rotate railway fitting twice from the
   default to face **NE** (toward lower X), then put a path signal on
   `(30,14)`. The opposite facing doesn't provide a safe return order.
3. Electrify from `(28,14)` through `(37,14)`. Converting the ten
   pieces costs $680.
4. Inspect the depot. Buy the **SH '30' + passenger carriage**, then
   order it to the eastern platform and then the western one. This short
   Harbor Valley example shows the train and wire; use connected platforms
   with town-house catchments to earn passenger fares.

Both locomotives come from stock OpenTTD 14.1. Their source rows share
image index 20; LuanTTD mounts original 3D artwork for each locomotive.
At starting prices with a 40-seat carriage:

| Locomotive | Top speed | Power | Engine weight | Price with carriage |
| --- | ---: | ---: | ---: | ---: |
| SH '30' (#23) | 160 km/h | 3,600 hp | 84 t | $42,554 |
| SH '40' (#24) | 176 km/h | 5,000 hp | 82 t | $48,804 |

The native paid fixture uses a longer powered route with house
catchments. An unpowered gap blocks orders; once wired, the train
boards passengers and can earn fares after save/reopen.

## Cross the Harbor Valley channel

Use the same 1978 start. On row `z=15`, build a timber rail bridge
from `(21,15)` to `(27,15)` with **Railworks → Bridge**,
then choose Timber in the picker. Place the east-facing depot at
`(15,15)`, and lay the two approach straights `x16–20` and `x28–36`.
Build platforms `x18–19` and `x35–36`. Put a path signal at `(17,15)`
facing NE/lower X (rotate twice from the default, as above).

In Rail Types, click either bridge portal twice with Electrify selected:
the price is **$476** for the whole seven-tile span. To wire the complete
route at once, select `(15,15)` through `(36,15)`. Inspect the electrified
depot, buy an electric with a coach, and pick the eastern platform first
and the western one second. Its pantograph flexes over the two ramps.
This sample is intended to show movement and wire alignment; passenger
fare requires houses within platform catchment.

See [railtype rules](railtype-port.md) and the
[conversion adapter](rail-electrification-world.md) for the source,
transaction boundaries, and tests.
