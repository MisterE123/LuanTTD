# First stock coal ship: pinned source and pure host seam

Scope: one 1950 temperate Yate Cargo Ship refitted to Coal, two owned
ordinary docks, manual distribution, alternating full load at the mine
and no load at the power station. Source pin: OpenTTD 14.1. This does not
change the passenger ferry or enable new gameplay on its own.

* Engine #211, ship table #7, standard cargo sprite index 0. Original
  base intro day 2557 after 1920-01-01, 30-year life, 55-year base life.
  Goods by default. The original non-Toyland mask accepts Mail,
  Armoured, Express, Bulk and Piece Goods; excludes Liquid and Passengers.
  Coal CargoID 1 is Bulk. The 160 Goods hull carries 160 t after refit;
  source does not rescale stock ship capacity by cargo.
* Base purchase 32500 and coal refit 507 in unscaled source money:
  65000 × 128 / 256 and 65000 × 8 / 1024, each truncated. Supply the
  current/inflated base price to Roster.quote(cargo_id, base_price,
  current_cargo_id). After purchase charge only refit, not total again.
* Speed 48 source units (24 km/h), acceleration 1, no sea/canal speed
  fraction. Actual carrier tile is the occupied water berth next to
  the wet dock tile. The fixture uses existing region YAPF and motion.
* Initial load wait 1 tick, gradual 10 t per pulse at 10 ticks per active
  round; non-gradual waits the actual changed amount (min 1); empty
  full-load probes wait 20. No-load doesn't prevent unloading. 185-tick
  cargo age post-motion. Rate 840000 fractional money units/year before
  inflation. Charge unstopped ticks including loading, in 1/256 cash.

## Mounting

Persist Service.new() and the real stock motion actor in a separate
cargo-ship slot. Bind the service to ctx.board=ShipNetwork.board(s).
The factory dependencies are Sim, Coal, Catchment, ShipRoster, Packets,
Rating, Station, Income, LoadingFactory and Timing.

1. Build/refit at one's depot and register B.vehicle({id, owner,
   engine=211, cargo=1, built=year}). Configure a separate instance of the
   current boat controller with ShipRoster. Never overwrite the live
   passenger ferry singleton. Validate both legs, berth and source/sink
   cash/catchment before debiting or starting.
2. B.extend(stations,covers) appends saved dock coal views once per bind
   to the one road+rail offer list. Send that list to the existing
   RailCoal.distribute wrapper, which defers packet origin until the
   actual carrier and merges fresh mine packets. Never run a second
   producer or offer. Owner-best choice and rating fractions are shared.
3. In the common clock call B.economy_day(day) at the economy boundary
   before vehicles. Call B.loading_tick(tick, stopped) in the station
   stage, then B.leave(visit,tick) before physical departure and
   B.arrive(local_dock,visit,tick,actual_berth,"full"|"no_load") on arrival,
   and B.after_motion(tick) afterwards. Nonphysical berths/foreign docks
   are refused. Lost berth fails closed without clearing the ledger.
4. Both physical dock tiles contribute to radius 5 with modified
   catchment. Call B.rating(st,tick) in CargoID order after the shared
   physical dock's 185-tick station timers increment once. If passenger
   service uses that dock, ctx.stationwide(st) must reference canonical
   timers and last transport type. Goods entries are per cargo. Call
   B.update_acceptance(st) in the existing stock acceptance big tick.
5. ctx.credit(s,owner,fare,paid_units), ctx.charge_fixed(s,owner,n) and
   ctx.received(s,industry,tons) connect to company/site accounting.
   Boarding and fare effects are for display only. Shared berth/vehicle
   occupancy with a passenger ferry, native saves/UI and an untouched
   campaign location remain mount work. No NewGRF, mixed hold, breakdown,
   transfer, or complete fleet is claimed.

## Proof

tests/ship_roster_upstream.py authenticates primary source hashes and
compiles stock price, loading and leave code against 12,000 cases.
tests/ship_coal_service.lua uses the real water/region YAPF and stock
dock/depot construction, one original mine terrain loop, and shared
road/rail competitor station views. The Yate fills 160t, restores twice
from partial load and unload, pays one $1753 fare for 160t accepted over
18 physical berth tiles, then returns to the mine. Age reaches 76
periods. Exact fixture shore (8,9)/(8,27), depot (12,10), mine (3,8),
power (3,26). This is a controlled coast fixture, not a native graphical
playtest or unmodified campaign. Tests also prove preserved cargo when
a saved occupied berth disappears.

## Live South Coast workbench

Enable bayline_ship_coal_preview. For the verified natural seed 1751
route, additionally set bayline_scenario = south_coast **before
creating a new world**. This chooses the exact real mine/plant layouts
at (12,27)/(5,28) instead of the older inland coal workbench placement;
it does not move towns, edit any heights/water, or create prebuilt
infrastructure. A saved world does not have its industry repositioned.
Without the explicit scenario, the inland test industry remains
unchanged. Do not mix the known inland rail/road route recipes with the
South Coast geography.

Build an axis-X ship depot at (12,34), a load dock ashore at (8,32),
and an unload dock ashore at (5,32). Inspect the depot to buy the
original #211 Yate for 32500 (Goods) and refit it for 507 (Coal);
use Harbor → Order Yate to select mine then power. Stop/Resume is
available in the owned depot inspector and preserves position,
loading and reservations. The model is the real cargo ship mesh, not
the ferry. Old ferry-only saves retain their old actor. The first coal
ship slice rejects shared depots and intersecting *sets* of assigned
ferry/coal water berths in either start order. Once dispatched, even a
stopped voyage protects its existing waterworks from edits. There is
no sell, ship replacement or permanent withdrawal command yet.

The native two-process SQLite fixture also builds a real competing
company coal truck: loop (5,27) → (11,27) → (11,25) → (5,25) →
(5,27), mine stop (10,27), plant stop (6,27), depot (7,26). A separate
paid ferry uses natural north docks (29,3)/(29,4) and east–west depot
(24,4). The truck, ferry and Yate use the world stock clock, not the
client frame rate. The fixture persists the Yate during partial coal
loading, restores precise position/reservation and owner accounts, then
stops and resumes it. A 160t cargo ship payment of 305, a real truck's
160t/448, sixteen actual ferry arrivals and exact accepted plant total
all passed; source ship running cost in this short route test is 1034.
The fixture doesn't claim this is a profitable short route or that
arbitrary multiple ship routes/facility destruction are supported.
