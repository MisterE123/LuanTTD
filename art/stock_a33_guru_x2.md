# Airtaxi A33 and Guru X2 Helicopter

The stock data is read against OpenTTD 16.0-RC1 `table/engines.h`,
MA #236 and #254 and AVI #21 and #39.

| Aircraft | Stock ID | Passengers | Mail | Compatible facilities |
| --- | ---: | ---: | ---: | --- |
| Airtaxi A33 | 236 | 220 | 20 | City Airport |
| Guru X2 Helicopter | 254 | 55 | 20 | Country/City hangar; playable outbound and inbound Oil Rig orders |

The A33 has a late wide-body pressure shell, swept wing, broad open fan
housings and separate native gear-up and gear-down geometry. The Guru X2
has a larger passenger cabin, individual side doors and boarding steps,
twin turboshaft fairings, a five-blade main rotor and a four-blade tail
rotor. The rotor meshes have independent fitted pivot points and move
on their own axes through the worker's authoritative rotor period.
Both aircraft were made from scratch and do not include original sprites
or external textures.

- Blender sources: `stock_airtaxi_a33.blend`, `stock_guru_x2.blend`.
- Exporter: `tools/build_stock_a33_guru_x2_art.py`.
- Proofs: exact source comparison, geometry/ground contact, native A33
  airport taxi/flight/landing, and actual helicopter passenger/Mail route
  to a live generated-type Oil Rig with process/SQLite restore. The
  graphical rig fixture checks both independent rotor axes move and that
  the detailed helicopter is actually visible on screen.
