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
physics, rail reservations or transactions in the simulation. If a
vehicle is temporarily unloaded, its old view is immediately removed
and a returning body is identified by its physical car ID. A lost
vehicle automatically returns you to the builder view.

The focused safeguards run with `lua tests/vehicle_ride.lua`. The
two-client Linux test is `tests/campaign_worker_ride_native.sh`.
