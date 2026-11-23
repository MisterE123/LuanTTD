# Seated sightseeing

Aim at a vehicle or select it first. **Ride** in its details, or
`/ride`, seats you inside a running passenger bus or rail coach.
**Cab view** or `/train` seats you inside a running locomotive.
If you select a locomotive with a coach, Ride uses the nearest
passenger coach. Cab view works on freight trains too.

Look around with the normal camera controls. You cannot walk in the
vehicle or drive it. Press **E**, **right-click**, or use the command
again to return to your exact builder view. On touch screens, open the
inventory and choose **Leave ride**.

Only your client sees the private interior. Everyone else still sees
the actual moving vehicle. The feature does not change any orders,
physics, rail reservations or transactions in the simulation. If the
vehicle briefly falls out of view, the cabin stays at its last known
position for up to three seconds. A returning vehicle is matched by
its physical car ID. If it doesn't return, the game restores your
builder camera. Leaving voluntarily restores it immediately.

The focused safeguards run with `lua tests/vehicle_ride.lua`. The
two-client Linux test is `tests/campaign_worker_ride_native.sh`. It checks
that only the rider sees the cabin, and that leaving restores the normal
vehicle while the second player keeps seeing it. The paired native
focus test also verifies a real paid bus arrival after refocusing and
preserves that bus and its earnings after restarting the game.
