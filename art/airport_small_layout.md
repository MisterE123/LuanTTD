# Small/Country airfield, OpenTTD 14.1

The stock fixed-wing airport program occupies **4×3 logical tiles**; it
is a short strip with one hangar and two loading stands. Coordinates below
are relative to the unrotated airport origin, in **16 source pixels per
tile**. Horizontal coordinates are X/Z in LuanTTD (X/Y upstream); source
height is eight pixels per terrain elevation level. Negative coordinates
and values outside the footprint are flight targets, not extra land that
must be allocated.

## Geometry available to art

- Runway along X across the last row (logical Z=2). The centerline is
  Z=40, the nominal runway endpoints are X=3 and X=61. Surface markings
  and curbs must not protrude into the movement path.
- Hangar tile is (3,0). Aircraft park at (53,3), nose +Z. The departure
  path exits south toward (53,27); keep an open portal and enough internal
  space for the short prop plane. Original meshes and materials can be
  designed without using source game sprites.
- Two terminal stands, at (32,23) and (10,23), are reached nose −Z.
  Keep the stand centers clear and locate platforms, waiting structures
  and props outside the aircraft/wingspan envelope. The stand-B taxi
  route passes through (43,37) and (24,37).
- Taxi between hangar, main crossing and runway uses (53,27), (53,37),
  (53,40), and (61,40). Runway turn-around taxi after the west threshold
  starts at (7,40).

The stock graphic role grid from `table/airport_defaults.h` is:

| Logical Z | X=0 | X=1 | X=2 | X=3 |
| --- | --- | --- | --- | --- |
| 0 | Building 1 | Building 2 | Building 3 | Hangar, portal +Z |
| 1 | Grass / outer fence / flag | Grass | Grass | Grass / outer fence |
| 2 | Runway far end | Runway middle | Runway middle | Runway near end |

The stock country airfield ships this one orientation. The angle helper is
the original generic rotation math (use rotated footprint dimensions when
supplying an independently authored rotated airport design).

## Fixed-wing route arrows

- Depart: hangar/stand → main crossing → (61,40), face −X → (3,40)
  runway acceleration → (−79,40) climb-out. Next airport receives the plane
  at an entry fix chosen relative to its own rotated footprint.
- Arrive: airborne loop waypoints (1,193) → (1,1) → (257,1) → (273,47)
  → (177,40). When the runway is free at the last fix, approach
  (56,40) → flare/brake toward (3,40) → taxi through (7,40);
  otherwise circle. One terminal branch then uses (24,37) → (10,23);
  the other (53,40) → (53,27) → (32,23).
- One shared runway/taxi block, distinct bits for the two stands.
  The runway block is held across the actual approach/taxi phase, not
  released immediately upon touchdown. A busy airport holds airborne
  aircraft at stock speed and refuses to release the selected runway
  block until the relevant position has actually been passed.

The movement table also contains stock helicopter rows for reference.
The isolated controller intentionally runs **ordinary fixed-wing aircraft
only**. Flight permissions, weather, audio, cargo/order policy, service,
aircraft operating limits, and crash consequences are host responsibilities.
