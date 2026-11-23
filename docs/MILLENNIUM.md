# Stock Millennium Z1 monorail

The Millennium Z1 is a single stock depot purchase but arrives as
two powered vehicles with outward-facing cabs. Each body carries
25 passengers, for 50 seats in the matched set. Both heads have
independent compartments and bogies. They keep the same physical
IDs and cargo through a reversal: the other cab leads, rather than
swapping the bodies or turning their noses toward the middle.

In a fresh **2010** game, build a monorail depot and two passenger
platforms. In the depot choose **Millennium Z1**. Give it two platform
orders as you would for the X2001. If the line uses up your starting
capital, use **Company → Finances**. The starter Z1 formation does
not require a coach. Attached passenger or freight wagons behind
this specific linked pair are not yet part of ordinary paid admission.

The 16.0-RC1 source record (#55) supplies the 336 km/h speed limit,
10,000 horsepower across both heads, 85-ton mass and 25 seats per
physical head, plus the lifecycle and price factors. The powered
ends use the stock carried mass, train length, station-loading
and reversal systems already mounted for other real dual-head trains.

**Art:** `art/rail_millennium_z1.blend` contains original editable
pressure shell, panoramic pilot glazing, separate side-entry doors
and saloon windows, and actual Monorail straddle running gear. The
guideway uses the same geometry as the X2001.

**Verification:** `BAYLINE_DMU_PROFILE=millennium bash
tests/stock_dash_worker_native.sh` constructs a normal line, buys
the exact Z1 depot offer, loads both cab bodies, restores the
half-loaded save, reverses on the same line, and credits the
50-seat arrival. The normal Dash with a separate coach is tested
with the default profile.
