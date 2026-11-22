# Stock OpenTTD comparison: first paid bus service

Manual graphical baseline, OpenTTD 14.1 with OpenGFX. Use a fresh temperate
game with seed 1751, normal speed, and 1500×925 window when replaying this trace.
No commands to modify or inspect the simulation; only keyboard and mouse
against the stock client on an isolated Linux X server. This is not a matched
topology, timing, vehicle model, or price benchmark.

1. Open the Towns directory, jump to Defingley (2,561 residents on arrival),
   then open Road Construction.
2. Extend the northeast city road with Autoroad by clicking and dragging.
   The construction float was £430.
3. Choose the northeast/southwest drive-through stop orientation. Place
   Defingley's stop on the newly extended road. The stop panel forecasts
   passenger acceptance and supply. Attempting a drive-through stop on a
   junction fails with “drive through stops can't have junctions.”
4. Choose the perpendicular drive-through stop orientation. Place the
   second stop on the northwest street (Defingley Heights).
5. Choose a depot orientation whose entrance faces the northeast street.
   Placing the depot beside the road automatically adds a connection:
   £390 depot + £71 road.
6. Open the depot, then New Vehicles, buy the MPS Regal Bus for £4,921.
   Open Orders and pick the two actual stops in the world using Go To.
   The order list displays both non-stop destinations. Start from the
   vehicle's current-action/status bar.

## Observed last mile

| Evidence file | Observation |
| --- | --- |
| `extended-road.png` | Drag construction succeeded and shows cost float. |
| `second-stop.png` | Upstream rejects the attempted drive-through stop on a junction. |
| `depot-built.png` | Depot construction and automatic connecting road are separately priced. |
| `new-vehicles.png` | Depot catalogue; MPS Regal Bus has 31-seat capacity. |
| `orders-complete.png` | Two human-picked non-stop destinations. |
| `pre-dispatch.png` | The purchased bus stopped in the depot on 3 June 1950. |
| `run-12.png` | On 7 June, the paper announces first arrival at Defingley on 5 June; bus heading for Defingley Heights. |
| `after-service.png` | On 28 June, the bus is carrying 16 passengers from Defingley and the other stop has waiting passengers. |
| `paid-fare.png` | No road-vehicle revenue yet on 5 July. |
| `paid-finances.png` | On 14 July, the first observed road-vehicle revenue is +£89. No other vehicles were purchased. |

First arrival was visible roughly 8.3 wall seconds after dispatch in the
recorded run. Positive revenue was first observed in the interval between 64
and 82 seconds after dispatch. This is an observation bracket, not exact event
latency. Stations started without waiting passengers; they accumulated riders
after service began. Road geometry, station placement, cargo generation and
normal simulation speed differ from LuanTTD's current test, so the two routes
do not establish pace parity.

## Design lessons

- Construction tools forecast footprint, accepted/supplied cargo and cost
  before placement; direction filters and explicit invalidity messaging are
  part of game rules, not merely sprites. In particular, a drive-through
  stop has no junction, unlike the current LuanTTD corner shelter variant.
- Depot orientation and road connectivity are two aspects of placement; the
  stock auto-connection produces its own cost float.
- Waiting cargo tied to service and the first-arrival newspaper create more
  visible milestones than going directly from fresh stations to fare income.
- Choosing stations in the world and starting from a vehicle status affordance
  feel very close across games; LuanTTD avoids managing separate depot,
  catalogue, vehicle and order windows for a one-bus starter route.
