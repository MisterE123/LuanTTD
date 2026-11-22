# Isolated first-delivery continuation

This developer-only fixture advances the same loaded stock 14.1 bus used in
`OPENTTD_PAUSED_BUS.md`. It is **not a playable importer or export path**.
The original stock save remains read-only, and no save, station graphics,
or model from OpenTTD is included. The optional native view uses LuanTTD's
own bus, terrain, road and platform art.

## Supported scope

One validated paused temperate 256² checkpoint, a single stock MPS Regal bus,
an unobstructed axial road at one level, one non-stop order to a single free
bay, at most eight onboard passengers, and no cached path alternatives,
active breakdown, pending payment, transfer subsidy or addressed station
waiting queue. The trip begins from the actual source tile, movement frame,
direction, speed, sub-speed, progress, calendar tick and cargo-age countdown.
The destination's acceptance and existing waiting passengers are extracted
from the real save; they are not supplied by a demo script.

The continuation uses the existing stock motion/tile tables, fixed-point
speed budget, gradual road loading, cargo aging/distance and temperate
fare modules. The small realistic-acceleration adapter specializes the
pinned stock power/drag/weight and corner-speed formulas to the one flat
Regal bus. It is not a new full-world simulation. It stops at the first
settlement and does not advance the next order, town production, broad
station ratings, breakdown generation, or other economy and company
expenses. The temporary cash figure is a **fare-only ledger projection**,
not OpenTTD's eventual company cash after its ordinary expenses.

A first-delivery journal stores the content-bound fixture identity and a
bounded elapsed-tick checkpoint. After a process restart, it deterministically
reconstructs just that trip into a paused scratch state. A new explicit
resume posts any still-pending fare once. This is **not** a general LuanTTD
save format or an encoded OpenTTD `.sav`.

## Verification

With a private fixture from `tests/openttd_save_map.py --retain-fixture`:

```sh
python3 tests/openttd_bus_checkpoint_resume.py \
  --openttd /path/to/OpenTTD-14.1/openttd --share /path/to/stock-data \
  --save /private/stock.sav > /private/stock-trajectory.json

python3 tests/openttd_bus_first_delivery.py \
  --luanti /path/to/luantiserver --save /private/stock.sav \
  --reference /private/stock-trajectory.json

# Optional, separate graphical capture in real Luanti:
tests/openttd_bus_first_delivery_visual.sh \
  /private/stock.sav /private/stock-trajectory.json /private/new-evidence
```

The stock runner only samples an independent real stock process; the
Luanti continuation is not driven by those samples. The test compares
each sampled stock tile, XYZ, frame, direction, speed, sub-speed, progress,
loading timer, onboard unit count, transit-age countdown and posted fare.
For the regenerated 256² reference starting at tick 2541, there were 18
matching stock observations before the isolated guard stops. The local
arrival was at 2725; five passengers arrived at age 3 at 2726; the £9
fare was still pending until the next loading pulse at 2746. At that pulse
eight of the fourteen existing waiting passengers boarded with six still
on the platform. The stock readouts show delivery and booking separated
and do not book the fare again. The short journey is not age-sensitive in
cash terms alone, so age is checked independently.

The second and third test boots shut down an actual Luanti server after
delivery, reopen the disposable journal in a new process, verify the
original five are not unloaded again, and, after resume, check that £9
is posted exactly once. A corrupt journal or a journal from an altered
waiting queue is rejected. The native mesh view separately verifies and
captures the loaded start, movement, pending-credit berth, and booked
state. Both native runners verify that the input SHA-256 is unchanged.
Keep the temporary staged files private; share only intended proof media.
