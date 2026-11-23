# Buy and assemble trains in the depot

Open a rail depot and select **Buy locomotives and wagons separately**.
Pick an available locomotive or wagon from the catalog and buy that one
vehicle. Every wagon has its own persisted ID and exact stock price; buying
a wagon does not buy another engine or consume a locomotive number.

The OpenTTD 16.0-RC1 purchase behavior is preserved for the mounted stock
roster. A new wagon first tries to join an existing loose row headed by the
same model. The depot purchase callback tries to move **only the new wagon**
behind the only stopped locomotive in that depot, if there is exactly one.
With no clear recipient, or when the attachment would exceed the length
limit, the paid wagon stays loose. Buying a locomotive tries to take the
depot's loose rows in order without charging for previously bought cars.

In the depot panel, choose a real wagon and a vehicle to insert it after.
To move everything from the selected wagon back, enable **Move this wagon
and all following wagons**. **Move to loose wagons** works like dropping it
onto empty depot space: it tries a same-model loose row, or starts a new
one. This uses click selection rather than continuous drag, which Luanti
forms do not expose. Arrangement is free. Only vehicles wholly staged
inside this owned depot can be rearranged. The existing bundled recipes
remain shortcuts.

Assembled consists can be saved regardless of which commercial service
patterns the simulation supports. A modeled conventional engine can run
with multiple passenger coaches; use platforms long enough for all of
them. Each coach loads its own 40 seats and contributes its actual cargo
weight. Native Linux QA built an engine and two coaches separately, kept
both coaches' passenger loads across restart, and reversed the train to
earn fares. Some formations, including multiple freight wagons in one
service, cannot receive orders yet. No vehicle or capacity is substituted.

Source: 16.0-RC1 [train commands](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/train_cmd.cpp#L584-L694),
[vehicle purchase](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/vehicle_cmd.cpp#L184-L187),
[depot wagon-purchase callback](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/train_gui.cpp#L26-L49)
and [single/chain depot placement](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/depot_gui.cpp#L129-L143).

Verify depot purchase, assembly, persistence, finance and the in-game form
handlers on Linux with `lua5.1 tests/rail_loose_wagons.lua`. This scope covers
stock wagon moves, not locomotive swaps, selling, or NewGRF attachment
callbacks.
