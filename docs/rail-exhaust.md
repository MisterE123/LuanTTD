# Locomotive exhaust

Steam engines puff from their modeled chimney mouths when they pull a train.
The Kirby, Jubilee, Ginzu and SH 8P each have their own stack position. Diesel
exhaust is smaller and fainter, limited to pulling away below half speed, and
comes from each modeled outlet rather than the roof center. Coaches, wagons
and electric engines do not emit exhaust.

The worker applies the activity and visibility gates from OpenTTD 16.0-RC1's
[`Vehicle::ShowVisualEffect`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/vehicle.cpp#L2603)
and [`TrainLocoHandler`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/train_cmd.cpp#L3731).
Luanti uses a slower wall-clock cadence and an original translucent sprite
for the 3D presentation. Steam is more frequent when pulling away; diesel
never leaves a continuous dark cloud. Nothing is emitted on depot or tunnel
tiles, under an overhead span, during station stops, or by a stationary or
teleported visual sample. The emitter never changes simulation state.

```sh
lua5.1 tests/rail_exhaust.lua
LUANTTD_NATIVE_RAIL_EXHAUST=1 bash tests/campaign_worker_graphical_native.sh
```

The native check builds a line, buys a Kirby and coach, dispatches them from
a depot in a fresh generated worker campaign, verifies each observed puff is
above the actual locomotive, and captures the Linux client view.
