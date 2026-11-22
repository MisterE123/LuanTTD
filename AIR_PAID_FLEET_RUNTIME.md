# Shared passenger economics for two owned country aircraft

One stock house event mux, source airport motion, one canonical rating
and loading queue per real airport, no duplicated passenger production.
The paid controller visits aircraft in ascending purchase/vehicle
identity even when their dispatch order differs. Ground traffic,
reservations, heading and model selection remain owned by the airport
controller. This adapter doesn't allocate separate runway flags.

The save's original encoded singleton air_serial remains a primary
alias (0xC000 + raw paid_clock). On first fleet reconciliation the
existing cargo row, station queue participation, packet payload and
clock counters are retained in place. The saved air_serials set tracks
all live paid aircraft. Withdrawal from one dispatcher row can't
discard or restart another. Committed fares and owner receipts are
handled by the existing shared passenger service.

Each cargo and motion event includes the raw paid_clock; cargo events
retain the encoded service vehicle ID. Status and interpolated pose
accept optional raw paid_clock, defaulting to the dispatcher primary for
old callers. Ungathered or unknown selected IDs do not display the
first actor by mistake. A missing native asset suspends that aircraft's
movement, elapsed visit and cargo age without deleting its saved
passengers or actual airport state. Other aircraft can advance when
their own real runway/approach permissions allow it. Disabling the
feature similarly doesn't desynchronize the shared road/town clock.

tests/air_paid_fleet_runtime.lua uses the real original airport/run
kernels and two actual bought Sampson U52s ordered to a common field.
It tests dispatch-order independence, conversion from the old primary
save representation, save/reload while loading, a per-actor art pause,
actual terminal verification, independent accounting and shared
ownership of exactly one hub queue. It settles 25 passengers for $232
on one aircraft and 25 for $223 on the other. The existing singleton
air, paired rail and ferry tests remain unchanged. Native graphical
interaction is separately exercised by the workbench mount, not by
this simulation-only test. The first fleet exposes only Sampsons and no
mail hold.
