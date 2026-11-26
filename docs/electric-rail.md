# Electrify an owned railway

The electric roster includes the stock **SH '30'** and **SH '40'** and overhead
wire for ordinary track, including eligible flat and founded junctions. Steam and diesel can still
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
Single shared-edge turnouts, full diamonds and junctions with three to
six track pieces can be converted on flat ground or a stock leveled
foundation. Wiring follows the OpenTTD 16.0-RC1 branch filter. A branch
may lose its wire when disconnected or unelectrified, without changing
the track geometry or charging for more work. Complex junctions have an
original native steel portal, not an emulation of every OpenTTD pylon
position. Independent diagonal pairs, other slopes, and some structures
remain outside this conversion mount. Overhead
wire inside the depot is hidden by the shed. For ordinary flat straight
track and single curves, the OpenTTD pylon selector chooses actual edge
positions, including on visually straightened diagonal runs. A
disconnected end can gain a mast even when the adjacent track falls
outside your view. Multi-piece track, slopes and structures are not
covered by this pylon-placement mount.
Electric locomotives support one owned shuttle, not the paired pilot.

## Run an electric service

Start an ordinary world in 1970 or later for the SH ’30’, or 1978 or
later for the SH ’40’ (`bayline_stock_bus_start_year`). Build an
owned rail depot and two connected passenger platforms. Choose the
far platform first and give the train a safe return at the near
platform. Electrify the depot and the whole route, then right-click
the depot, buy an electric with a coach, pick the platforms and
click **Dispatch**. Put both platforms within reach of houses for fares.

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

The [compound native regression](../tests/rail_compound_wire_native.lua)
shows an SH ’30’ taking a curve through six pieces and paying a fare.
Adding powered approaches changes the contact mask from 4 to 21 to 63
while the same portal stays on the ground. A diamond and founded
three-piece layout retain their metalwork after SQLite reload. See the
[editable Blender portal and wires](../art/rail_compound_wire.blend) and
the [contact geometry comparison](../tests/rail_compound_wire_art.py).
The [independent pair replay](../tests/rail_paired_wire_native.lua)
keeps an actual 45° continuation while the second contact comes live,
then runs a paid SH ’30’ service after reopening.

## Electrify a timber bridge

Build a supported timber rail span and its approaches. Electrify
either portal to quote the complete span, or include both approaches
in one selection. Watch the pantograph extend and compress on the
ramps. Electric tunnels are not supported.

See [railtype rules](railtype-port.md) and the
[conversion adapter](rail-electrification-world.md) for the source,
transaction boundaries, and tests.
